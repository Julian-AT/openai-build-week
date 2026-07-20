import { createHash } from "node:crypto";

export interface AcquiredContentReference {
  storageKey: string;
  sha256: string;
  byteLength: number;
}

export type AcquisitionPhase = "pending" | "partial" | "retry_wait" | "complete" | "failed";

export interface AcquisitionCheckpoint {
  schemaVersion: 1;
  acquisitionID: string;
  sourceURL: string;
  phase: AcquisitionPhase;
  attempts: number;
  receivedBytes: number;
  totalBytes?: number;
  etag?: string;
  nextAttemptAtMs?: number;
  lastFailure?: string;
  updatedAtMs: number;
  content?: AcquiredContentReference;
}

export interface AcquisitionStateStore {
  load(acquisitionID: string): Promise<AcquisitionCheckpoint | undefined>;
  save(checkpoint: AcquisitionCheckpoint): Promise<void>;
}

export interface AcquisitionContentStore {
  partialSize(acquisitionID: string): Promise<number>;
  appendPartial(acquisitionID: string, expectedOffset: number, bytes: Uint8Array): Promise<void>;
  replacePartial(acquisitionID: string, bytes: Uint8Array): Promise<void>;
  readPartial(acquisitionID: string): Promise<Uint8Array>;
  commitContent(sha256: string, bytes: Uint8Array): Promise<string>;
  discardPartial(acquisitionID: string): Promise<void>;
}

export interface AcquisitionDownloadRequest {
  sourceURL: string;
  offset: number;
  ifRangeETag?: string;
  maxResponseBytes: number;
}

export interface AcquisitionDownloadResponse {
  status: number;
  bytes: Uint8Array;
  etag?: string;
  rangeStart?: number;
  totalBytes?: number;
  retryAfterMs?: number;
}

export interface AcquisitionTransport {
  download(request: AcquisitionDownloadRequest): Promise<AcquisitionDownloadResponse>;
}

export interface AcquireCatalogBinaryOptions {
  acquisitionID: string;
  sourceURL: string;
  state: AcquisitionStateStore;
  content: AcquisitionContentStore;
  transport: AcquisitionTransport;
  nowMs: number;
  maxAttempts?: number;
  baseRetryMs?: number;
  maxResponseBytes?: number;
  maxAssetBytes?: number;
}

export interface AcquisitionResult {
  status: "partial" | "deferred" | "complete" | "failed";
  checkpoint: AcquisitionCheckpoint;
}

const SAFE_ID = /^[a-z0-9][a-z0-9._-]{1,127}$/u;
const TRANSIENT_STATUS = new Set([408, 425, 429, 500, 502, 503, 504]);
const DEFAULT_MAX_ATTEMPTS = 5;
const DEFAULT_BASE_RETRY_MS = 1_000;
const DEFAULT_MAX_RESPONSE_BYTES = 16 * 1_024 * 1_024;
const DEFAULT_MAX_ASSET_BYTES = 250 * 1_024 * 1_024;
const MAX_RETRY_DELAY_MS = 5 * 60 * 1_000;

export async function acquireCatalogBinary(
  options: AcquireCatalogBinaryOptions,
): Promise<AcquisitionResult> {
  validateOptions(options);
  const maxAttempts = options.maxAttempts ?? DEFAULT_MAX_ATTEMPTS;
  const baseRetryMs = options.baseRetryMs ?? DEFAULT_BASE_RETRY_MS;
  const maxResponseBytes = options.maxResponseBytes ?? DEFAULT_MAX_RESPONSE_BYTES;
  const maxAssetBytes = options.maxAssetBytes ?? DEFAULT_MAX_ASSET_BYTES;
  const stored = await options.state.load(options.acquisitionID);
  const checkpoint = stored ?? initialCheckpoint(options);
  validateCheckpoint(checkpoint, options);

  if (checkpoint.phase === "complete") return { status: "complete", checkpoint };
  if (checkpoint.phase === "failed") return { status: "failed", checkpoint };
  if (
    checkpoint.phase === "retry_wait" &&
    checkpoint.nextAttemptAtMs !== undefined &&
    options.nowMs < checkpoint.nextAttemptAtMs
  ) {
    return { status: "deferred", checkpoint };
  }

  const partialSize = await options.content.partialSize(options.acquisitionID);
  if (partialSize !== checkpoint.receivedBytes) throw new Error("acquisition_partial_mismatch");

  let response: AcquisitionDownloadResponse;
  try {
    response = await options.transport.download({
      sourceURL: options.sourceURL,
      offset: partialSize,
      ...(checkpoint.etag === undefined ? {} : { ifRangeETag: checkpoint.etag }),
      maxResponseBytes,
    });
  } catch {
    return scheduleRetry(checkpoint, "transport_error", options, maxAttempts, baseRetryMs);
  }

  if (!Number.isSafeInteger(response.status) || response.status < 100 || response.status > 599)
    throw new Error("invalid_acquisition_http_status");
  if (
    response.retryAfterMs !== undefined &&
    (!Number.isSafeInteger(response.retryAfterMs) || response.retryAfterMs < 0)
  ) {
    throw new Error("invalid_acquisition_retry_after");
  }

  if (TRANSIENT_STATUS.has(response.status)) {
    return scheduleRetry(
      checkpoint,
      `http_${response.status}`,
      options,
      maxAttempts,
      baseRetryMs,
      response.retryAfterMs,
    );
  }
  if (response.status !== 200 && response.status !== 206) {
    return failCheckpoint(checkpoint, `http_${response.status}`, options);
  }
  validateDownloadResponse(response, partialSize, maxResponseBytes, maxAssetBytes);

  let receivedBytes: number;
  if (response.status === 200) {
    await options.content.replacePartial(options.acquisitionID, response.bytes);
    receivedBytes = response.bytes.byteLength;
  } else {
    if (response.rangeStart !== partialSize) throw new Error("acquisition_range_mismatch");
    if (
      checkpoint.etag !== undefined &&
      (response.etag === undefined || response.etag !== checkpoint.etag)
    ) {
      await options.content.replacePartial(options.acquisitionID, new Uint8Array());
      return scheduleRetry(
        {
          schemaVersion: 1,
          acquisitionID: checkpoint.acquisitionID,
          sourceURL: checkpoint.sourceURL,
          phase: "pending",
          attempts: checkpoint.attempts,
          receivedBytes: 0,
          updatedAtMs: options.nowMs,
        },
        "etag_changed",
        options,
        maxAttempts,
        baseRetryMs,
      );
    }
    await options.content.appendPartial(options.acquisitionID, partialSize, response.bytes);
    receivedBytes = partialSize + response.bytes.byteLength;
  }

  const totalBytes = response.totalBytes ?? receivedBytes;
  if (receivedBytes > totalBytes) throw new Error("acquisition_size_mismatch");
  const next: AcquisitionCheckpoint = {
    schemaVersion: 1,
    acquisitionID: checkpoint.acquisitionID,
    sourceURL: checkpoint.sourceURL,
    phase: receivedBytes === totalBytes ? "pending" : "partial",
    attempts: checkpoint.attempts,
    receivedBytes,
    totalBytes,
    ...(response.etag === undefined ? {} : { etag: response.etag }),
    updatedAtMs: options.nowMs,
  };

  if (receivedBytes < totalBytes) {
    await options.state.save(next);
    return { status: "partial", checkpoint: next };
  }

  const bytes = await options.content.readPartial(options.acquisitionID);
  if (bytes.byteLength !== receivedBytes) throw new Error("acquisition_partial_mismatch");
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  const storageKey = await options.content.commitContent(sha256, bytes);
  if (storageKey !== `sha256/${sha256}`) throw new Error("invalid_content_address");
  const complete: AcquisitionCheckpoint = {
    ...next,
    phase: "complete",
    content: { storageKey, sha256, byteLength: bytes.byteLength },
  };
  await options.state.save(complete);
  await options.content.discardPartial(options.acquisitionID);
  return { status: "complete", checkpoint: complete };
}

async function scheduleRetry(
  checkpoint: AcquisitionCheckpoint,
  failure: string,
  options: AcquireCatalogBinaryOptions,
  maxAttempts: number,
  baseRetryMs: number,
  retryAfterMs?: number,
): Promise<AcquisitionResult> {
  const attempts = checkpoint.attempts + 1;
  if (attempts >= maxAttempts) {
    return failCheckpoint({ ...checkpoint, attempts }, failure, options);
  }
  const exponentialDelay = baseRetryMs * 2 ** (attempts - 1);
  const delay = Math.min(Math.max(exponentialDelay, retryAfterMs ?? 0), MAX_RETRY_DELAY_MS);
  const retry: AcquisitionCheckpoint = {
    ...checkpoint,
    phase: "retry_wait",
    attempts,
    nextAttemptAtMs: options.nowMs + delay,
    lastFailure: failure,
    updatedAtMs: options.nowMs,
  };
  await options.state.save(retry);
  return { status: "deferred", checkpoint: retry };
}

async function failCheckpoint(
  checkpoint: AcquisitionCheckpoint,
  failure: string,
  options: AcquireCatalogBinaryOptions,
): Promise<AcquisitionResult> {
  const failed: AcquisitionCheckpoint = {
    ...checkpoint,
    phase: "failed",
    lastFailure: failure,
    updatedAtMs: options.nowMs,
  };
  delete failed.nextAttemptAtMs;
  await options.state.save(failed);
  return { status: "failed", checkpoint: failed };
}

function initialCheckpoint(options: AcquireCatalogBinaryOptions): AcquisitionCheckpoint {
  return {
    schemaVersion: 1,
    acquisitionID: options.acquisitionID,
    sourceURL: options.sourceURL,
    phase: "pending",
    attempts: 0,
    receivedBytes: 0,
    updatedAtMs: options.nowMs,
  };
}

function validateOptions(options: AcquireCatalogBinaryOptions): void {
  if (!SAFE_ID.test(options.acquisitionID)) throw new Error("invalid_acquisition_id");
  const source = new URL(options.sourceURL);
  if (
    source.protocol !== "https:" ||
    source.username !== "" ||
    source.password !== "" ||
    source.hash !== ""
  ) {
    throw new Error("invalid_acquisition_source_url");
  }
  if (!Number.isSafeInteger(options.nowMs) || options.nowMs < 0)
    throw new Error("invalid_acquisition_clock");
  for (const value of [
    options.maxAttempts ?? DEFAULT_MAX_ATTEMPTS,
    options.baseRetryMs ?? DEFAULT_BASE_RETRY_MS,
    options.maxResponseBytes ?? DEFAULT_MAX_RESPONSE_BYTES,
    options.maxAssetBytes ?? DEFAULT_MAX_ASSET_BYTES,
  ]) {
    if (!Number.isSafeInteger(value) || value < 1) throw new Error("invalid_acquisition_limit");
  }
}

function validateCheckpoint(
  checkpoint: AcquisitionCheckpoint,
  options: AcquireCatalogBinaryOptions,
): void {
  if (
    checkpoint.schemaVersion !== 1 ||
    checkpoint.acquisitionID !== options.acquisitionID ||
    checkpoint.sourceURL !== options.sourceURL ||
    !Number.isSafeInteger(checkpoint.receivedBytes) ||
    checkpoint.receivedBytes < 0 ||
    !Number.isSafeInteger(checkpoint.attempts) ||
    checkpoint.attempts < 0
  ) {
    throw new Error("invalid_acquisition_checkpoint");
  }
  if (checkpoint.etag !== undefined) validateETag(checkpoint.etag);
  if (
    checkpoint.phase === "complete" &&
    (checkpoint.content === undefined ||
      checkpoint.content.byteLength !== checkpoint.receivedBytes ||
      checkpoint.content.storageKey !== `sha256/${checkpoint.content.sha256}`)
  ) {
    throw new Error("invalid_acquisition_checkpoint");
  }
}

function validateDownloadResponse(
  response: AcquisitionDownloadResponse,
  offset: number,
  maxResponseBytes: number,
  maxAssetBytes: number,
): void {
  if (
    response.bytes.byteLength === 0 ||
    response.bytes.byteLength > maxResponseBytes ||
    offset + response.bytes.byteLength > maxAssetBytes
  ) {
    throw new Error("invalid_acquisition_response_size");
  }
  if (response.etag !== undefined) validateETag(response.etag);
  if (
    response.totalBytes !== undefined &&
    (!Number.isSafeInteger(response.totalBytes) ||
      response.totalBytes < response.bytes.byteLength ||
      response.totalBytes > maxAssetBytes)
  ) {
    throw new Error("invalid_acquisition_total_size");
  }
  if (response.status === 206 && response.totalBytes === undefined)
    throw new Error("missing_acquisition_total_size");
}

function validateETag(etag: string): void {
  const hasControlCharacter = [...etag].some((character) => {
    const code = character.charCodeAt(0);
    return code <= 31 || code === 127;
  });
  if (etag.length === 0 || etag.length > 512 || hasControlCharacter)
    throw new Error("invalid_acquisition_etag");
}
