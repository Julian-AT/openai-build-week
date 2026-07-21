import type { Database } from "bun:sqlite";
import { test } from "bun:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { type DurableRoomSessionStore, RoomCredentialError } from "../src/durable-session-store.ts";
import { InferenceWorkerError } from "../src/inference-client.ts";
import type { InferenceJobRequest } from "../src/inference-protocol.ts";
import { createGatewayApp } from "../src/server.ts";

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

test("health is public while private readiness is scoped", async () => {
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
      readiness: async () => expected,
      run: async () => {
        throw new Error("must not run");
      },
    },
  });

  const health = await app.request("/health");
  assert.equal(health.status, 200);
  assert.deepEqual(await health.json(), { status: "ok" });
  assert.equal((await app.request("/v1/inference/status")).status, 401);
  const readiness = await app.request("/v1/inference/status", {
    headers: { authorization: "Bearer test-token" },
  });
  assert.equal(readiness.status, 200);
  assert.deepEqual(await readiness.json(), expected);
});

test("public health identifies a degraded local catalog runtime without leaking paths", async () => {
  const app = createGatewayApp({
    gatewayToken: "test-token",
    runtimeReadiness: {
      snapshot: async () => ({
        status: "degraded" as const,
        dependencies: {
          gateway: { status: "ready" as const },
          catalog_store: { status: "ready" as const },
          asset_storage: { status: "ready" as const },
          qdrant: { status: "unavailable" as const },
        },
      }),
    },
  });

  const response = await app.request("/health");

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    status: "degraded",
    dependencies: {
      gateway: { status: "ready" },
      catalog_store: { status: "ready" },
      asset_storage: { status: "ready" },
      qdrant: { status: "unavailable" },
    },
  });
});

test("typed inference jobs are request-bound and private failures stay closed", async () => {
  let received: unknown;
  const mask = Buffer.from([1]);
  const expected = {
    protocol_version: "1.0.0" as const,
    request_id: validInferenceRequest.request_id,
    task: "segment" as const,
    provider: {
      provider_id: "sam3",
      provider_revision: "unmeasured-local",
      evidence_class: "unmeasured" as const,
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
  const rejected = await busy.request("/v1/inference/jobs", {
    method: "POST",
    headers: {
      authorization: "Bearer test-token",
      "content-type": "application/json",
    },
    body: JSON.stringify(validInferenceRequest),
  });
  assert.equal(rejected.status, 429);
  assert.deepEqual(await rejected.json(), { error: "worker_busy" });
});

test("Realtime exchanges SDP without exposing the server credential", async () => {
  let receivedOffer: string | undefined;
  const app = createGatewayApp({
    gatewayToken: "test-token",
    realtimeService: {
      exchange: async (offer) => {
        receivedOffer = offer;
        return "answer-sdp";
      },
    },
  });
  const response = await app.request("/v1/realtime/calls", {
    method: "POST",
    headers: {
      authorization: "Bearer test-token",
      "content-type": "application/sdp",
    },
    body: "offer-sdp",
  });

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "application/sdp; charset=UTF-8");
  assert.equal(await response.text(), "answer-sdp");
  assert.equal(receivedOffer, "offer-sdp");
});

test("Realtime accepts a valid room credential without exposing the gateway credential", async () => {
  let receivedCredential: string | undefined;
  const app = createGatewayApp({
    gatewayToken: "gateway-token",
    durableSessionStore: {
      withAuthorizedScene: async (
        credential: string,
        operation: (sessionID: string, database: Database) => unknown,
      ) => {
        receivedCredential = credential;
        return await operation("room_demo", {} as Database);
      },
    } as unknown as DurableRoomSessionStore,
    realtimeService: {
      exchange: async (offer) => `answer-for-${offer}`,
    },
  });
  const response = await app.request("/v1/realtime/calls", {
    method: "POST",
    headers: {
      authorization: "Bearer room-scoped-token",
      "content-type": "application/sdp",
    },
    body: "offer-sdp",
  });

  assert.equal(response.status, 200);
  assert.equal(await response.text(), "answer-for-offer-sdp");
  assert.equal(receivedCredential, "room-scoped-token");
});

test("Realtime rejects a room credential when the authoritative scene store rejects it", async () => {
  const app = createGatewayApp({
    gatewayToken: "gateway-token",
    durableSessionStore: {
      withAuthorizedScene: async () => {
        throw new RoomCredentialError();
      },
    } as unknown as DurableRoomSessionStore,
    realtimeService: { exchange: async () => "must-not-run" },
  });
  const response = await app.request("/v1/realtime/calls", {
    method: "POST",
    headers: {
      authorization: "Bearer room-scoped-token",
      "content-type": "application/sdp",
    },
    body: "offer-sdp",
  });

  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: "unauthorized" });
});

test("the legacy one-shot proposal surface is absent", async () => {
  const app = createGatewayApp({ gatewayToken: "test-token" });
  const response = await app.request("/v1/proposals", { method: "POST" });
  assert.equal(response.status, 404);
  assert.deepEqual(await response.json(), { error: "not_found" });
});

test("known methods and query-free routes fail closed", async () => {
  let calls = 0;
  const app = createGatewayApp({
    gatewayToken: "test-token",
    realtimeService: {
      exchange: async () => {
        calls += 1;
        return "answer";
      },
    },
  });
  const wrongMethod = await app.request("/v1/realtime/calls");
  assert.equal(wrongMethod.status, 405);
  assert.equal(wrongMethod.headers.get("allow"), "POST");
  const decorated = await app.request("/v1/realtime/calls?unsafe=true", {
    method: "POST",
    headers: {
      authorization: "Bearer test-token",
      "content-type": "application/sdp",
    },
    body: "offer",
  });
  assert.equal(decorated.status, 404);
  assert.equal(calls, 0);
});

test("request logs exclude credentials and SDP bodies", async () => {
  const logs: unknown[] = [];
  const app = createGatewayApp({
    gatewayToken: "PRIVATE_GATEWAY_TOKEN",
    requestID: () => "60000000-0000-4000-8000-000000000001",
    logger: (record) => logs.push(record),
    realtimeService: { exchange: async () => "PRIVATE_ANSWER_SDP" },
  });
  const response = await app.request("/v1/realtime/calls", {
    method: "POST",
    headers: {
      authorization: "Bearer PRIVATE_GATEWAY_TOKEN",
      "content-type": "application/sdp",
    },
    body: "PRIVATE_OFFER_SDP",
  });
  await response.text();

  assert.equal(logs.length, 1);
  const serialized = JSON.stringify(logs);
  assert.doesNotMatch(serialized, /PRIVATE_GATEWAY_TOKEN|PRIVATE_(?:OFFER|ANSWER)_SDP/u);
  assert.deepEqual(Object.keys(logs[0] as Record<string, unknown>).sort(), [
    "duration_ms",
    "method",
    "path",
    "request_id",
    "status",
  ]);
});

test("deadlines cancel upstream work and provider failures are redacted", async () => {
  let observedAbort = false;
  const timeoutApp = createGatewayApp({
    gatewayToken: "test-token",
    requestTimeoutMilliseconds: 5,
    realtimeService: {
      exchange: async (_offer, signal) =>
        await new Promise((resolve, reject) => {
          const timer = setTimeout(() => resolve("too-late"), 80);
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
  const timedOut = await realtimeRequest(timeoutApp);
  assert.equal(timedOut.status, 504);
  assert.deepEqual(await timedOut.json(), { error: "upstream_timeout" });
  assert.equal(observedAbort, true);

  const failedApp = createGatewayApp({
    gatewayToken: "test-token",
    realtimeService: {
      exchange: async () => {
        throw new Error("sk-private upstream response");
      },
    },
  });
  const failed = await realtimeRequest(failedApp);
  assert.equal(failed.status, 502);
  assert.deepEqual(await failed.json(), { error: "upstream_failure" });
});

test("protected routes use a bounded process-local admission budget", async () => {
  let now = 1_000;
  const app = createGatewayApp({
    gatewayToken: "test-token",
    protectedRequestsPerMinute: 2,
    nowMilliseconds: () => now,
  });
  const request = () => app.request("/v1/realtime/calls", { method: "POST" });

  assert.equal((await request()).status, 401);
  assert.equal((await request()).status, 401);
  const limited = await request();
  assert.equal(limited.status, 429);
  assert.equal(limited.headers.get("retry-after"), "60");
  now += 60_000;
  assert.equal((await request()).status, 401);
});

function realtimeRequest(app: ReturnType<typeof createGatewayApp>): Promise<Response> {
  return Promise.resolve(
    app.request("/v1/realtime/calls", {
      method: "POST",
      headers: {
        authorization: "Bearer test-token",
        "content-type": "application/sdp",
      },
      body: "offer-sdp",
    }),
  );
}
