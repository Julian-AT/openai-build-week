import type {
  CatalogEnricher,
  CatalogProduct,
  CatalogSink,
  EmbeddedCatalogProduct,
} from "./types.ts";

export interface CatalogSyncOptions {
  source: () => AsyncIterable<CatalogProduct>;
  enricher: CatalogEnricher;
  sink: CatalogSink;
  batchSize?: number;
}

export interface CatalogSyncResult {
  discovered: number;
  indexed: number;
  skippedWithoutAsset: number;
}

export async function syncCatalog(options: CatalogSyncOptions): Promise<CatalogSyncResult> {
  const batchSize = Math.max(1, Math.min(options.batchSize ?? 32, 128));
  const batch: EmbeddedCatalogProduct[] = [];
  let discovered = 0;
  let indexed = 0;
  let skippedWithoutAsset = 0;
  let vectorSize: number | undefined;

  for await (const product of options.source()) {
    discovered += 1;
    if (product.assetURLs.length === 0) {
      skippedWithoutAsset += 1;
      continue;
    }
    const enriched = await options.enricher.enrich(product);
    if (
      enriched.textVector.length === 0 ||
      enriched.textVector.some((value) => !Number.isFinite(value))
    ) {
      throw new Error("invalid_catalog_vector");
    }
    if (vectorSize === undefined) {
      vectorSize = enriched.textVector.length;
      await options.sink.prepare(vectorSize);
    } else if (enriched.textVector.length !== vectorSize) {
      throw new Error("catalog_vector_size_changed");
    }
    batch.push(enriched);
    if (batch.length >= batchSize) {
      await options.sink.upsert(batch);
      indexed += batch.length;
      batch.length = 0;
    }
  }
  if (batch.length > 0) {
    await options.sink.upsert(batch);
    indexed += batch.length;
  }
  return { discovered, indexed, skippedWithoutAsset };
}
