import { expect, test } from "bun:test";

import { parseFramePacket } from "@reframe/protocol";

import { createCaptureSession } from "./capture-upload.ts";

const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);

test("creates a room and uploads a protocol-valid JPEG frame and event", async () => {
  const requests: Array<{ url: string; init: RequestInit }> = [];
  const session = await createCaptureSession({
    gatewayURL: "https://gateway.example",
    gatewayToken: "gateway-token",
    sessionID: "room_browser_demo",
    expiresAtMilliseconds: 1_000_600_000,
    nowMilliseconds: () => 1_000_000_000,
    fetch: async (input, init) => {
      requests.push({ url: String(input), init: init ?? {} });
      if (String(input).endsWith("/v1/sessions")) {
        return new Response(
          JSON.stringify({
            session_id: "room_browser_demo",
            credential: "room-credential",
            expires_at_ms: 1_000_600_000,
          }),
          { status: 201 },
        );
      }
      if (String(input).endsWith("/frames")) {
        return new Response(
          JSON.stringify({
            session_id: "room_browser_demo",
            frame_id: 0,
            sha256: "a".repeat(64),
            byte_length: 4,
            accepted_at_ms: 1_000_000_001,
            replayed: false,
          }),
          { status: 202 },
        );
      }
      return new Response(
        JSON.stringify({
          session_id: "room_browser_demo",
          event_id: "event_00000000-0000-4000-8000-000000000001",
          event_sequence: 0,
          monotonic_timestamp_ns: "123",
          type: "session_started",
          payload: { source: "browser" },
          payload_sha256: "b".repeat(64),
          accepted_at_ms: 1_000_000_002,
          replayed: false,
        }),
        { status: 202 },
      );
    },
  });

  const frame = await session.uploadJPEGFrame({ bytes: jpeg, width: 2, height: 2 });
  const event = await session.appendEvent({
    type: "session_started",
    payload: { source: "browser" },
    eventID: "event_00000000-0000-4000-8000-000000000001",
    monotonicTimestampNanoseconds: "123",
  });

  expect(frame.frame_id).toBe(0);
  expect(event.event_sequence).toBe(0);
  expect(requests.map((request) => request.url)).toEqual([
    "https://gateway.example/v1/sessions",
    "https://gateway.example/v1/sessions/room_browser_demo/frames",
    "https://gateway.example/v1/sessions/room_browser_demo/events",
  ]);
  const frameBody = new Uint8Array(await new Response(requests[1]?.init.body).arrayBuffer());
  const packet = parseFramePacket(frameBody);
  expect(packet.metadata.session_id).toBe("room_browser_demo");
  expect(packet.metadata.clock_domain).toBe("browser_monotonic_performance");
  expect(packet.metadata.tracking).toEqual({
    state: "not_available",
    reason: "browser_capture",
    world_frame_version: 0,
  });
  expect(
    new TextDecoder().decode(await new Response(requests[2]?.init.body).arrayBuffer()),
  ).toContain('"event_sequence":0');
});

test("rejects malformed JPEG bytes and prevents non-monotonic frame IDs", async () => {
  let requests = 0;
  const session = await createCaptureSession({
    gatewayURL: "https://gateway.example",
    gatewayToken: "gateway-token",
    sessionID: "room_browser_invalid",
    expiresAtMilliseconds: 1_000_600_000,
    nowMilliseconds: () => 1_000_000_000,
    fetch: async () => {
      requests += 1;
      if (requests === 1) {
        return new Response(
          JSON.stringify({
            session_id: "room_browser_invalid",
            credential: "room-credential",
            expires_at_ms: 1_000_600_000,
          }),
          { status: 201 },
        );
      }
      return new Response(
        JSON.stringify({
          session_id: "room_browser_invalid",
          frame_id: 2,
          sha256: "a".repeat(64),
          byte_length: 4,
          accepted_at_ms: 1_000_000_001,
          replayed: false,
        }),
        { status: 202 },
      );
    },
  });

  await expect(
    session.uploadJPEGFrame({ bytes: new Uint8Array([1, 2, 3, 4]), width: 2, height: 2 }),
  ).rejects.toThrow("invalid_capture_jpeg");
  await session.uploadJPEGFrame({ bytes: jpeg, width: 2, height: 2, frameID: 2 });
  await expect(
    session.uploadJPEGFrame({ bytes: jpeg, width: 2, height: 2, frameID: 1 }),
  ).rejects.toThrow("invalid_capture_frame_id");
});
