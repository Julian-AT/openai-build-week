import type { CatalogSearchHit, EligibleCatalogSearch } from "./qdrant-store.ts";
import { SEMANTIC_VECTOR_SIZE } from "./types.ts";

export const MAX_CATALOG_RETRIEVAL_RESULTS = 8;
const MAX_CATALOG_QUERY_LENGTH = 500;

export interface CatalogQueryVectorizer {
  embed(query: string, signal?: AbortSignal): Promise<readonly number[]>;
}

export interface CatalogSearchStore {
  search(request: EligibleCatalogSearch): Promise<CatalogSearchHit[]>;
}

export type CatalogRetrievalRequest = Omit<EligibleCatalogSearch, "semanticVector"> & {
  query: string;
};

export interface CatalogRetriever {
  search(request: CatalogRetrievalRequest, signal?: AbortSignal): Promise<CatalogSearchHit[]>;
}

export function createCatalogRetriever(options: {
  vectorizer: CatalogQueryVectorizer;
  store: CatalogSearchStore;
}): CatalogRetriever {
  return {
    async search(request, signal) {
      signal?.throwIfAborted();
      const query = request.query.replace(/\s+/gu, " ").trim();
      if (query.length === 0 || query.length > MAX_CATALOG_QUERY_LENGTH) {
        throw new Error("invalid_catalog_query");
      }
      const limit = request.limit ?? MAX_CATALOG_RETRIEVAL_RESULTS;
      if (!Number.isSafeInteger(limit) || limit < 1 || limit > MAX_CATALOG_RETRIEVAL_RESULTS) {
        throw new Error("invalid_catalog_retrieval_limit");
      }
      const semanticVector = await options.vectorizer.embed(query, signal);
      signal?.throwIfAborted();
      if (
        semanticVector.length !== SEMANTIC_VECTOR_SIZE ||
        semanticVector.some((component) => !Number.isFinite(component))
      ) {
        throw new Error("invalid_semantic_v1_vector");
      }
      return await options.store.search({
        semanticVector,
        category: request.category,
        maxDimensionsM: request.maxDimensionsM,
        supportType: request.supportType,
        cacheProfile: request.cacheProfile,
        limit,
      });
    },
  };
}
