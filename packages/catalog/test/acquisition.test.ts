import { test } from "bun:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";

import {
  type AcquisitionCheckpoint,
  type AcquisitionContentStore,
  type AcquisitionStateStore,
  type AcquisitionTransport,
  acquireCatalogBinary,
} from "../src/index.ts";

test("acquisition resumes with ETag validation and commits by content hash", async () => {
  const state = memoryState();
  const content = memoryContent();
  const requests: Array<{ offset: number; ifRangeETag?: string }> = [];
  let responseIndex = 0;
  const responses = [
    { status: 206, bytes: bytes("hello"), etag: '"model-v1"', rangeStart: 0, totalBytes: 10 },
    { status: 206, bytes: bytes("world"), etag: '"model-v1"', rangeStart: 5, totalBytes: 10 },
  ];
  const transport: AcquisitionTransport = {
    download: async (request) => {
      requests.push({
        offset: request.offset,
        ...(request.ifRangeETag === undefined ? {} : { ifRangeETag: request.ifRangeETag }),
      });
      const response = responses[responseIndex++];
      assert.ok(response);
      return response;
    },
  };

  const first = await acquireCatalogBinary({
    acquisitionID: "ikea-us-00000001-glb",
    sourceURL: "https://web-api.ikea.com/model.glb",
    state,
    content,
    transport,
    nowMs: 1_000,
  });
  assert.equal(first.status, "partial");
  assert.equal(first.checkpoint.receivedBytes, 5);

  const second = await acquireCatalogBinary({
    acquisitionID: "ikea-us-00000001-glb",
    sourceURL: "https://web-api.ikea.com/model.glb",
    state,
    content,
    transport,
    nowMs: 1_100,
  });
  const sha256 = createHash("sha256").update("helloworld").digest("hex");
  assert.deepEqual(requests, [{ offset: 0 }, { offset: 5, ifRangeETag: '"model-v1"' }]);
  assert.deepEqual(second, {
    status: "complete",
    checkpoint: {
      schemaVersion: 1,
      acquisitionID: "ikea-us-00000001-glb",
      sourceURL: "https://web-api.ikea.com/model.glb",
      phase: "complete",
      attempts: 0,
      receivedBytes: 10,
      totalBytes: 10,
      etag: '"model-v1"',
      updatedAtMs: 1_100,
      content: { storageKey: `sha256/${sha256}`, sha256, byteLength: 10 },
    },
  });
  assert.deepEqual(content.committed.get(sha256), bytes("helloworld"));
});

test("transient failures persist bounded retry state and defer network I/O", async () => {
  const state = memoryState();
  const content = memoryContent();
  let downloads = 0;
  const transport: AcquisitionTransport = {
    download: async () => {
      downloads += 1;
      if (downloads === 1) {
        return { status: 503, bytes: new Uint8Array(), retryAfterMs: 4_000 };
      }
      return { status: 200, bytes: bytes("asset"), etag: '"ready"', totalBytes: 5 };
    },
  };
  const options = {
    acquisitionID: "ikea-us-00000002-glb",
    sourceURL: "https://web-api.ikea.com/second.glb",
    state,
    content,
    transport,
  };

  const failedAttempt = await acquireCatalogBinary({ ...options, nowMs: 1_000 });
  assert.equal(failedAttempt.status, "deferred");
  assert.equal(failedAttempt.checkpoint.attempts, 1);
  assert.equal(failedAttempt.checkpoint.lastFailure, "http_503");
  assert.equal(failedAttempt.checkpoint.nextAttemptAtMs, 5_000);

  const tooEarly = await acquireCatalogBinary({ ...options, nowMs: 4_999 });
  assert.equal(tooEarly.status, "deferred");
  assert.equal(downloads, 1);

  const completed = await acquireCatalogBinary({ ...options, nowMs: 5_000 });
  assert.equal(completed.status, "complete");
  assert.equal(completed.checkpoint.attempts, 1);
  assert.equal(downloads, 2);
});

test("a changed ETag discards partial bytes before a bounded retry", async () => {
  const state = memoryState();
  const content = memoryContent();
  let downloads = 0;
  const transport: AcquisitionTransport = {
    download: async () => {
      downloads += 1;
      if (downloads === 1) {
        return {
          status: 206,
          bytes: bytes("old"),
          etag: '"v1"',
          rangeStart: 0,
          totalBytes: 6,
        };
      }
      return {
        status: 206,
        bytes: bytes("mix"),
        etag: '"v2"',
        rangeStart: 3,
        totalBytes: 6,
      };
    },
  };
  const options = {
    acquisitionID: "ikea-us-00000003-glb",
    sourceURL: "https://web-api.ikea.com/changed.glb",
    state,
    content,
    transport,
  };

  await acquireCatalogBinary({ ...options, nowMs: 1_000 });
  const changed = await acquireCatalogBinary({ ...options, nowMs: 1_100 });

  assert.equal(changed.status, "deferred");
  assert.equal(changed.checkpoint.receivedBytes, 0);
  assert.equal(changed.checkpoint.attempts, 1);
  assert.equal(changed.checkpoint.lastFailure, "etag_changed");
  assert.equal(await content.partialSize(options.acquisitionID), 0);
});

test("invalid retry metadata fails closed without persisting unusable state", async () => {
  const state = memoryState();
  await assert.rejects(
    acquireCatalogBinary({
      acquisitionID: "ikea-us-00000004-glb",
      sourceURL: "https://web-api.ikea.com/retry.glb",
      state,
      content: memoryContent(),
      transport: {
        download: async () => ({
          status: 429,
          bytes: new Uint8Array(),
          retryAfterMs: Number.NaN,
        }),
      },
      nowMs: 1_000,
    }),
    /invalid_acquisition_retry_after/,
  );
  assert.equal(state.checkpoints.size, 0);
});

function bytes(value: string): Uint8Array {
  return new TextEncoder().encode(value);
}

function memoryState(): AcquisitionStateStore & {
  checkpoints: Map<string, AcquisitionCheckpoint>;
} {
  const checkpoints = new Map<string, AcquisitionCheckpoint>();
  return {
    checkpoints,
    load: async (id) => checkpoints.get(id),
    save: async (checkpoint) => {
      checkpoints.set(checkpoint.acquisitionID, structuredClone(checkpoint));
    },
  };
}

function memoryContent(): AcquisitionContentStore & {
  committed: Map<string, Uint8Array>;
} {
  const partials = new Map<string, Uint8Array>();
  const committed = new Map<string, Uint8Array>();
  return {
    committed,
    partialSize: async (id) => partials.get(id)?.byteLength ?? 0,
    appendPartial: async (id, expectedOffset, chunk) => {
      const previous = partials.get(id) ?? new Uint8Array();
      assert.equal(previous.byteLength, expectedOffset);
      const next = new Uint8Array(previous.byteLength + chunk.byteLength);
      next.set(previous);
      next.set(chunk, previous.byteLength);
      partials.set(id, next);
    },
    replacePartial: async (id, chunk) => {
      partials.set(id, chunk.slice());
    },
    readPartial: async (id) => partials.get(id)?.slice() ?? new Uint8Array(),
    commitContent: async (sha256, value) => {
      committed.set(sha256, value.slice());
      return `sha256/${sha256}`;
    },
    discardPartial: async (id) => {
      partials.delete(id);
    },
  };
}
