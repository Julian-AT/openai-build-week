import { test } from "bun:test";
import assert from "node:assert/strict";

import { createIkeaGLBFetchTransport } from "../src/index.ts";

test("the IKEA GLB transport enforces origin, byte bound, and resumable validators", async () => {
  let requested: Request | undefined;
  const transport = createIkeaGLBFetchTransport({
    fetch: async (input, init) => {
      requested = new Request(input, init);
      return new Response(glbBody(), {
        status: 206,
        headers: {
          "content-type": "model/gltf-binary",
          "content-range": "bytes 5-28/29",
          etag: '"source-v1"',
        },
      });
    },
  });

  const response = await transport.download({
    sourceURL: "https://web-api.ikea.com/dimma/assets/40541421.glb",
    offset: 5,
    ifRangeETag: '"source-v1"',
    maxResponseBytes: 32,
  });

  assert.equal(requested?.headers.get("range"), "bytes=5-");
  assert.equal(requested?.headers.get("if-range"), '"source-v1"');
  assert.deepEqual(response, {
    status: 206,
    bytes: minimalGLB(),
    etag: '"source-v1"',
    rangeStart: 5,
    totalBytes: 29,
  });
});

test("the IKEA GLB transport rejects disallowed origins before a network request", async () => {
  let fetches = 0;
  const transport = createIkeaGLBFetchTransport({
    fetch: async () => {
      fetches += 1;
      return new Response(glbBody());
    },
  });

  await assert.rejects(
    transport.download({
      sourceURL: "https://example.invalid/model.glb",
      offset: 0,
      maxResponseBytes: 32,
    }),
    /invalid_ikea_glb_url/,
  );
  assert.equal(fetches, 0);
});

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

function glbBody(): ArrayBuffer {
  const bytes = minimalGLB();
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}
