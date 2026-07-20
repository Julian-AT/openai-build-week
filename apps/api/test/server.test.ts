import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { test } from "bun:test";

import { InferenceWorkerError } from "../src/inference-client.ts";
import type { InferenceJobRequest } from "../src/inference-protocol.ts";
import { createGatewayApp } from "../src/server.ts";

const validProposalRequest = {
  prompt: "Replace this with a warm chair and preserve the walkway.",
  ingress_source: "typed",
  request_context: {
    session_id: "session_10000000-0000-4000-8000-000000000001",
    revision_branch_id: "branch_20000000-0000-4000-8000-000000000001",
    base_scene_revision: 7,
    world_frame_id: "world_30000000-0000-4000-8000-000000000001",
    world_frame_version: 2,
    selected_object_id: "object_40000000-0000-4000-8000-000000000001",
  },
} as const;

const inferenceJPEG = Buffer.from([0xff, 0xd8, 0xff, 0xd9]);
const validInferenceRequest: InferenceJobRequest = {
  protocol_version: "1.0.0",
  request_id: "inference_70000000-0000-4000-8000-000000000001",
  task: "segment",
  image: {
    frame_id: "frame_71000000-0000-4000-8000-000000000001",
    media_type: "image/jpeg",
    data_base64: inferenceJPEG.toString("base64"),
    sha256: createHash("sha256").update(inferenceJPEG).digest("hex"),
    width: 1,
    height: 1,
  },
  prompt: { kind: "point", x: 0, y: 0, label: "foreground" },
};

test("GET /health reports readiness without authentication", async () => {
  const app = createGatewayApp({ gatewayToken: "test-token" });
  const response = await app.request("/health");
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "ok" });
  assert.equal(response.headers.get("access-control-allow-origin"), null);
});

test("GET /v1/inference/status protects and forwards private worker readiness", async () => {
  let receivedSignal: AbortSignal | undefined;
  const expected = {
    protocol_version: "1.0.0" as const,
    status: "disabled" as const,
    provider: {
      provider_id: "disabled",
      provider_revision: "none",
      evidence_class: "unmeasured" as const,
    },
    tasks: { segment: false, metric_depth: false, reconstruct: false },
    torch: { installed: false, version: null, mps_available: false },
  };
  const app = createGatewayApp({
    gatewayToken: "test-token",
    inferenceService: {
      readiness: async (signal) => {
        receivedSignal = signal;
        return expected;
      },
      run: async () => {
        throw new Error("must not run");
      },
    },
  });

  assert.equal((await app.request("/v1/inference/status")).status, 401);
  const response = await app.request("/v1/inference/status", {
    headers: { authorization: "Bearer test-token" },
  });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), expected);
  assert.equal(receivedSignal instanceof AbortSignal, true);
});

test("POST /v1/inference/jobs validates and proxies the typed job", async () => {
  let received: unknown;
  const mask = Buffer.from([1]);
  const expected = {
    protocol_version: "1.0.0" as const,
    request_id: validInferenceRequest.request_id,
    task: "segment" as const,
    provider: {
      provider_id: "fixture",
      provider_revision: "fixture-v1",
      evidence_class: "fixture_only" as const,
    },
    result: {
      kind: "mask" as const,
      width: 1,
      height: 1,
      encoding: "binary_rle" as const,
      counts: [0, 1],
      foreground_pixels: 1,
      sha256: createHash("sha256").update(mask).digest("hex"),
    },
  };
  const app = createGatewayApp({
    gatewayToken: "test-token",
    inferenceService: {
      readiness: async () => {
        throw new Error("must not check readiness");
      },
      run: async (job) => {
        received = job;
        return expected;
      },
    },
  });

  const response = await app.request("/v1/inference/jobs", {
    method: "POST",
    headers: {
      authorization: "Bearer test-token",
      "content-type": "application/json",
    },
    body: JSON.stringify(validInferenceRequest),
  });
  assert.equal(response.status, 200);
  assert.deepEqual(received, validInferenceRequest);
  assert.deepEqual(await response.json(), expected);
});

test("inference routes fail closed and preserve only safe worker errors", async () => {
  const unavailable = createGatewayApp({ gatewayToken: "test-token" });
  const missing = await unavailable.request("/v1/inference/status", {
    headers: { authorization: "Bearer test-token" },
  });
  assert.equal(missing.status, 503);
  assert.deepEqual(await missing.json(), { error: "service_unavailable" });

  const busy = createGatewayApp({
    gatewayToken: "test-token",
    inferenceService: {
      readiness: async () => {
        throw new Error("must not check readiness");
      },
      run: async () => {
        throw new InferenceWorkerError("worker_busy", 429);
      },
    },
  });
  const response = await busy.request("/v1/inference/jobs", {
    method: "POST",
    headers: {
      authorization: "Bearer test-token",
      "content-type": "application/json",
    },
    body: JSON.stringify(validInferenceRequest),
  });
  assert.equal(response.status, 429);
  assert.deepEqual(await response.json(), { error: "worker_busy" });
});

test("POST /v1/proposals rejects a missing bearer credential", async () => {
  let calls = 0;
  const app = createGatewayApp({
    gatewayToken: "test-token",
    proposalService: {
      propose: async () => {
        calls += 1;
        throw new Error("must not be called");
      },
    },
  });
  const response = await app.request("/v1/proposals", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: "{}",
  });

  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: "unauthorized" });
  assert.equal(calls, 0);
});

test("POST /v1/proposals validates and forwards a closed trusted request", async () => {
  let received: unknown;
  const expectedEnvelope = {
    schema_version: "1.0.0",
    envelope_id: "envelope_50000000-0000-4000-8000-000000000001",
    created_at_utc: "2026-07-19T10:00:00.000Z",
    request_context: validProposalRequest.request_context,
    ingress_source: validProposalRequest.ingress_source,
    semantic_model: {
      provider: "openai",
      model: "gpt-5.6-sol",
      response_id: "resp_test",
    },
    status: "ready",
    intent: {
      operation: "replace",
      arguments: { asset_id: "asset_53000000-0000-4000-8000-000000000002" },
      constraints: [{ kind: "preserve_walkway", value: true }],
    },
    explanation: "The warm chair fits the requested style.",
    clarification: null,
  };
  const app = createGatewayApp({
    gatewayToken: "test-token",
    proposalService: {
      propose: async (request) => {
        received = request;
        return expectedEnvelope;
      },
    },
  });

  const response = await app.request("/v1/proposals", {
    method: "POST",
    headers: {
      authorization: "Bearer test-token",
      "content-type": "application/json; charset=utf-8",
    },
    body: JSON.stringify(validProposalRequest),
  });

  assert.equal(response.status, 200);
  assert.deepEqual(received, validProposalRequest);
  assert.deepEqual(await response.json(), expectedEnvelope);
});

test("POST /v1/proposals rejects duplicate JSON member names before validation", async () => {
  let calls = 0;
  const app = createGatewayApp({
    gatewayToken: "test-token",
    proposalService: {
      propose: async () => {
        calls += 1;
        return {};
      },
    },
  });
  const body = JSON.stringify(validProposalRequest).replace(
    '"prompt":',
    '"\\u0070rompt":"attacker override","prompt":',
  );

  const response = await app.request("/v1/proposals", {
    method: "POST",
    headers: {
      authorization: "Bearer test-token",
      "content-type": "application/json",
    },
    body,
  });

  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: "invalid_request" });
  assert.equal(calls, 0);
});

test("POST /v1/proposals rejects non-UTF-8 JSON bytes", async () => {
  let calls = 0;
  const app = createGatewayApp({
    gatewayToken: "test-token",
    proposalService: {
      propose: async () => {
        calls += 1;
        return {};
      },
    },
  });
  const validBody = Buffer.from(JSON.stringify(validProposalRequest), "utf8");
  const promptByte = validBody.indexOf(Buffer.from("Replace", "utf8"));
  assert.notEqual(promptByte, -1);
  validBody[promptByte] = 0xff;

  const response = await app.request("/v1/proposals", {
    method: "POST",
    headers: {
      authorization: "Bearer test-token",
      "content-type": "application/json",
    },
    body: validBody,
  });

  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: "invalid_request" });
  assert.equal(calls, 0);
});

test("POST /v1/proposals rejects client catalog allowlists and unknown fields", async () => {
  let calls = 0;
  const app = createGatewayApp({
    gatewayToken: "test-token",
    proposalService: {
      propose: async () => {
        calls += 1;
        return {};
      },
    },
  });

  const response = await app.request("/v1/proposals", {
    method: "POST",
    headers: {
      authorization: "Bearer test-token",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      ...validProposalRequest,
      asset_allowlist: ["asset_attacker-controlled"],
    }),
  });

  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: "invalid_request" });
  assert.equal(calls, 0);
});

test("known routes reject query-decorated URLs without invoking services", async () => {
  let calls = 0;
  const app = createGatewayApp({
    gatewayToken: "test-token",
    proposalService: {
      propose: async () => {
        calls += 1;
        return {};
      },
    },
  });

  const response = await app.request("/v1/proposals?context=forbidden", {
    method: "POST",
    headers: {
      authorization: "Bearer test-token",
      "content-type": "application/json",
    },
    body: JSON.stringify(validProposalRequest),
  });

  assert.equal(response.status, 404);
  assert.deepEqual(await response.json(), { error: "not_found" });
  assert.equal(calls, 0);
});

test("POST /v1/proposals requires a JSON content type", async () => {
  const app = createGatewayApp({
    gatewayToken: "test-token",
    proposalService: { propose: async () => ({}) },
  });

  const response = await app.request("/v1/proposals", {
    method: "POST",
    headers: {
      authorization: "Bearer test-token",
      "content-type": "text/plain",
    },
    body: JSON.stringify(validProposalRequest),
  });

  assert.equal(response.status, 415);
  assert.deepEqual(await response.json(), { error: "unsupported_media_type" });
});

test("POST /v1/proposals rejects a body over the fixed byte limit", async () => {
  const app = createGatewayApp({
    gatewayToken: "test-token",
    proposalService: { propose: async () => ({}) },
  });

  const response = await app.request("/v1/proposals", {
    method: "POST",
    headers: {
      authorization: "Bearer test-token",
      "content-type": "application/json",
    },
    body: JSON.stringify({ ...validProposalRequest, prompt: "x".repeat(2_500_001) }),
  });

  assert.equal(response.status, 413);
  assert.deepEqual(await response.json(), { error: "payload_too_large" });
});

test("POST /v1/proposals rejects a non-JPEG image data URL", async () => {
  let calls = 0;
  const app = createGatewayApp({
    gatewayToken: "test-token",
    proposalService: {
      propose: async () => {
        calls += 1;
        return {};
      },
    },
  });

  const response = await app.request("/v1/proposals", {
    method: "POST",
    headers: {
      authorization: "Bearer test-token",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      ...validProposalRequest,
      ingress_source: "vision",
      image_data_url: "data:image/png;base64,iVBORw0KGgo=",
    }),
  });

  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: "invalid_request" });
  assert.equal(calls, 0);
});

test("POST /v1/proposals binds vision ingress to exactly one JPEG", async () => {
  let calls = 0;
  const app = createGatewayApp({
    gatewayToken: "test-token",
    proposalService: {
      propose: async () => {
        calls += 1;
        return {};
      },
    },
  });
  const jpeg = "data:image/jpeg;base64,/9j/2Q==";
  const mismatches = [
    { ...validProposalRequest, ingress_source: "vision" },
    { ...validProposalRequest, image_data_url: jpeg },
    { ...validProposalRequest, ingress_source: "voice", image_data_url: jpeg },
  ];

  for (const body of mismatches) {
    const response = await app.request("/v1/proposals", {
      method: "POST",
      headers: {
        authorization: "Bearer test-token",
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    });
    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), { error: "invalid_request" });
  }
  assert.equal(calls, 0);
});

test("POST /v1/proposals rejects an empty semantic prompt", async () => {
  const app = createGatewayApp({
    gatewayToken: "test-token",
    proposalService: { propose: async () => ({ should_not: "run" }) },
  });

  const response = await app.request("/v1/proposals", {
    method: "POST",
    headers: {
      authorization: "Bearer test-token",
      "content-type": "application/json",
    },
    body: JSON.stringify({ ...validProposalRequest, prompt: "   " }),
  });

  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: "invalid_request" });
});

test("POST /v1/realtime/client-secret returns only the validated ephemeral subset", async () => {
  const expected = {
    value: "ek_ephemeral",
    expires_at: 1_753_000_600,
    url: "wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1",
    model: "gpt-realtime-2.1" as const,
  };
  const app = createGatewayApp({
    gatewayToken: "test-token",
    realtimeService: { mint: async () => expected },
  });

  const response = await app.request("/v1/realtime/client-secret", {
    method: "POST",
    headers: {
      authorization: "Bearer test-token",
      "content-type": "application/json",
    },
    body: "{}",
  });

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), expected);
});

test("known paths reject unsupported methods while unknown paths remain hidden", async () => {
  const app = createGatewayApp({ gatewayToken: "test-token" });

  const wrongMethod = await app.request("/v1/proposals");
  assert.equal(wrongMethod.status, 405);
  assert.equal(wrongMethod.headers.get("allow"), "POST");
  assert.deepEqual(await wrongMethod.json(), { error: "method_not_allowed" });

  const unknown = await app.request("/v1/unknown");
  assert.equal(unknown.status, 404);
  assert.deepEqual(await unknown.json(), { error: "not_found" });
});

test("structured request logs exclude credentials, prompts, images, and ephemeral values", async () => {
  const logs: unknown[] = [];
  const secretImage = Buffer.concat([
    Buffer.from([0xff, 0xd8, 0xff]),
    Buffer.from("PRIVATE_IMAGE_BYTES"),
    Buffer.from([0xff, 0xd9]),
  ]).toString("base64");
  const app = createGatewayApp({
    gatewayToken: "PRIVATE_GATEWAY_TOKEN",
    requestID: () => "60000000-0000-4000-8000-000000000001",
    logger: (record) => logs.push(record),
    proposalService: {
      propose: async () => ({ status: "needs_clarification" }),
    },
    realtimeService: {
      mint: async () => ({
        value: "ek_PRIVATE_EPHEMERAL_VALUE",
        expires_at: 1_753_000_600,
        url: "wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1",
        model: "gpt-realtime-2.1",
      }),
    },
  });

  const proposalResponse = await app.request("/v1/proposals", {
    method: "POST",
    headers: {
      authorization: "Bearer PRIVATE_GATEWAY_TOKEN",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      ...validProposalRequest,
      ingress_source: "vision",
      prompt: "PRIVATE_PROMPT_TEXT",
      image_data_url: `data:image/jpeg;base64,${secretImage}`,
    }),
  });
  assert.equal(
    proposalResponse.headers.get("x-request-id"),
    "60000000-0000-4000-8000-000000000001",
  );
  await proposalResponse.json();
  const secretResponse = await app.request("/v1/realtime/client-secret", {
    method: "POST",
    headers: {
      authorization: "Bearer PRIVATE_GATEWAY_TOKEN",
      "content-type": "application/json",
    },
    body: "{}",
  });
  await secretResponse.json();
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(logs.length, 2);
  const serializedLogs = JSON.stringify(logs);
  assert.doesNotMatch(serializedLogs, /PRIVATE_GATEWAY_TOKEN/u);
  assert.doesNotMatch(serializedLogs, /PRIVATE_PROMPT_TEXT/u);
  assert.doesNotMatch(serializedLogs, /PRIVATE_IMAGE_BYTES/u);
  assert.doesNotMatch(serializedLogs, /PRIVATE_EPHEMERAL_VALUE/u);
  for (const record of logs) {
    assert.deepEqual(Object.keys(record as Record<string, unknown>).sort(), [
      "duration_ms",
      "method",
      "path",
      "request_id",
      "status",
    ]);
  }
});

test("an upstream deadline aborts work and returns a generic timeout", async () => {
  let observedAbort = false;
  const app = createGatewayApp({
    gatewayToken: "test-token",
    requestTimeoutMilliseconds: 5,
    proposalService: {
      propose: async (_request, signal) =>
        await new Promise((resolve, reject) => {
          const timer = setTimeout(() => resolve({ too_late: true }), 80);
          signal.addEventListener(
            "abort",
            () => {
              observedAbort = true;
              clearTimeout(timer);
              reject(new DOMException("aborted", "AbortError"));
            },
            { once: true },
          );
        }),
    },
  });

  const response = await app.request("/v1/proposals", {
    method: "POST",
    headers: {
      authorization: "Bearer test-token",
      "content-type": "application/json",
    },
    body: JSON.stringify(validProposalRequest),
  });

  assert.equal(response.status, 504);
  assert.deepEqual(await response.json(), { error: "upstream_timeout" });
  assert.equal(observedAbort, true);
});

test("upstream failures expose no provider details", async () => {
  const app = createGatewayApp({
    gatewayToken: "test-token",
    proposalService: {
      propose: async () => {
        throw new Error("sk-private upstream prompt and response");
      },
    },
  });

  const response = await app.request("/v1/proposals", {
    method: "POST",
    headers: {
      authorization: "Bearer test-token",
      "content-type": "application/json",
    },
    body: JSON.stringify(validProposalRequest),
  });

  assert.equal(response.status, 502);
  const publicBody = JSON.stringify(await response.json());
  assert.equal(publicBody, '{"error":"upstream_failure"}');
  assert.doesNotMatch(publicBody, /private|prompt|response/iu);
});

test("protected routes have a bounded process-local admission rate", async () => {
  let now = 1_000;
  const app = createGatewayApp({
    gatewayToken: "test-token",
    protectedRequestsPerMinute: 2,
    nowMilliseconds: () => now,
  });
  const request = () =>
    app.request("/v1/proposals", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "{}",
    });

  assert.equal((await request()).status, 401);
  assert.equal((await request()).status, 401);
  const limited = await request();
  assert.equal(limited.status, 429);
  assert.equal(limited.headers.get("retry-after"), "60");
  assert.deepEqual(await limited.json(), { error: "rate_limited" });

  now += 60_000;
  assert.equal((await request()).status, 401);
});
