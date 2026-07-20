import OpenAI from "openai";

import type { CatalogQueryVectorizer } from "./retrieval.ts";
import { SEMANTIC_VECTOR_SIZE } from "./types.ts";

export const CATALOG_EMBEDDING_MODEL = "text-embedding-3-small";

export interface OpenAICatalogQueryVectorizerOptions {
  apiKey: string;
  fetch?: typeof globalThis.fetch;
}

export function createOpenAICatalogQueryVectorizer(
  options: OpenAICatalogQueryVectorizerOptions,
): CatalogQueryVectorizer {
  if (options.apiKey.length === 0) throw new Error("missing_openai_api_key");
  const client = new OpenAI({
    apiKey: options.apiKey,
    ...(options.fetch === undefined ? {} : { fetch: options.fetch }),
  });
  return {
    async embed(query, signal) {
      const response = await client.embeddings.create(
        {
          model: CATALOG_EMBEDDING_MODEL,
          input: query,
          dimensions: SEMANTIC_VECTOR_SIZE,
          encoding_format: "float",
        },
        signal === undefined ? undefined : { signal },
      );
      const embedding = response.data[0]?.embedding;
      if (embedding === undefined) throw new Error("missing_catalog_embedding");
      return embedding;
    },
  };
}
