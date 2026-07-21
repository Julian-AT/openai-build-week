import { test } from "bun:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";

import {
  createInferenceWorkerClient,
  createInferenceWorkerClientFromEnvironment,
  InferenceWorkerError,
} from "../src/inference-client.ts";
import type { InferenceJobRequest } from "../src/inference-protocol.ts";

const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xd9]);
const request: InferenceJobRequest = {
  protocol_version: "1.0.0",
  request_id: "inference_00000000-0000-4000-8000-000000000001",
  task: "segment",
  image: {
    frame_id: "frame_00000000-0000-4000-8000-000000000001",
    media_type: "image/jpeg",
    data_base64: jpeg.toString("base64"),
    sha256: createHash("sha256").update(jpeg).digest("hex"),
    width: 1,
    height: 1,
  },
  prompt: { kind: "point", x: 0, y: 0, label: "foreground" },
};

const metricDepthRequest: InferenceJobRequest = {
  protocol_version: "1.0.0",
  request_id: "inference_00000000-0000-4000-8000-000000000002",
  task: "metric_depth",
  image: request.image,
  intrinsics_encoded_pixels: {
    fx: 1,
    fy: 1,
    cx: 0.5,
    cy: 0.5,
    width: 1,
    height: 1,
    units: "encoded_pixels",
  },
};

const reconstructionRequest: InferenceJobRequest = {
  protocol_version: "1.0.0",
  request_id: "inference_00000000-0000-4000-8000-000000000003",
  task: "reconstruct",
  archive_sha256: "0".repeat(64),
  frame_ids: [
    "frame_00000000-0000-4000-8000-000000000001",
    "frame_00000000-0000-4000-8000-000000000002",
  ],
};

const readiness = {
  protocol_version: "1.0.0",
  status: "disabled",
  provider: {
    provider_id: "disabled",
    provider_revision: "none",
    evidence_class: "unmeasured",
  },
  tasks: { segment: false, metric_depth: false, reconstruct: false },
  torch: { installed: false, version: null, mps_available: false },
} as const;

test("worker client accepts only private-safe origins and a bounded token", () => {
  assert.doesNotThrow(() =>
    createInferenceWorkerClient({
      baseURL: "http://host.docker.internal:8790",
      token: "secret",
    }),
  );
  assert.throws(() =>
    createInferenceWorkerClient({ baseURL: "http://worker.example.com", token: "secret" }),
  );
  assert.throws(() =>
    createInferenceWorkerClient({ baseURL: "http://127.0.0.1:8790/private", token: "secret" }),
  );
  assert.throws(() => createInferenceWorkerClient({ baseURL: "http://127.0.0.1:8790", token: "" }));
});

test("worker environment configuration is either complete or disabled", () => {
  assert.equal(createInferenceWorkerClientFromEnvironment({}), undefined);
  assert.throws(() =>
    createInferenceWorkerClientFromEnvironment({
      REFRAME_VISION_URL: "http://127.0.0.1:8790",
    }),
  );
  assert.throws(() =>
    createInferenceWorkerClientFromEnvironment({
      REFRAME_VISION_TOKEN: "internal-worker-token",
    }),
  );
  assert.notEqual(
    createInferenceWorkerClientFromEnvironment({
      REFRAME_VISION_URL: "http://127.0.0.1:8790",
      REFRAME_VISION_TOKEN: "internal-worker-token",
    }),
    undefined,
  );
});

test("worker client keeps its private token internal and validates readiness", async () => {
  let observed: Request | undefined;
  const client = createInferenceWorkerClient({
    baseURL: "http://127.0.0.1:8790",
    token: "internal-worker-token",
    fetch: async (input, init) => {
      observed = new Request(input, init);
      return Response.json(readiness);
    },
  });

  const result = await client.readiness(new AbortController().signal);
  assert.deepEqual(result, readiness);
  assert.equal(observed?.url, "http://127.0.0.1:8790/readyz");
  assert.equal(observed?.method, "GET");
  assert.equal(observed?.headers.get("authorization"), "Bearer internal-worker-token");
});

test("worker job responses are request-bound and cancellation is forwarded", async () => {
  const controller = new AbortController();
  let observed: Request | undefined;
  const mask = Buffer.from([1]);
  const client = createInferenceWorkerClient({
    baseURL: "https://private-worker.example",
    token: "internal-worker-token",
    fetch: async (input, init) => {
      observed = new Request(input, init);
      return Response.json({
        protocol_version: "1.0.0",
        request_id: request.request_id,
        task: "segment",
        provider: {
          provider_id: "sam3",
          provider_revision: "unmeasured-local",
          evidence_class: "unmeasured",
        },
        result: {
          kind: "mask",
          width: 1,
          height: 1,
          encoding: "binary_rle",
          counts: [0, 1],
          foreground_pixels: 1,
          sha256: createHash("sha256").update(mask).digest("hex"),
        },
      });
    },
  });

  const result = await client.run(request, controller.signal);
  assert.equal(result.request_id, request.request_id);
  assert.equal(observed?.url, "https://private-worker.example/v1/jobs");
  assert.equal(observed?.headers.get("content-type"), "application/json");
  assert.equal(observed?.signal.aborted, false);
  assert.deepEqual(await observed?.json(), {
    ...request,
    session_id: `worker_${request.request_id}`,
    target_id: "target_0",
    frame_index: 0,
  });
});

test("worker client uses the gateway GPU priority lane before dispatching private jobs", async () => {
  const started: string[] = [];
  let releaseBackground: (() => void) | undefined;
  const client = createInferenceWorkerClient({
    baseURL: "http://127.0.0.1:8790",
    token: "internal-worker-token",
    fetch: async (input, init) => {
      const submitted = (await new Request(input, init).json()) as InferenceJobRequest;
      started.push(submitted.task);
      if (submitted.task === "reconstruct") {
        await new Promise<void>((resolve) => {
          releaseBackground = resolve;
        });
      }
      return Response.json(responseFor(submitted));
    },
  });

  const background = client.run(reconstructionRequest, new AbortController().signal);
  await eventually(() => started.length === 1);
  const depth = client.run(metricDepthRequest, new AbortController().signal);
  const target = client.run(request, new AbortController().signal);

  releaseBackground?.();
  await Promise.all([background, target, depth]);
  assert.deepEqual(started, ["reconstruct", "segment", "metric_depth"]);
});

test("worker client bounds responses and hides upstream error bodies", async () => {
  const oversized = createInferenceWorkerClient({
    baseURL: "http://localhost:8790",
    token: "internal-worker-token",
    fetch: async () =>
      new Response("{}", {
        headers: { "content-length": "12000001", "content-type": "application/json" },
      }),
  });
  await assert.rejects(
    () => oversized.run(request, new AbortController().signal),
    (error: unknown) =>
      error instanceof InferenceWorkerError && error.publicCode === "upstream_failure",
  );

  const failed = createInferenceWorkerClient({
    baseURL: "http://[::1]:8790",
    token: "internal-worker-token",
    fetch: async () => Response.json({ error: "PRIVATE_WORKER_DETAIL" }, { status: 503 }),
  });
  await assert.rejects(
    () => failed.run(request, new AbortController().signal),
    (error: unknown) =>
      error instanceof InferenceWorkerError &&
      error.status === 503 &&
      error.publicCode === "service_unavailable" &&
      !error.message.includes("PRIVATE_WORKER_DETAIL"),
  );

  const timedOut = createInferenceWorkerClient({
    baseURL: "http://127.0.0.1:8790",
    token: "internal-worker-token",
    fetch: async () => Response.json({ error: "worker_timeout" }, { status: 504 }),
  });
  await assert.rejects(
    () => timedOut.run(request, new AbortController().signal),
    (error: unknown) =>
      error instanceof InferenceWorkerError &&
      error.status === 504 &&
      error.publicCode === "upstream_timeout",
  );
});

function responseFor(submitted: InferenceJobRequest): object {
  const provider = {
    provider_id: "sam3",
    provider_revision: "unmeasured-local",
    evidence_class: "unmeasured",
  } as const;
  if (submitted.task === "segment") {
    const mask = Buffer.from([1]);
    return {
      protocol_version: "1.0.0",
      request_id: submitted.request_id,
      task: submitted.task,
      provider,
      result: {
        kind: "mask",
        width: 1,
        height: 1,
        encoding: "binary_rle",
        counts: [0, 1],
        foreground_pixels: 1,
        sha256: createHash("sha256").update(mask).digest("hex"),
      },
    };
  }
  if (submitted.task === "metric_depth") {
    const depth = Buffer.alloc(4);
    return {
      protocol_version: "1.0.0",
      request_id: submitted.request_id,
      task: submitted.task,
      provider,
      result: {
        kind: "metric_depth",
        width: 1,
        height: 1,
        encoding: "float32_le_base64",
        unit: "metre",
        data_base64: depth.toString("base64"),
        sha256: createHash("sha256").update(depth).digest("hex"),
      },
    };
  }
  const pointCloud = Buffer.from("ply\nformat binary_little_endian 1.0\n");
  return {
    protocol_version: "1.0.0",
    request_id: submitted.request_id,
    task: submitted.task,
    provider,
    result: {
      kind: "point_cloud",
      encoding: "ply_binary_little_endian",
      data_base64: pointCloud.toString("base64"),
      sha256: createHash("sha256").update(pointCloud).digest("hex"),
    },
  };
}

async function eventually(predicate: () => boolean): Promise<void> {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  assert.fail("condition was not reached");
}
