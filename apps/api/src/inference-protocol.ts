import { createHash } from "node:crypto";

import { ProtocolError } from "./protocol.ts";

export const INFERENCE_PROTOCOL_VERSION = "1.0.0";
export const MAX_INFERENCE_IMAGE_BYTES = 1_750_000;
export const MAX_INFERENCE_PIXELS = 16_777_216;
export const MAX_INFERENCE_BINARY_RESULT_BYTES = 8_000_000;

const stableUUID = "[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}";
const frameIDPattern = new RegExp(`^frame_${stableUUID}$`, "u");
const inferenceIDPattern = new RegExp(`^inference_${stableUUID}$`, "u");
const sha256Pattern = /^[0-9a-f]{64}$/u;

export interface InferenceImageInput {
  frame_id: string;
  media_type: "image/jpeg";
  data_base64: string;
  sha256: string;
  width: number;
  height: number;
}

export interface SegmentationJobRequest {
  protocol_version: "1.0.0";
  request_id: string;
  task: "segment";
  image: InferenceImageInput;
  prompt: {
    kind: "point";
    x: number;
    y: number;
    label: "foreground" | "background";
  };
}

export interface MetricDepthJobRequest {
  protocol_version: "1.0.0";
  request_id: string;
  task: "metric_depth";
  image: InferenceImageInput;
}

export interface ReconstructionJobRequest {
  protocol_version: "1.0.0";
  request_id: string;
  task: "reconstruct";
  archive_sha256: string;
  frame_ids: string[];
}

export type InferenceJobRequest =
  | SegmentationJobRequest
  | MetricDepthJobRequest
  | ReconstructionJobRequest;

export type InferenceTask = InferenceJobRequest["task"];

export interface InferenceProviderIdentity {
  provider_id: string;
  provider_revision: string;
  evidence_class: "fixture_only" | "unmeasured" | "measured";
}

export interface WorkerReadiness {
  protocol_version: "1.0.0";
  status: "ready" | "disabled" | "degraded";
  provider: InferenceProviderIdentity;
  tasks: Record<InferenceTask, boolean>;
  torch: {
    installed: boolean;
    version: string | null;
    mps_available: boolean;
  };
}

export interface MaskResult {
  kind: "mask";
  width: number;
  height: number;
  encoding: "binary_rle";
  counts: number[];
  foreground_pixels: number;
  sha256: string;
}

export interface MetricDepthResult {
  kind: "metric_depth";
  width: number;
  height: number;
  encoding: "float32_le_base64";
  unit: "metre";
  data_base64: string;
  sha256: string;
}

export interface ReconstructionResult {
  kind: "point_cloud";
  encoding: "ply_binary_little_endian";
  data_base64: string;
  sha256: string;
}

export type InferenceResult = MaskResult | MetricDepthResult | ReconstructionResult;

export interface InferenceJobResponse {
  protocol_version: "1.0.0";
  request_id: string;
  task: InferenceTask;
  provider: InferenceProviderIdentity;
  result: InferenceResult;
}

export function parseInferenceJobRequest(value: unknown): InferenceJobRequest {
  if (!isRecord(value) || value.protocol_version !== INFERENCE_PROTOCOL_VERSION) {
    throw invalidProtocol();
  }
  if (!matchesString(value.request_id, inferenceIDPattern)) throw invalidProtocol();
  if (value.task === "segment") {
    if (!hasExactKeys(value, ["protocol_version", "request_id", "task", "image", "prompt"])) {
      throw invalidProtocol();
    }
    const image = parseImage(value.image);
    const prompt = value.prompt;
    if (
      !isRecord(prompt) ||
      !hasExactKeys(prompt, ["kind", "x", "y", "label"]) ||
      prompt.kind !== "point" ||
      !isBoundedInteger(prompt.x, 0, image.width - 1) ||
      !isBoundedInteger(prompt.y, 0, image.height - 1) ||
      (prompt.label !== "foreground" && prompt.label !== "background")
    ) {
      throw invalidProtocol();
    }
    return value as unknown as SegmentationJobRequest;
  }
  if (value.task === "metric_depth") {
    if (!hasExactKeys(value, ["protocol_version", "request_id", "task", "image"])) {
      throw invalidProtocol();
    }
    parseImage(value.image);
    return value as unknown as MetricDepthJobRequest;
  }
  if (value.task === "reconstruct") {
    if (
      !hasExactKeys(value, [
        "protocol_version",
        "request_id",
        "task",
        "archive_sha256",
        "frame_ids",
      ]) ||
      !matchesString(value.archive_sha256, sha256Pattern) ||
      !Array.isArray(value.frame_ids) ||
      value.frame_ids.length < 2 ||
      value.frame_ids.length > 64 ||
      !value.frame_ids.every((frameID) => matchesString(frameID, frameIDPattern)) ||
      new Set(value.frame_ids).size !== value.frame_ids.length
    ) {
      throw invalidProtocol();
    }
    return value as unknown as ReconstructionJobRequest;
  }
  throw invalidProtocol();
}

export function parseWorkerReadiness(value: unknown): WorkerReadiness {
  if (
    !isRecord(value) ||
    !hasExactKeys(value, ["protocol_version", "status", "provider", "tasks", "torch"]) ||
    value.protocol_version !== INFERENCE_PROTOCOL_VERSION ||
    !["ready", "disabled", "degraded"].includes(value.status as string)
  ) {
    throw invalidProtocol();
  }
  parseProvider(value.provider);
  if (
    !isRecord(value.tasks) ||
    !hasExactKeys(value.tasks, ["segment", "metric_depth", "reconstruct"]) ||
    !Object.values(value.tasks).every((available) => typeof available === "boolean") ||
    (value.status === "disabled" && Object.values(value.tasks).some(Boolean))
  ) {
    throw invalidProtocol();
  }
  const torch = value.torch;
  if (
    !isRecord(torch) ||
    !hasExactKeys(torch, ["installed", "version", "mps_available"]) ||
    typeof torch.installed !== "boolean" ||
    typeof torch.mps_available !== "boolean" ||
    !(torch.version === null || isBoundedString(torch.version, 1, 64)) ||
    torch.installed !== (torch.version !== null) ||
    (torch.mps_available && !torch.installed)
  ) {
    throw invalidProtocol();
  }
  return value as unknown as WorkerReadiness;
}

export function parseInferenceJobResponse(
  value: unknown,
  request: InferenceJobRequest,
): InferenceJobResponse {
  if (
    !isRecord(value) ||
    !hasExactKeys(value, ["protocol_version", "request_id", "task", "provider", "result"]) ||
    value.protocol_version !== INFERENCE_PROTOCOL_VERSION ||
    value.request_id !== request.request_id ||
    value.task !== request.task
  ) {
    throw invalidProtocol();
  }
  parseProvider(value.provider);
  const result = value.result;
  if (!isRecord(result)) throw invalidProtocol();
  if (request.task === "segment") parseMaskResult(result);
  else if (request.task === "metric_depth") parseMetricDepthResult(result);
  else parseReconstructionResult(result);
  return value as unknown as InferenceJobResponse;
}

function parseImage(value: unknown): InferenceImageInput {
  if (
    !isRecord(value) ||
    !hasExactKeys(value, [
      "frame_id",
      "media_type",
      "data_base64",
      "sha256",
      "width",
      "height",
    ]) ||
    !matchesString(value.frame_id, frameIDPattern) ||
    value.media_type !== "image/jpeg" ||
    !matchesString(value.sha256, sha256Pattern) ||
    !isBoundedInteger(value.width, 1, 4_096) ||
    !isBoundedInteger(value.height, 1, 4_096) ||
    value.width * value.height > MAX_INFERENCE_PIXELS
  ) {
    throw invalidProtocol();
  }
  const jpeg = decodeCanonicalBase64(value.data_base64, MAX_INFERENCE_IMAGE_BYTES);
  if (
    jpeg.length < 4 ||
    jpeg[0] !== 0xff ||
    jpeg[1] !== 0xd8 ||
    jpeg.at(-2) !== 0xff ||
    jpeg.at(-1) !== 0xd9 ||
    sha256(jpeg) !== value.sha256
  ) {
    throw invalidProtocol();
  }
  return value as unknown as InferenceImageInput;
}

function parseProvider(value: unknown): InferenceProviderIdentity {
  if (
    !isRecord(value) ||
    !hasExactKeys(value, ["provider_id", "provider_revision", "evidence_class"]) ||
    !matchesString(value.provider_id, /^[a-z][a-z0-9_-]{0,63}$/u) ||
    !matchesString(value.provider_revision, /^[A-Za-z0-9._-]{1,128}$/u) ||
    !["fixture_only", "unmeasured", "measured"].includes(value.evidence_class as string)
  ) {
    throw invalidProtocol();
  }
  return value as unknown as InferenceProviderIdentity;
}

function parseMaskResult(value: Record<string, unknown>): MaskResult {
  if (
    !hasExactKeys(value, [
      "kind",
      "width",
      "height",
      "encoding",
      "counts",
      "foreground_pixels",
      "sha256",
    ]) ||
    value.kind !== "mask" ||
    value.encoding !== "binary_rle" ||
    !isBoundedInteger(value.width, 1, 4_096) ||
    !isBoundedInteger(value.height, 1, 4_096) ||
    value.width * value.height > MAX_INFERENCE_PIXELS ||
    !Array.isArray(value.counts) ||
    value.counts.length < 1 ||
    value.counts.length > 1_000_000 ||
    !value.counts.every((count) => isBoundedInteger(count, 0, MAX_INFERENCE_PIXELS)) ||
    !isBoundedInteger(value.foreground_pixels, 0, MAX_INFERENCE_PIXELS) ||
    !matchesString(value.sha256, sha256Pattern)
  ) {
    throw invalidProtocol();
  }
  const counts = value.counts as number[];
  if (
    counts.reduce((total, count) => total + count, 0) !== value.width * value.height ||
    counts.reduce((total, count, index) => total + (index % 2 ? count : 0), 0) !==
      value.foreground_pixels ||
    digestRLE(counts) !== value.sha256
  ) {
    throw invalidProtocol();
  }
  return value as unknown as MaskResult;
}

function parseMetricDepthResult(value: Record<string, unknown>): MetricDepthResult {
  if (
    !hasExactKeys(value, [
      "kind",
      "width",
      "height",
      "encoding",
      "unit",
      "data_base64",
      "sha256",
    ]) ||
    value.kind !== "metric_depth" ||
    value.encoding !== "float32_le_base64" ||
    value.unit !== "metre" ||
    !isBoundedInteger(value.width, 1, 4_096) ||
    !isBoundedInteger(value.height, 1, 4_096) ||
    value.width * value.height > MAX_INFERENCE_PIXELS ||
    !matchesString(value.sha256, sha256Pattern)
  ) {
    throw invalidProtocol();
  }
  const depth = decodeCanonicalBase64(value.data_base64, MAX_INFERENCE_BINARY_RESULT_BYTES);
  if (depth.length !== value.width * value.height * 4 || sha256(depth) !== value.sha256) {
    throw invalidProtocol();
  }
  return value as unknown as MetricDepthResult;
}

function parseReconstructionResult(value: Record<string, unknown>): ReconstructionResult {
  if (
    !hasExactKeys(value, ["kind", "encoding", "data_base64", "sha256"]) ||
    value.kind !== "point_cloud" ||
    value.encoding !== "ply_binary_little_endian" ||
    !matchesString(value.sha256, sha256Pattern)
  ) {
    throw invalidProtocol();
  }
  const pointCloud = decodeCanonicalBase64(value.data_base64, MAX_INFERENCE_BINARY_RESULT_BYTES);
  if (
    !pointCloud.subarray(0, 31).equals(Buffer.from("ply\nformat binary_little_endian")) ||
    sha256(pointCloud) !== value.sha256
  ) {
    throw invalidProtocol();
  }
  return value as unknown as ReconstructionResult;
}

function decodeCanonicalBase64(value: unknown, maximumBytes: number): Buffer {
  if (
    typeof value !== "string" ||
    value.length < 4 ||
    value.length > Math.ceil(maximumBytes / 3) * 4 ||
    !/^[A-Za-z0-9+/]+={0,2}$/u.test(value)
  ) {
    throw invalidProtocol();
  }
  const bytes = Buffer.from(value, "base64");
  if (bytes.length < 1 || bytes.length > maximumBytes || bytes.toString("base64") !== value) {
    throw invalidProtocol();
  }
  return bytes;
}

function digestRLE(counts: readonly number[]): string {
  const digest = createHash("sha256");
  for (const [index, count] of counts.entries()) {
    let remaining = count;
    while (remaining > 0) {
      const chunkLength = Math.min(remaining, 65_536);
      digest.update(Buffer.alloc(chunkLength, index % 2));
      remaining -= chunkLength;
    }
  }
  return digest.digest("hex");
}

function sha256(value: Uint8Array): string {
  return createHash("sha256").update(value).digest("hex");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, expected: readonly string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === expected.length && expected.every((key) => key in value);
}

function matchesString(value: unknown, pattern: RegExp): value is string {
  return typeof value === "string" && pattern.test(value);
}

function isBoundedString(value: unknown, minimum: number, maximum: number): value is string {
  return typeof value === "string" && value.length >= minimum && value.length <= maximum;
}

function isBoundedInteger(value: unknown, minimum: number, maximum: number): value is number {
  return Number.isSafeInteger(value) && (value as number) >= minimum && (value as number) <= maximum;
}

function invalidProtocol(): ProtocolError {
  return new ProtocolError("invalid_inference_protocol");
}
