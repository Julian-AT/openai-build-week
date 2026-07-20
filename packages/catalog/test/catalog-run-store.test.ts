import { test } from "bun:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  type CatalogAssetLifecycleState,
  type CatalogRunConfiguration,
  createFilesystemCatalogRunStore,
} from "../src/index.ts";

test("persists a frontier checkpoint, raw record hash, counters, and terminal reconciliation report", async () => {
  const dataDirectory = await mkdtemp(join(tmpdir(), "reframe-catalog-runs-"));
  try {
    const store = await createFilesystemCatalogRunStore({ dataDirectory });
    const configuration = runConfiguration("full");
    const run = await store.createRun({
      configuration,
      nowMs: 1_000,
      runID: "run_catalog_full_001",
    });
    assert.equal(run.status, "running");
    assert.equal(run.configurationDigest.length, 64);

    const discovery = await store.recordDiscovery({
      runID: run.runID,
      cursor: "https://www.ikea.com/us/en/p/kallax-white-s99017186/",
      sourceProductID: "99017186",
      canonicalProductID: "ikea-us-99017186",
      variantIDs: ["ikea-us-99017186-blue", "ikea-us-99017186-white"],
      categoryPage: true,
      productHasModelReference: true,
      modelURLsObserved: 2,
      rawRecord: { name: "KALLAX", description: "untrusted source data" },
      nowMs: 1_100,
    });
    assert.equal(discovery.rawRecordSHA256.length, 64);

    await store.recordAcquisitionOutcome({
      runID: run.runID,
      outcome: "downloaded",
      nowMs: 1_150,
    });

    const states: readonly CatalogAssetLifecycleState[] = [
      "discovered",
      "metadata_ready",
      "acquired",
      "source_validated",
      "normalized",
      "derivatives_ready",
      "enriched",
      "indexed",
      "injection_ready",
    ];
    for (const [index, state] of states.entries()) {
      await store.recordStage({
        runID: run.runID,
        assetID: "ikea-us-99017186-aaaaaaaaaaaa",
        state,
        nowMs: 1_200 + index,
      });
    }
    await store.completeDiscovery({ runID: run.runID, nowMs: 1_300 });
    await store.recordCacheSynchronization({ runID: run.runID, assets: 1, nowMs: 1_400 });
    const finalized = await store.finalizeRun({
      runID: run.runID,
      nowMs: 1_500,
      reconciliation: {
        durablePreparedAssets: 1,
        qdrantPoints: 1,
        deliveryProbeVerified: true,
        eligibleRetrievalProbes: 1,
      },
    });

    assert.equal(finalized.status, "succeeded");
    assert.equal(finalized.counters.canonicalProductsDiscovered, 1);
    assert.equal(finalized.counters.variantsDiscovered, 2);
    assert.equal(finalized.counters.assetsDerived, 1);
    assert.equal(finalized.counters.assetsDownloaded, 1);
    assert.equal(finalized.counters.placementEligible, 1);
    assert.equal(finalized.counters.primaryCacheSynchronized, 1);
    assert.equal(finalized.lastCheckpoint.cursor, discovery.cursor);

    const resumed = await store.loadLatestCheckpoint({
      source: "ikea-us",
      market: "us",
      locale: "en-US",
      frontierRevision: "ikea-us-en-v1",
    });
    assert.deepEqual(resumed, finalized.lastCheckpoint);
    assert.equal((await store.loadRun(run.runID))?.status, "succeeded");
  } finally {
    await rm(dataDirectory, { recursive: true, force: true });
  }
});

function runConfiguration(profile: CatalogRunConfiguration["profile"]): CatalogRunConfiguration {
  return {
    schemaVersion: 1,
    profile,
    frontier: {
      source: "ikea-us",
      market: "us",
      locale: "en-US",
      frontierRevision: "ikea-us-en-v1",
      parserRevision: "ikea-html-v1",
      downloaderRevision: "3a036f1820c44b470aded71e651a1e791fd5d022",
    },
    acquisition: {
      concurrency: 4,
      requestsPerMinute: 30,
      maxAttempts: 3,
      maxAssetBytes: 250 * 1_024 * 1_024,
    },
    processing: {
      processorRevision: "blender-5.2.0-fbe6228777e7",
      processorConfigurationDigest: "a".repeat(64),
    },
    index: { collection: "reframe_catalog_v1", vectorName: "semantic_v1", vectorSize: 1024 },
    primaryCacheProfiles: ["ios-primary", "web-primary"],
  };
}
