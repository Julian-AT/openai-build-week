import type { CatalogAssetRecord, ValidatedCatalogDerivative } from "./types.ts";

export type InjectionReadinessFailure =
  | "asset_identity_invalid"
  | "authorization_not_verified"
  | "category_invalid"
  | "dimensions_invalid"
  | "support_type_invalid"
  | "normalization_invalid"
  | "glb_derivative_invalid"
  | "usdz_derivative_invalid"
  | "collision_derivative_invalid"
  | "cache_profile_invalid";

export interface InjectionReadiness {
  ready: boolean;
  failures: InjectionReadinessFailure[];
}

const SAFE_IDENTIFIER = /^[a-z0-9][a-z0-9._-]{1,127}$/u;
const SAFE_CATEGORY = /^[a-z][a-z0-9_]{1,63}$/u;
const SHA256 = /^[a-f0-9]{64}$/u;
const SUPPORT_TYPES = new Set(["floor", "surface", "wall", "ceiling"]);

export function assessAssetInjectionReadiness(asset: CatalogAssetRecord): InjectionReadiness {
  const failures: InjectionReadinessFailure[] = [];
  if (!SAFE_IDENTIFIER.test(asset.assetID)) failures.push("asset_identity_invalid");
  if (
    asset.authorization.status !== "authorized" ||
    asset.authorization.reference.trim().length === 0
  ) {
    failures.push("authorization_not_verified");
  }
  if (!SAFE_CATEGORY.test(asset.category)) failures.push("category_invalid");
  if (!validDimensions(asset.dimensionsM)) failures.push("dimensions_invalid");
  if (!SUPPORT_TYPES.has(asset.supportType)) failures.push("support_type_invalid");
  if (
    asset.normalization.units !== "meters" ||
    asset.normalization.origin !== "floor-contact-center" ||
    asset.normalization.forwardAxis !== "+z"
  ) {
    failures.push("normalization_invalid");
  }
  if (!validDerivative(asset.derivatives.glb)) failures.push("glb_derivative_invalid");
  if (!validDerivative(asset.derivatives.usdz)) failures.push("usdz_derivative_invalid");
  if (
    !validDerivative(asset.derivatives.collision) ||
    !["aabb", "convex_hull", "mesh"].includes(asset.derivatives.collision.representation)
  ) {
    failures.push("collision_derivative_invalid");
  }
  if (
    asset.cacheProfiles.some((profile) => !SAFE_IDENTIFIER.test(profile) || profile.includes("://"))
  ) {
    failures.push("cache_profile_invalid");
  }
  return { ready: failures.length === 0, failures };
}

function validDimensions(dimensions: CatalogAssetRecord["dimensionsM"]): boolean {
  return Object.values(dimensions).every(
    (dimension) => Number.isFinite(dimension) && dimension > 0 && dimension < 100,
  );
}

function validDerivative(derivative: ValidatedCatalogDerivative): boolean {
  return (
    derivative.validated === true &&
    SHA256.test(derivative.sha256) &&
    Number.isSafeInteger(derivative.byteLength) &&
    derivative.byteLength > 0 &&
    derivative.storageKey.startsWith(`sha256/${derivative.sha256}`) &&
    !derivative.storageKey.includes("://")
  );
}
