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

test("capture events strictly parse calibrated target and plane coordination payloads", () => {
  const targetSeed = coordinationEvent("target_seed", {
    type: "target_seed",
    session_id: "room_2026_07_21_target",
    frame_id: 42,
    pixel_encoded: [318, 251],
    ray_world: { origin: [1.42, 1.53, -2.18], direction: [0.11, -0.18, -0.98] },
    arkit_hit: { surface_id: "arkit_plane_07", position_world: [1.66, 0.01, -4.31] },
    source: "tap",
  });
  const planeUpsert = coordinationEvent("plane_upsert", {
    type: "plane_upsert",
    session_id: "room_2026_07_21_target",
    plane_id: "arkit_plane_07",
    revision: 4,
    classification: "floor",
    world_from_plane: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
    extent_m: [3.82, 4.1],
    boundary_vertices_local_xz_m: [
      [-1.9, -2],
      [1.9, -2],
      [1.9, 2.1],
    ],
    confidence: 0.88,
  });
  const planeRemove = coordinationEvent("plane_remove", {
    type: "plane_remove",
    session_id: "room_2026_07_21_target",
    plane_id: "arkit_plane_07",
    revision: 5,
  });

  assert.equal(parseCaptureEvent(targetSeed).type, "target_seed");
  assert.equal(parseCaptureEvent(planeUpsert).type, "plane_upsert");
  assert.equal(parseCaptureEvent(planeRemove).type, "plane_remove");
  assert.throws(() => parseCaptureEvent({ ...targetSeed, payload: { frame_id: 42 } }));
  assert.throws(() =>
    parseCaptureEvent({
      ...planeRemove,
      payload: { ...planeRemove.payload, client_object_id: "object_attacker" },
    }),
  );
});

function coordinationEvent(
  type: "target_seed" | "plane_upsert" | "plane_remove",
  payload: unknown,
) {
  return { ...event, type, payload };
}
