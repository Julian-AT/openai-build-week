import { test } from "bun:test";
import assert from "node:assert/strict";
import { validateAssetDerivatives, validateUSDZ } from "../src/index.ts";

const glb = minimalGLB();
const usdz = minimalUSDZ();

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

test("rejects GLBs whose declared binary length does not match their bytes", () => {
  const malformed = minimalGLB();
  new DataView(malformed.buffer).setUint32(8, malformed.byteLength + 4, true);
  assert.throws(
    () =>
      validateAssetDerivatives(
        { glb: malformed },
        {
          glbURL: "https://example.invalid/a.glb",
          units: "meters",
          origin: "floor",
          dimensionsM: { width: 1, height: 1, depth: 1 },
          collision: "aabb",
        },
      ),
    /invalid_glb_length/,
  );
});

test("rejects GLBs that try to resolve an external resource", () => {
  const json = JSON.stringify({ buffers: [{ byteLength: 0, uri: "file:///etc/passwd" }] });
  assert.throws(
    () =>
      validateAssetDerivatives(
        { glb: glbWithJSON(json) },
        {
          glbURL: "https://example.invalid/a.glb",
          units: "meters",
          origin: "floor",
          dimensionsM: { width: 1, height: 1, depth: 1 },
          collision: "aabb",
        },
      ),
    /external_glb_resource/,
  );
});

test("rejects a truncated ZIP signature masquerading as USDZ", () => {
  assert.throws(
    () => validateUSDZ(new Uint8Array([0x50, 0x4b, 0x03, 0x04])),
    /invalid_usdz_container/,
  );
});

function minimalGLB(): Uint8Array {
  const bytes = new Uint8Array(24);
  bytes.set([0x67, 0x6c, 0x54, 0x46]);
  const view = new DataView(bytes.buffer);
  view.setUint32(4, 2, true);
  view.setUint32(8, bytes.byteLength, true);
  view.setUint32(12, 4, true);
  view.setUint32(16, 0x4e4f534a, true);
  bytes.set([0x7b, 0x7d, 0x20, 0x20], 20);
  return bytes;
}

function glbWithJSON(json: string): Uint8Array {
  const encoded = new TextEncoder().encode(json);
  const paddedLength = Math.ceil(encoded.byteLength / 4) * 4;
  const bytes = new Uint8Array(20 + paddedLength);
  bytes.set([0x67, 0x6c, 0x54, 0x46]);
  const view = new DataView(bytes.buffer);
  view.setUint32(4, 2, true);
  view.setUint32(8, bytes.byteLength, true);
  view.setUint32(12, paddedLength, true);
  view.setUint32(16, 0x4e4f534a, true);
  bytes.set(encoded, 20);
  bytes.fill(0x20, 20 + encoded.byteLength);
  return bytes;
}

function minimalUSDZ(): Uint8Array {
  const name = new TextEncoder().encode("scene.usdc");
  const localLength = 30 + name.byteLength;
  const centralLength = 46 + name.byteLength;
  const bytes = new Uint8Array(localLength + centralLength + 22);
  const view = new DataView(bytes.buffer);
  view.setUint32(0, 0x04034b50, true);
  view.setUint16(4, 20, true);
  view.setUint16(26, name.byteLength, true);
  bytes.set(name, 30);

  const central = localLength;
  view.setUint32(central, 0x02014b50, true);
  view.setUint16(central + 4, 20, true);
  view.setUint16(central + 6, 20, true);
  view.setUint16(central + 28, name.byteLength, true);
  bytes.set(name, central + 46);

  const end = central + centralLength;
  view.setUint32(end, 0x06054b50, true);
  view.setUint16(end + 8, 1, true);
  view.setUint16(end + 10, 1, true);
  view.setUint32(end + 12, centralLength, true);
  view.setUint32(end + 16, localLength, true);
  return bytes;
}
