import { describe, expect, test } from "bun:test";

import {
  type CatalogQueryVectorizer,
  type CatalogVectorDatabase,
  createCatalogRetriever,
  QdrantCatalogStore,
  SEMANTIC_VECTOR_SIZE,
} from "../src/index.ts";

const vector = Array.from({ length: SEMANTIC_VECTOR_SIZE }, (_, index) => index / 10_000);

describe("catalog retrieval", () => {
  test("embeds one bounded query and searches only deterministic fit constraints", async () => {
    const embedded: string[] = [];
    const searches: unknown[] = [];
    const vectorizer: CatalogQueryVectorizer = {
      embed: async (query) => {
        embedded.push(query);
        return vector;
      },
    };
    const database: CatalogVectorDatabase = {
      getCollections: async () => ({ collections: [] }),
      createCollection: async () => undefined,
      createPayloadIndex: async () => undefined,
      upsert: async () => undefined,
      search: async (_collection, options) => {
        searches.push(options);
        return [];
      },
    };
    const retriever = createCatalogRetriever({
      vectorizer,
      store: new QdrantCatalogStore({ url: "http://127.0.0.1:6333", client: database }),
    });

    await retriever.search({
      query: "  warm oak chair   with arms ",
      category: "chair",
      maxDimensionsM: { width: 0.9, height: 1.2, depth: 0.9 },
      supportType: "floor",
      cacheProfile: "iphone17",
      limit: 8,
    });

    expect(embedded).toEqual(["warm oak chair with arms"]);
    expect(searches).toHaveLength(1);
    expect(searches[0]).toMatchObject({
      vector: { name: "semantic_v1", vector },
      limit: 8,
      filter: {
        must: expect.arrayContaining([
          { key: "injection_ready", match: { value: true } },
          { key: "dimensions_m.width", range: { lte: 0.9 } },
          { key: "cache_profiles", match: { value: "iphone17" } },
        ]),
      },
    });
  });

  test("rejects empty, overlong, or over-budget retrieval before embedding", async () => {
    let calls = 0;
    const retriever = createCatalogRetriever({
      vectorizer: {
        embed: async () => {
          calls += 1;
          return vector;
        },
      },
      store: new QdrantCatalogStore({
        url: "http://127.0.0.1:6333",
        client: {
          getCollections: async () => ({ collections: [] }),
          createCollection: async () => undefined,
          createPayloadIndex: async () => undefined,
          upsert: async () => undefined,
          search: async () => [],
        },
      }),
    });
    const common = {
      category: "chair",
      maxDimensionsM: { width: 1, height: 1, depth: 1 },
      supportType: "floor" as const,
      cacheProfile: "iphone17",
    };

    await expect(retriever.search({ ...common, query: "   " })).rejects.toThrow(
      "invalid_catalog_query",
    );
    await expect(retriever.search({ ...common, query: "x".repeat(501) })).rejects.toThrow(
      "invalid_catalog_query",
    );
    await expect(retriever.search({ ...common, query: "chair", limit: 9 })).rejects.toThrow(
      "invalid_catalog_retrieval_limit",
    );
    expect(calls).toBe(0);
  });

  test("rejects malformed vectors returned by a provider", async () => {
    const retriever = createCatalogRetriever({
      vectorizer: { embed: async () => [0.1, 0.2] },
      store: new QdrantCatalogStore({
        url: "http://127.0.0.1:6333",
        client: {
          getCollections: async () => ({ collections: [] }),
          createCollection: async () => undefined,
          createPayloadIndex: async () => undefined,
          upsert: async () => undefined,
          search: async () => [],
        },
      }),
    });

    await expect(
      retriever.search({
        query: "chair",
        category: "chair",
        maxDimensionsM: { width: 1, height: 1, depth: 1 },
        supportType: "floor",
        cacheProfile: "iphone17",
      }),
    ).rejects.toThrow("invalid_semantic_v1_vector");
  });
});
