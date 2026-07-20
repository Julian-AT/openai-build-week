import { test } from "bun:test";
import assert from "node:assert/strict";

import { canonicalizePreviewPNG, canonicalizeUSDZ } from "../src/asset-canonicalizer.ts";

test("canonicalizes USDZ archive timestamps to a stable DOS epoch", () => {
  const first = timestampedUSDZ(0x4a21, 0x5d7c);
  const second = timestampedUSDZ(0x4a22, 0x5d7d);

  assert.notDeepEqual(first, second);
  assert.deepEqual(canonicalizeUSDZ(first), canonicalizeUSDZ(second));
});

test("strips mutable preview metadata while retaining image chunks", () => {
  const first = timestampedPNG("2026/07/20 22:06:02", "00.54");
  const second = timestampedPNG("2026/07/20 22:06:03", "00.23");

  assert.notDeepEqual(first, second);
  assert.deepEqual(canonicalizePreviewPNG(first), canonicalizePreviewPNG(second));
});

test("rejects a preview whose untrusted chunk checksum is invalid", () => {
  const corrupt = timestampedPNG("2026/07/20 22:06:02", "00.54");
  corrupt[44] = (corrupt[44] ?? 0) ^ 0x01;
  assert.throws(() => canonicalizePreviewPNG(corrupt), /invalid_preview_png/);
});

function timestampedUSDZ(time: number, date: number): Uint8Array {
  const name = new TextEncoder().encode("scene.usdc");
  const localLength = 30 + name.byteLength;
  const centralLength = 46 + name.byteLength;
  const bytes = new Uint8Array(localLength + centralLength + 22);
  const view = new DataView(bytes.buffer);
  view.setUint32(0, 0x04034b50, true);
  view.setUint16(4, 20, true);
  view.setUint16(10, time, true);
  view.setUint16(12, date, true);
  view.setUint16(26, name.byteLength, true);
  bytes.set(name, 30);
  view.setUint32(localLength, 0x02014b50, true);
  view.setUint16(localLength + 4, 20, true);
  view.setUint16(localLength + 6, 20, true);
  view.setUint16(localLength + 12, time, true);
  view.setUint16(localLength + 14, date, true);
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

function timestampedPNG(date: string, renderTime: string): Uint8Array {
  return concat(
    new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", new Uint8Array([0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0])),
    chunk("sRGB", new Uint8Array([0])),
    chunk("tEXt", new TextEncoder().encode(`Date\\0${date}`)),
    chunk("tEXt", new TextEncoder().encode(`RenderTime\\0${renderTime}`)),
    chunk("IDAT", new Uint8Array([0x78, 0x9c, 0x63, 0x60, 0x60, 0x60, 0, 0, 0, 4, 0, 1])),
    chunk("IEND", new Uint8Array()),
  );
}

function chunk(type: string, data: Uint8Array): Uint8Array {
  const typeBytes = new TextEncoder().encode(type);
  const bytes = new Uint8Array(12 + data.byteLength);
  const view = new DataView(bytes.buffer);
  view.setUint32(0, data.byteLength, false);
  bytes.set(typeBytes, 4);
  bytes.set(data, 8);
  view.setUint32(8 + data.byteLength, crc32(concat(typeBytes, data)), false);
  return bytes;
}

function concat(...values: Uint8Array[]): Uint8Array {
  const result = new Uint8Array(values.reduce((total, value) => total + value.byteLength, 0));
  let offset = 0;
  for (const value of values) {
    result.set(value, offset);
    offset += value.byteLength;
  }
  return result;
}

function crc32(bytes: Uint8Array): number {
  let value = 0xffffffff;
  for (const byte of bytes) {
    value ^= byte;
    for (let bit = 0; bit < 8; bit += 1) value = (value >>> 1) ^ (value & 1 ? 0xedb88320 : 0);
  }
  return (value ^ 0xffffffff) >>> 0;
}
