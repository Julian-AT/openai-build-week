import { GpuLaneCoordinator, type GpuWorkKind } from "./gpu-lane-coordinator.ts";
import {
  type InferenceJobRequest,
  type InferenceJobResponse,
  parseInferenceJobResponse,
  parseWorkerReadiness,
  type WorkerReadiness,
} from "./inference-protocol.ts";
import { ProtocolError } from "./protocol.ts";
import { parseJSONBytesStrict } from "./strict-json.ts";

const MAX_WORKER_TOKEN_BYTES = 512;
const MAX_READINESS_RESPONSE_BYTES = 32_768;
const MAX_JOB_RESPONSE_BYTES = 12_000_000;

export interface InferenceService {
  readiness(signal: AbortSignal): Promise<WorkerReadiness>;
  run(request: InferenceJobRequest, signal: AbortSignal): Promise<InferenceJobResponse>;
}

export interface InferenceWorkerClientOptions {
  baseURL: string;
  token: string;
  fetch?: WorkerFetch;
  gpuLaneCoordinator?: GpuLaneCoordinator;
}

export type WorkerFetch = (input: URL, init: RequestInit) => Promise<Response>;

export interface InferenceEnvironment {
  REFRAME_VISION_URL?: string | undefined;
  REFRAME_VISION_TOKEN?: string | undefined;
}

export function createInferenceWorkerClientFromEnvironment(
  environment: InferenceEnvironment,
  fetchImplementation?: WorkerFetch,
): InferenceService | undefined {
  const baseURL = environment.REFRAME_VISION_URL;
  const token = environment.REFRAME_VISION_TOKEN;
  const hasBaseURL = baseURL !== undefined && baseURL !== "";
  const hasToken = token !== undefined && token !== "";
  if (!hasBaseURL && !hasToken) return undefined;
  if (!hasBaseURL || !hasToken) throw new Error("incomplete_inference_config");
  return createInferenceWorkerClient({
    baseURL,
    token,
    ...(fetchImplementation ? { fetch: fetchImplementation } : {}),
  });
}

export class InferenceWorkerError extends Error {
  readonly publicCode:
    | "service_unavailable"
    | "worker_busy"
    | "upstream_failure"
    | "upstream_timeout";
  readonly status: 429 | 502 | 503 | 504;

  constructor(
    publicCode: "service_unavailable" | "worker_busy" | "upstream_failure" | "upstream_timeout",
    status: 429 | 502 | 503 | 504,
    options?: ErrorOptions,
  ) {
    super(publicCode, options);
    this.publicCode = publicCode;
    this.status = status;
  }
}

export function createInferenceWorkerClient(
  options: InferenceWorkerClientOptions,
): InferenceService {
  const baseURL = parseWorkerBaseURL(options.baseURL);
  const tokenBytes = Buffer.byteLength(options.token, "utf8");
  if (
    tokenBytes < 1 ||
    tokenBytes > MAX_WORKER_TOKEN_BYTES ||
    options.token.trim() !== options.token
  ) {
    throw new Error("invalid_inference_token");
  }
  const fetchImplementation: WorkerFetch = options.fetch ?? ((input, init) => fetch(input, init));
  const gpuLaneCoordinator = options.gpuLaneCoordinator ?? new GpuLaneCoordinator();

  return {
    async readiness(signal) {
      const value = await requestWorker({
        url: new URL("/readyz", baseURL),
        token: options.token,
        signal,
        maximumResponseBytes: MAX_READINESS_RESPONSE_BYTES,
        fetchImplementation,
      });
      try {
        return parseWorkerReadiness(value);
      } catch (error) {
        throw invalidWorkerResponse(error);
      }
    },

    async run(request, signal) {
      let response: InferenceJobResponse | undefined;
      let failure: unknown;
      const scheduled = await gpuLaneCoordinator.submit({
        id: request.request_id,
        kind: gpuWorkKind(request),
        signal,
        run: async (workerSignal) => {
          try {
            const value = await requestWorker({
              url: new URL("/v1/jobs", baseURL),
              token: options.token,
              signal: workerSignal,
              maximumResponseBytes: MAX_JOB_RESPONSE_BYTES,
              fetchImplementation,
              body: JSON.stringify(workerRequest(request)),
            });
            response = parseInferenceJobResponse(value, request);
          } catch (error) {
            failure = error;
            throw error;
          }
        },
      });
      if (scheduled.status === "completed" && response !== undefined) return response;
      if (scheduled.status === "cancelled") {
        throw signal.reason ?? new DOMException("inference request cancelled", "AbortError");
      }
      if (scheduled.status === "dropped") throw new InferenceWorkerError("worker_busy", 429);
      if (failure instanceof InferenceWorkerError) throw failure;
      throw invalidWorkerResponse(failure);
    },
  };
}

function workerRequest(request: InferenceJobRequest): InferenceJobRequest {
  if (request.task !== "segment") return request;
  return {
    ...request,
    session_id: request.session_id ?? `worker_${request.request_id}`,
    target_id: request.target_id ?? "target_0",
    frame_index: request.frame_index ?? 0,
  };
}

function gpuWorkKind(request: InferenceJobRequest): GpuWorkKind {
  if (request.task === "segment") return "target_semantics";
  if (request.task === "metric_depth") return "live_depth";
  return "b0_batch";
}

interface WorkerRequestOptions {
  url: URL;
  token: string;
  signal: AbortSignal;
  maximumResponseBytes: number;
  fetchImplementation: WorkerFetch;
  body?: string;
}

async function requestWorker(options: WorkerRequestOptions): Promise<unknown> {
  let response: Response;
  try {
    response = await options.fetchImplementation(options.url, {
      method: options.body === undefined ? "GET" : "POST",
      headers: {
        accept: "application/json",
        authorization: `Bearer ${options.token}`,
        ...(options.body === undefined ? {} : { "content-type": "application/json" }),
      },
      ...(options.body === undefined ? {} : { body: options.body }),
      signal: options.signal,
      redirect: "error",
    });
  } catch (error) {
    if (options.signal.aborted) throw options.signal.reason;
    throw new InferenceWorkerError("upstream_failure", 502, { cause: error });
  }

  if (!response.ok) {
    await response.body?.cancel().catch(() => undefined);
    if (response.status === 429) throw new InferenceWorkerError("worker_busy", 429);
    if (response.status === 503) {
      throw new InferenceWorkerError("service_unavailable", 503);
    }
    if (response.status === 504) {
      throw new InferenceWorkerError("upstream_timeout", 504);
    }
    throw new InferenceWorkerError("upstream_failure", 502);
  }
  if (!hasJSONContentType(response.headers.get("content-type"))) {
    await response.body?.cancel().catch(() => undefined);
    throw new InferenceWorkerError("upstream_failure", 502);
  }

  try {
    const bytes = await readBoundedResponse(response, options.maximumResponseBytes);
    return parseJSONBytesStrict(bytes);
  } catch (error) {
    if (options.signal.aborted) throw options.signal.reason;
    throw invalidWorkerResponse(error);
  }
}

async function readBoundedResponse(response: Response, maximumBytes: number): Promise<Uint8Array> {
  const declaredLength = response.headers.get("content-length");
  if (
    declaredLength !== null &&
    (!/^(?:0|[1-9][0-9]*)$/u.test(declaredLength) || Number(declaredLength) > maximumBytes)
  ) {
    await response.body?.cancel().catch(() => undefined);
    throw new RangeError("worker response exceeds byte limit");
  }
  if (response.body === null) return new Uint8Array();

  const chunks: Uint8Array[] = [];
  const reader = response.body.getReader();
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maximumBytes) {
        await reader.cancel().catch(() => undefined);
        throw new RangeError("worker response exceeds byte limit");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const combined = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    combined.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return combined;
}

function parseWorkerBaseURL(raw: string): URL {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new Error("invalid_inference_url");
  }
  // Docker Desktop exposes host services to containers through this fixed,
  // local-only DNS name. It is equivalent to loopback for the development
  // compose topology; all other non-TLS worker origins remain rejected.
  const isLocalWorkerHost = [
    "localhost",
    "127.0.0.1",
    "::1",
    "[::1]",
    "host.docker.internal",
  ].includes(url.hostname);
  if (
    (url.protocol !== "https:" && !(url.protocol === "http:" && isLocalWorkerHost)) ||
    url.username !== "" ||
    url.password !== "" ||
    (url.pathname !== "" && url.pathname !== "/") ||
    url.search !== "" ||
    url.hash !== ""
  ) {
    throw new Error("invalid_inference_url");
  }
  return url;
}

function hasJSONContentType(contentType: string | null): boolean {
  return contentType?.split(";", 1)[0]?.trim().toLowerCase() === "application/json";
}

function invalidWorkerResponse(cause: unknown): InferenceWorkerError {
  const safeCause =
    cause instanceof ProtocolError || cause instanceof SyntaxError ? cause : undefined;
  return new InferenceWorkerError("upstream_failure", 502, { cause: safeCause });
}
