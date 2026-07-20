import { test } from "bun:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { type AssetProcessorCommandRunner, createBlenderAssetProcessor } from "../src/index.ts";

test("processes in an isolated workspace and runs ARKit USDZ validation before returning bytes", async () => {
  const workDirectory = await mkdtemp(join(tmpdir(), "reframe-catalog-processor-"));
  const commands: string[] = [];
  const runner: AssetProcessorCommandRunner = {
    run: async (request) => {
      commands.push(request.command);
      if (request.command === "/tools/blender") {
        await writeFile(valueAfter(request.arguments, "--glb"), minimalGLB());
        await writeFile(valueAfter(request.arguments, "--usdz"), minimalUSDZ());
        await writeFile(valueAfter(request.arguments, "--collision"), differentGLB());
        await writeFile(valueAfter(request.arguments, "--preview"), png());
        await writeFile(
          valueAfter(request.arguments, "--manifest"),
          JSON.stringify({ dimensions_m: { width: 0.8, height: 0.52, depth: 0.31 } }),
        );
      }
      return { exitCode: 0 };
    },
  };
  try {
    const processor = createBlenderAssetProcessor({
      blenderPath: "/tools/blender",
      usdzipPath: "/tools/usdzip",
      usdcheckerPath: "/tools/usdchecker",
      scriptPath: "/tools/reframe-normalize.py",
      workDirectory,
      timeoutMs: 10_000,
      runner,
    });

    const sourceGLB = minimalGLB();
    const output = await processor.process({
      sourceGLB,
      sourceSHA256: hash(sourceGLB),
      derivationID: "b".repeat(64),
      expectedDimensionsM: { width: 0.8, height: 0.52, depth: 0.31 },
    });

    assert.deepEqual(output.dimensionsM, { width: 0.8, height: 0.52, depth: 0.31 });
    assert.deepEqual(commands, ["/tools/blender", "/tools/usdchecker", "/tools/usdzip"]);
  } finally {
    await rm(workDirectory, { recursive: true, force: true });
  }
});

function valueAfter(arguments_: readonly string[], flag: string): string {
  const index = arguments_.indexOf(flag);
  const value = arguments_[index + 1];
  if (index < 0 || value === undefined) throw new Error(`missing ${flag}`);
  return value;
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

function differentGLB(): Uint8Array {
  const bytes = minimalGLB();
  bytes[23] = 0x0a;
  return bytes;
}

function minimalUSDZ(): Uint8Array {
  const name = new TextEncoder().encode("scene.usdc");
  const localLength = 30 + name.byteLength;
  const centralLength = 46 + name.byteLength;
  const bytes = new Uint8Array(localLength + centralLength + 22);
  const view = new DataView(bytes.buffer);
  view.setUint32(0, 0x04034b50, true);
  view.setUint16(4, 20, true);
  view.setUint16(26, name.byteLength, true);
  bytes.set(name, 30);
  view.setUint32(localLength, 0x02014b50, true);
  view.setUint16(localLength + 4, 20, true);
  view.setUint16(localLength + 6, 20, true);
  view.setUint16(localLength + 28, name.byteLength, true);
  bytes.set(name, localLength + 46);
  const end = localLength + centralLength;
  view.setUint32(end, 0x06054b50, true);
  view.setUint16(end + 8, 1, true);
  view.setUint16(end + 10, 1, true);
  view.setUint32(end + 12, centralLength, true);
  view.setUint32(end + 16, localLength, true);
  return bytes;
}

function png(): Uint8Array {
  return new Uint8Array([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x02, 0x00, 0x08, 0x02, 0x00, 0x00, 0x00,
  ]);
}

function hash(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}
