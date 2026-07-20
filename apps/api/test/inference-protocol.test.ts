import { test } from "bun:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";

import {
  type InferenceJobRequest,
  parseInferenceJobRequest,
  parseInferenceJobResponse,
  parseWorkerReadiness,
} from "../src/inference-protocol.ts";

const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xd9]);
const requestID = "inference_00000000-0000-4000-8000-000000000001";
const image = {
  frame_id: "frame_00000000-0000-4000-8000-000000000001",
  media_type: "image/jpeg",
  data_base64: jpeg.toString("base64"),
  sha256: createHash("sha256").update(jpeg).digest("hex"),
  width: 1,
  height: 1,
} as const;
const segmentJob = {
  protocol_version: "1.0.0",
  request_id: requestID,
  task: "segment",
  image,
  prompt: { kind: "point", x: 0, y: 0, label: "foreground" },
} as const;

test("inference requests are exact, digest-bound, and prompt-bound", () => {
  assert.deepEqual(parseInferenceJobRequest(segmentJob), segmentJob);

  assert.throws(() =>
    parseInferenceJobRequest({
      ...segmentJob,
      image: { ...image, sha256: "0".repeat(64) },
    }),
  );
  assert.throws(() => parseInferenceJobRequest({ ...segmentJob, authority: "model" }));
  assert.throws(() =>
    parseInferenceJobRequest({
      ...segmentJob,
      prompt: { ...segmentJob.prompt, x: image.width },
    }),
  );
});

test("reconstruction requests require unique stable frame IDs", () => {
  assert.throws(() =>
    parseInferenceJobRequest({
      protocol_version: "1.0.0",
      request_id: requestID,
      task: "reconstruct",
      archive_sha256: "0".repeat(64),
      frame_ids: [image.frame_id, image.frame_id],
    }),
  );
});

test("worker readiness is closed and internally consistent", () => {
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
  assert.deepEqual(parseWorkerReadiness(readiness), readiness);
  assert.throws(() =>
    parseWorkerReadiness({
      ...readiness,
      torch: { installed: false, version: "2.13.0", mps_available: false },
    }),
  );
  assert.throws(() => parseWorkerReadiness({ ...readiness, queue_depth: 12 }));
});

test("inference responses bind request, task, RLE bytes, and provider evidence", () => {
  const mask = Buffer.from([1]);
  const response = {
    protocol_version: "1.0.0",
    request_id: requestID,
    task: "segment",
    provider: {
      provider_id: "fixture",
      provider_revision: "fixture-v1",
      evidence_class: "fixture_only",
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
  } as const;
  assert.deepEqual(
    parseInferenceJobResponse(response, segmentJob as InferenceJobRequest),
    response,
  );
  assert.throws(() =>
    parseInferenceJobResponse(
      { ...response, request_id: "inference_00000000-0000-4000-8000-000000000002" },
      segmentJob as InferenceJobRequest,
    ),
  );
  assert.throws(() =>
    parseInferenceJobResponse(
      { ...response, result: { ...response.result, sha256: "0".repeat(64) } },
      segmentJob as InferenceJobRequest,
    ),
  );
});
