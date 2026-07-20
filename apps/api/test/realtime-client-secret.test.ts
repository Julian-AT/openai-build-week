import assert from "node:assert/strict";
import { test } from "bun:test";

import { createRealtimeClientSecretService } from "../src/realtime-client-secret.ts";

test("Realtime bootstrap uses a 600-second server-owned nonmutating session", async () => {
  let requestedURL: unknown;
  let requestedInit: RequestInit | undefined;
  const service = createRealtimeClientSecretService({
    apiKey: "sk-test-secret",
    fetch: async (url, init) => {
      requestedURL = url;
      requestedInit = init;
      return new Response(
        JSON.stringify({
          value: "ek_ephemeral-secret",
          expires_at: 1_753_000_600,
          session: {
            id: "sess_test",
            model: "gpt-realtime-2.1",
            instructions: "upstream echo that must not be returned",
          },
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    },
    nowEpochSeconds: () => 1_753_000_000,
  });
  const controller = new AbortController();

  const result = await service.mint(controller.signal);

  assert.deepEqual(result, {
    value: "ek_ephemeral-secret",
    expires_at: 1_753_000_600,
    session: { id: "sess_test", model: "gpt-realtime-2.1" },
  });
  assert.equal(requestedURL, "https://api.openai.com/v1/realtime/client_secrets");
  assert(requestedInit);
  assert.equal(requestedInit.method, "POST");
  assert.equal(requestedInit.signal, controller.signal);
  assert.deepEqual(requestedInit.headers, {
    authorization: "Bearer sk-test-secret",
    "content-type": "application/json",
  });

  const body = JSON.parse(String(requestedInit.body)) as Record<string, unknown>;
  assert.deepEqual(body.expires_after, { anchor: "created_at", seconds: 600 });
  const session = body.session as Record<string, unknown>;
  assert.equal(session.type, "realtime");
  assert.equal(session.model, "gpt-realtime-2.1");
  assert.equal("tool_choice" in session, false);
  assert.equal("tools" in session, false);
  assert.deepEqual(session.output_modalities, ["audio"]);
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

test("malformed, expired, or wrong-model upstream secrets are rejected", async () => {
  const invalidResponses = [
    { value: "sk_not_ephemeral", expires_at: 1_753_000_600, session: { id: "sess_a", model: "gpt-realtime-2.1" } },
    { value: "ek_expired", expires_at: 1_752_999_999, session: { id: "sess_b", model: "gpt-realtime-2.1" } },
    { value: "ek_wrong_model", expires_at: 1_753_000_600, session: { id: "sess_c", model: "gpt-realtime-2" } },
  ];

  for (const upstream of invalidResponses) {
    const service = createRealtimeClientSecretService({
      apiKey: "sk-test-secret",
      fetch: async () =>
        new Response(JSON.stringify(upstream), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      nowEpochSeconds: () => 1_753_000_000,
    });
    await assert.rejects(service.mint(new AbortController().signal), /invalid_realtime_response/u);
  }
});

test("Realtime bootstrap rejects duplicate, invalid UTF-8, and oversized upstream JSON", async () => {
  const responses = [
    new Response(
      '{"value":"ek_first","value":"ek_second","expires_at":1753000600,"session":{"id":"sess_a","model":"gpt-realtime-2.1"}}',
      { status: 200, headers: { "content-type": "application/json" } },
    ),
    new Response(new Uint8Array([0x7b, 0x22, 0x78, 0x22, 0x3a, 0xff, 0x7d]), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
    new Response(" ".repeat(8_193), {
      status: 200,
      headers: { "content-type": "application/json" },
    }),
  ];

  for (const response of responses) {
    const service = createRealtimeClientSecretService({
      apiKey: "sk-test-secret",
      fetch: async () => response,
      nowEpochSeconds: () => 1_753_000_000,
    });
    await assert.rejects(
      service.mint(new AbortController().signal),
      /^Error: invalid_realtime_response$/u,
    );
  }
});

test("an upstream HTTP failure is collapsed to a generic service error", async () => {
  const service = createRealtimeClientSecretService({
    apiKey: "sk-test-secret",
    fetch: async () => new Response("PRIVATE_UPSTREAM_BODY", { status: 401 }),
  });

  await assert.rejects(
    service.mint(new AbortController().signal),
    /^Error: realtime_upstream_failure$/u,
  );
});
