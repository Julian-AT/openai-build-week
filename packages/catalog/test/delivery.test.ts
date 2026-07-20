import { test } from "bun:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";

import {
  type CatalogAssetRecord,
  type LocalAssetCache,
  resolveLocalAssetDelivery,
} from "../src/index.ts";

test("delivery returns verified local bytes without source or storage URLs", async () => {
  const body = new TextEncoder().encode("validated-glb");
  const asset = readyAsset(body);
  const reads: unknown[] = [];
  const cache: LocalAssetCache = {
    read: async (request) => {
      reads.push(request);
      return {
        bytes: body,
        sha256: asset.derivatives.glb.sha256,
        byteLength: body.byteLength,
      };
    },
  };

  const delivery = await resolveLocalAssetDelivery(
    {
      asset,
      cacheProfile: "ios-primary",
      derivative: "glb",
    },
    cache,
  );

  assert.deepEqual(reads, [
    {
      assetID: "ikea-us-00000001-v1",
      cacheProfile: "ios-primary",
      derivative: "glb",
    },
  ]);
  assert.deepEqual(delivery, {
    assetID: "ikea-us-00000001-v1",
    cacheProfile: "ios-primary",
    derivative: "glb",
    mediaType: "model/gltf-binary",
    sha256: asset.derivatives.glb.sha256,
    byteLength: body.byteLength,
    bytes: body,
  });
  assert.equal(JSON.stringify(delivery).includes("https://"), false);
  assert.equal("url" in delivery, false);
  assert.equal("storageKey" in delivery, false);
});

test("delivery fails closed for uncached, unauthorized, and corrupted assets", async () => {
  const body = new TextEncoder().encode("validated-glb");
  const asset = readyAsset(body);
  let reads = 0;
  const missingCache: LocalAssetCache = {
    read: async () => {
      reads += 1;
      return undefined;
    },
  };

  await assert.rejects(
    resolveLocalAssetDelivery(
      { asset, cacheProfile: "web-primary", derivative: "glb" },
      missingCache,
    ),
    /asset_not_cached/,
  );
  asset.authorization.status = "unverified";
  await assert.rejects(
    resolveLocalAssetDelivery(
      { asset, cacheProfile: "ios-primary", derivative: "glb" },
      missingCache,
    ),
    /asset_not_injection_ready/,
  );
  assert.equal(reads, 1);

  const validAsset = readyAsset(body);
  await assert.rejects(
    resolveLocalAssetDelivery(
      { asset: validAsset, cacheProfile: "ios-primary", derivative: "glb" },
      {
        read: async () => ({
          bytes: new TextEncoder().encode("tampered-data"),
          sha256: validAsset.derivatives.glb.sha256,
          byteLength: body.byteLength,
        }),
      },
    ),
    /cached_asset_hash_mismatch/,
  );
});

function readyAsset(body: Uint8Array): CatalogAssetRecord {
  const sha256 = createHash("sha256").update(body).digest("hex");
  const derivative = {
    storageKey: `sha256/${sha256}`,
    sha256,
    byteLength: body.byteLength,
    validated: true,
  };
  return {
    assetID: "ikea-us-00000001-v1",
    authorization: { status: "authorized", reference: "ikea-model-terms" },
    category: "side_table",
    dimensionsM: { width: 0.55, height: 0.5, depth: 0.55 },
    supportType: "floor",
    normalization: {
      units: "meters",
      origin: "floor-contact-center",
      forwardAxis: "+z",
    },
    derivatives: {
      glb: { ...derivative },
      usdz: { ...derivative },
      collision: { ...derivative, representation: "convex_hull" },
    },
    cacheProfiles: ["ios-primary", "web-primary"],
  };
}
