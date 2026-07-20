import type {
  CatalogAcquisitionOutcome,
  CatalogAssetLifecycleState,
  CatalogDiscoveryObservation,
  CatalogRunCheckpoint,
  CatalogRunConfiguration,
  CatalogRunReconciliation,
  CatalogRunRecord,
  CatalogRunStore,
} from "./catalog-run-store.ts";

export interface CatalogOperationDiscovery
  extends Omit<CatalogDiscoveryObservation, "runID" | "nowMs"> {}

/** A source is discovery-only: it cannot derive, index, or mutate Qdrant. */
export interface CatalogSource<
  TDiscovery extends CatalogOperationDiscovery = CatalogOperationDiscovery,
> {
  discover(context: {
    profile: CatalogRunConfiguration["profile"];
    /** Present only for an incremental run of the same source/market/locale/frontier revision. */
    checkpoint: CatalogRunCheckpoint | undefined;
    signal: AbortSignal | undefined;
  }): AsyncIterable<TDiscovery>;
}

export interface CatalogOperationProgress {
  readonly run: CatalogRunRecord;
  acquisition(outcome: CatalogAcquisitionOutcome, reason?: string): Promise<void>;
  stage(assetID: string, state: CatalogAssetLifecycleState, reason?: string): Promise<void>;
  cacheSynchronized(assets: number): Promise<void>;
}

export interface RunCatalogOperationOptions<
  TDiscovery extends CatalogOperationDiscovery = CatalogOperationDiscovery,
> {
  store: CatalogRunStore;
  configuration: CatalogRunConfiguration;
  source: CatalogSource<TDiscovery>;
  /** Performs non-secret processor, OpenAI, Qdrant, cache-volume, and capacity checks. */
  verifyInfrastructure(context: {
    run: CatalogRunRecord;
    signal: AbortSignal | undefined;
  }): Promise<void>;
  /** Must persist the asset lifecycle after each successful stage before proceeding to the next. */
  process(discovery: TDiscovery, progress: CatalogOperationProgress): Promise<void>;
  /** Reconciles durable prepared records, Qdrant, eligible retrieval, and hash-verified delivery. */
  reconcile(context: {
    run: CatalogRunRecord;
    signal: AbortSignal | undefined;
  }): Promise<CatalogRunReconciliation>;
  now?: () => number;
  runID?: string;
  signal?: AbortSignal;
}

/**
 * The operator sequence for smoke, full, and incremental catalog profiles.
 * It deliberately persists configuration and every discovery/lifecycle update
 * before delegating to a later stage, so crashes resume from durable state.
 */
export async function runCatalogOperation<TDiscovery extends CatalogOperationDiscovery>(
  options: RunCatalogOperationOptions<TDiscovery>,
): Promise<CatalogRunRecord> {
  const now = options.now ?? Date.now;
  throwIfAborted(options.signal);
  const run = await options.store.createRun({
    configuration: options.configuration,
    nowMs: now(),
    ...(options.runID === undefined ? {} : { runID: options.runID }),
  });
  const checkpoint =
    options.configuration.profile === "incremental"
      ? await options.store.loadLatestCheckpoint(options.configuration.frontier)
      : undefined;
  const progress = createProgress(options.store, run, now);
  try {
    throwIfAborted(options.signal);
    await options.verifyInfrastructure({ run, signal: options.signal });
    for await (const discovery of options.source.discover({
      profile: options.configuration.profile,
      checkpoint,
      signal: options.signal,
    })) {
      throwIfAborted(options.signal);
      const receipt = await options.store.recordDiscovery({
        ...discovery,
        runID: run.runID,
        nowMs: now(),
      });
      await options.process(discovery, progress);
      await options.store.advanceCheckpoint({ ...receipt, runID: run.runID, nowMs: now() });
    }
    throwIfAborted(options.signal);
    await options.store.completeDiscovery({ runID: run.runID, nowMs: now() });
    const reconciliation = await options.reconcile({ run, signal: options.signal });
    throwIfAborted(options.signal);
    return await options.store.finalizeRun({ runID: run.runID, nowMs: now(), reconciliation });
  } catch (error) {
    await failInfrastructure(options.store, run.runID, now);
    throw error;
  }
}

function createProgress(
  store: CatalogRunStore,
  run: CatalogRunRecord,
  now: () => number,
): CatalogOperationProgress {
  return {
    run,
    acquisition: async (outcome, reason) =>
      await store.recordAcquisitionOutcome({
        runID: run.runID,
        outcome,
        nowMs: now(),
        ...(reason === undefined ? {} : { reason }),
      }),
    stage: async (assetID, state, reason) =>
      await store.recordStage({
        runID: run.runID,
        assetID,
        state,
        nowMs: now(),
        ...(reason === undefined ? {} : { reason }),
      }),
    cacheSynchronized: async (assets) =>
      await store.recordCacheSynchronization({ runID: run.runID, assets, nowMs: now() }),
  };
}

async function failInfrastructure(
  store: CatalogRunStore,
  runID: string,
  now: () => number,
): Promise<void> {
  try {
    await store.recordFailure({
      runID,
      reason: "operation_infrastructure_failure",
      infrastructure: true,
      nowMs: now(),
    });
  } catch {
    // The original fault remains authoritative; never replace it with a logging failure.
  }
}

function throwIfAborted(signal: AbortSignal | undefined): void {
  if (signal?.aborted) throw new Error("catalog_operation_cancelled");
}
