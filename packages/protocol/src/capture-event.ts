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
  return Object.freeze({
    event_id: event.event_id,
    event_sequence: event.event_sequence,
    monotonic_timestamp_ns: event.monotonic_timestamp_ns,
    type: event.type as CaptureEventType,
    payload: event.payload,
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
