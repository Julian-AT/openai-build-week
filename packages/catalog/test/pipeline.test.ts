import { test } from "bun:test";
import assert from "node:assert/strict";

import { type CatalogProduct, syncCatalog } from "../src/index.ts";

const semanticVector = Array.from({ length: 1_024 }, (_, index) => index / 1_024);

const products: CatalogProduct[] = [
  {
    id: "ikea-us-00000001",
    source: "ikea-us",
    sourceProductID: "00000001",
    locale: "en-US",
    name: "Chair",
    description: "Oak chair",
    productURL: "https://www.ikea.com/us/en/p/chair-s00000001/",
    imageURLs: ["https://www.ikea.com/chair.jpg"],
    assetURLs: ["https://web-api.ikea.com/chair.glb"],
    searchableText: "Chair. Oak chair",
  },
  {
    id: "ikea-us-00000002",
    source: "ikea-us",
    sourceProductID: "00000002",
    locale: "en-US",
    name: "Textile",
    description: "No spatial asset",
    productURL: "https://www.ikea.com/us/en/p/textile-s00000002/",
    imageURLs: [],
    assetURLs: [],
    searchableText: "Textile. No spatial asset",
  },
];

test("catalog sync indexes only products with usable GLB assets in bounded batches", async () => {
  const prepared: number[] = [];
  const batches: string[][] = [];
  const result = await syncCatalog({
    source: async function* () {
      yield* products;
    },
    enricher: {
      enrich: async (product) => ({
        ...product,
        visualDescriptor: "light oak, compact, Scandinavian",
        textVector: semanticVector,
      }),
    },
    sink: {
      prepare: async (size) => {
        prepared.push(size);
      },
      upsert: async (batch) => {
        batches.push(batch.map((product) => product.id));
      },
    },
    batchSize: 1,
  });

  assert.deepEqual(prepared, [1_024]);
  assert.deepEqual(batches, [["ikea-us-00000001"]]);
  assert.deepEqual(result, { discovered: 2, indexed: 1, skippedWithoutAsset: 1 });
});

test("catalog sync rejects embeddings outside the semantic_v1 contract", async () => {
  const firstProduct = products[0];
  assert.ok(firstProduct);
  await assert.rejects(
    syncCatalog({
      source: async function* () {
        yield firstProduct;
      },
      enricher: {
        enrich: async (product) => ({
          ...product,
          visualDescriptor: "chair",
          textVector: [0.1, 0.2, 0.3],
        }),
      },
      sink: { prepare: async () => {}, upsert: async () => {} },
    }),
    /invalid_semantic_v1_vector/,
  );
});
