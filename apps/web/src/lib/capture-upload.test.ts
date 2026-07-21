import { expect, test } from "bun:test";

import { createCaptureSession } from "./capture-upload.ts";

const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);

test("routes an ordinary video frame to the mapping boundary without ARKit authority", async () => {
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
      if (String(input).endsWith("/video-frames")) {
        return new Response(
          JSON.stringify({
            session_id: "room_browser_demo",
            frame_index: 0,
            sha256: "a".repeat(64),
            byte_length: 4,
            accepted_at_ms: 1_000_000_001,
            mapping_provider: "lingbot_map",
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
          type: "ordinary_video_imported",
          payload: { source: "browser" },
          payload_sha256: "b".repeat(64),
          accepted_at_ms: 1_000_000_002,
          replayed: false,
        }),
        { status: 202 },
      );
    },
  });

  const frame = await session.uploadOrdinaryVideoFrame({ bytes: jpeg, width: 2, height: 2 });
  const event = await session.appendEvent({
    type: "ordinary_video_imported",
    payload: { source: "browser" },
    eventID: "event_00000000-0000-4000-8000-000000000001",
    monotonicTimestampNanoseconds: "123",
  });

  expect(frame.frame_index).toBe(0);
  expect(frame.mapping_provider).toBe("lingbot_map");
  expect(event.event_sequence).toBe(0);

  const created = JSON.parse(
    new TextDecoder().decode(await new Response(requests[0]?.init.body).arrayBuffer()),
  ) as { allowed_paths: string[] };
  expect(created.allowed_paths).toEqual(["events"]);

  expect(requests.map((request) => request.url)).toEqual([
    "https://gateway.example/v1/sessions",
    "https://gateway.example/v1/sessions/room_browser_demo/video-frames",
    "https://gateway.example/v1/sessions/room_browser_demo/events",
  ]);

  const envelope = JSON.parse(
    new TextDecoder().decode(await new Response(requests[1]?.init.body).arrayBuffer()),
  ) as Record<string, unknown>;
  expect(envelope.mapping_provider).toBe("lingbot_map");
  expect(envelope.pose_source).toBe("none");
  expect(envelope.clock_domain).toBe("browser_monotonic_performance");
  expect(envelope).not.toHaveProperty("intrinsics_encoded");
  expect(envelope).not.toHaveProperty("world_from_camera_arkit");
  expect(envelope).not.toHaveProperty("tracking");
  expect(JSON.stringify(envelope)).not.toContain("arkit");
});

test("rejects malformed JPEG bytes and prevents non-monotonic frame indices", async () => {
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
          frame_index: 2,
          sha256: "a".repeat(64),
          byte_length: 4,
          accepted_at_ms: 1_000_000_001,
          mapping_provider: "lingbot_map",
        }),
        { status: 202 },
      );
    },
  });

  await expect(
    session.uploadOrdinaryVideoFrame({ bytes: new Uint8Array([1, 2, 3, 4]), width: 2, height: 2 }),
  ).rejects.toThrow("invalid_capture_jpeg");
  await session.uploadOrdinaryVideoFrame({ bytes: jpeg, width: 2, height: 2, frameIndex: 2 });
  await expect(
    session.uploadOrdinaryVideoFrame({ bytes: jpeg, width: 2, height: 2, frameIndex: 1 }),
  ).rejects.toThrow("invalid_capture_frame_index");
});
