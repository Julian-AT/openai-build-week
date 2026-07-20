import { test } from "bun:test";
import assert from "node:assert/strict";

import { encodeFramePacket, parseFramePacket } from "../src/index.ts";

const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);

function metadata() {
  return {
    protocol_version: 1 as const,
    session_id: "room_2026_07_13_01",
    submap_id: 0,
    frame_id: 842,
    timestamp_ns: 1_783_918_472_391_823,
    clock_domain: "ios_monotonic_uptime" as const,
    image: {
      codec: "jpeg" as const,
      width: 640,
      height: 480,
      orientation: "up" as const,
      color_space: "sRGB" as const,
      payload_bytes: jpeg.byteLength,
    },
    intrinsics_encoded: [514.4, 0, 319.8, 0, 513.9, 239.6, 0, 0, 1],
    world_from_camera_arkit: [1, 0, 0, 1.42, 0, 1, 0, 1.53, 0, 0, 1, -2.18, 0, 0, 0, 1],
    tracking: { state: "normal" as const, reason: "none" as const, world_frame_version: 1 },
    capture_quality: {
      blur_score: 0.08,
      angular_velocity_rad_s: 0.19,
      translation_since_last_m: 0.034,
      rotation_since_last_deg: 3.2,
      exposure_s: 0.0083,
      iso: 142,
    },
  };
}

test("FramePacket round trips its exact binary envelope and canonical metadata", () => {
  const bytes = encodeFramePacket({ metadata: metadata(), image: jpeg, flags: 0b1001 });
  const packet = parseFramePacket(bytes);

  assert.equal(packet.header.frame_id, 842);
  assert.equal(packet.header.flags, 0b1001);
  assert.deepEqual(packet.metadata, metadata());
  assert.deepEqual(packet.image, jpeg);
});

test("FramePacket fails closed on length, image, identifier, and incompatible version drift", () => {
  const bytes = encodeFramePacket({ metadata: metadata(), image: jpeg, flags: 0 });
  const truncated = bytes.slice(0, -1);
  assert.throws(() => parseFramePacket(truncated), /invalid_frame_packet_length/);

  const malformed = metadata();
  malformed.image.payload_bytes += 1;
  assert.throws(
    () => encodeFramePacket({ metadata: malformed, image: jpeg, flags: 0 }),
    /invalid_frame_packet/,
  );

  const badVersion = metadata();
  (badVersion as { protocol_version: number }).protocol_version = 2;
  assert.throws(
    () => encodeFramePacket({ metadata: badVersion, image: jpeg, flags: 0 }),
    /unsupported_frame_packet_version/,
  );
});
