import { test } from "bun:test";
import assert from "node:assert/strict";

import {
  type CatalogAssetRecord,
  type EmbeddedCatalogProduct,
  QdrantCatalogStore,
  SEMANTIC_VECTOR_SIZE,
} from "../src/index.ts";

const semanticVector = Array.from({ length: SEMANTIC_VECTOR_SIZE }, () => 0.25);

function readyAsset(): CatalogAssetRecord {
  const derivative = {
    storageKey: `sha256/${"a".repeat(64)}`,
    sha256: "a".repeat(64),
    byteLength: 1_024,
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

function product(asset = readyAsset()): EmbeddedCatalogProduct {
  return {
    id: "ikea-us-00000001",
    source: "ikea-us",
    sourceProductID: "00000001",
    locale: "en-US",
    name: "Side table",
    description: "Light oak table",
    productURL: "https://www.ikea.com/us/en/p/side-table-s00000001/",
    imageURLs: ["https://www.ikea.com/image.jpg"],
    assetURLs: ["https://web-api.ikea.com/model.glb"],
    searchableText: "Side table. Light oak table",
    visualDescriptor: "compact light oak side table",
    textVector: semanticVector,
    preparedAsset: asset,
  };
}

test("Qdrant preparation and payload use the fixed semantic vector and derived readiness", async () => {
  const calls: Array<{ method: string; args: unknown[] }> = [];
  const client = fakeClient(calls);
  const store = new QdrantCatalogStore({ url: "http://qdrant.test", client });

  await store.prepare(SEMANTIC_VECTOR_SIZE);
  const denied = readyAsset();
  denied.authorization.status = "prohibited";
  await store.upsert([product(), { ...product(denied), id: "ikea-us-00000002" }]);

  const create = calls.find((call) => call.method === "createCollection");
  assert.deepEqual(create?.args[1], {
    vectors: { semantic_v1: { size: 1_024, distance: "Cosine" } },
    on_disk_payload: true,
  });
  const upsertCall = calls.find((call) => call.method === "upsert");
  assert.ok(upsertCall);
  const points = (
    upsertCall.args[1] as {
      points: Array<{ vector: unknown; payload: Record<string, unknown> }>;
    }
  ).points;
  assert.deepEqual(points[0]?.vector, { semantic_v1: semanticVector });
  assert.equal(points[0]?.payload.injection_ready, true);
  assert.equal(points[1]?.payload.injection_ready, false);
  assert.equal("asset_urls" in (points[0]?.payload ?? {}), false);
  assert.equal(JSON.stringify(points[0]?.payload).includes("storageKey"), false);
});

test("Qdrant preserves sibling prepared variants under distinct point identities", async () => {
  const calls: Array<{ method: string; args: unknown[] }> = [];
  const store = new QdrantCatalogStore({ url: "http://qdrant.test", client: fakeClient(calls) });
  const first = readyAsset();
  const second = { ...readyAsset(), assetID: "ikea-us-00000001-v2" };

  await store.upsert([product(first), product(second)]);

  const upsertCall = calls.find((call) => call.method === "upsert");
  assert.ok(upsertCall);
  const points = (
    upsertCall.args[1] as {
      points: Array<{ id: string; payload: Record<string, unknown> }>;
    }
  ).points;
  assert.notEqual(points[0]?.id, points[1]?.id);
  assert.equal(points[0]?.payload.catalog_id, "ikea-us-00000001");
  assert.equal(points[1]?.payload.catalog_id, "ikea-us-00000001");
});

test("eligible search filters before ranking and returns only stable asset references", async () => {
  const calls: Array<{ method: string; args: unknown[] }> = [];
  const client = fakeClient(calls, [
    {
      id: "point-1",
      score: 0.91,
      payload: {
        catalog_id: "ikea-us-00000001",
        asset_id: "ikea-us-00000001-v1",
        name: "Side table",
        category: "side_table",
        support_type: "floor",
        dimensions_m: { width: 0.55, height: 0.5, depth: 0.55 },
        authorization_status: "authorized",
        injection_ready: true,
        glb_ready: true,
        usdz_ready: true,
        collision_ready: true,
        cache_profiles: ["ios-primary"],
      },
    },
    {
      id: "point-2",
      score: 0.99,
      payload: {
        catalog_id: "unsafe",
        asset_id: "unsafe",
        name: "Unsafe",
        injection_ready: false,
        asset_urls: ["https://example.invalid/raw.glb"],
      },
    },
    {
      id: "point-3",
      score: 0.95,
      payload: {
        catalog_id: "ikea-us-00000003",
        asset_id: "https://example.invalid/raw.glb",
        name: "URL disguised as an asset reference",
        category: "side_table",
        support_type: "floor",
        dimensions_m: { width: 0.55, height: 0.5, depth: 0.55 },
        authorization_status: "authorized",
        injection_ready: true,
        glb_ready: true,
        usdz_ready: true,
        collision_ready: true,
        cache_profiles: ["ios-primary"],
      },
    },
  ]);
  const store = new QdrantCatalogStore({ url: "http://qdrant.test", client });

  const hits = await store.search({
    semanticVector,
    category: "side_table",
    maxDimensionsM: { width: 0.8, height: 0.7, depth: 0.8 },
    supportType: "floor",
    cacheProfile: "ios-primary",
    limit: 8,
  });

  const query = calls.find((call) => call.method === "search")?.args[1] as {
    vector: unknown;
    filter: { must: unknown[] };
    with_payload: string[];
  };
  assert.deepEqual(query.vector, { name: "semantic_v1", vector: semanticVector });
  assert.deepEqual(query.filter.must, [
    { key: "source", match: { value: "ikea-us" } },
    { key: "authorization_status", match: { value: "authorized" } },
    { key: "injection_ready", match: { value: true } },
    { key: "category", match: { value: "side_table" } },
    { key: "support_type", match: { value: "floor" } },
    { key: "glb_ready", match: { value: true } },
    { key: "usdz_ready", match: { value: true } },
    { key: "collision_ready", match: { value: true } },
    { key: "cache_profiles", match: { value: "ios-primary" } },
    { key: "dimensions_m.width", range: { lte: 0.8 } },
    { key: "dimensions_m.height", range: { lte: 0.7 } },
    { key: "dimensions_m.depth", range: { lte: 0.8 } },
  ]);
  assert.equal(query.with_payload.includes("asset_urls"), false);
  assert.deepEqual(hits, [
    {
      id: "ikea-us-00000001",
      assetID: "ikea-us-00000001-v1",
      score: 0.91,
      name: "Side table",
      category: "side_table",
      dimensionsM: { width: 0.55, height: 0.5, depth: 0.55 },
      supportType: "floor",
      cacheProfile: "ios-primary",
    },
  ]);
});

test("eligible search rejects malformed vectors and physical constraints before I/O", async () => {
  const calls: Array<{ method: string; args: unknown[] }> = [];
  const store = new QdrantCatalogStore({
    url: "http://qdrant.test",
    client: fakeClient(calls),
  });
  const request = {
    category: "side_table",
    maxDimensionsM: { width: 0.8, height: 0.7, depth: 0.8 },
    supportType: "floor" as const,
    cacheProfile: "ios-primary",
  };

  await assert.rejects(
    store.search({ ...request, semanticVector: [0.1] }),
    /invalid_semantic_v1_vector/,
  );
  await assert.rejects(
    store.search({
      ...request,
      semanticVector,
      maxDimensionsM: { ...request.maxDimensionsM, width: 0 },
    }),
    /invalid_catalog_search_dimensions/,
  );
  assert.equal(
    calls.some((call) => call.method === "search"),
    false,
  );
});

function fakeClient(
  calls: Array<{ method: string; args: unknown[] }>,
  searchPoints: Array<{
    id: unknown;
    score: number;
    payload?: Record<string, unknown> | null;
  }> = [],
) {
  return {
    async getCollections() {
      calls.push({ method: "getCollections", args: [] });
      return { collections: [] };
    },
    async createCollection(...args: unknown[]) {
      calls.push({ method: "createCollection", args });
      return true;
    },
    async createPayloadIndex(...args: unknown[]) {
      calls.push({ method: "createPayloadIndex", args });
      return true;
    },
    async upsert(...args: unknown[]) {
      calls.push({ method: "upsert", args });
      return true;
    },
    async search(...args: unknown[]) {
      calls.push({ method: "search", args });
      return searchPoints;
    },
  };
}
