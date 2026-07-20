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
  while (offset < bytes.byteLength) {
    if (offset + 8 > bytes.byteLength) throw new Error("invalid_glb_chunk_header");
    const chunkLength = view.getUint32(offset, true);
    const chunkType = view.getUint32(offset + 4, true);
    const end = offset + 8 + chunkLength;
    if (chunkLength % 4 !== 0 || end > bytes.byteLength)
      throw new Error("invalid_glb_chunk_length");
    if (chunkIndex === 0 && chunkType !== 0x4e4f534a) throw new Error("missing_glb_json_chunk");
    offset = end;
    chunkIndex += 1;
  }
  if (offset !== bytes.byteLength || chunkIndex === 0) throw new Error("invalid_glb_chunks");
}

export function validateUSDZ(bytes: Uint8Array): void {
  if (
    bytes.byteLength < 4 ||
    bytes[0] !== 0x50 ||
    bytes[1] !== 0x4b ||
    bytes[2] !== 0x03 ||
    bytes[3] !== 0x04
  )
    throw new Error("invalid_usdz_container");
}

function sha256(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}
