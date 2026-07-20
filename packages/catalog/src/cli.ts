import { REFRAME_IKEA_US_AUTHORIZATION } from "./ikea-authorization.ts";
import { crawlIkeaUSProducts } from "./ikea-source.ts";
import { createOpenAICatalogEnricher } from "./openai-enricher.ts";
import { syncCatalog } from "./pipeline.ts";
import { QdrantCatalogStore } from "./qdrant-store.ts";

const openAIAPIKey = process.env.OPENAI_API_KEY ?? "";
const qdrantURL = process.env.QDRANT_URL ?? "http://127.0.0.1:6333";
const qdrantAPIKey = process.env.QDRANT_API_KEY;

const result = await syncCatalog({
  source: () => crawlIkeaUSProducts({ authorization: REFRAME_IKEA_US_AUTHORIZATION }),
  enricher: createOpenAICatalogEnricher({ apiKey: openAIAPIKey }),
  sink: new QdrantCatalogStore({
    url: qdrantURL,
    ...(qdrantAPIKey === undefined ? {} : { apiKey: qdrantAPIKey }),
  }),
});

process.stdout.write(`${JSON.stringify(result)}\n`);
