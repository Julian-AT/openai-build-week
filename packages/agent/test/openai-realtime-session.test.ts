import { expect, test } from "bun:test";
import assert from "node:assert/strict";

import {
  createOpenAIRealtimeSessionService,
  parseRealtimeSubmitUserTurn,
  REALTIME_MODEL,
} from "../src/index.ts";

const validTurn = {
  client_turn_id: "turn_browser_1",
  utterance: "Replace this chair",
  intent_hint: "replace",
  pointer_context_id: "pointer_1",
  client_scene_revision: 4,
  pending_proposal_id: null,
} as const;

test("parses only the closed non-mutating Realtime turn envelope", () => {
  expect(parseRealtimeSubmitUserTurn(validTurn)).toEqual(validTurn);
  expect(() => parseRealtimeSubmitUserTurn({ ...validTurn, commit: true })).toThrow(
    "invalid_realtime_turn",
  );
  expect(() => parseRealtimeSubmitUserTurn({ ...validTurn, utterance: " padded" })).toThrow(
    "invalid_realtime_turn",
  );
  expect(() => parseRealtimeSubmitUserTurn({ ...validTurn, client_scene_revision: -1 })).toThrow(
    "invalid_realtime_turn",
  );
  // A client-supplied world position is an unknown property and is rejected;
  // the gateway binds spatial context from authoritative durable state.
  expect(() =>
    parseRealtimeSubmitUserTurn({
      ...validTurn,
      pointer_context: { world_position: { x: 0, y: 0, z: 0 }, surface_id: null },
    }),
  ).toThrow("invalid_realtime_turn");
});

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
  assert.deepEqual(session.tools, [
    {
      type: "function",
      name: "submit_user_turn",
      description: "Submit one normalized user turn to Reframe's authoritative gateway.",
      parameters: {
        type: "object",
        additionalProperties: false,
        required: [
          "client_turn_id",
          "utterance",
          "intent_hint",
          "pointer_context_id",
          "client_scene_revision",
          "pending_proposal_id",
        ],
        properties: {
          client_turn_id: { type: "string", minLength: 1, maxLength: 128 },
          utterance: { type: "string", minLength: 1, maxLength: 2_000 },
          intent_hint: {
            type: ["string", "null"],
            enum: ["place", "replace", "remove", "restore", null],
          },
          pointer_context_id: { type: ["string", "null"], maxLength: 128 },
          client_scene_revision: { type: "integer", minimum: 0 },
          pending_proposal_id: { type: ["string", "null"], maxLength: 128 },
        },
      },
    },
  ]);
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
