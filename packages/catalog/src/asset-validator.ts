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
  ) throw new Error("invalid_asset_dimensions");
  const glbSHA256 = sha256(bytes.glb);
  const usdzSHA256 = bytes.usdz === undefined ? undefined : sha256(bytes.usdz);
  return {
    ...metadata,
    glbSHA256,
    ...(usdzSHA256 === undefined ? {} : { usdzSHA256 }),
  };
}

export function validateGLB(bytes: Uint8Array): void {
  if (bytes.byteLength < 20 || bytes[0] !== 0x67 || bytes[1] !== 0x6c || bytes[2] !== 0x54 || bytes[3] !== 0x46)
    throw new Error("invalid_glb_header");
  const version = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(4, true);
  if (version !== 2) throw new Error("unsupported_glb_version");
}

export function validateUSDZ(bytes: Uint8Array): void {
  if (bytes.byteLength < 4 || bytes[0] !== 0x50 || bytes[1] !== 0x4b || bytes[2] !== 0x03 || bytes[3] !== 0x04)
    throw new Error("invalid_usdz_container");
}

function sha256(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}
