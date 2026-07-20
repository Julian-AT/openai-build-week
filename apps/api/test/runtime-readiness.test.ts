import { test } from "bun:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { createLocalRuntimeReadiness } from "../src/runtime-readiness.ts";

test("local runtime initializes a WAL catalog store, writable asset storage, and Qdrant readiness", async () => {
  const dataDirectory = await mkdtemp(join(tmpdir(), "reframe-runtime-"));
  try {
    const runtime = await createLocalRuntimeReadiness({
      dataDirectory,
      qdrantURL: "http://qdrant.test:6333",
      fetch: async () => new Response(null, { status: 200 }),
    });

    assert.deepEqual(await runtime.snapshot(), {
      status: "ok",
      dependencies: {
        gateway: { status: "ready" },
        catalog_store: { status: "ready" },
        asset_storage: { status: "ready" },
        qdrant: { status: "ready" },
      },
    });
    assert.equal(
      (await readFile(join(dataDirectory, "catalog", "catalog.sqlite"))).subarray(0, 15).toString(),
      "SQLite format 3",
    );
  } finally {
    await rm(dataDirectory, { recursive: true, force: true });
  }
});

test("local runtime keeps durable storage ready when Qdrant is unavailable", async () => {
  const dataDirectory = await mkdtemp(join(tmpdir(), "reframe-runtime-"));
  try {
    const runtime = await createLocalRuntimeReadiness({
      dataDirectory,
      qdrantURL: "http://qdrant.test:6333",
      fetch: async () => new Response(null, { status: 503 }),
    });

    assert.deepEqual(await runtime.snapshot(), {
      status: "degraded",
      dependencies: {
        gateway: { status: "ready" },
        catalog_store: { status: "ready" },
        asset_storage: { status: "ready" },
        qdrant: { status: "unavailable" },
      },
    });
  } finally {
    await rm(dataDirectory, { recursive: true, force: true });
  }
});
