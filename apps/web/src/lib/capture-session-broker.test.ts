import { expect, test } from "bun:test";

import { createCaptureRoom } from "./capture-session-broker.ts";

test("creates a short-lived scoped room without exposing gateway credentials", async () => {
  let authorization = "";
  const room = await createCaptureRoom({
    gatewayURL: "https://gateway.example/",
    gatewayToken: "gateway-token",
    sessionID: "room_web_broker",
    nowMilliseconds: () => 1_000_000_000,
    fetch: async (_input, init) => {
      const headers = init?.headers as Record<string, string> | undefined;
      authorization = String(headers?.Authorization);
      return new Response(
        JSON.stringify({
          session_id: "room_web_broker",
          credential: "scoped-room-token",
          expires_at_ms: 1_000_600_000,
        }),
        { status: 201 },
      );
    },
  });

  expect(room).toEqual({
    gatewayURL: "https://gateway.example",
    sessionID: "room_web_broker",
    credential: "scoped-room-token",
    expiresAtMilliseconds: 1_000_600_000,
  });
  expect(authorization).toBe("Bearer gateway-token");
  expect(JSON.stringify(room)).not.toContain("gateway-token");
});

test("rejects a gateway response that changes the requested session identity", async () => {
  await expect(
    createCaptureRoom({
      gatewayURL: "https://gateway.example",
      gatewayToken: "gateway-token",
      sessionID: "room_web_broker",
      fetch: async () =>
        new Response(
          JSON.stringify({
            session_id: "room_other",
            credential: "scoped-room-token",
            expires_at_ms: 1_000_600_000,
          }),
          { status: 201 },
        ),
    }),
  ).rejects.toThrow("invalid_capture_session");
});
