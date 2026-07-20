import { createHash, randomUUID } from "node:crypto";
import { link, mkdir, rename, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve, sep } from "node:path";

const SHA256 = /^[a-f0-9]{64}$/u;
const GIT_REVISION = /^[a-f0-9]{40}$/u;
const SAFE_IDENTIFIER = /^[a-z0-9][a-z0-9._-]{1,127}$/u;
const RUN_ID = /^run_[a-z0-9][a-z0-9_-]{2,127}$/u;
const MAX_RAW_RECORD_BYTES = 8 * 1_024 * 1_024;

export type CatalogRunProfile = "smoke" | "full" | "incremental";
export type CatalogAssetLifecycleState =
  | "discovered"
  | "metadata_ready"
  | "acquired"
  | "source_validated"
  | "normalized"
  | "derivatives_ready"
  | "enriched"
  | "indexed"
  | "injection_ready"
  | "quarantined"
  | "source_unavailable"
  | "rights_blocked"
  | "retired";

export interface CatalogFrontierIdentity {
  source: "ikea-us";
  market: "us";
  locale: "en-US";
  frontierRevision: string;
}

/** Persisted, non-secret operation settings. Credentials and filesystem paths are intentionally excluded. */
export interface CatalogRunConfiguration {
  schemaVersion: 1;
  profile: CatalogRunProfile;
  frontier: CatalogFrontierIdentity & {
    parserRevision: string;
    /** Build-only downloader provenance, even when the source adapter performs an incremental crawl. */
    downloaderRevision: string;
  };
  acquisition: {
    concurrency: number;
    requestsPerMinute: number;
    maxAttempts: number;
    maxAssetBytes: number;
  };
  processing: {
    processorRevision: string;
    processorConfigurationDigest: string;
  };
  index: {
    collection: string;
    vectorName: "semantic_v1";
    vectorSize: 1_024;
  };
  primaryCacheProfiles: string[];
}

export interface CatalogRunCounters {
  categoryPagesDiscovered: number;
  productPagesDiscovered: number;
  canonicalProductsDiscovered: number;
  variantsDiscovered: number;
  productsWithModelReference: number;
  productsWithoutModelReference: number;
  modelURLsObserved: number;
  assetsDownloaded: number;
  assetsUnchanged: number;
  assetsDeduplicated: number;
  assetsRetried: number;
  assetsFailed: number;
  assetsQuarantined: Record<string, number>;
  assetsNormalized: number;
  assetsDerived: number;
  productsEnriched: number;
  productsEmbedded: number;
  productsIndexed: number;
  placementEligible: number;
  replacementEligible: number;
  primaryCacheSynchronized: number;
}

export interface CatalogRunCheckpoint extends CatalogFrontierIdentity {
  parserRevision: string;
  cursor?: string;
  lastRawRecordSHA256?: string;
  complete: boolean;
  updatedAtMs: number;
}

export interface CatalogRunReconciliation {
  durablePreparedAssets: number;
  qdrantPoints: number;
  deliveryProbeVerified: boolean;
  eligibleRetrievalProbes: number;
}

export interface CatalogRunRecord {
  schemaVersion: 1;
  runID: string;
  status: "running" | "succeeded" | "failed";
  configuration: CatalogRunConfiguration;
  configurationDigest: string;
  startedAtMs: number;
  updatedAtMs: number;
  finishedAtMs?: number;
  lastCheckpoint: CatalogRunCheckpoint;
  counters: CatalogRunCounters;
  failures: Record<string, number>;
  reconciliation?: CatalogRunReconciliation;
}

export interface CatalogDiscoveryObservation {
  runID: string;
  cursor: string;
  sourceProductID: string;
  canonicalProductID: string;
  variantIDs: readonly string[];
  categoryPage: boolean;
  productHasModelReference: boolean;
  modelURLsObserved: number;
  /** Untrusted raw metadata. It is stored by canonical SHA-256, never interpreted as instructions. */
  rawRecord: unknown;
  nowMs: number;
}

export interface CatalogDiscoveryReceipt {
  cursor: string;
  rawRecordSHA256: string;
}

export interface CatalogStageUpdate {
  runID: string;
  assetID: string;
  state: CatalogAssetLifecycleState;
  nowMs: number;
  /** Stable reason code required for terminal states. */
  reason?: string;
}

export type CatalogAcquisitionOutcome =
  | "downloaded"
  | "unchanged"
  | "deduplicated"
  | "retried"
  | "failed";

export interface FilesystemCatalogRunStoreOptions {
  /** Absolute persistent Reframe data directory, never a repository path. */
  dataDirectory: string;
}

export interface CatalogRunStore {
  createRun(options: {
    configuration: CatalogRunConfiguration;
    nowMs: number;
    runID?: string;
  }): Promise<CatalogRunRecord>;
  loadRun(runID: string): Promise<CatalogRunRecord | undefined>;
  loadLatestCheckpoint(
    frontier: CatalogFrontierIdentity,
  ): Promise<CatalogRunCheckpoint | undefined>;
  recordDiscovery(observation: CatalogDiscoveryObservation): Promise<CatalogDiscoveryReceipt>;
  advanceCheckpoint(options: {
    runID: string;
    cursor: string;
    rawRecordSHA256: string;
    nowMs: number;
  }): Promise<void>;
  recordStage(update: CatalogStageUpdate): Promise<void>;
  recordAcquisitionOutcome(options: {
    runID: string;
    outcome: CatalogAcquisitionOutcome;
    nowMs: number;
    reason?: string;
  }): Promise<void>;
  recordCacheSynchronization(options: {
    runID: string;
    assets: number;
    nowMs: number;
  }): Promise<void>;
  completeDiscovery(options: { runID: string; nowMs: number }): Promise<void>;
  recordFailure(options: {
    runID: string;
    reason: string;
    infrastructure: boolean;
    nowMs: number;
  }): Promise<void>;
  finalizeRun(options: {
    runID: string;
    nowMs: number;
    reconciliation: CatalogRunReconciliation;
  }): Promise<CatalogRunRecord>;
}

interface DiscoveryState {
  sourceProductID: string;
  canonicalProductID: string;
  variantIDs: string[];
  productHasModelReference: boolean;
  rawRecordSHA256: string;
}

interface AssetLifecycleRecord {
  schemaVersion: 1;
  assetID: string;
  state: CatalogAssetLifecycleState;
  priorValidState?: Extract<CatalogAssetLifecycleState, "injection_ready">;
  reason?: string;
  updatedAtMs: number;
}

/**
 * Durable catalog authority for restart-safe source runs. The report is small
 * and machine-readable; high-cardinality raw and lifecycle facts are stored as
 * separate immutable/atomic records outside Git.
 */
export async function createFilesystemCatalogRunStore(
  options: FilesystemCatalogRunStoreOptions,
): Promise<CatalogRunStore> {
  const root = requirePersistentDirectory(options.dataDirectory);
  const runsDirectory = join(root, "catalog", "runs");
  const rawDirectory = join(root, "catalog", "metadata", "raw", "sha256");
  const frontierDirectory = join(runsDirectory, "frontiers");
  await Promise.all([
    mkdir(runsDirectory, { recursive: true }),
    mkdir(rawDirectory, { recursive: true }),
    mkdir(frontierDirectory, { recursive: true }),
  ]);

  const loadRun = async (runID: string): Promise<CatalogRunRecord | undefined> => {
    assertRunID(runID);
    const file = Bun.file(runPath(runsDirectory, runID));
    if (!(await file.exists())) return undefined;
    return parseRun(await file.text());
  };

  const saveRun = async (record: CatalogRunRecord): Promise<void> => {
    validateRun(record);
    await writeAtomically(runPath(runsDirectory, record.runID), canonicalJSON(record));
  };

  const updateRun = async (
    runID: string,
    updater: (record: CatalogRunRecord) => CatalogRunRecord,
  ): Promise<CatalogRunRecord> => {
    const existing = await loadRun(runID);
    if (existing === undefined) throw new Error("catalog_run_not_found");
    const next = updater(existing);
    await saveRun(next);
    return next;
  };

  return {
    createRun: async ({ configuration, nowMs, runID }) => {
      validateConfiguration(configuration);
      assertTimestamp(nowMs);
      const id = runID ?? `run_${randomUUID().replaceAll("-", "_")}`;
      assertRunID(id);
      const digest = configurationDigest(configuration);
      const record: CatalogRunRecord = {
        schemaVersion: 1,
        runID: id,
        status: "running",
        configuration: structuredClone(configuration),
        configurationDigest: digest,
        startedAtMs: nowMs,
        updatedAtMs: nowMs,
        lastCheckpoint: {
          source: configuration.frontier.source,
          market: configuration.frontier.market,
          locale: configuration.frontier.locale,
          frontierRevision: configuration.frontier.frontierRevision,
          parserRevision: configuration.frontier.parserRevision,
          complete: false,
          updatedAtMs: nowMs,
        },
        counters: emptyCounters(),
        failures: {},
      };
      const path = runPath(runsDirectory, id);
      if (!(await writeImmutably(path, canonicalJSON(record)))) {
        const existing = await loadRun(id);
        if (existing === undefined || existing.configurationDigest !== digest)
          throw new Error("catalog_run_id_collision");
        return existing;
      }
      return record;
    },
    loadRun,
    loadLatestCheckpoint: async (frontier) => {
      validateFrontierIdentity(frontier);
      const file = Bun.file(frontierPath(frontierDirectory, frontier));
      if (!(await file.exists())) return undefined;
      let parsed: unknown;
      try {
        parsed = JSON.parse(await file.text()) as unknown;
      } catch {
        throw new Error("invalid_catalog_frontier_checkpoint");
      }
      validateCheckpoint(parsed, frontier);
      return parsed;
    },
    recordDiscovery: async (observation) => {
      assertTimestamp(observation.nowMs);
      assertCursor(observation.cursor);
      assertSourceProductID(observation.sourceProductID);
      assertAssetID(observation.canonicalProductID);
      if (
        !Number.isSafeInteger(observation.modelURLsObserved) ||
        observation.modelURLsObserved < 0 ||
        observation.modelURLsObserved > 10_000 ||
        observation.productHasModelReference !== observation.modelURLsObserved > 0
      ) {
        throw new Error("invalid_catalog_discovery_model_urls");
      }
      const variantIDs = normalizeVariantIDs(observation.variantIDs);
      const raw = canonicalJSON(observation.rawRecord);
      const rawBytes = new TextEncoder().encode(raw);
      if (rawBytes.byteLength > MAX_RAW_RECORD_BYTES)
        throw new Error("catalog_raw_record_too_large");
      const rawRecordSHA256 = sha256(rawBytes);
      await writeImmutableOrVerify(safeChild(rawDirectory, rawRecordSHA256), raw);
      const current = await loadRun(observation.runID);
      if (current === undefined) throw new Error("catalog_run_not_found");
      assertRunning(current);
      const discoveryPath = observationPath(
        runsDirectory,
        observation.runID,
        observation.canonicalProductID,
      );
      const previous = await loadDiscoveryState(discoveryPath);
      const nextDiscovery: DiscoveryState = {
        sourceProductID: observation.sourceProductID,
        canonicalProductID: observation.canonicalProductID,
        variantIDs,
        productHasModelReference: observation.productHasModelReference,
        rawRecordSHA256,
      };
      await writeAtomically(discoveryPath, canonicalJSON(nextDiscovery));
      if (previous === undefined) {
        await updateRun(observation.runID, (record) => {
          assertRunning(record);
          const counters = structuredClone(record.counters);
          counters.productPagesDiscovered += 1;
          counters.canonicalProductsDiscovered += 1;
          counters.variantsDiscovered += variantIDs.length;
          counters.modelURLsObserved += observation.modelURLsObserved;
          if (observation.categoryPage) counters.categoryPagesDiscovered += 1;
          if (observation.productHasModelReference) counters.productsWithModelReference += 1;
          else counters.productsWithoutModelReference += 1;
          return { ...record, updatedAtMs: observation.nowMs, counters };
        });
      }
      return { cursor: observation.cursor, rawRecordSHA256 };
    },
    advanceCheckpoint: async ({ runID, cursor, rawRecordSHA256, nowMs }) => {
      assertCursor(cursor);
      if (!SHA256.test(rawRecordSHA256)) throw new Error("invalid_catalog_raw_record_hash");
      assertTimestamp(nowMs);
      const record = await updateRun(runID, (current) => {
        assertRunning(current);
        return {
          ...current,
          updatedAtMs: nowMs,
          lastCheckpoint: {
            ...current.lastCheckpoint,
            cursor,
            lastRawRecordSHA256: rawRecordSHA256,
            updatedAtMs: nowMs,
          },
        };
      });
      await writeAtomically(
        frontierPath(frontierDirectory, record.lastCheckpoint),
        canonicalJSON(record.lastCheckpoint),
      );
    },
    recordStage: async (update) => {
      assertTimestamp(update.nowMs);
      assertAssetID(update.assetID);
      const current = await loadRun(update.runID);
      if (current === undefined) throw new Error("catalog_run_not_found");
      assertRunning(current);
      const path = assetPath(runsDirectory, update.runID, update.assetID);
      const previous = await loadAssetLifecycle(path);
      validateLifecycleTransition(previous, update);
      const next: AssetLifecycleRecord = {
        schemaVersion: 1,
        assetID: update.assetID,
        state: update.state,
        ...(previous?.state === "injection_ready" && isTerminal(update.state)
          ? { priorValidState: "injection_ready" as const }
          : {}),
        ...(update.reason === undefined ? {} : { reason: update.reason }),
        updatedAtMs: update.nowMs,
      };
      await writeAtomically(path, canonicalJSON(next));
      if (previous?.state !== update.state) {
        await updateRun(update.runID, (record) => {
          assertRunning(record);
          return {
            ...record,
            updatedAtMs: update.nowMs,
            counters: countStageTransition(record.counters, update.state, update.reason),
            failures:
              isTerminal(update.state) && update.reason !== undefined
                ? incrementReason(record.failures, update.reason)
                : record.failures,
          };
        });
      }
    },
    recordAcquisitionOutcome: async ({ runID, outcome, nowMs, reason }) => {
      assertTimestamp(nowMs);
      if (!ACQUISITION_OUTCOMES.has(outcome))
        throw new Error("invalid_catalog_acquisition_outcome");
      if (outcome === "failed") {
        if (reason === undefined) throw new Error("missing_catalog_acquisition_reason");
        assertReason(reason);
      } else if (reason !== undefined) {
        throw new Error("invalid_catalog_acquisition_reason");
      }
      await updateRun(runID, (record) => {
        assertRunning(record);
        const counters = { ...record.counters };
        if (outcome === "downloaded") counters.assetsDownloaded += 1;
        if (outcome === "unchanged") counters.assetsUnchanged += 1;
        if (outcome === "deduplicated") counters.assetsDeduplicated += 1;
        if (outcome === "retried") counters.assetsRetried += 1;
        if (outcome === "failed") counters.assetsFailed += 1;
        return {
          ...record,
          updatedAtMs: nowMs,
          counters,
          failures:
            outcome === "failed" && reason !== undefined
              ? incrementReason(record.failures, reason)
              : record.failures,
        };
      });
    },
    recordCacheSynchronization: async ({ runID, assets, nowMs }) => {
      assertTimestamp(nowMs);
      if (!Number.isSafeInteger(assets) || assets < 0) throw new Error("invalid_cache_sync_count");
      await updateRun(runID, (record) => {
        assertRunning(record);
        return {
          ...record,
          updatedAtMs: nowMs,
          counters: {
            ...record.counters,
            primaryCacheSynchronized: record.counters.primaryCacheSynchronized + assets,
          },
        };
      });
    },
    completeDiscovery: async ({ runID, nowMs }) => {
      assertTimestamp(nowMs);
      const record = await updateRun(runID, (current) => {
        assertRunning(current);
        return {
          ...current,
          updatedAtMs: nowMs,
          lastCheckpoint: { ...current.lastCheckpoint, complete: true, updatedAtMs: nowMs },
        };
      });
      await writeAtomically(
        frontierPath(frontierDirectory, record.lastCheckpoint),
        canonicalJSON(record.lastCheckpoint),
      );
    },
    recordFailure: async ({ runID, reason, infrastructure, nowMs }) => {
      assertTimestamp(nowMs);
      assertReason(reason);
      await updateRun(runID, (record) => {
        assertRunning(record);
        return {
          ...record,
          updatedAtMs: nowMs,
          status: infrastructure ? "failed" : record.status,
          ...(infrastructure ? { finishedAtMs: nowMs } : {}),
          counters: {
            ...record.counters,
            assetsFailed: record.counters.assetsFailed + (infrastructure ? 0 : 1),
          },
          failures: incrementReason(record.failures, reason),
        };
      });
    },
    finalizeRun: async ({ runID, nowMs, reconciliation }) => {
      assertTimestamp(nowMs);
      validateReconciliation(reconciliation);
      return await updateRun(runID, (record) => {
        assertRunning(record);
        assertFinalizable(record, reconciliation);
        return {
          ...record,
          status: "succeeded",
          updatedAtMs: nowMs,
          finishedAtMs: nowMs,
          reconciliation: structuredClone(reconciliation),
        };
      });
    },
  };
}

function emptyCounters(): CatalogRunCounters {
  return {
    categoryPagesDiscovered: 0,
    productPagesDiscovered: 0,
    canonicalProductsDiscovered: 0,
    variantsDiscovered: 0,
    productsWithModelReference: 0,
    productsWithoutModelReference: 0,
    modelURLsObserved: 0,
    assetsDownloaded: 0,
    assetsUnchanged: 0,
    assetsDeduplicated: 0,
    assetsRetried: 0,
    assetsFailed: 0,
    assetsQuarantined: {},
    assetsNormalized: 0,
    assetsDerived: 0,
    productsEnriched: 0,
    productsEmbedded: 0,
    productsIndexed: 0,
    placementEligible: 0,
    replacementEligible: 0,
    primaryCacheSynchronized: 0,
  };
}

function countStageTransition(
  counters: CatalogRunCounters,
  state: CatalogAssetLifecycleState,
  reason: string | undefined,
): CatalogRunCounters {
  const next = structuredClone(counters);
  if (state === "normalized") next.assetsNormalized += 1;
  if (state === "derivatives_ready") next.assetsDerived += 1;
  if (state === "enriched") {
    next.productsEnriched += 1;
    next.productsEmbedded += 1;
  }
  if (state === "indexed") next.productsIndexed += 1;
  if (state === "injection_ready") {
    next.placementEligible += 1;
    next.replacementEligible += 1;
  }
  if (state === "quarantined") {
    const code = reason ?? "unspecified";
    next.assetsQuarantined[code] = (next.assetsQuarantined[code] ?? 0) + 1;
  }
  return next;
}

function validateLifecycleTransition(
  previous: AssetLifecycleRecord | undefined,
  update: CatalogStageUpdate,
): void {
  if (!LIFECYCLE_STATES.has(update.state)) throw new Error("invalid_catalog_asset_state");
  if (isTerminal(update.state)) {
    if (update.reason === undefined) throw new Error("missing_catalog_terminal_reason");
    assertReason(update.reason);
    if (previous?.state !== undefined && isTerminal(previous.state))
      throw new Error("catalog_asset_terminal_state");
    return;
  }
  if (update.reason !== undefined) throw new Error("catalog_nonterminal_reason");
  const expected = nextLifecycleState(previous?.state);
  if (update.state !== expected) throw new Error("invalid_catalog_lifecycle_transition");
}

function nextLifecycleState(
  previous: CatalogAssetLifecycleState | undefined,
): CatalogAssetLifecycleState | undefined {
  if (previous === undefined) return "discovered";
  const index = ACTIVE_STATES.indexOf(previous as (typeof ACTIVE_STATES)[number]);
  return index < 0 ? undefined : ACTIVE_STATES[index + 1];
}

function isTerminal(state: CatalogAssetLifecycleState): boolean {
  return !ACTIVE_STATES.includes(state as (typeof ACTIVE_STATES)[number]);
}

const ACTIVE_STATES = [
  "discovered",
  "metadata_ready",
  "acquired",
  "source_validated",
  "normalized",
  "derivatives_ready",
  "enriched",
  "indexed",
  "injection_ready",
] as const;
const LIFECYCLE_STATES = new Set<CatalogAssetLifecycleState>([
  ...ACTIVE_STATES,
  "quarantined",
  "source_unavailable",
  "rights_blocked",
  "retired",
]);
const ACQUISITION_OUTCOMES = new Set<CatalogAcquisitionOutcome>([
  "downloaded",
  "unchanged",
  "deduplicated",
  "retried",
  "failed",
]);

function assertFinalizable(
  record: CatalogRunRecord,
  reconciliation: CatalogRunReconciliation,
): void {
  if (!record.lastCheckpoint.complete) throw new Error("catalog_discovery_incomplete");
  if (
    record.configuration.profile === "full" &&
    record.counters.canonicalProductsDiscovered > 0 &&
    record.counters.placementEligible === 0
  ) {
    throw new Error("catalog_zero_injection_ready");
  }
  if (record.counters.placementEligible > 0) {
    if (reconciliation.eligibleRetrievalProbes < 1)
      throw new Error("catalog_retrieval_probe_missing");
    if (!reconciliation.deliveryProbeVerified) throw new Error("catalog_delivery_probe_failed");
  }
  if (reconciliation.durablePreparedAssets !== reconciliation.qdrantPoints)
    throw new Error("catalog_qdrant_reconciliation_failed");
  if (record.counters.placementEligible !== reconciliation.durablePreparedAssets)
    throw new Error("catalog_prepared_asset_reconciliation_failed");
}

function validateConfiguration(value: CatalogRunConfiguration): void {
  if (typeof value !== "object" || value === null || value.schemaVersion !== 1)
    throw new Error("invalid_catalog_run_configuration");
  if (!(["smoke", "full", "incremental"] as const).includes(value.profile))
    throw new Error("invalid_catalog_run_profile");
  validateFrontierIdentity(value.frontier);
  if (
    !SAFE_IDENTIFIER.test(value.frontier.parserRevision) ||
    !GIT_REVISION.test(value.frontier.downloaderRevision) ||
    !Number.isSafeInteger(value.acquisition.concurrency) ||
    value.acquisition.concurrency < 1 ||
    value.acquisition.concurrency > 12 ||
    !Number.isSafeInteger(value.acquisition.requestsPerMinute) ||
    value.acquisition.requestsPerMinute < 1 ||
    value.acquisition.requestsPerMinute > 600 ||
    !Number.isSafeInteger(value.acquisition.maxAttempts) ||
    value.acquisition.maxAttempts < 1 ||
    value.acquisition.maxAttempts > 8 ||
    !Number.isSafeInteger(value.acquisition.maxAssetBytes) ||
    value.acquisition.maxAssetBytes < 24 ||
    value.acquisition.maxAssetBytes > 500 * 1_024 * 1_024 ||
    !SAFE_IDENTIFIER.test(value.processing.processorRevision) ||
    !SHA256.test(value.processing.processorConfigurationDigest) ||
    !SAFE_IDENTIFIER.test(value.index.collection) ||
    value.index.vectorName !== "semantic_v1" ||
    value.index.vectorSize !== 1_024 ||
    !Array.isArray(value.primaryCacheProfiles) ||
    value.primaryCacheProfiles.length === 0 ||
    value.primaryCacheProfiles.some((profile) => !SAFE_IDENTIFIER.test(profile)) ||
    new Set(value.primaryCacheProfiles).size !== value.primaryCacheProfiles.length
  ) {
    throw new Error("invalid_catalog_run_configuration");
  }
}

function validateFrontierIdentity(value: CatalogFrontierIdentity): void {
  if (
    typeof value !== "object" ||
    value === null ||
    value.source !== "ikea-us" ||
    value.market !== "us" ||
    value.locale !== "en-US" ||
    !SAFE_IDENTIFIER.test(value.frontierRevision)
  ) {
    throw new Error("invalid_catalog_frontier");
  }
}

function validateRun(value: CatalogRunRecord): void {
  if (
    typeof value !== "object" ||
    value === null ||
    value.schemaVersion !== 1 ||
    !RUN_ID.test(value.runID) ||
    !(["running", "succeeded", "failed"] as const).includes(value.status) ||
    !SHA256.test(value.configurationDigest)
  ) {
    throw new Error("invalid_catalog_run_record");
  }
  validateConfiguration(value.configuration);
  if (configurationDigest(value.configuration) !== value.configurationDigest)
    throw new Error("invalid_catalog_run_record");
  assertTimestamp(value.startedAtMs);
  assertTimestamp(value.updatedAtMs);
  validateCheckpoint(value.lastCheckpoint, value.configuration.frontier);
  validateCounters(value.counters);
  validateReasons(value.failures);
  if (value.reconciliation !== undefined) validateReconciliation(value.reconciliation);
}

function parseRun(value: string): CatalogRunRecord {
  let parsed: unknown;
  try {
    parsed = JSON.parse(value) as unknown;
  } catch {
    throw new Error("invalid_catalog_run_record");
  }
  validateRun(parsed as CatalogRunRecord);
  return parsed as CatalogRunRecord;
}

function validateCheckpoint(
  value: unknown,
  frontier: CatalogFrontierIdentity,
): asserts value is CatalogRunCheckpoint {
  if (typeof value !== "object" || value === null || Array.isArray(value))
    throw new Error("invalid_catalog_frontier_checkpoint");
  const checkpoint = value as Partial<CatalogRunCheckpoint>;
  if (
    checkpoint.source !== frontier.source ||
    checkpoint.market !== frontier.market ||
    checkpoint.locale !== frontier.locale ||
    checkpoint.frontierRevision !== frontier.frontierRevision ||
    typeof checkpoint.parserRevision !== "string" ||
    !SAFE_IDENTIFIER.test(checkpoint.parserRevision) ||
    typeof checkpoint.complete !== "boolean"
  ) {
    throw new Error("invalid_catalog_frontier_checkpoint");
  }
  assertTimestamp(checkpoint.updatedAtMs);
  if (checkpoint.cursor !== undefined) assertCursor(checkpoint.cursor);
  if (checkpoint.lastRawRecordSHA256 !== undefined && !SHA256.test(checkpoint.lastRawRecordSHA256))
    throw new Error("invalid_catalog_frontier_checkpoint");
}

function validateCounters(counters: CatalogRunCounters): void {
  if (typeof counters !== "object" || counters === null || Array.isArray(counters))
    throw new Error("invalid_catalog_run_counters");
  for (const [key, value] of Object.entries(counters)) {
    if (key === "assetsQuarantined") continue;
    if (!Number.isSafeInteger(value) || value < 0) throw new Error("invalid_catalog_run_counters");
  }
  validateReasons(counters.assetsQuarantined);
}

function validateReasons(value: Record<string, number>): void {
  if (typeof value !== "object" || value === null || Array.isArray(value))
    throw new Error("invalid_catalog_failure_reasons");
  for (const [reason, count] of Object.entries(value)) {
    assertReason(reason);
    if (!Number.isSafeInteger(count) || count < 1)
      throw new Error("invalid_catalog_failure_reasons");
  }
}

function validateReconciliation(value: CatalogRunReconciliation): void {
  if (
    typeof value !== "object" ||
    value === null ||
    !Number.isSafeInteger(value.durablePreparedAssets) ||
    value.durablePreparedAssets < 0 ||
    !Number.isSafeInteger(value.qdrantPoints) ||
    value.qdrantPoints < 0 ||
    typeof value.deliveryProbeVerified !== "boolean" ||
    !Number.isSafeInteger(value.eligibleRetrievalProbes) ||
    value.eligibleRetrievalProbes < 0
  ) {
    throw new Error("invalid_catalog_reconciliation");
  }
}

function incrementReason(reasons: Record<string, number>, reason: string): Record<string, number> {
  return { ...reasons, [reason]: (reasons[reason] ?? 0) + 1 };
}

function assertRunning(record: CatalogRunRecord): void {
  if (record.status !== "running") throw new Error("catalog_run_not_running");
}

function assertTimestamp(value: unknown): asserts value is number {
  if (!Number.isSafeInteger(value) || (value as number) < 0)
    throw new Error("invalid_catalog_timestamp");
}

function assertCursor(value: unknown): asserts value is string {
  if (typeof value !== "string" || value.length === 0 || value.length > 4_096)
    throw new Error("invalid_catalog_cursor");
}

function assertReason(value: unknown): asserts value is string {
  if (typeof value !== "string" || !SAFE_IDENTIFIER.test(value))
    throw new Error("invalid_catalog_reason");
}

function assertRunID(value: unknown): asserts value is string {
  if (typeof value !== "string" || !RUN_ID.test(value)) throw new Error("invalid_catalog_run_id");
}

function assertAssetID(value: unknown): asserts value is string {
  if (typeof value !== "string" || !SAFE_IDENTIFIER.test(value))
    throw new Error("invalid_catalog_asset_id");
}

function assertSourceProductID(value: unknown): asserts value is string {
  if (typeof value !== "string" || !/^\d{8}$/u.test(value))
    throw new Error("invalid_catalog_source_product_id");
}

function normalizeVariantIDs(value: readonly string[]): string[] {
  if (!Array.isArray(value) || value.length > 10_000) throw new Error("invalid_catalog_variants");
  const normalized = [...new Set(value)];
  if (normalized.some((variantID) => !SAFE_IDENTIFIER.test(variantID)))
    throw new Error("invalid_catalog_variants");
  return normalized.sort();
}

function configurationDigest(configuration: CatalogRunConfiguration): string {
  return sha256(new TextEncoder().encode(canonicalJSON(configuration)));
}

function frontierPath(directory: string, frontier: CatalogFrontierIdentity): string {
  const identity: CatalogFrontierIdentity = {
    source: frontier.source,
    market: frontier.market,
    locale: frontier.locale,
    frontierRevision: frontier.frontierRevision,
  };
  const digest = sha256(new TextEncoder().encode(canonicalJSON(identity)));
  return safeChild(directory, `${digest}.json`);
}

function runPath(directory: string, runID: string): string {
  assertRunID(runID);
  return safeChild(directory, `${runID}.json`);
}

function observationPath(directory: string, runID: string, productID: string): string {
  assertRunID(runID);
  assertAssetID(productID);
  return safeChild(join(directory, runID, "discovery"), `${productID}.json`);
}

function assetPath(directory: string, runID: string, assetID: string): string {
  assertRunID(runID);
  assertAssetID(assetID);
  return safeChild(join(directory, runID, "assets"), `${assetID}.json`);
}

async function loadDiscoveryState(path: string): Promise<DiscoveryState | undefined> {
  const file = Bun.file(path);
  if (!(await file.exists())) return undefined;
  let parsed: unknown;
  try {
    parsed = JSON.parse(await file.text()) as unknown;
  } catch {
    throw new Error("invalid_catalog_discovery_state");
  }
  if (
    typeof parsed !== "object" ||
    parsed === null ||
    Array.isArray(parsed) ||
    !/^\d{8}$/u.test((parsed as Partial<DiscoveryState>).sourceProductID ?? "") ||
    !SAFE_IDENTIFIER.test((parsed as Partial<DiscoveryState>).canonicalProductID ?? "") ||
    !Array.isArray((parsed as Partial<DiscoveryState>).variantIDs) ||
    !SHA256.test((parsed as Partial<DiscoveryState>).rawRecordSHA256 ?? "")
  ) {
    throw new Error("invalid_catalog_discovery_state");
  }
  return parsed as DiscoveryState;
}

async function loadAssetLifecycle(path: string): Promise<AssetLifecycleRecord | undefined> {
  const file = Bun.file(path);
  if (!(await file.exists())) return undefined;
  let parsed: unknown;
  try {
    parsed = JSON.parse(await file.text()) as unknown;
  } catch {
    throw new Error("invalid_catalog_asset_lifecycle");
  }
  if (
    typeof parsed !== "object" ||
    parsed === null ||
    Array.isArray(parsed) ||
    (parsed as Partial<AssetLifecycleRecord>).schemaVersion !== 1 ||
    !SAFE_IDENTIFIER.test((parsed as Partial<AssetLifecycleRecord>).assetID ?? "") ||
    !LIFECYCLE_STATES.has(
      (parsed as Partial<AssetLifecycleRecord>).state as CatalogAssetLifecycleState,
    )
  ) {
    throw new Error("invalid_catalog_asset_lifecycle");
  }
  return parsed as AssetLifecycleRecord;
}

function requirePersistentDirectory(value: string): string {
  if (typeof value !== "string" || value.length === 0 || !value.startsWith(sep))
    throw new Error("invalid_catalog_data_directory");
  return resolve(value);
}

function safeChild(directory: string, filename: string): string {
  const root = resolve(directory);
  const candidate = resolve(join(root, filename));
  if (!candidate.startsWith(`${root}${sep}`)) throw new Error("invalid_catalog_storage_path");
  return candidate;
}

async function writeAtomically(path: string, data: string): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  const temporaryPath = `${path}.${randomUUID()}.tmp`;
  try {
    await writeFile(temporaryPath, data, { flag: "wx" });
    await rename(temporaryPath, path);
  } finally {
    await rm(temporaryPath, { force: true });
  }
}

async function writeImmutably(path: string, data: string): Promise<boolean> {
  await mkdir(dirname(path), { recursive: true });
  const temporaryPath = `${path}.${randomUUID()}.tmp`;
  try {
    await writeFile(temporaryPath, data, { flag: "wx" });
    try {
      await link(temporaryPath, path);
      return true;
    } catch (error) {
      if (isAlreadyExists(error)) return false;
      throw error;
    }
  } finally {
    await rm(temporaryPath, { force: true });
  }
}

async function writeImmutableOrVerify(path: string, data: string): Promise<void> {
  if (await writeImmutably(path, data)) return;
  if ((await Bun.file(path).text()) !== data) throw new Error("catalog_raw_record_hash_collision");
}

function isAlreadyExists(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    (error as { code?: unknown }).code === "EEXIST"
  );
}

function sha256(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

function canonicalJSON(value: unknown): string {
  return `${JSON.stringify(canonicalize(value))}\n`;
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
