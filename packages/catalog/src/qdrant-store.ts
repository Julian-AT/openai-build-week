import { createHash } from "node:crypto";

import { QdrantClient } from "@qdrant/js-client-rest";

import { assessAssetInjectionReadiness } from "./catalog-eligibility.ts";
import type {
  AssetSupportType,
  CatalogDimensionsM,
  CatalogSink,
  EmbeddedCatalogProduct,
} from "./types.ts";
import { SEMANTIC_VECTOR_NAME, SEMANTIC_VECTOR_SIZE } from "./types.ts";

export const CATALOG_COLLECTION = "reframe_products_v2";

interface CatalogScoredPoint {
  id: unknown;
  score: number;
  payload?: Record<string, unknown> | null;
}

/** Narrow database port keeps catalog rules testable without a live Qdrant process. */
export interface CatalogVectorDatabase {
  getCollections(): Promise<{ collections: Array<{ name: string }> }>;
  createCollection(collection: string, options: unknown): Promise<unknown>;
  createPayloadIndex(collection: string, options: unknown): Promise<unknown>;
  upsert(collection: string, options: unknown): Promise<unknown>;
  search(collection: string, options: unknown): Promise<readonly CatalogScoredPoint[]>;
}

export interface QdrantCatalogStoreOptions {
  url: string;
  apiKey?: string;
  collection?: string;
  client?: CatalogVectorDatabase;
}

export interface EligibleCatalogSearch {
  semanticVector: readonly number[];
  category: string;
  maxDimensionsM: CatalogDimensionsM;
  supportType: AssetSupportType;
  cacheProfile: string;
  limit?: number;
}

export interface CatalogSearchHit {
  id: string;
  assetID: string;
  score: number;
  name: string;
  category: string;
  dimensionsM: CatalogDimensionsM;
  supportType: AssetSupportType;
  cacheProfile: string;
}

const SAFE_IDENTIFIER = /^[a-z0-9][a-z0-9._-]{1,127}$/u;
const SAFE_CATEGORY = /^[a-z][a-z0-9_]{1,63}$/u;
const SUPPORT_TYPES = new Set<AssetSupportType>(["floor", "surface", "wall", "ceiling"]);

export class QdrantCatalogStore implements CatalogSink {
  readonly #client: CatalogVectorDatabase;
  readonly #collection: string;

  constructor(options: QdrantCatalogStoreOptions) {
    const url = new URL(options.url);
    if (url.protocol !== "http:" && url.protocol !== "https:")
      throw new Error("invalid_qdrant_url");
    this.#client =
      options.client ??
      (new QdrantClient({
        url: url.toString(),
        ...(options.apiKey === undefined ? {} : { apiKey: options.apiKey }),
      }) as unknown as CatalogVectorDatabase);
    this.#collection = options.collection ?? CATALOG_COLLECTION;
  }

  async prepare(vectorSize: number): Promise<void> {
    if (vectorSize !== SEMANTIC_VECTOR_SIZE) throw new Error("invalid_semantic_v1_vector");
    const collections = await this.#client.getCollections();
    const exists = collections.collections.some(
      (collection) => collection.name === this.#collection,
    );
    if (!exists) {
      await this.#client.createCollection(this.#collection, {
        vectors: {
          [SEMANTIC_VECTOR_NAME]: { size: SEMANTIC_VECTOR_SIZE, distance: "Cosine" },
        },
        on_disk_payload: true,
      });
      const indexes: Array<[string, "keyword" | "bool" | "float"]> = [
        ["source", "keyword"],
        ["authorization_status", "keyword"],
        ["injection_ready", "bool"],
        ["category", "keyword"],
        ["support_type", "keyword"],
        ["glb_ready", "bool"],
        ["usdz_ready", "bool"],
        ["collision_ready", "bool"],
        ["cache_profiles", "keyword"],
        ["dimensions_m.width", "float"],
        ["dimensions_m.height", "float"],
        ["dimensions_m.depth", "float"],
      ];
      await Promise.all(
        indexes.map(([fieldName, fieldSchema]) =>
          this.#client.createPayloadIndex(this.#collection, {
            field_name: fieldName,
            field_schema: fieldSchema,
            wait: true,
          }),
        ),
      );
    }
  }

  async upsert(products: readonly EmbeddedCatalogProduct[]): Promise<void> {
    for (const product of products) validateSemanticVector(product.textVector);
    await this.#client.upsert(this.#collection, {
      wait: true,
      points: products.map((product) => ({
        id: stableUUID(product.id),
        vector: { [SEMANTIC_VECTOR_NAME]: product.textVector },
        payload: catalogPayload(product),
      })),
    });
  }

  async search(request: EligibleCatalogSearch): Promise<CatalogSearchHit[]> {
    validateSearchRequest(request);
    const limit = Math.max(1, Math.min(request.limit ?? 12, 50));
    const points = await this.#client.search(this.#collection, {
      vector: { name: SEMANTIC_VECTOR_NAME, vector: request.semanticVector },
      limit,
      filter: { must: eligibleFilter(request) },
      with_payload: [
        "catalog_id",
        "asset_id",
        "name",
        "category",
        "support_type",
        "dimensions_m",
        "authorization_status",
        "injection_ready",
        "glb_ready",
        "usdz_ready",
        "collision_ready",
        "cache_profiles",
      ],
      with_vector: false,
    });
    return points.flatMap((point) => {
      const hit = parseEligibleHit(point, request);
      return hit === undefined ? [] : [hit];
    });
  }
}

function catalogPayload(product: EmbeddedCatalogProduct): Record<string, unknown> {
  const asset = product.preparedAsset;
  const readiness = asset === undefined ? undefined : assessAssetInjectionReadiness(asset);
  return {
    catalog_id: product.id,
    source: product.source,
    source_product_id: product.sourceProductID,
    locale: product.locale,
    name: product.name,
    description: product.description,
    visual_descriptor: product.visualDescriptor,
    product_url: product.productURL,
    ...(product.price === undefined ? {} : { price: product.price }),
    injection_ready: readiness?.ready ?? false,
    ...(asset === undefined
      ? {}
      : {
          asset_id: asset.assetID,
          authorization_status: asset.authorization.status,
          category: asset.category,
          support_type: asset.supportType,
          dimensions_m: asset.dimensionsM,
          glb_ready: derivativeReady(asset.derivatives.glb),
          usdz_ready: derivativeReady(asset.derivatives.usdz),
          collision_ready: derivativeReady(asset.derivatives.collision),
          cache_profiles: asset.cacheProfiles,
        }),
  };
}

function eligibleFilter(request: EligibleCatalogSearch): unknown[] {
  return [
    { key: "source", match: { value: "ikea-us" } },
    { key: "authorization_status", match: { value: "authorized" } },
    { key: "injection_ready", match: { value: true } },
    { key: "category", match: { value: request.category } },
    { key: "support_type", match: { value: request.supportType } },
    { key: "glb_ready", match: { value: true } },
    { key: "usdz_ready", match: { value: true } },
    { key: "collision_ready", match: { value: true } },
    { key: "cache_profiles", match: { value: request.cacheProfile } },
    { key: "dimensions_m.width", range: { lte: request.maxDimensionsM.width } },
    { key: "dimensions_m.height", range: { lte: request.maxDimensionsM.height } },
    { key: "dimensions_m.depth", range: { lte: request.maxDimensionsM.depth } },
  ];
}

function validateSearchRequest(request: EligibleCatalogSearch): void {
  validateSemanticVector(request.semanticVector);
  if (!SAFE_CATEGORY.test(request.category)) throw new Error("invalid_catalog_search_category");
  if (!SUPPORT_TYPES.has(request.supportType))
    throw new Error("invalid_catalog_search_support_type");
  if (!SAFE_IDENTIFIER.test(request.cacheProfile) || request.cacheProfile.includes("://"))
    throw new Error("invalid_catalog_cache_profile");
  if (!validDimensions(request.maxDimensionsM))
    throw new Error("invalid_catalog_search_dimensions");
  if (request.limit !== undefined && (!Number.isSafeInteger(request.limit) || request.limit < 1)) {
    throw new Error("invalid_catalog_search_limit");
  }
}

function validateSemanticVector(vector: readonly number[]): void {
  if (
    vector.length !== SEMANTIC_VECTOR_SIZE ||
    vector.some((component) => !Number.isFinite(component))
  ) {
    throw new Error("invalid_semantic_v1_vector");
  }
}

function parseEligibleHit(
  point: CatalogScoredPoint,
  request: EligibleCatalogSearch,
): CatalogSearchHit | undefined {
  const payload = point.payload;
  if (payload === undefined || payload === null || !Number.isFinite(point.score)) return undefined;
  const id = stringField(payload, "catalog_id");
  const assetID = stringField(payload, "asset_id");
  const name = stringField(payload, "name");
  const category = stringField(payload, "category");
  const supportType = stringField(payload, "support_type");
  const dimensionsM = dimensionsField(payload.dimensions_m);
  const cacheProfiles = payload.cache_profiles;
  if (
    id === undefined ||
    assetID === undefined ||
    !SAFE_IDENTIFIER.test(id) ||
    !SAFE_IDENTIFIER.test(assetID) ||
    name === undefined ||
    category !== request.category ||
    supportType !== request.supportType ||
    !SUPPORT_TYPES.has(supportType as AssetSupportType) ||
    dimensionsM === undefined ||
    dimensionsM.width > request.maxDimensionsM.width ||
    dimensionsM.height > request.maxDimensionsM.height ||
    dimensionsM.depth > request.maxDimensionsM.depth ||
    payload.authorization_status !== "authorized" ||
    payload.injection_ready !== true ||
    payload.glb_ready !== true ||
    payload.usdz_ready !== true ||
    payload.collision_ready !== true ||
    !Array.isArray(cacheProfiles) ||
    !cacheProfiles.includes(request.cacheProfile)
  ) {
    return undefined;
  }
  return {
    id,
    assetID,
    score: point.score,
    name,
    category,
    dimensionsM,
    supportType: supportType as AssetSupportType,
    cacheProfile: request.cacheProfile,
  };
}

function derivativeReady(derivative: { validated: boolean }): boolean {
  return derivative.validated === true;
}

function dimensionsField(value: unknown): CatalogDimensionsM | undefined {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return undefined;
  const dimensions = value as Record<string, unknown>;
  const candidate = {
    width: dimensions.width,
    height: dimensions.height,
    depth: dimensions.depth,
  };
  if (!validDimensions(candidate)) return undefined;
  return candidate as CatalogDimensionsM;
}

function validDimensions(value: {
  width: unknown;
  height: unknown;
  depth: unknown;
}): value is CatalogDimensionsM {
  return [value.width, value.height, value.depth].every(
    (dimension) =>
      typeof dimension === "number" &&
      Number.isFinite(dimension) &&
      dimension > 0 &&
      dimension < 100,
  );
}

function stringField(payload: Record<string, unknown>, key: string): string | undefined {
  const value = payload[key];
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function stableUUID(value: string): string {
  const bytes = Buffer.from(createHash("sha256").update(value).digest().subarray(0, 16));
  bytes[6] = ((bytes[6] ?? 0) & 0x0f) | 0x50;
  bytes[8] = ((bytes[8] ?? 0) & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
