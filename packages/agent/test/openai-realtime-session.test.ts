import { test } from "bun:test";
import assert from "node:assert/strict";

import { createOpenAIRealtimeSessionService, REALTIME_MODEL } from "../src/index.ts";

test("the Realtime service exchanges browser SDP through the unified WebRTC interface", async () => {
  let requestedURL: string | undefined;
  let requestedInit: RequestInit | undefined;
  const controller = new AbortController();
  const service = createOpenAIRealtimeSessionService({
    apiKey: "test-api-key",
    safetyIdentifier: "user_hash_123",
    fetch: async (input, init) => {
      requestedURL = input instanceof Request ? input.url : input.toString();
      requestedInit = init;
      return new Response("answer-sdp", {
        status: 201,
        headers: { "content-type": "application/sdp" },
      });
    },
  });

  const result = await service.exchange("offer-sdp", controller.signal);

  assert.equal(result, "answer-sdp");
  assert.equal(requestedURL, "https://api.openai.com/v1/realtime/calls");
  assert.equal(requestedInit?.signal, controller.signal);
  assert.deepEqual(requestedInit?.headers, {
    Authorization: "Bearer test-api-key",
    "OpenAI-Safety-Identifier": "user_hash_123",
  });
  assert(requestedInit?.body instanceof FormData);
  assert.equal(requestedInit.body.get("sdp"), "offer-sdp");
  const session = JSON.parse(String(requestedInit.body.get("session"))) as Record<string, unknown>;
  assert.equal(session.type, "realtime");
  assert.equal(session.model, REALTIME_MODEL);
  assert.deepEqual(session.output_modalities, ["audio"]);
  assert.deepEqual(session.audio, {
    input: {
      noise_reduction: { type: "near_field" },
      transcription: { model: "gpt-4o-mini-transcribe", language: "en" },
      turn_detection: { type: "semantic_vad", eagerness: "auto", create_response: true },
    },
    output: { voice: "marin" },
  });
  assert.deepEqual(session.tools, []);
  assert.match(String(session.instructions), /non-authoritative/iu);
});

test("the Realtime service rejects malformed SDP and failed upstream exchanges", async () => {
  const invalidSDP = createOpenAIRealtimeSessionService({
    apiKey: "test-api-key",
    fetch: async () => new Response("unused"),
  });
  await assert.rejects(
    invalidSDP.exchange("", new AbortController().signal),
    /^Error: invalid_realtime_offer$/u,
  );

  const upstreamFailure = createOpenAIRealtimeSessionService({
    apiKey: "test-api-key",
    fetch: async () => new Response("upstream detail", { status: 400 }),
  });
  await assert.rejects(
    upstreamFailure.exchange("offer-sdp", new AbortController().signal),
    /^Error: invalid_realtime_response$/u,
  );
});

test("the Realtime service rejects oversized upstream responses", async () => {
  const service = createOpenAIRealtimeSessionService({
    apiKey: "test-api-key",
    fetch: async () => new Response(" ".repeat(64_001)),
  });

  await assert.rejects(
    service.exchange("offer-sdp", new AbortController().signal),
    /^Error: invalid_realtime_response$/u,
  );
});
