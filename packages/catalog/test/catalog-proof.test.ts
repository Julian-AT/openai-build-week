import { test } from "bun:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";

import {
  type CatalogProduct,
  type LocalAssetCache,
  type PreparedCatalogAssetRecord,
  provePreparedCatalogAsset,
  SEMANTIC_VECTOR_SIZE,
} from "../src/index.ts";

test("binds untrusted enrichment to prepared source facts before indexing, retrieval, and hash-verified delivery", async () => {
  const bytes = new TextEncoder().encode("validated delivery GLB");
  const prepared = preparedRecord(bytes);
  const indexed: CatalogProduct[] = [];
  const result = await provePreparedCatalogAsset({
    product: product(),
    prepared,
    enricher: {
      enrich: async (candidate) => ({
        ...candidate,
        name: "model must not replace source facts",
        visualDescriptor: "light oak Scandinavian side table",
        textVector: vector(0.1),
      }),
    },
    store: {
      prepare: async (size) => {
        assert.equal(size, SEMANTIC_VECTOR_SIZE);
      },
      upsert: async (products) => {
        indexed.push(...products);
      },
      search: async () => [
        {
          id: "ikea-us-40541421",
          assetID: prepared.asset.assetID,
          score: 0.99,
          name: "HOLMERUD Side table",
          category: "side_table",
          dimensionsM: prepared.asset.dimensionsM,
          supportType: "floor",
          cacheProfile: "ios-primary",
        },
      ],
    },
    vectorizer: { embed: async () => vector(0.2) },
    cache: cache(bytes, prepared.asset.derivatives.glb.sha256),
    query: "light oak side table",
    cacheProfile: "ios-primary",
    maxDimensionsM: { width: 0.9, height: 0.6, depth: 0.4 },
  });

  assert.equal(indexed.length, 1);
  assert.equal(indexed[0]?.name, "HOLMERUD Side table");
  assert.equal(indexed[0]?.preparedAsset?.assetID, prepared.asset.assetID);
  assert.equal(result.hit.assetID, prepared.asset.assetID);
  assert.equal(result.delivery.sha256, prepared.asset.derivatives.glb.sha256);
  assert.deepEqual(result.delivery.bytes, bytes);
});

function product(): CatalogProduct {
  return {
    id: "ikea-us-40541421",
    source: "ikea-us",
    sourceProductID: "40541421",
    locale: "en-US",
    name: "HOLMERUD Side table",
    description: "Oak effect side table",
    productURL: "https://www.ikea.com/us/en/p/holmerud-side-table-oak-effect-40541421/",
    imageURLs: ["https://www.ikea.com/us/en/images/products/holmerud.jpg"],
    assetURLs: ["https://web-api.ikea.com/model.glb"],
    searchableText: "HOLMERUD Side table. Oak effect side table.",
  };
}

function preparedRecord(bytes: Uint8Array): PreparedCatalogAssetRecord {
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  const derivative = {
    storageKey: `sha256/${sha256}`,
    sha256,
    byteLength: bytes.byteLength,
    validated: true,
  };
  return {
    asset: {
      assetID: "ikea-us-40541421-d74d34f0a861",
      authorization: { status: "authorized", reference: "operator-authorized-2026-07-20" },
      category: "side_table",
      dimensionsM: { width: 0.805, height: 0.523, depth: 0.307 },
      supportType: "floor",
      normalization: { units: "meters", origin: "floor-contact-center", forwardAxis: "+z" },
      derivatives: {
        glb: derivative,
        usdz: derivative,
        collision: { ...derivative, representation: "aabb" },
      },
      cacheProfiles: ["ios-primary"],
    },
    preview: { ...derivative, mediaType: "image/png", width: 512, height: 512 },
    source: { storageKey: `sha256/${"a".repeat(64)}`, sha256: "a".repeat(64), byteLength: 1 },
    processor: { revision: "blender-5.2.0", configurationDigest: "b".repeat(64) },
    derivationID: "c".repeat(64),
  };
}

function cache(bytes: Uint8Array, sha256: string): LocalAssetCache {
  return {
    read: async () => ({ bytes, sha256, byteLength: bytes.byteLength }),
  };
}

function vector(value: number): number[] {
  return Array.from({ length: SEMANTIC_VECTOR_SIZE }, () => value);
}
