import { Database } from "bun:sqlite";
import { afterEach, test } from "bun:test";
import assert from "node:assert/strict";
import { mkdir, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  type IkeaDownloaderContentStore,
  importPinnedIkeaDownloaderOutput,
  REFRAME_IKEA_US_AUTHORIZATION,
} from "../src/index.ts";

const temporaryDirectories: string[] = [];

afterEach(async () => {
  await Promise.all(
    temporaryDirectories
      .splice(0)
      .map((directory) => rm(directory, { force: true, recursive: true })),
  );
});

test("imports pinned downloader rows through validated content-addressed storage", async () => {
  const directory = await createDownloaderOutput();
  await Bun.write(join(directory, "downloaded-files", "HOLMERUD - Oak effect.glb"), minimalGLB());
  const commits = new Map<string, Uint8Array>();

  const report = await importPinnedIkeaDownloaderOutput({
    authorization: REFRAME_IKEA_US_AUTHORIZATION,
    databasePath: join(directory, "ikea_products.db"),
    downloadDirectory: join(directory, "downloaded-files"),
    content: memoryContentStore(commits),
  });

  assert.equal(report.schemaVersion, 1);
  assert.deepEqual(report.counters, {
    discovered: 2,
    imported: 1,
    withoutDownloadedModel: 1,
    quarantined: 0,
    deduplicated: 0,
  });
  const imported = report.records[0];
  assert.ok(imported);
  assert.deepEqual(imported, {
    status: "imported",
    productURL: "https://www.ikea.com/us/en/p/holmerud-side-table-oak-effect-40541421/",
    name: "HOLMERUD",
    color: "Oak effect",
    glbURL: "https://web-api.ikea.com/dimma/assets/40541421.glb",
    content: {
      storageKey: "sha256/ab7cb3261b3327eca0eed861fd7d0f73b784dbf7f1b4d839b48661a2878d6e63",
      sha256: "ab7cb3261b3327eca0eed861fd7d0f73b784dbf7f1b4d839b48661a2878d6e63",
      byteLength: 24,
    },
  });
  assert.equal(commits.size, 1);
});

test("rejects downloader schema drift before reading content", async () => {
  const directory = await createDownloaderOutput({ invalidSchema: true });
  const commits = new Map<string, Uint8Array>();

  await assert.rejects(
    importPinnedIkeaDownloaderOutput({
      authorization: REFRAME_IKEA_US_AUTHORIZATION,
      databasePath: join(directory, "ikea_products.db"),
      downloadDirectory: join(directory, "downloaded-files"),
      content: memoryContentStore(commits),
    }),
    /unsupported_ikea_downloader_schema/,
  );
  assert.equal(commits.size, 0);
});

test("quarantines malformed downloader GLBs instead of committing or indexing them", async () => {
  const directory = await createDownloaderOutput();
  await Bun.write(join(directory, "downloaded-files", "HOLMERUD - Oak effect.glb"), "not a glb");
  const commits = new Map<string, Uint8Array>();

  const report = await importPinnedIkeaDownloaderOutput({
    authorization: REFRAME_IKEA_US_AUTHORIZATION,
    databasePath: join(directory, "ikea_products.db"),
    downloadDirectory: join(directory, "downloaded-files"),
    content: memoryContentStore(commits),
  });

  assert.deepEqual(report.counters, {
    discovered: 2,
    imported: 0,
    withoutDownloadedModel: 1,
    quarantined: 1,
    deduplicated: 0,
  });
  assert.deepEqual(report.records[0], {
    status: "quarantined",
    productURL: "https://www.ikea.com/us/en/p/holmerud-side-table-oak-effect-40541421/",
    name: "HOLMERUD",
    color: "Oak effect",
    glbURL: "https://web-api.ikea.com/dimma/assets/40541421.glb",
    reason: "invalid_glb_header",
  });
  assert.equal(commits.size, 0);
});

test("quarantines structurally invalid GLBs without ending a resumable importer run", async () => {
  const directory = await createDownloaderOutput();
  const malformed = minimalGLB();
  new DataView(malformed.buffer).setUint32(8, malformed.byteLength + 4, true);
  await Bun.write(join(directory, "downloaded-files", "HOLMERUD - Oak effect.glb"), malformed);

  const report = await importPinnedIkeaDownloaderOutput({
    authorization: REFRAME_IKEA_US_AUTHORIZATION,
    databasePath: join(directory, "ikea_products.db"),
    downloadDirectory: join(directory, "downloaded-files"),
    content: memoryContentStore(new Map()),
  });

  assert.equal(report.counters.quarantined, 1);
  const record = report.records[0];
  assert.ok(record);
  assert.equal(record.status, "quarantined");
  if (record.status !== "quarantined") throw new Error("expected_quarantined_record");
  assert.equal(record.reason, "invalid_glb_length");
});

async function createDownloaderOutput(options: { invalidSchema?: boolean } = {}): Promise<string> {
  const directory = await mkdtemp(join(tmpdir(), "reframe-ikea-downloader-"));
  temporaryDirectories.push(directory);
  await mkdir(join(directory, "downloaded-files"));
  const database = new Database(join(directory, "ikea_products.db"));
  database.run(
    options.invalidSchema
      ? "CREATE TABLE products (url TEXT PRIMARY KEY, name TEXT, color TEXT, glb_url TEXT)"
      : "CREATE TABLE products (url TEXT PRIMARY KEY, name TEXT, color TEXT, glb_url TEXT, downloaded INTEGER)",
  );
  if (!options.invalidSchema) {
    database.run("INSERT INTO products VALUES (?, ?, ?, ?, ?)", [
      "https://www.ikea.com/us/en/p/holmerud-side-table-oak-effect-40541421/",
      "HOLMERUD",
      "Oak effect",
      "https://web-api.ikea.com/dimma/assets/40541421.glb",
      1,
    ]);
    database.run("INSERT INTO products VALUES (?, ?, ?, ?, ?)", [
      "https://www.ikea.com/us/en/p/holmerud-side-table-dark-brown-50541425/",
      "HOLMERUD variant",
      "Dark brown",
      null,
      0,
    ]);
  }
  database.close();
  return directory;
}

function memoryContentStore(commits: Map<string, Uint8Array>): IkeaDownloaderContentStore {
  return {
    commitSourceContent: async (sha256, bytes) => {
      commits.set(sha256, bytes.slice());
      return `sha256/${sha256}`;
    },
  };
}

function minimalGLB(): Uint8Array {
  const bytes = new Uint8Array(24);
  bytes.set([0x67, 0x6c, 0x54, 0x46]);
  const view = new DataView(bytes.buffer);
  view.setUint32(4, 2, true);
  view.setUint32(8, bytes.byteLength, true);
  view.setUint32(12, 4, true);
  view.setUint32(16, 0x4e4f534a, true);
  bytes.set([0x7b, 0x7d, 0x20, 0x20], 20);
  return bytes;
}
