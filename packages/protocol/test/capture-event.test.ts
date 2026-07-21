import { test } from "bun:test";
import assert from "node:assert/strict";

import { captureEventSHA256, parseCaptureEvent } from "../src/capture-event.ts";

const event = {
  event_id: "event_12345678-1234-4123-8123-123456789abc",
  event_sequence: 0,
  monotonic_timestamp_ns: "1783918472391823",
  type: "session_started",
  payload: { source: "ios" },
} as const;

test("capture events are strict, typed, and canonically digestible", () => {
  const parsed = parseCaptureEvent(event);
  assert.equal(parsed.type, "session_started");
  assert.match(captureEventSHA256(parsed), /^[a-f0-9]{64}$/u);
  assert.throws(() => parseCaptureEvent({ ...event, event_sequence: 1, extra: true }));
});

test("capture events reject invalid identity, timestamp, type, and oversized payloads", () => {
  assert.throws(() => parseCaptureEvent({ ...event, event_id: "event_bad" }));
  assert.throws(() => parseCaptureEvent({ ...event, monotonic_timestamp_ns: "01" }));
  assert.throws(() => parseCaptureEvent({ ...event, type: "unknown" }));
  assert.throws(() => parseCaptureEvent({ ...event, payload: "x".repeat(64 * 1024 + 1) }));
});

test("capture events accept target and plane coordination events", () => {
  for (const type of ["target_seed", "plane_upsert", "plane_remove"] as const) {
    const coordinationEvent = {
      ...event,
      type,
      payload: { frame_id: 42, pointer_context_id: "pointer_1" },
    };
    assert.equal(parseCaptureEvent(coordinationEvent).type, type);
  }
});
