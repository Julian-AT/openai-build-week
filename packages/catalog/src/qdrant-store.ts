import { createHash } from "node:crypto";

import { QdrantClient } from "@qdrant/js-client-rest";

import type { CatalogSink, EmbeddedCatalogProduct } from "./types.ts";

export const CATALOG_COLLECTION = "reframe_products_v1";

export interface QdrantCatalogStoreOptions {
  url: string;
  apiKey?: string;
  collection?: string;
}

export interface CatalogSearchHit {
  id: string;
  score: number;
  name: string;
  productURL: string;
  assetURLs: string[];
}

export class QdrantCatalogStore implements CatalogSink {
  readonly #client: QdrantClient;
  readonly #collection: string;

  constructor(options: QdrantCatalogStoreOptions) {
    const url = new URL(options.url);
    if (url.protocol !== "http:" && url.protocol !== "https:")
      throw new Error("invalid_qdrant_url");
    this.#client = new QdrantClient({
      url: url.toString(),
      ...(options.apiKey === undefined ? {} : { apiKey: options.apiKey }),
    });
    this.#collection = options.collection ?? CATALOG_COLLECTION;
  }

  async prepare(vectorSize: number): Promise<void> {
    const collections = await this.#client.getCollections();
    const exists = collections.collections.some(
      (collection) => collection.name === this.#collection,
    );
    if (!exists) {
      await this.#client.createCollection(this.#collection, {
        vectors: { text: { size: vectorSize, distance: "Cosine" } },
        on_disk_payload: true,
      });
      await Promise.all([
        this.#client.createPayloadIndex(this.#collection, {
          field_name: "source",
          field_schema: "keyword",
          wait: true,
        }),
        this.#client.createPayloadIndex(this.#collection, {
          field_name: "locale",
          field_schema: "keyword",
          wait: true,
        }),
      ]);
    }
  }

  async upsert(products: readonly EmbeddedCatalogProduct[]): Promise<void> {
    await this.#client.upsert(this.#collection, {
      wait: true,
      points: products.map((product) => ({
        id: stableUUID(product.id),
        vector: { text: product.textVector },
        payload: {
          catalog_id: product.id,
          source: product.source,
          source_product_id: product.sourceProductID,
          locale: product.locale,
          name: product.name,
          description: product.description,
          visual_descriptor: product.visualDescriptor,
          product_url: product.productURL,
          image_urls: product.imageURLs,
          asset_urls: product.assetURLs,
          ...(product.price === undefined ? {} : { price: product.price }),
        },
      })),
    });
  }

  async search(vector: number[], limit = 12): Promise<CatalogSearchHit[]> {
    const points = await this.#client.search(this.#collection, {
      vector: { name: "text", vector },
      limit: Math.max(1, Math.min(limit, 50)),
      filter: { must: [{ key: "source", match: { value: "ikea-us" } }] },
      with_payload: ["catalog_id", "name", "product_url", "asset_urls"],
      with_vector: false,
    });
    return points.map((point) => {
      const payload = point.payload ?? {};
      return {
        id: String(payload.catalog_id),
        score: point.score,
        name: String(payload.name),
        productURL: String(payload.product_url),
        assetURLs: Array.isArray(payload.asset_urls) ? payload.asset_urls.map(String) : [],
      };
    });
  }
}

function stableUUID(value: string): string {
  const bytes = Buffer.from(createHash("sha256").update(value).digest().subarray(0, 16));
  bytes[6] = ((bytes[6] ?? 0) & 0x0f) | 0x50;
  bytes[8] = ((bytes[8] ?? 0) & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
