import { test } from "bun:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";

import {
  type AssetPreparationContentStore,
  type CatalogAssetProcessor,
  prepareCatalogAsset,
} from "../src/index.ts";

test("prepares a normalized asset only after every derivative is validated and content-addressed", async () => {
  const commits: string[] = [];
  const source = minimalGLB();
  const sourceSHA256 = hash(source);
  const prepared = await prepareCatalogAsset({
    product: {
      id: "ikea-us-40541421",
      sourceProductID: "40541421",
      name: "HOLMERUD Side table",
    },
    source: {
      storageKey: `sha256/${sourceSHA256}`,
      sha256: sourceSHA256,
      bytes: source,
    },
    authorization: { status: "authorized", reference: "operator-authorized-2026-07-20" },
    category: "side_table",
    supportType: "floor",
    expectedDimensionsM: { width: 0.8, height: 0.52, depth: 0.31 },
    cacheProfiles: ["ios-primary", "web-primary"],
    processor: validProcessor(),
    processorRevision: "blender-5.2.0-fbe6228777e7",
    processorConfiguration: { collision: "aabb", preview: "png-512", units: "meters" },
    content: contentStore(commits),
  });

  assert.equal(prepared.asset.assetID, `ikea-us-40541421-${sourceSHA256.slice(0, 12)}`);
  assert.deepEqual(prepared.asset.normalization, {
    units: "meters",
    origin: "floor-contact-center",
    forwardAxis: "+z",
  });
  assert.deepEqual(prepared.asset.dimensionsM, { width: 0.8, height: 0.52, depth: 0.31 });
  assert.equal(prepared.asset.derivatives.collision.representation, "aabb");
  assert.equal(prepared.preview.mediaType, "image/png");
  assert.equal(commits.length, 4);
  assert.match(prepared.derivationID, /^[a-f0-9]{64}$/u);
});

test("rejects a processor output whose measured dimensions disagree with source facts", async () => {
  const processor = validProcessor({ dimensionsM: { width: 1.6, height: 0.52, depth: 0.31 } });
  const source = minimalGLB();
  const sourceSHA256 = hash(source);
  await assert.rejects(
    prepareCatalogAsset({
      product: { id: "ikea-us-40541421", sourceProductID: "40541421", name: "HOLMERUD" },
      source: {
        storageKey: `sha256/${sourceSHA256}`,
        sha256: sourceSHA256,
        bytes: source,
      },
      authorization: { status: "authorized", reference: "operator-authorized-2026-07-20" },
      category: "side_table",
      supportType: "floor",
      expectedDimensionsM: { width: 0.8, height: 0.52, depth: 0.31 },
      cacheProfiles: [],
      processor,
      processorRevision: "blender-5.2.0-fbe6228777e7",
      processorConfiguration: { collision: "aabb" },
      content: contentStore([]),
    }),
    /asset_dimension_mismatch/,
  );
});

function validProcessor(
  overrides: Partial<Awaited<ReturnType<CatalogAssetProcessor["process"]>>> = {},
): CatalogAssetProcessor {
  return {
    process: async () => ({
      glb: minimalGLB(),
      usdz: minimalUSDZ(),
      collision: differentGLB(),
      preview: png(),
      dimensionsM: { width: 0.8, height: 0.52, depth: 0.31 },
      ...overrides,
    }),
  };
}

function contentStore(commits: string[]): AssetPreparationContentStore {
  return {
    commitDerivative: async (request) => {
      commits.push(request.kind);
      return `sha256/${request.sha256}/${request.kind}`;
    },
  };
}

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

function differentGLB(): Uint8Array {
  const bytes = minimalGLB();
  bytes[23] = 0x0a;
  return bytes;
}

function png(): Uint8Array {
  return new Uint8Array([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x02, 0x00, 0x08, 0x02, 0x00, 0x00, 0x00,
  ]);
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
  view.setUint32(localLength, 0x02014b50, true);
  view.setUint16(localLength + 4, 20, true);
  view.setUint16(localLength + 6, 20, true);
  view.setUint16(localLength + 28, name.byteLength, true);
  bytes.set(name, localLength + 46);
  const end = localLength + centralLength;
  view.setUint32(end, 0x06054b50, true);
  view.setUint16(end + 8, 1, true);
  view.setUint16(end + 10, 1, true);
  view.setUint32(end + 12, centralLength, true);
  view.setUint32(end + 16, localLength, true);
  return bytes;
}

function hash(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}
