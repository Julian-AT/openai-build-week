import { test } from "bun:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  createFilesystemPreparedAssetStore,
  type PreparedCatalogAssetRecord,
} from "../src/index.ts";

test("durably commits immutable derivatives before atomically saving a prepared record", async () => {
  const dataDirectory = await mkdtemp(join(tmpdir(), "reframe-catalog-prepared-"));
  try {
    const store = await createFilesystemPreparedAssetStore({ dataDirectory });
    const bytes = new Uint8Array([1, 2, 3, 4]);
    const sha256 = hash(bytes);
    const storageKey = await store.commitDerivative({
      kind: "preview",
      bytes,
      sha256,
      sourceSHA256: "a".repeat(64),
      derivationID: "b".repeat(64),
    });

    assert.equal(storageKey, `sha256/${sha256}`);
    assert.deepEqual(await store.readDerivative(storageKey, sha256), bytes);

    const prepared = preparedRecord(storageKey, sha256);
    await store.savePreparedAsset(prepared);
    assert.deepEqual(
      await store.loadPreparedAsset(prepared.asset.assetID, prepared.derivationID),
      prepared,
    );
    await assert.rejects(
      store.savePreparedAsset({
        ...prepared,
        processor: { ...prepared.processor, revision: "blender-5.2.1-next" },
      }),
      /prepared_asset_derivation_collision/,
    );
    await writeFile(
      join(
        dataDirectory,
        "catalog",
        "prepared",
        prepared.asset.assetID,
        `${prepared.derivationID}.json`,
      ),
      "{}",
    );
    await assert.rejects(
      store.loadPreparedAsset(prepared.asset.assetID, prepared.derivationID),
      /invalid_prepared_asset_record/,
    );
  } finally {
    await rm(dataDirectory, { recursive: true, force: true });
  }
});

function preparedRecord(storageKey: string, sha256: string): PreparedCatalogAssetRecord {
  const derivative = { storageKey, sha256, byteLength: 4, validated: true };
  return {
    asset: {
      assetID: "ikea-us-40541421-aaaaaaaaaaaa",
      authorization: { status: "authorized", reference: "operator-authorized-2026-07-20" },
      category: "side_table",
      dimensionsM: { width: 0.8, height: 0.52, depth: 0.31 },
      supportType: "floor",
      normalization: { units: "meters", origin: "floor-contact-center", forwardAxis: "+z" },
      derivatives: {
        glb: derivative,
        usdz: derivative,
        collision: { ...derivative, representation: "aabb" },
      },
      cacheProfiles: ["ios-primary"],
    },
    preview: { ...derivative, mediaType: "image/png", width: 512, height: 512 },
    source: { storageKey: `sha256/${"a".repeat(64)}`, sha256: "a".repeat(64), byteLength: 24 },
    processor: { revision: "blender-5.2.0-fbe6228777e7", configurationDigest: "c".repeat(64) },
    derivationID: "b".repeat(64),
  };
}

function hash(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}
