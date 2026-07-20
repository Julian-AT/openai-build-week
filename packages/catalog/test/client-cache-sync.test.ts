import { test } from "bun:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  createFilesystemLocalAssetCache,
  createFilesystemPreparedAssetStore,
  type PreparedCatalogAssetRecord,
  resolveLocalAssetDelivery,
  synchronizePreparedAssetsToLocalCache,
} from "../src/index.ts";

test("synchronizes only verified prepared derivatives into an explicit primary cache", async () => {
  const dataDirectory = await mkdtemp(join(tmpdir(), "reframe-catalog-cache-"));
  try {
    const preparedStore = await createFilesystemPreparedAssetStore({ dataDirectory });
    const prepared = await preparedRecord(preparedStore);

    const report = await synchronizePreparedAssetsToLocalCache({
      dataDirectory,
      cacheProfile: "ios-primary",
      records: [prepared],
      preparedStore,
    });

    assert.equal(report.counters.assetsSynchronized, 1);
    assert.equal(report.entries.length, 1);
    assert.equal(report.entries[0]?.assetID, prepared.asset.assetID);

    const cache = await createFilesystemLocalAssetCache({ dataDirectory });
    const delivery = await resolveLocalAssetDelivery(
      { asset: prepared.asset, cacheProfile: "ios-primary", derivative: "usdz" },
      cache,
    );
    assert.equal(delivery.sha256, prepared.asset.derivatives.usdz.sha256);
    assert.deepEqual(delivery.bytes, new Uint8Array([5, 6, 7, 8]));
    await assert.rejects(
      resolveLocalAssetDelivery(
        { asset: prepared.asset, cacheProfile: "web-primary", derivative: "glb" },
        cache,
      ),
      /asset_not_cached/,
    );
  } finally {
    await rm(dataDirectory, { recursive: true, force: true });
  }
});

async function preparedRecord(
  store: Awaited<ReturnType<typeof createFilesystemPreparedAssetStore>>,
): Promise<PreparedCatalogAssetRecord> {
  const sourceSHA256 = "a".repeat(64);
  const derivationID = "b".repeat(64);
  const glb = await derivative(
    store,
    "glb",
    new Uint8Array([1, 2, 3, 4]),
    sourceSHA256,
    derivationID,
  );
  const usdz = await derivative(
    store,
    "usdz",
    new Uint8Array([5, 6, 7, 8]),
    sourceSHA256,
    derivationID,
  );
  const collision = await derivative(
    store,
    "collision",
    new Uint8Array([9, 10, 11, 12]),
    sourceSHA256,
    derivationID,
  );
  const preview = await derivative(
    store,
    "preview",
    new Uint8Array([13, 14, 15, 16]),
    sourceSHA256,
    derivationID,
  );
  const prepared: PreparedCatalogAssetRecord = {
    asset: {
      assetID: "ikea-us-40541421-aaaaaaaaaaaa",
      authorization: { status: "authorized", reference: "operator-authorized-2026-07-20" },
      category: "side_table",
      dimensionsM: { width: 0.8, height: 0.52, depth: 0.31 },
      supportType: "floor",
      normalization: { units: "meters", origin: "floor-contact-center", forwardAxis: "+z" },
      derivatives: { glb, usdz, collision: { ...collision, representation: "aabb" } },
      cacheProfiles: ["ios-primary", "web-primary"],
    },
    preview: { ...preview, mediaType: "image/png", width: 512, height: 512 },
    source: { storageKey: `sha256/${sourceSHA256}`, sha256: sourceSHA256, byteLength: 24 },
    processor: { revision: "blender-5.2.0-fbe6228777e7", configurationDigest: "c".repeat(64) },
    derivationID,
  };
  await store.savePreparedAsset(prepared);
  return prepared;
}

async function derivative(
  store: Awaited<ReturnType<typeof createFilesystemPreparedAssetStore>>,
  kind: "glb" | "usdz" | "collision" | "preview",
  bytes: Uint8Array,
  sourceSHA256: string,
  derivationID: string,
) {
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  const storageKey = await store.commitDerivative({
    kind,
    bytes,
    sha256,
    sourceSHA256,
    derivationID,
  });
  return { storageKey, sha256, byteLength: bytes.byteLength, validated: true };
}
