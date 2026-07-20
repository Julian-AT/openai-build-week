import { test } from "bun:test";
import assert from "node:assert/strict";

import { assessAssetInjectionReadiness, type CatalogAssetRecord } from "../src/index.ts";

function readyAsset(): CatalogAssetRecord {
  return {
    assetID: "ikea-us-00000001-v1",
    authorization: {
      status: "authorized",
      reference: "ikea-us-public-product-model",
    },
    category: "side_table",
    dimensionsM: { width: 0.55, height: 0.5, depth: 0.55 },
    supportType: "floor",
    normalization: {
      units: "meters",
      origin: "floor-contact-center",
      forwardAxis: "+z",
    },
    derivatives: {
      glb: derivative("glb"),
      usdz: derivative("usdz"),
      collision: { ...derivative("collision"), representation: "convex_hull" },
    },
    cacheProfiles: ["ios-primary", "web-primary"],
  };
}

function derivative(kind: string) {
  const sha256 = "a".repeat(64);
  return {
    storageKey: `sha256/${sha256}/${kind}`,
    sha256,
    byteLength: 1_024,
    validated: true as const,
  };
}

test("an authorized normalized asset with every validated derivative is injectable", () => {
  assert.deepEqual(assessAssetInjectionReadiness(readyAsset()), {
    ready: true,
    failures: [],
  });
});

test("injection readiness fails closed and reports every missing requirement", () => {
  const asset = readyAsset();
  asset.authorization.status = "unverified";
  asset.normalization.origin = "center" as never;
  asset.derivatives.usdz.validated = false as never;
  asset.derivatives.collision.storageKey = "https://example.invalid/hull.bin";

  assert.deepEqual(assessAssetInjectionReadiness(asset), {
    ready: false,
    failures: [
      "authorization_not_verified",
      "normalization_invalid",
      "usdz_derivative_invalid",
      "collision_derivative_invalid",
    ],
  });
});
