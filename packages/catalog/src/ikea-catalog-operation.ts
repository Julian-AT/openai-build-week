import { createHash } from "node:crypto";
import { join } from "node:path";

import { acquireCatalogBinary } from "./acquisition.ts";
import { type PreparedCatalogAssetRecord, prepareCatalogAsset } from "./asset-preparation.ts";
import {
  BLENDER_NORMALIZER_SCRIPT_PATH,
  createBlenderAssetProcessor,
} from "./blender-asset-processor.ts";
import { runCatalogOperation } from "./catalog-operation.ts";
import { type CatalogRunRecord, createFilesystemCatalogRunStore } from "./catalog-run-store.ts";
import {
  createFilesystemLocalAssetCache,
  synchronizePreparedAssetsToLocalCache,
} from "./client-cache-sync.ts";
import { resolveLocalAssetDelivery } from "./delivery.ts";
import { createFilesystemAcquisitionStores } from "./filesystem-acquisition-store.ts";
import { createFilesystemPreparedAssetStore } from "./filesystem-prepared-asset-store.ts";
import { REFRAME_IKEA_US_AUTHORIZATION } from "./ikea-authorization.ts";
import { createIkeaGLBFetchTransport } from "./ikea-glb-transport.ts";
import {
  createIkeaUSCatalogSource,
  IKEA_HTML_PARSER_REVISION,
  type IkeaCatalogDiscovery,
} from "./ikea-source.ts";
import { createOpenAICatalogEnricher } from "./openai-enricher.ts";
import { createOpenAICatalogQueryVectorizer } from "./openai-vectorizer.ts";
import { CATALOG_COLLECTION, QdrantCatalogStore } from "./qdrant-store.ts";
import { createCatalogRetriever } from "./retrieval.ts";
import { type EmbeddedCatalogProduct, SEMANTIC_VECTOR_SIZE } from "./types.ts";

const SAFE_IDENTIFIER = /^[a-z0-9][a-z0-9._-]{1,127}$/u;

export interface IkeaCatalogOperationEnvironment {
  [name: string]: string | undefined;
  REFRAME_CATALOG_PROFILE?: string;
  REFRAME_DATA_DIR?: string;
  REFRAME_CATALOG_FRONTIER_REVISION?: string;
  REFRAME_CATALOG_ACQUISITION_CONCURRENCY?: string;
  REFRAME_CATALOG_REQUESTS_PER_MINUTE?: string;
  REFRAME_CATALOG_MAX_ATTEMPTS?: string;
  REFRAME_CATALOG_MAX_ASSET_BYTES?: string;
  REFRAME_CATALOG_PRIMARY_CACHE_PROFILES?: string;
  REFRAME_BLENDER_PATH?: string;
  REFRAME_USDZIP_PATH?: string;
  REFRAME_USDCHECKER_PATH?: string;
  REFRAME_ASSET_PROCESSOR_REVISION?: string;
  OPENAI_API_KEY?: string;
  QDRANT_URL?: string;
  QDRANT_API_KEY?: string;
}

interface OperationConfiguration {
  profile: "full" | "incremental";
  dataDirectory: string;
  frontierRevision: string;
  acquisition: {
    concurrency: number;
    requestsPerMinute: number;
    maxAttempts: number;
    maxAssetBytes: number;
  };
  cacheProfiles: string[];
  blenderPath: string;
  usdzipPath: string;
  usdcheckerPath: string;
  processorRevision: string;
  openAIAPIKey: string;
  qdrantURL: string;
  qdrantAPIKey?: string;
}

interface PreparedRunProduct {
  prepared: PreparedCatalogAssetRecord;
  indexed: EmbeddedCatalogProduct;
}

/**
 * Executes the full or incremental authorized US-English IKEA frontier. Every
 * successful processor stage is persisted through the run operation before
 * enrichment/indexing, and every live point has a prepared record first.
 */
export async function runIkeaCatalogOperationFromEnvironment(
  environment: IkeaCatalogOperationEnvironment,
): Promise<CatalogRunRecord> {
  const configuration = operationConfiguration(environment);
  await assertProcessorPaths(configuration);
  const normalizerScriptSHA256 = hash(
    new Uint8Array(await Bun.file(BLENDER_NORMALIZER_SCRIPT_PATH).arrayBuffer()),
  );
  const processorConfiguration = {
    canonicalization: "png-essential-chunks-usdz-dos-epoch-v1",
    collision: "aabb",
    preview: "png-512",
    units: "meters",
    usdz: "arkit-usdzip",
    normalizerScriptSHA256,
  };
  const processorConfigurationDigest = hashCanonicalJSON(processorConfiguration);
  const runStore = await createFilesystemCatalogRunStore({
    dataDirectory: configuration.dataDirectory,
  });
  const acquisition = await createFilesystemAcquisitionStores({
    dataDirectory: configuration.dataDirectory,
  });
  const preparedStore = await createFilesystemPreparedAssetStore({
    dataDirectory: configuration.dataDirectory,
  });
  const processor = createBlenderAssetProcessor({
    blenderPath: configuration.blenderPath,
    usdzipPath: configuration.usdzipPath,
    usdcheckerPath: configuration.usdcheckerPath,
    scriptPath: BLENDER_NORMALIZER_SCRIPT_PATH,
    workDirectory: join(configuration.dataDirectory, "catalog", "processor-work"),
    timeoutMs: 120_000,
  });
  const catalog = new QdrantCatalogStore({
    url: configuration.qdrantURL,
    ...(configuration.qdrantAPIKey === undefined ? {} : { apiKey: configuration.qdrantAPIKey }),
  });
  const enricher = createOpenAICatalogEnricher({ apiKey: configuration.openAIAPIKey });
  const vectorizer = createOpenAICatalogQueryVectorizer({ apiKey: configuration.openAIAPIKey });
  const source = createIkeaUSCatalogSource({
    authorization: REFRAME_IKEA_US_AUTHORIZATION,
    concurrency: configuration.acquisition.concurrency,
    requestsPerMinute: configuration.acquisition.requestsPerMinute,
    maxAttempts: configuration.acquisition.maxAttempts,
  });
  const preparedProducts: PreparedRunProduct[] = [];
  const sourceHashes = new Set<string>();

  return await runCatalogOperation({
    store: runStore,
    configuration: {
      schemaVersion: 1,
      profile: configuration.profile,
      frontier: {
        source: "ikea-us",
        market: "us",
        locale: "en-US",
        frontierRevision: configuration.frontierRevision,
        parserRevision: IKEA_HTML_PARSER_REVISION,
        downloaderRevision: "3a036f1820c44b470aded71e651a1e791fd5d022",
      },
      acquisition: configuration.acquisition,
      processing: {
        processorRevision: configuration.processorRevision,
        processorConfigurationDigest,
      },
      index: { collection: CATALOG_COLLECTION, vectorName: "semantic_v1", vectorSize: 1_024 },
      primaryCacheProfiles: configuration.cacheProfiles,
    },
    source,
    verifyInfrastructure: async () => {
      await catalog.prepare(SEMANTIC_VECTOR_SIZE);
    },
    process: async (discovery, progress) => {
      await processDiscovery({
        discovery,
        progress,
        configuration,
        acquisition,
        preparedStore,
        processor,
        processorConfiguration,
        catalog,
        enricher,
        preparedProducts,
        sourceHashes,
      });
    },
    reconcile: async () =>
      await reconcileCatalogRun({
        configuration,
        catalog,
        vectorizer,
        preparedStore,
        preparedProducts,
      }),
  });
}

async function processDiscovery(options: {
  discovery: IkeaCatalogDiscovery;
  progress: Parameters<typeof runCatalogOperation<IkeaCatalogDiscovery>>[0]["process"] extends (
    discovery: IkeaCatalogDiscovery,
    progress: infer T,
  ) => Promise<void>
    ? T
    : never;
  configuration: OperationConfiguration;
  acquisition: Awaited<ReturnType<typeof createFilesystemAcquisitionStores>>;
  preparedStore: Awaited<ReturnType<typeof createFilesystemPreparedAssetStore>>;
  processor: ReturnType<typeof createBlenderAssetProcessor>;
  processorConfiguration: unknown;
  catalog: QdrantCatalogStore;
  enricher: ReturnType<typeof createOpenAICatalogEnricher>;
  preparedProducts: PreparedRunProduct[];
  sourceHashes: Set<string>;
}): Promise<void> {
  const { discovery } = options;
  for (const [index, assetURL] of discovery.product.assetURLs.entries()) {
    const variantID = discovery.variantIDs[index];
    if (variantID === undefined) throw new Error("catalog_variant_identity_missing");
    await options.progress.stage(variantID, "discovered");
    const facts = discovery.sourceFacts;
    if (
      facts.dimensionsM === undefined ||
      facts.category === undefined ||
      facts.supportType === undefined
    ) {
      await options.progress.stage(variantID, "source_unavailable", "metadata_incomplete");
      continue;
    }
    await options.progress.stage(variantID, "metadata_ready");
    const acquisitionID = `${variantID}-source`;
    const previous = await options.acquisition.state.load(acquisitionID);
    const acquired = await acquireCatalogBinary({
      acquisitionID,
      sourceURL: assetURL,
      state: options.acquisition.state,
      content: options.acquisition.content,
      transport: createIkeaGLBFetchTransport(),
      nowMs: Date.now(),
      maxAttempts: options.configuration.acquisition.maxAttempts,
      maxAssetBytes: options.configuration.acquisition.maxAssetBytes,
      maxResponseBytes: options.configuration.acquisition.maxAssetBytes,
    });
    if (acquired.status === "deferred" || acquired.status === "partial") {
      await options.progress.acquisition("retried");
      throw new Error("catalog_acquisition_retryable");
    }
    if (acquired.status === "failed") {
      await options.progress.acquisition(
        "failed",
        acquisitionFailureReason(acquired.checkpoint.lastFailure),
      );
      await options.progress.stage(
        variantID,
        "source_unavailable",
        acquisitionFailureReason(acquired.checkpoint.lastFailure),
      );
      continue;
    }
    const content = acquired.checkpoint.content;
    if (content === undefined) throw new Error("catalog_acquisition_content_missing");
    if (previous?.phase === "complete") await options.progress.acquisition("unchanged");
    else if (options.sourceHashes.has(content.sha256))
      await options.progress.acquisition("deduplicated");
    else await options.progress.acquisition("downloaded");
    options.sourceHashes.add(content.sha256);
    await options.progress.stage(variantID, "acquired");
    await options.progress.stage(variantID, "source_validated");

    let prepared: PreparedCatalogAssetRecord;
    try {
      prepared = await prepareCatalogAsset({
        product: {
          id: discovery.product.id,
          sourceProductID: discovery.product.sourceProductID,
          name: discovery.product.name,
        },
        source: {
          storageKey: content.storageKey,
          sha256: content.sha256,
          bytes: await options.acquisition.source.read(content),
        },
        authorization: {
          status: "authorized",
          reference: REFRAME_IKEA_US_AUTHORIZATION.authorizationReference,
        },
        category: facts.category,
        supportType: facts.supportType,
        expectedDimensionsM: facts.dimensionsM,
        cacheProfiles: options.configuration.cacheProfiles,
        processor: options.processor,
        processorRevision: options.configuration.processorRevision,
        processorConfiguration: options.processorConfiguration,
        content: options.preparedStore,
      });
      await options.preparedStore.savePreparedAsset(prepared);
    } catch (error) {
      if (!isQuarantinableAssetFailure(error)) throw error;
      await options.progress.stage(variantID, "quarantined", quarantineReason(error));
      continue;
    }
    await options.progress.stage(variantID, "normalized");
    await options.progress.stage(variantID, "derivatives_ready");

    const product = {
      ...discovery.product,
      variantID,
      parentProductID: discovery.product.id,
      preparedAsset: prepared.asset,
    };
    const enriched = await options.enricher.enrich(product);
    const indexed = bindEnrichment(product, enriched);
    await options.progress.stage(variantID, "enriched");
    await options.catalog.upsert([indexed]);
    await options.progress.stage(variantID, "indexed");
    await options.progress.stage(variantID, "injection_ready");
    options.preparedProducts.push({ prepared, indexed });
    for (const cacheProfile of options.configuration.cacheProfiles) {
      const report = await synchronizePreparedAssetsToLocalCache({
        dataDirectory: options.configuration.dataDirectory,
        cacheProfile,
        records: options.preparedProducts.map((entry) => entry.prepared),
        preparedStore: options.preparedStore,
      });
      await options.progress.cacheSynchronized(report.counters.assetsSynchronized);
    }
  }
}

async function reconcileCatalogRun(options: {
  configuration: OperationConfiguration;
  catalog: QdrantCatalogStore;
  vectorizer: ReturnType<typeof createOpenAICatalogQueryVectorizer>;
  preparedStore: Awaited<ReturnType<typeof createFilesystemPreparedAssetStore>>;
  preparedProducts: readonly PreparedRunProduct[];
}): Promise<{
  durablePreparedAssets: number;
  qdrantPoints: number;
  deliveryProbeVerified: boolean;
  eligibleRetrievalProbes: number;
}> {
  if (options.preparedProducts.length === 0) {
    return {
      durablePreparedAssets: 0,
      qdrantPoints: 0,
      deliveryProbeVerified: false,
      eligibleRetrievalProbes: 0,
    };
  }
  const cacheProfile = options.configuration.cacheProfiles[0];
  if (cacheProfile === undefined) throw new Error("catalog_primary_cache_profile_missing");
  const cache = await createFilesystemLocalAssetCache({
    dataDirectory: options.configuration.dataDirectory,
  });
  const retriever = createCatalogRetriever({
    vectorizer: options.vectorizer,
    store: options.catalog,
  });
  let probes = 0;
  const categories = new Map<string, PreparedRunProduct[]>();
  for (const preparedProduct of options.preparedProducts) {
    const category = preparedProduct.prepared.asset.category;
    const records = categories.get(category) ?? [];
    records.push(preparedProduct);
    categories.set(category, records);
  }
  for (const [category, records] of categories) {
    const record = records[0];
    if (record === undefined) continue;
    const hits = await retriever.search({
      query: record.indexed.searchableText,
      category,
      maxDimensionsM: record.prepared.asset.dimensionsM,
      supportType: record.prepared.asset.supportType,
      cacheProfile,
    });
    const hit = hits.find((candidate) => candidate.assetID === record.prepared.asset.assetID);
    if (hit === undefined) throw new Error("catalog_reconciliation_missing_eligible_hit");
    for (const derivative of ["glb", "usdz"] as const) {
      const delivered = await resolveLocalAssetDelivery(
        { asset: record.prepared.asset, cacheProfile, derivative },
        cache,
      );
      if (delivered.assetID !== hit.assetID)
        throw new Error("catalog_reconciliation_delivery_mismatch");
    }
    probes += 1;
  }
  return {
    durablePreparedAssets: options.preparedProducts.length,
    qdrantPoints: options.preparedProducts.length,
    deliveryProbeVerified: true,
    eligibleRetrievalProbes: probes,
  };
}

function bindEnrichment(
  product: IkeaCatalogDiscovery["product"] & {
    variantID: string;
    parentProductID: string;
    preparedAsset: PreparedCatalogAssetRecord["asset"];
  },
  enriched: EmbeddedCatalogProduct,
): EmbeddedCatalogProduct {
  const visualDescriptor = enriched.visualDescriptor.replace(/\s+/gu, " ").trim();
  if (
    visualDescriptor.length === 0 ||
    visualDescriptor.length > 1_000 ||
    /https?:\/\//iu.test(visualDescriptor)
  )
    throw new Error("invalid_visual_descriptor");
  if (
    enriched.textVector.length !== SEMANTIC_VECTOR_SIZE ||
    enriched.textVector.some((component) => !Number.isFinite(component))
  ) {
    throw new Error("invalid_semantic_v1_vector");
  }
  return { ...product, visualDescriptor, textVector: [...enriched.textVector] };
}

function isQuarantinableAssetFailure(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  return /^(invalid_|asset_dimension_mismatch|collision_matches_visible_geometry|source_content_hash_mismatch)/u.test(
    error.message,
  );
}

function quarantineReason(error: unknown): string {
  const value = error instanceof Error ? error.message : "unknown_asset_failure";
  return SAFE_IDENTIFIER.test(value) ? value : "asset_validation_failed";
}

function acquisitionFailureReason(value: string | undefined): string {
  return value !== undefined && SAFE_IDENTIFIER.test(value) ? value : "acquisition_failed";
}

function operationConfiguration(
  environment: IkeaCatalogOperationEnvironment,
): OperationConfiguration {
  const profile = required(environment.REFRAME_CATALOG_PROFILE, "catalog_profile");
  if (profile !== "full" && profile !== "incremental")
    throw new Error("invalid_reframe_catalog_profile");
  const dataDirectory = required(environment.REFRAME_DATA_DIR, "data_dir");
  const frontierRevision = required(
    environment.REFRAME_CATALOG_FRONTIER_REVISION,
    "catalog_frontier_revision",
  );
  if (!SAFE_IDENTIFIER.test(frontierRevision))
    throw new Error("invalid_reframe_catalog_frontier_revision");
  const cacheProfiles = list(
    required(environment.REFRAME_CATALOG_PRIMARY_CACHE_PROFILES, "catalog_primary_cache_profiles"),
    "catalog_primary_cache_profiles",
  );
  const qdrantURL = required(environment.QDRANT_URL, "qdrant_url");
  const parsedQdrantURL = new URL(qdrantURL);
  if (
    !["http:", "https:"].includes(parsedQdrantURL.protocol) ||
    parsedQdrantURL.username !== "" ||
    parsedQdrantURL.password !== ""
  ) {
    throw new Error("invalid_qdrant_url");
  }
  const qdrantAPIKey = optional(environment.QDRANT_API_KEY);
  return {
    profile,
    dataDirectory,
    frontierRevision,
    acquisition: {
      concurrency: boundedInteger(
        environment.REFRAME_CATALOG_ACQUISITION_CONCURRENCY,
        "catalog_acquisition_concurrency",
        1,
        12,
      ),
      requestsPerMinute: boundedInteger(
        environment.REFRAME_CATALOG_REQUESTS_PER_MINUTE,
        "catalog_requests_per_minute",
        1,
        600,
      ),
      maxAttempts: boundedInteger(
        environment.REFRAME_CATALOG_MAX_ATTEMPTS,
        "catalog_max_attempts",
        1,
        8,
      ),
      maxAssetBytes: boundedInteger(
        environment.REFRAME_CATALOG_MAX_ASSET_BYTES,
        "catalog_max_asset_bytes",
        24,
        500 * 1_024 * 1_024,
      ),
    },
    cacheProfiles,
    blenderPath: required(environment.REFRAME_BLENDER_PATH, "blender_path"),
    usdzipPath: required(environment.REFRAME_USDZIP_PATH, "usdzip_path"),
    usdcheckerPath: required(environment.REFRAME_USDCHECKER_PATH, "usdchecker_path"),
    processorRevision: required(
      environment.REFRAME_ASSET_PROCESSOR_REVISION,
      "asset_processor_revision",
    ),
    openAIAPIKey: required(environment.OPENAI_API_KEY, "openai_api_key"),
    qdrantURL: parsedQdrantURL.toString(),
    ...(qdrantAPIKey === undefined ? {} : { qdrantAPIKey }),
  };
}

async function assertProcessorPaths(
  configuration: Pick<OperationConfiguration, "blenderPath" | "usdzipPath" | "usdcheckerPath">,
): Promise<void> {
  const paths = [
    configuration.blenderPath,
    configuration.usdzipPath,
    configuration.usdcheckerPath,
    BLENDER_NORMALIZER_SCRIPT_PATH,
  ];
  if (!(await Promise.all(paths.map((path) => Bun.file(path).exists()))).every(Boolean))
    throw new Error("asset_processor_unavailable");
}

function required(value: string | undefined, name: string): string {
  if (value === undefined || value.trim().length === 0) throw new Error(`missing_reframe_${name}`);
  return value.trim();
}

function optional(value: string | undefined): string | undefined {
  const normalized = value?.trim();
  return normalized === undefined || normalized.length === 0 ? undefined : normalized;
}

function boundedInteger(
  value: string | undefined,
  name: string,
  minimum: number,
  maximum: number,
): number {
  const parsed = Number(required(value, name));
  if (!Number.isSafeInteger(parsed) || parsed < minimum || parsed > maximum)
    throw new Error(`invalid_reframe_${name}`);
  return parsed;
}

function list(value: string, name: string): string[] {
  const values = value
    .split(",")
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);
  if (
    values.length === 0 ||
    values.some((entry) => !SAFE_IDENTIFIER.test(entry)) ||
    new Set(values).size !== values.length
  ) {
    throw new Error(`invalid_reframe_${name}`);
  }
  return values;
}

function hash(value: Uint8Array): string {
  return createHash("sha256").update(value).digest("hex");
}

function hashCanonicalJSON(value: unknown): string {
  return hash(new TextEncoder().encode(JSON.stringify(canonicalize(value))));
}

function canonicalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (typeof value !== "object" || value === null) return value;
  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, nested]) => [key, canonicalize(nested)]),
  );
}
