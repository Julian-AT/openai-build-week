import { createHash } from "node:crypto";
import { readdir, readFile } from "node:fs/promises";
import { join, resolve, sep } from "node:path";

import { assessAssetInjectionReadiness, type CatalogAssetRecord } from "@reframe/catalog";

export interface VerifiedAssetDelivery {
  readonly assetID: string;
  readonly derivative: "usdz";
  readonly sha256: string;
  readonly byteLength: number;
  readonly bytes: Uint8Array;
}

export interface AssetDeliveryService {
  deliver(assetID: string, signal?: AbortSignal): Promise<VerifiedAssetDelivery>;
}

/**
 * Serves only an explicitly prepared, authorized USDZ from the persistent
 * catalog volume. It never follows source URLs or accepts a path from a
 * client. Each response is re-hashed before it crosses the gateway boundary.
 */
export function createFilesystemAssetDeliveryService(options: {
  dataDirectory: string;
  cacheProfile: string;
}): AssetDeliveryService {
  const root = resolve(options.dataDirectory);
  if (!root.startsWith(sep) || !SAFE_PROFILE.test(options.cacheProfile)) {
    throw new Error("invalid_asset_delivery_configuration");
  }
  const preparedRoot = join(root, "catalog", "prepared");
  const derivativeRoot = join(root, "catalog", "derived", "sha256");

  return {
    async deliver(assetID, signal) {
      assertAssetID(assetID);
      signal?.throwIfAborted();
      const assetDirectory = safeChild(preparedRoot, assetID);
      let filenames: string[];
      try {
        filenames = (await readdir(assetDirectory)).filter(
          (name) => SHA256.test(name.slice(0, -5)) && name.endsWith(".json"),
        );
      } catch {
        throw new Error("asset_not_found");
      }
      filenames.sort();
      for (const filename of filenames) {
        signal?.throwIfAborted();
        let parsed: unknown;
        try {
          parsed = JSON.parse(await readFile(join(assetDirectory, filename), "utf8")) as unknown;
        } catch {
          continue;
        }
        const record = preparedRecord(parsed, assetID, options.cacheProfile);
        if (record === undefined) continue;
        const derivative = record.asset.derivatives.usdz;
        const bytes = new Uint8Array(await readFile(safeChild(derivativeRoot, derivative.sha256)));
        if (bytes.byteLength !== derivative.byteLength || sha256(bytes) !== derivative.sha256) {
          throw new Error("asset_hash_mismatch");
        }
        return Object.freeze({
          assetID,
          derivative: "usdz" as const,
          sha256: derivative.sha256,
          byteLength: derivative.byteLength,
          bytes,
        });
      }
      throw new Error("asset_not_found");
    },
  };
}

const SHA256 = /^[a-f0-9]{64}$/u;
const SAFE_ID = /^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$/u;
const SAFE_PROFILE = SAFE_ID;

function preparedRecord(
  value: unknown,
  assetID: string,
  cacheProfile: string,
):
  | {
      asset: {
        assetID: string;
        cacheProfiles: string[];
        derivatives: { usdz: { sha256: string; byteLength: number; validated: boolean } };
      };
    }
  | undefined {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return undefined;
  const record = value as Record<string, unknown>;
  const asset = record.asset;
  if (typeof asset !== "object" || asset === null || Array.isArray(asset)) return undefined;
  const candidate = asset as Record<string, unknown>;
  if (candidate.assetID !== assetID || !Array.isArray(candidate.cacheProfiles)) return undefined;
  if (!candidate.cacheProfiles.every((profile) => typeof profile === "string")) return undefined;
  if (!candidate.cacheProfiles.includes(cacheProfile)) return undefined;
  const derivatives = candidate.derivatives;
  if (typeof derivatives !== "object" || derivatives === null || Array.isArray(derivatives))
    return undefined;
  const usdz = (derivatives as Record<string, unknown>).usdz;
  if (typeof usdz !== "object" || usdz === null || Array.isArray(usdz)) return undefined;
  const derivative = usdz as Record<string, unknown>;
  if (
    typeof derivative.sha256 !== "string" ||
    !SHA256.test(derivative.sha256) ||
    !Number.isSafeInteger(derivative.byteLength) ||
    (derivative.byteLength as number) <= 0 ||
    derivative.validated !== true
  )
    return undefined;
  try {
    if (!assessAssetInjectionReadiness(candidate as unknown as CatalogAssetRecord).ready)
      return undefined;
  } catch {
    return undefined;
  }
  return {
    asset: {
      assetID,
      cacheProfiles: candidate.cacheProfiles,
      derivatives: {
        usdz: derivative as unknown as {
          sha256: string;
          byteLength: number;
          validated: boolean;
        },
      },
    },
  };
}

function assertAssetID(value: string): void {
  if (!SAFE_ID.test(value)) throw new Error("invalid_asset_id");
}

function safeChild(directory: string, child: string): string {
  const root = resolve(directory);
  const candidate = resolve(join(root, child));
  if (!candidate.startsWith(`${root}${sep}`)) throw new Error("invalid_asset_path");
  return candidate;
}

function sha256(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}
