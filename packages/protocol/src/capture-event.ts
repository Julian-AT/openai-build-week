import { canonicalJSONSHA256, canonicalJSONStringify } from "./canonical.ts";

export const CAPTURE_EVENT_TYPES = [
  "session_started",
  "ordinary_video_imported",
  "world_frame_changed",
  "frame_selected",
  "frame_image_and_metadata_durable",
  "frame_journaled",
  "frame_network_eligible",
  "frame_server_acknowledged",
  "tracking_changed",
  "target_seed",
  "plane_upsert",
  "plane_remove",
  "transaction",
  "session_finalized",
] as const;

export type CaptureEventType = (typeof CAPTURE_EVENT_TYPES)[number];

export interface TargetSeedPayload {
  readonly type: "target_seed";
  readonly session_id: string;
  readonly frame_id: number;
  readonly pixel_encoded: readonly [number, number];
  readonly ray_world: Readonly<{
    origin: readonly [number, number, number];
    direction: readonly [number, number, number];
  }>;
  readonly arkit_hit: Readonly<{
    surface_id: string;
    position_world: readonly [number, number, number];
  }> | null;
  readonly source: "reticle_dwell" | "tap" | "voice_capture" | "debug_web";
}

export interface PlaneUpsertPayload {
  readonly type: "plane_upsert";
  readonly session_id: string;
  readonly plane_id: string;
  readonly revision: number;
  readonly classification: "floor" | "wall" | "ceiling" | "table" | "unknown";
  readonly world_from_plane: readonly number[];
  readonly extent_m: readonly [number, number];
  readonly boundary_vertices_local_xz_m: readonly (readonly [number, number])[];
  readonly confidence: number;
}

export interface PlaneRemovePayload {
  readonly type: "plane_remove";
  readonly session_id: string;
  readonly plane_id: string;
  readonly revision: number;
}

export type CoordinationEventPayload = TargetSeedPayload | PlaneUpsertPayload | PlaneRemovePayload;

export interface CaptureEventInput {
  readonly event_id: string;
  readonly event_sequence: number;
  readonly monotonic_timestamp_ns: string;
  readonly type: CaptureEventType;
  readonly payload: unknown;
}

export function parseCaptureEvent(value: unknown): CaptureEventInput {
  if (!isRecord(value) || !hasExactKeys(value, EVENT_KEYS)) {
    throw new TypeError("invalid_capture_event");
  }
  const event = value as Record<string, unknown>;
  if (
    typeof event.event_id !== "string" ||
    !EVENT_ID.test(event.event_id) ||
    !isSafeInteger(event.event_sequence, 0) ||
    typeof event.monotonic_timestamp_ns !== "string" ||
    !/^(?:0|[1-9][0-9]{0,29})$/u.test(event.monotonic_timestamp_ns) ||
    typeof event.type !== "string" ||
    !(CAPTURE_EVENT_TYPES as readonly string[]).includes(event.type)
  ) {
    throw new TypeError("invalid_capture_event");
  }
  try {
    const canonicalJSONString = canonicalJSONStringify(event.payload);
    if (canonicalJSONString.length > 64 * 1024) throw new TypeError("invalid_capture_event");
  } catch {
    throw new TypeError("invalid_capture_event");
  }
  const type = event.type as CaptureEventType;
  return Object.freeze({
    event_id: event.event_id,
    event_sequence: event.event_sequence,
    monotonic_timestamp_ns: event.monotonic_timestamp_ns,
    type,
    payload: parseCoordinationPayload(type, event.payload),
  });
}

export function captureEventSHA256(event: CaptureEventInput): string {
  return canonicalJSONSHA256(event);
}

const EVENT_ID = /^event_[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u;
const EVENT_KEYS = [
  "event_id",
  "event_sequence",
  "monotonic_timestamp_ns",
  "type",
  "payload",
] as const;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, keys: readonly string[]): boolean {
  return Object.keys(value).length === keys.length && keys.every((key) => key in value);
}

function isSafeInteger(value: unknown, minimum: number): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= minimum;
}

function parseCoordinationPayload(type: CaptureEventType, payload: unknown): unknown {
  if (type !== "target_seed" && type !== "plane_upsert" && type !== "plane_remove") {
    return payload;
  }
  if (!isRecord(payload)) throw new TypeError("invalid_capture_event");
  if (type === "target_seed") return parseTargetSeed(payload);
  if (type === "plane_upsert") return parsePlaneUpsert(payload);
  return parsePlaneRemove(payload);
}

function parseTargetSeed(payload: Record<string, unknown>): TargetSeedPayload {
  if (
    !hasExactKeys(payload, [
      "type",
      "session_id",
      "frame_id",
      "pixel_encoded",
      "ray_world",
      "arkit_hit",
      "source",
    ]) ||
    payload.type !== "target_seed" ||
    !validRoomID(payload.session_id) ||
    !isSafeInteger(payload.frame_id, 0) ||
    !isVector(payload.pixel_encoded, 2) ||
    !isRecord(payload.ray_world) ||
    !hasExactKeys(payload.ray_world, ["origin", "direction"]) ||
    !isVector(payload.ray_world.origin, 3) ||
    !isNormalizedVector3(payload.ray_world.direction) ||
    !validHit(payload.arkit_hit) ||
    !["reticle_dwell", "tap", "voice_capture", "debug_web"].includes(String(payload.source))
  ) {
    throw new TypeError("invalid_capture_event");
  }
  return payload as unknown as TargetSeedPayload;
}

function parsePlaneUpsert(payload: Record<string, unknown>): PlaneUpsertPayload {
  if (
    !hasExactKeys(payload, [
      "type",
      "session_id",
      "plane_id",
      "revision",
      "classification",
      "world_from_plane",
      "extent_m",
      "boundary_vertices_local_xz_m",
      "confidence",
    ]) ||
    payload.type !== "plane_upsert" ||
    !validRoomID(payload.session_id) ||
    !validReference(payload.plane_id) ||
    !isSafeInteger(payload.revision, 1) ||
    !["floor", "wall", "ceiling", "table", "unknown"].includes(String(payload.classification)) ||
    !isVector(payload.world_from_plane, 16) ||
    !isPositiveVector2(payload.extent_m) ||
    !isBoundary(payload.boundary_vertices_local_xz_m) ||
    !isUnitInterval(payload.confidence)
  ) {
    throw new TypeError("invalid_capture_event");
  }
  return payload as unknown as PlaneUpsertPayload;
}

function parsePlaneRemove(payload: Record<string, unknown>): PlaneRemovePayload {
  if (
    !hasExactKeys(payload, ["type", "session_id", "plane_id", "revision"]) ||
    payload.type !== "plane_remove" ||
    !validRoomID(payload.session_id) ||
    !validReference(payload.plane_id) ||
    !isSafeInteger(payload.revision, 1)
  ) {
    throw new TypeError("invalid_capture_event");
  }
  return payload as unknown as PlaneRemovePayload;
}

function validRoomID(value: unknown): value is string {
  return typeof value === "string" && /^room_[a-z0-9_]{3,120}$/u.test(value);
}

function validReference(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z][A-Za-z0-9_-]{0,127}$/u.test(value);
}

function validHit(value: unknown): boolean {
  return (
    value === null ||
    (isRecord(value) &&
      hasExactKeys(value, ["surface_id", "position_world"]) &&
      validReference(value.surface_id) &&
      isVector(value.position_world, 3))
  );
}

function isVector(value: unknown, length: number): value is number[] {
  return Array.isArray(value) && value.length === length && value.every(Number.isFinite);
}

function isNormalizedVector3(value: unknown): value is number[] {
  if (!isVector(value, 3)) return false;
  const norm = Math.hypot(value[0] ?? 0, value[1] ?? 0, value[2] ?? 0);
  return Math.abs(norm - 1) <= 0.01;
}

function isPositiveVector2(value: unknown): value is number[] {
  return isVector(value, 2) && value.every((component) => component > 0);
}

function isBoundary(value: unknown): boolean {
  return (
    Array.isArray(value) &&
    value.length >= 3 &&
    value.length <= 256 &&
    value.every((point) => isVector(point, 2))
  );
}

function isUnitInterval(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= 1;
}
