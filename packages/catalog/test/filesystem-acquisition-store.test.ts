import { afterEach, test } from "bun:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { createFilesystemAcquisitionStores } from "../src/index.ts";

const temporaryDirectories: string[] = [];

afterEach(async () => {
  await Promise.all(
    temporaryDirectories
      .splice(0)
      .map((directory) => rm(directory, { force: true, recursive: true })),
  );
});

test("durably resumes partial source bytes and commits immutable content by verified hash", async () => {
  const dataDirectory = await temporaryDataDirectory();
  const first = await createFilesystemAcquisitionStores({ dataDirectory });
  const partial = bytes("source-");
  await first.content.replacePartial("ikea-us-40541421-glb", partial);
  await first.state.save({
    schemaVersion: 1,
    acquisitionID: "ikea-us-40541421-glb",
    sourceURL: "https://web-api.ikea.com/dimma/assets/40541421.glb",
    phase: "partial",
    attempts: 0,
    receivedBytes: partial.byteLength,
    updatedAtMs: 1_000,
  });

  const resumed = await createFilesystemAcquisitionStores({ dataDirectory });
  assert.equal(await resumed.content.partialSize("ikea-us-40541421-glb"), partial.byteLength);
  assert.deepEqual(await resumed.state.load("ikea-us-40541421-glb"), {
    schemaVersion: 1,
    acquisitionID: "ikea-us-40541421-glb",
    sourceURL: "https://web-api.ikea.com/dimma/assets/40541421.glb",
    phase: "partial",
    attempts: 0,
    receivedBytes: partial.byteLength,
    updatedAtMs: 1_000,
  });

  const complete = bytes("source-glb-content");
  const sha256 = createHash("sha256").update(complete).digest("hex");
  const storageKey = await resumed.content.commitContent(sha256, complete);
  assert.equal(storageKey, `sha256/${sha256}`);
  assert.equal(await resumed.content.commitContent(sha256, complete), storageKey);
  await assert.rejects(
    resumed.content.commitContent("a".repeat(64), complete),
    /content_hash_mismatch/,
  );
});

test("requires an explicit external persistent data directory", async () => {
  await assert.rejects(
    createFilesystemAcquisitionStores({ dataDirectory: "catalog-data" }),
    /invalid_catalog_data_directory/,
  );
});

async function temporaryDataDirectory(): Promise<string> {
  const directory = await mkdtemp(join(tmpdir(), "reframe-catalog-data-"));
  temporaryDirectories.push(directory);
  return directory;
}

function bytes(value: string): Uint8Array {
  return new TextEncoder().encode(value);
}
