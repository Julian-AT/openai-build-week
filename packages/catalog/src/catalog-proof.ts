import type { PreparedCatalogAssetRecord } from "./asset-preparation.ts";
import { assessAssetInjectionReadiness } from "./catalog-eligibility.ts";
import type { LocalAssetCache, LocalAssetDelivery } from "./delivery.ts";
import { resolveLocalAssetDelivery } from "./delivery.ts";
import type { CatalogSearchHit } from "./qdrant-store.ts";
import type { CatalogQueryVectorizer, CatalogSearchStore } from "./retrieval.ts";
import { createCatalogRetriever } from "./retrieval.ts";
import type {
  CatalogDimensionsM,
  CatalogEnricher,
  CatalogProduct,
  CatalogSink,
  EmbeddedCatalogProduct,
} from "./types.ts";
import { SEMANTIC_VECTOR_SIZE } from "./types.ts";

export interface PreparedCatalogProofStore extends CatalogSink, CatalogSearchStore {}

export interface PreparedCatalogProofOptions {
  product: CatalogProduct;
  prepared: PreparedCatalogAssetRecord;
  enricher: CatalogEnricher;
  store: PreparedCatalogProofStore;
  vectorizer: CatalogQueryVectorizer;
  cache: LocalAssetCache;
  query: string;
  cacheProfile: string;
  maxDimensionsM: CatalogDimensionsM;
}

export interface PreparedCatalogProofResult {
  indexed: EmbeddedCatalogProduct;
  hit: CatalogSearchHit;
  delivery: LocalAssetDelivery;
}

/**
 * The smoke proof binds untrusted model output to durable source and prepared
 * facts, then proves Qdrant eligibility and exact local delivery of one asset.
 */
export async function provePreparedCatalogAsset(
  options: PreparedCatalogProofOptions,
): Promise<PreparedCatalogProofResult> {
  assertPreparedProductBinding(options.product, options.prepared);
  const product = { ...options.product, preparedAsset: options.prepared.asset };
  const enriched = await options.enricher.enrich(product);
  const indexed = bindEnrichment(product, enriched);
  await options.store.prepare(SEMANTIC_VECTOR_SIZE);
  await options.store.upsert([indexed]);

  const retriever = createCatalogRetriever({
    vectorizer: options.vectorizer,
    store: options.store,
  });
  const hits = await retriever.search({
    query: options.query,
    category: options.prepared.asset.category,
    maxDimensionsM: options.maxDimensionsM,
    supportType: options.prepared.asset.supportType,
    cacheProfile: options.cacheProfile,
  });
  const hit = hits.find(
    (candidate) =>
      candidate.id === options.product.id && candidate.assetID === options.prepared.asset.assetID,
  );
  if (hit === undefined) throw new Error("indexed_asset_not_retrieved");

  const delivery = await resolveLocalAssetDelivery(
    {
      asset: options.prepared.asset,
      cacheProfile: options.cacheProfile,
      derivative: "glb",
    },
    options.cache,
  );
  if (
    delivery.assetID !== options.prepared.asset.assetID ||
    delivery.sha256 !== options.prepared.asset.derivatives.glb.sha256 ||
    delivery.byteLength !== options.prepared.asset.derivatives.glb.byteLength
  ) {
    throw new Error("delivered_asset_verification_failed");
  }
  return { indexed, hit, delivery };
}

function assertPreparedProductBinding(
  product: CatalogProduct,
  prepared: PreparedCatalogAssetRecord,
): void {
  if (!assessAssetInjectionReadiness(prepared.asset).ready)
    throw new Error("prepared_asset_not_injection_ready");
  if (!prepared.asset.assetID.startsWith(`${product.id}-`))
    throw new Error("prepared_asset_product_mismatch");
}

function bindEnrichment(
  product: CatalogProduct,
  enriched: EmbeddedCatalogProduct,
): EmbeddedCatalogProduct {
  const descriptor = enriched.visualDescriptor.replace(/\s+/gu, " ").trim();
  if (descriptor.length === 0 || descriptor.length > 1_000 || /https?:\/\//iu.test(descriptor))
    throw new Error("invalid_visual_descriptor");
  if (
    enriched.textVector.length !== SEMANTIC_VECTOR_SIZE ||
    enriched.textVector.some((component) => !Number.isFinite(component))
  ) {
    throw new Error("invalid_semantic_v1_vector");
  }
  return { ...product, visualDescriptor: descriptor, textVector: [...enriched.textVector] };
}
