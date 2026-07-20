import assert from "node:assert/strict";
import { test } from "bun:test";

import {
  createOpenAIRealtimeTokenService,
  REALTIME_MODEL,
} from "../src/index.ts";

test("the AI SDK Realtime adapter creates a closed push-to-talk session", async () => {
  let requestedURL: string | undefined;
  let requestedInit: RequestInit | undefined;
  const controller = new AbortController();
  const service = createOpenAIRealtimeTokenService({
    apiKey: "test-api-key",
    fetch: async (input, init) => {
      requestedURL = input instanceof Request ? input.url : input.toString();
      requestedInit = init;
      return Response.json({
        value: "ek_ephemeral-secret",
        expires_at: 1_753_000_600,
        session: { id: "sess_upstream", model: REALTIME_MODEL },
      });
    },
    nowEpochSeconds: () => 1_753_000_000,
  });

  const result = await service.mint(controller.signal);

  assert.deepEqual(result, {
    value: "ek_ephemeral-secret",
    expires_at: 1_753_000_600,
    url: "wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1",
    model: REALTIME_MODEL,
  });
  assert.equal(requestedURL, "https://api.openai.com/v1/realtime/client_secrets");
  assert.equal(requestedInit?.signal, controller.signal);
  assert.deepEqual(requestedInit?.headers, {
    authorization: "Bearer test-api-key",
    "Content-Type": "application/json",
    "user-agent": "ai-sdk/openai/4.0.16",
  });
  assert(requestedInit?.body !== undefined && requestedInit.body !== null);
  const body = JSON.parse(requestedInit.body.toString()) as Record<string, unknown>;
  assert.deepEqual(body.expires_after, { anchor: "created_at", seconds: 600 });
  const session = body.session as Record<string, unknown>;
  assert.equal(session.type, "realtime");
  assert.equal(session.model, REALTIME_MODEL);
  assert.deepEqual(session.output_modalities, ["audio"]);
  assert.equal("tools" in session, false);
  assert.match(String(session.instructions), /non-authoritative/iu);
  assert.deepEqual(session.audio, {
    input: {
      format: { type: "audio/pcm", rate: 24_000 },
      noise_reduction: { type: "near_field" },
      transcription: { model: "gpt-4o-mini-transcribe", language: "en" },
      turn_detection: null,
    },
    output: {
      format: { type: "audio/pcm", rate: 24_000 },
      voice: "marin",
    },
  });
});

test("the Realtime adapter rejects invalid normalized token results", async () => {
  const invalidResponses = [
    { value: "sk_server-secret", expires_at: 1_753_000_600 },
    { value: "ek_expired", expires_at: 1_752_999_999 },
    { value: "ek_too_long", expires_at: 1_753_000_661 },
  ];

  for (const response of invalidResponses) {
    const service = createOpenAIRealtimeTokenService({
      apiKey: "test-api-key",
      fetch: async () => Response.json(response),
      nowEpochSeconds: () => 1_753_000_000,
    });
    await assert.rejects(
      service.mint(new AbortController().signal),
      /^Error: invalid_realtime_response$/u,
    );
  }
});

test("the Realtime adapter rejects oversized upstream responses", async () => {
  const service = createOpenAIRealtimeTokenService({
    apiKey: "test-api-key",
    fetch: async () => new Response(" ".repeat(8_193)),
  });

  await assert.rejects(
    service.mint(new AbortController().signal),
    /^Error: invalid_realtime_response$/u,
  );
});
