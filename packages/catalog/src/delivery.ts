import { createHash } from "node:crypto";

import { assessAssetInjectionReadiness } from "./catalog-eligibility.ts";
import type { CatalogAssetRecord, ValidatedCatalogDerivative } from "./types.ts";

export type CatalogDerivativeKind = "glb" | "usdz" | "collision";

export interface LocalAssetCacheRequest {
  assetID: string;
  cacheProfile: string;
  derivative: CatalogDerivativeKind;
}

export interface CachedAssetBinary {
  bytes: Uint8Array;
  sha256: string;
  byteLength: number;
}

export interface LocalAssetCache {
  read(request: LocalAssetCacheRequest): Promise<CachedAssetBinary | undefined>;
}

export interface LocalAssetDeliveryRequest {
  asset: CatalogAssetRecord;
  cacheProfile: string;
  derivative: CatalogDerivativeKind;
}

export interface LocalAssetDelivery {
  assetID: string;
  cacheProfile: string;
  derivative: CatalogDerivativeKind;
  mediaType: "model/gltf-binary" | "model/vnd.usdz+zip" | "application/octet-stream";
  sha256: string;
  byteLength: number;
  bytes: Uint8Array;
}

const SAFE_PROFILE = /^[a-z0-9][a-z0-9._-]{1,127}$/u;
const SHA256 = /^[a-f0-9]{64}$/u;

/**
 * Resolve a delivery exclusively from an explicitly synchronized local cache.
 * This boundary deliberately has no source URL or network fallback.
 */
export async function resolveLocalAssetDelivery(
  request: LocalAssetDeliveryRequest,
  cache: LocalAssetCache,
): Promise<LocalAssetDelivery> {
  if (!assessAssetInjectionReadiness(request.asset).ready)
    throw new Error("asset_not_injection_ready");
  if (!SAFE_PROFILE.test(request.cacheProfile) || request.cacheProfile.includes("://"))
    throw new Error("invalid_cache_profile");
  if (!request.asset.cacheProfiles.includes(request.cacheProfile))
    throw new Error("asset_not_cached");

  const expected = expectedDerivative(request.asset, request.derivative);
  const cached = await cache.read({
    assetID: request.asset.assetID,
    cacheProfile: request.cacheProfile,
    derivative: request.derivative,
  });
  if (cached === undefined) throw new Error("asset_not_cached");
  if (
    !Number.isSafeInteger(cached.byteLength) ||
    cached.byteLength !== expected.byteLength ||
    cached.bytes.byteLength !== expected.byteLength
  ) {
    throw new Error("cached_asset_length_mismatch");
  }
  if (!SHA256.test(cached.sha256) || cached.sha256 !== expected.sha256)
    throw new Error("cached_asset_hash_mismatch");
  const actualSHA256 = createHash("sha256").update(cached.bytes).digest("hex");
  if (actualSHA256 !== expected.sha256) throw new Error("cached_asset_hash_mismatch");

  return {
    assetID: request.asset.assetID,
    cacheProfile: request.cacheProfile,
    derivative: request.derivative,
    mediaType: mediaType(request.derivative),
    sha256: expected.sha256,
    byteLength: expected.byteLength,
    bytes: cached.bytes.slice(),
  };
}

function expectedDerivative(
  asset: CatalogAssetRecord,
  kind: CatalogDerivativeKind,
): ValidatedCatalogDerivative {
  if (kind === "glb") return asset.derivatives.glb;
  if (kind === "usdz") return asset.derivatives.usdz;
  if (kind === "collision") return asset.derivatives.collision;
  throw new Error("invalid_asset_derivative");
}

function mediaType(kind: CatalogDerivativeKind): LocalAssetDelivery["mediaType"] {
  if (kind === "glb") return "model/gltf-binary";
  if (kind === "usdz") return "model/vnd.usdz+zip";
  return "application/octet-stream";
}
