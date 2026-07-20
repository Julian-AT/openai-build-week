import { test } from "bun:test";
import assert from "node:assert/strict";
import { validateAssetDerivatives } from "../src/index.ts";

const glb = new Uint8Array(20);
glb.set([0x67, 0x6c, 0x54, 0x46, 2]);
const usdz = new Uint8Array([0x50, 0x4b, 0x03, 0x04]);

test("validates derivatives and produces stable hashes", () => {
  const manifest = validateAssetDerivatives(
    { glb, usdz },
    {
      glbURL: "https://web-api.ikea.com/chair.glb",
      usdzURL: "https://web-api.ikea.com/chair.usdz",
      units: "meters",
      origin: "floor",
      dimensionsM: { width: 0.6, height: 0.9, depth: 0.6 },
      collision: "convex_hull",
    },
  );
  assert.match(manifest.glbSHA256, /^[a-f0-9]{64}$/u);
  assert.match(manifest.usdzSHA256 ?? "", /^[a-f0-9]{64}$/u);
});

test("rejects malformed or implausible assets", () => {
  assert.throws(
    () =>
      validateAssetDerivatives(
        { glb: new Uint8Array(20) },
        {
          glbURL: "https://example.invalid/a.glb",
          units: "meters",
          origin: "floor",
          dimensionsM: { width: 0, height: 1, depth: 1 },
          collision: "aabb",
        },
      ),
    /invalid_glb_header/,
  );
});
