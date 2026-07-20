import { validateUSDZ } from "./asset-validator.ts";

const PNG_SIGNATURE = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const PNG_COLOR_CHUNKS = new Set(["sRGB", "gAMA", "cHRM", "iCCP"]);
const USDZ_EPOCH_DATE = 0x0021;

/**
 * Removes non-rendering metadata emitted by Blender so the same preview pixels
 * always have one content address. All retained chunks retain their original
 * checksums; malformed or unknown critical chunks fail closed.
 */
export function canonicalizePreviewPNG(input: Uint8Array): Uint8Array {
  if (
    input.byteLength < PNG_SIGNATURE.byteLength ||
    !PNG_SIGNATURE.every((value, index) => input[index] === value)
  ) {
    throw new Error("invalid_preview_png");
  }
  const view = new DataView(input.buffer, input.byteOffset, input.byteLength);
  const chunks: Uint8Array[] = [PNG_SIGNATURE];
  let offset = PNG_SIGNATURE.byteLength;
  let seenHeader = false;
  let seenImageData = false;
  let seenEnd = false;

  while (offset < input.byteLength) {
    if (offset + 12 > input.byteLength) throw new Error("invalid_preview_png");
    const length = view.getUint32(offset, false);
    const dataEnd = offset + 8 + length;
    const end = dataEnd + 4;
    if (end > input.byteLength) throw new Error("invalid_preview_png");
    const type = chunkType(input, offset + 4);
    if (crc32(input.slice(offset + 4, dataEnd)) !== view.getUint32(dataEnd, false))
      throw new Error("invalid_preview_png");

    if (type === "IHDR") {
      if (seenHeader || seenImageData || seenEnd || length !== 13)
        throw new Error("invalid_preview_png");
      seenHeader = true;
      chunks.push(input.slice(offset, end));
    } else if (type === "PLTE") {
      if (!seenHeader || seenImageData || seenEnd || length === 0)
        throw new Error("invalid_preview_png");
      chunks.push(input.slice(offset, end));
    } else if (type === "IDAT") {
      if (!seenHeader || seenEnd || length === 0) throw new Error("invalid_preview_png");
      seenImageData = true;
      chunks.push(input.slice(offset, end));
    } else if (type === "IEND") {
      if (!seenHeader || !seenImageData || seenEnd || length !== 0 || end !== input.byteLength)
        throw new Error("invalid_preview_png");
      seenEnd = true;
      chunks.push(input.slice(offset, end));
    } else {
      if (!seenHeader || seenImageData || seenEnd) throw new Error("invalid_preview_png");
      if (isCriticalChunk(input[offset + 4])) throw new Error("invalid_preview_png");
      if (PNG_COLOR_CHUNKS.has(type)) chunks.push(input.slice(offset, end));
    }
    offset = end;
  }

  if (!seenHeader || !seenImageData || !seenEnd) throw new Error("invalid_preview_png");
  return concatenate(chunks);
}

/**
 * Canonicalizes ZIP DOS timestamps after the archive has already passed ARKit
 * validation. USDZ stores each entry uncompressed, so timestamp normalization
 * does not alter layer, texture, offset, or alignment bytes.
 */
export function canonicalizeUSDZ(input: Uint8Array): Uint8Array {
  validateUSDZ(input);
  const output = input.slice();
  const view = new DataView(output.buffer, output.byteOffset, output.byteLength);
  let offset = 0;

  while (signatureAt(view, offset) === 0x04034b50) {
    view.setUint16(offset + 10, 0, true);
    view.setUint16(offset + 12, USDZ_EPOCH_DATE, true);
    offset = localEntryEnd(view, offset);
  }
  while (signatureAt(view, offset) === 0x02014b50) {
    view.setUint16(offset + 12, 0, true);
    view.setUint16(offset + 14, USDZ_EPOCH_DATE, true);
    offset = centralEntryEnd(view, offset);
  }
  return output;
}

function chunkType(bytes: Uint8Array, offset: number): string {
  const type = String.fromCharCode(...bytes.slice(offset, offset + 4));
  if (!/^[A-Za-z]{4}$/u.test(type)) throw new Error("invalid_preview_png");
  return type;
}

function isCriticalChunk(firstTypeByte: number | undefined): boolean {
  if (firstTypeByte === undefined) throw new Error("invalid_preview_png");
  return (firstTypeByte & 0x20) === 0;
}

function crc32(bytes: Uint8Array): number {
  let value = 0xffffffff;
  for (const byte of bytes) {
    value ^= byte;
    for (let bit = 0; bit < 8; bit += 1) value = (value >>> 1) ^ (value & 1 ? 0xedb88320 : 0);
  }
  return (value ^ 0xffffffff) >>> 0;
}

function concatenate(values: readonly Uint8Array[]): Uint8Array {
  const output = new Uint8Array(values.reduce((total, value) => total + value.byteLength, 0));
  let offset = 0;
  for (const value of values) {
    output.set(value, offset);
    offset += value.byteLength;
  }
  return output;
}

function signatureAt(view: DataView, offset: number): number | undefined {
  return offset + 4 <= view.byteLength ? view.getUint32(offset, true) : undefined;
}

function localEntryEnd(view: DataView, offset: number): number {
  const nameLength = view.getUint16(offset + 26, true);
  const extraLength = view.getUint16(offset + 28, true);
  const compressedSize = view.getUint32(offset + 18, true);
  return offset + 30 + nameLength + extraLength + compressedSize;
}

function centralEntryEnd(view: DataView, offset: number): number {
  const nameLength = view.getUint16(offset + 28, true);
  const extraLength = view.getUint16(offset + 30, true);
  const commentLength = view.getUint16(offset + 32, true);
  return offset + 46 + nameLength + extraLength + commentLength;
}
