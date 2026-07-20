import { test } from "bun:test";
import assert from "node:assert/strict";

import {
  C_ARKIT_FROM_OPENCV_ROW_MAJOR,
  canonicalJSONSHA256,
  canonicalJSONStringify,
  projectEncodedPixelToOpenCVRay,
  worldFromCameraOpenCV,
} from "../src/index.ts";

test("canonical JSON has a stable digest independent of source key order", () => {
  const left = { session_id: "room_01", nested: { z: 1, a: [true, "x"] } };
  const right = { nested: { a: [true, "x"], z: 1 }, session_id: "room_01" };

  assert.equal(
    canonicalJSONStringify(left),
    '{"nested":{"a":[true,"x"],"z":1},"session_id":"room_01"}',
  );
  assert.equal(canonicalJSONSHA256(left), canonicalJSONSHA256(right));
  assert.throws(
    () => canonicalJSONStringify({ unsupported: Number.NaN }),
    /invalid_canonical_json/,
  );
});

test("ARKit/OpenCV transforms and encoded-intrinsic rays follow RF-COORD-1", () => {
  const arkit = [1, 0, 0, 1.42, 0, 1, 0, 1.53, 0, 0, 1, -2.18, 0, 0, 0, 1];
  assert.deepEqual(
    C_ARKIT_FROM_OPENCV_ROW_MAJOR,
    [1, 0, 0, 0, 0, -1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1],
  );
  assert.deepEqual(
    worldFromCameraOpenCV(arkit),
    [1, 0, 0, 1.42, 0, -1, 0, 1.53, 0, 0, -1, -2.18, 0, 0, 0, 1],
  );
  assert.deepEqual(
    projectEncodedPixelToOpenCVRay({ fx: 500, fy: 500, cx: 320, cy: 240 }, 320, 240),
    [0, 0, 1],
  );
  const ray = projectEncodedPixelToOpenCVRay({ fx: 500, fy: 500, cx: 320, cy: 240 }, 820, 240);
  assert.ok(Math.abs(ray[0] - Math.SQRT1_2) < 1e-12);
  assert.ok(Math.abs(ray[2] - Math.SQRT1_2) < 1e-12);
});
