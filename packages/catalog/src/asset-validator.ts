import { createHash } from "node:crypto";

/** Provenance and geometry facts required before an asset can be injected. */
export interface AssetManifest {
  glbURL: string;
  glbSHA256: string;
  usdzURL?: string;
  usdzSHA256?: string;
  units: "meters";
  origin: "floor" | "center";
  dimensionsM: { width: number; height: number; depth: number };
  collision: "aabb" | "convex_hull" | "mesh";
}

export interface AssetBytes {
  glb: Uint8Array;
  usdz?: Uint8Array;
}

/** Validate downloaded derivatives and return a content-addressed manifest. */
export function validateAssetDerivatives(
  bytes: AssetBytes,
  metadata: Omit<AssetManifest, "glbSHA256" | "usdzSHA256">,
): AssetManifest {
  validateGLB(bytes.glb);
  if (bytes.usdz !== undefined) validateUSDZ(bytes.usdz);
  const dimensions = metadata.dimensionsM;
  if (
    !Object.values(dimensions).every((value) => Number.isFinite(value) && value > 0 && value < 100)
  )
    throw new Error("invalid_asset_dimensions");
  const glbSHA256 = sha256(bytes.glb);
  const usdzSHA256 = bytes.usdz === undefined ? undefined : sha256(bytes.usdz);
  return {
    ...metadata,
    glbSHA256,
    ...(usdzSHA256 === undefined ? {} : { usdzSHA256 }),
  };
}

export function validateGLB(bytes: Uint8Array): void {
  if (
    bytes.byteLength < 24 ||
    bytes[0] !== 0x67 ||
    bytes[1] !== 0x6c ||
    bytes[2] !== 0x54 ||
    bytes[3] !== 0x46
  )
    throw new Error("invalid_glb_header");
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const version = view.getUint32(4, true);
  if (version !== 2) throw new Error("unsupported_glb_version");
  const declaredLength = view.getUint32(8, true);
  if (declaredLength !== bytes.byteLength || declaredLength % 4 !== 0)
    throw new Error("invalid_glb_length");

  let offset = 12;
  let chunkIndex = 0;
  let jsonChunk: Uint8Array | undefined;
  while (offset < bytes.byteLength) {
    if (offset + 8 > bytes.byteLength) throw new Error("invalid_glb_chunk_header");
    const chunkLength = view.getUint32(offset, true);
    const chunkType = view.getUint32(offset + 4, true);
    const end = offset + 8 + chunkLength;
    if (chunkLength % 4 !== 0 || end > bytes.byteLength)
      throw new Error("invalid_glb_chunk_length");
    if (chunkIndex === 0) {
      if (chunkType !== 0x4e4f534a) throw new Error("missing_glb_json_chunk");
      jsonChunk = bytes.slice(offset + 8, end);
    } else if (chunkType === 0x4e4f534a) {
      throw new Error("duplicate_glb_json_chunk");
    }
    offset = end;
    chunkIndex += 1;
  }
  if (offset !== bytes.byteLength || chunkIndex === 0) throw new Error("invalid_glb_chunks");
  validateGLBJSON(jsonChunk);
}

export function validateUSDZ(bytes: Uint8Array): void {
  if (bytes.byteLength < 52) throw new Error("invalid_usdz_container");
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let offset = 0;
  let localEntries = 0;
  let firstEntryName: string | undefined;
  while (signatureAt(view, offset) === 0x04034b50) {
    if (offset + 30 > bytes.byteLength) throw new Error("invalid_usdz_container");
    const flags = view.getUint16(offset + 6, true);
    const compression = view.getUint16(offset + 8, true);
    const compressedSize = view.getUint32(offset + 18, true);
    const uncompressedSize = view.getUint32(offset + 22, true);
    const nameLength = view.getUint16(offset + 26, true);
    const extraLength = view.getUint16(offset + 28, true);
    if ((flags & 0x9) !== 0 || compression !== 0 || compressedSize !== uncompressedSize)
      throw new Error("invalid_usdz_container");
    const nameStart = offset + 30;
    const dataStart = nameStart + nameLength + extraLength;
    const end = dataStart + compressedSize;
    if (nameLength === 0 || dataStart > bytes.byteLength || end > bytes.byteLength)
      throw new Error("invalid_usdz_container");
    const name = decodeZipName(bytes.slice(nameStart, nameStart + nameLength));
    if (!safeUSDZEntryName(name)) throw new Error("invalid_usdz_container");
    if (localEntries === 0) firstEntryName = name;
    localEntries += 1;
    offset = end;
  }
  if (localEntries === 0 || firstEntryName === undefined || !isUSDLayer(firstEntryName))
    throw new Error("invalid_usdz_container");

  let centralEntries = 0;
  while (signatureAt(view, offset) === 0x02014b50) {
    if (offset + 46 > bytes.byteLength) throw new Error("invalid_usdz_container");
    const flags = view.getUint16(offset + 8, true);
    const compression = view.getUint16(offset + 10, true);
    const nameLength = view.getUint16(offset + 28, true);
    const extraLength = view.getUint16(offset + 30, true);
    const commentLength = view.getUint16(offset + 32, true);
    const end = offset + 46 + nameLength + extraLength + commentLength;
    if ((flags & 0x9) !== 0 || compression !== 0 || nameLength === 0 || end > bytes.byteLength)
      throw new Error("invalid_usdz_container");
    centralEntries += 1;
    offset = end;
  }
  if (centralEntries !== localEntries || signatureAt(view, offset) !== 0x06054b50)
    throw new Error("invalid_usdz_container");
  if (offset + 22 > bytes.byteLength) throw new Error("invalid_usdz_container");
  const declaredEntries = view.getUint16(offset + 10, true);
  const commentLength = view.getUint16(offset + 20, true);
  if (declaredEntries !== localEntries || offset + 22 + commentLength !== bytes.byteLength)
    throw new Error("invalid_usdz_container");
}

function sha256(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

function validateGLBJSON(bytes: Uint8Array | undefined): void {
  if (bytes === undefined) throw new Error("missing_glb_json_chunk");
  let json: unknown;
  try {
    json = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    throw new Error("invalid_glb_json");
  }
  if (typeof json !== "object" || json === null || Array.isArray(json))
    throw new Error("invalid_glb_json");
  const stack: unknown[] = [json];
  let visited = 0;
  while (stack.length > 0) {
    const value = stack.pop();
    visited += 1;
    if (visited > 100_000) throw new Error("glb_json_too_complex");
    if (Array.isArray(value)) {
      stack.push(...value);
    } else if (typeof value === "object" && value !== null) {
      for (const [key, nested] of Object.entries(value)) {
        if (key === "uri" && typeof nested === "string") throw new Error("external_glb_resource");
        stack.push(nested);
      }
    }
  }
}

function signatureAt(view: DataView, offset: number): number | undefined {
  return offset + 4 <= view.byteLength ? view.getUint32(offset, true) : undefined;
}

function decodeZipName(bytes: Uint8Array): string {
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    throw new Error("invalid_usdz_container");
  }
}

function safeUSDZEntryName(name: string): boolean {
  return (
    name.length > 0 &&
    !name.startsWith("/") &&
    !name.includes("\\") &&
    !name.split("/").includes("..")
  );
}

function isUSDLayer(name: string): boolean {
  return /\.(?:usd|usda|usdc)$/iu.test(name);
}
