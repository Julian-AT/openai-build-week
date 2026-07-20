import { test } from "bun:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  type CatalogOperationDiscovery,
  type CatalogRunConfiguration,
  createFilesystemCatalogRunStore,
  runCatalogOperation,
} from "../src/index.ts";

test("orchestrates a source-only frontier through durable lifecycle records before reconciliation", async () => {
  const dataDirectory = await mkdtemp(join(tmpdir(), "reframe-catalog-operation-"));
  try {
    const store = await createFilesystemCatalogRunStore({ dataDirectory });
    const sourceRecord: CatalogOperationDiscovery = {
      cursor: "product:1",
      sourceProductID: "99017186",
      canonicalProductID: "ikea-us-99017186",
      variantIDs: ["ikea-us-99017186-white"],
      categoryPage: true,
      productHasModelReference: true,
      modelURLsObserved: 1,
      rawRecord: { source: "untrusted", name: "KALLAX" },
    };
    const result = await runCatalogOperation({
      store,
      configuration: configuration(),
      runID: "run_catalog_operation_001",
      now: () => 2_000,
      verifyInfrastructure: async (context) => {
        assert.equal(
          (await store.loadRun(context.run.runID))?.configurationDigest,
          context.run.configurationDigest,
        );
      },
      source: {
        discover: async function* ({ checkpoint }) {
          assert.equal(checkpoint, undefined);
          yield sourceRecord;
        },
      },
      process: async (discovery, progress) => {
        assert.deepEqual(discovery, sourceRecord);
        await progress.acquisition("downloaded");
        for (const state of [
          "discovered",
          "metadata_ready",
          "acquired",
          "source_validated",
          "normalized",
          "derivatives_ready",
          "enriched",
          "indexed",
          "injection_ready",
        ] as const) {
          await progress.stage("ikea-us-99017186-aaaaaaaaaaaa", state);
        }
        await progress.cacheSynchronized(1);
      },
      reconcile: async () => ({
        durablePreparedAssets: 1,
        qdrantPoints: 1,
        deliveryProbeVerified: true,
        eligibleRetrievalProbes: 1,
      }),
    });

    assert.equal(result.status, "succeeded");
    assert.equal(result.counters.productsIndexed, 1);
    assert.equal(result.counters.primaryCacheSynchronized, 1);
  } finally {
    await rm(dataDirectory, { recursive: true, force: true });
  }
});

function configuration(): CatalogRunConfiguration {
  return {
    schemaVersion: 1,
    profile: "full",
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
      maxAssetBytes: 10_000_000,
    },
    processing: {
      processorRevision: "blender-5.2.0-fbe6228777e7",
      processorConfigurationDigest: "a".repeat(64),
    },
    index: { collection: "reframe_catalog_v1", vectorName: "semantic_v1", vectorSize: 1024 },
    primaryCacheProfiles: ["ios-primary"],
  };
}
