import { createHash, randomUUID } from "node:crypto";
import { mkdir, rename, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve, sep } from "node:path";

import type { PreparedCatalogAssetRecord } from "./asset-preparation.ts";
import { assessAssetInjectionReadiness } from "./catalog-eligibility.ts";
import type {
  CachedAssetBinary,
  CatalogDerivativeKind,
  LocalAssetCache,
  LocalAssetCacheRequest,
} from "./delivery.ts";
import type { FilesystemPreparedAssetStore } from "./filesystem-prepared-asset-store.ts";
import type { ValidatedCatalogDerivative } from "./types.ts";

const SHA256 = /^[a-f0-9]{64}$/u;
const SAFE_IDENTIFIER = /^[a-z0-9][a-z0-9._-]{1,127}$/u;
const DELIVERY_KINDS = ["glb", "usdz", "collision"] as const;

export interface FilesystemLocalAssetCacheOptions {
  /** Absolute persistent Reframe data directory, never an application or repository path. */
  dataDirectory: string;
}

export interface SynchronizePreparedAssetsToLocalCacheOptions {
  /** Absolute persistent Reframe data directory, never an application or repository path. */
  dataDirectory: string;
  cacheProfile: string;
  /** Exact durable prepared records selected by the catalog authority for this cache generation. */
  records: readonly PreparedCatalogAssetRecord[];
  preparedStore: Pick<FilesystemPreparedAssetStore, "readDerivative">;
}

export interface ClientCacheSyncReport {
  schemaVersion: 1;
  cacheProfile: string;
  manifestSHA256: string;
  entries: readonly {
    assetID: string;
    derivationID: string;
    derivatives: Readonly<Record<CatalogDerivativeKind, string>>;
  }[];
  counters: {
    assetsSynchronized: number;
    assetsUnchanged: number;
    derivativesSynchronized: number;
    derivativesUnchanged: number;
  };
}

interface ClientCacheManifest {
  schemaVersion: 1;
  cacheProfile: string;
  entries: ClientCacheManifestEntry[];
}

interface ClientCacheManifestEntry {
  assetID: string;
  derivationID: string;
  derivatives: Record<CatalogDerivativeKind, CacheObjectReference>;
}

interface CacheObjectReference {
  sha256: string;
  byteLength: number;
}

/**
 * Materializes only injection-ready derivatives selected by the catalog into a
 * named local cache. The manifest publication is atomic; clients never fall
 * back to source URLs or catalog storage when an entry is absent.
 */
export async function synchronizePreparedAssetsToLocalCache(
  options: SynchronizePreparedAssetsToLocalCacheOptions,
): Promise<ClientCacheSyncReport> {
  const root = requirePersistentDirectory(options.dataDirectory);
  assertCacheProfile(options.cacheProfile);
  const cacheDirectory = safeChild(join(root, "catalog", "client-caches"), options.cacheProfile);
  const objectDirectory = join(cacheDirectory, "sha256");
  await mkdir(objectDirectory, { recursive: true });

  const entries = normalizeRecords(options.records, options.cacheProfile);
  let derivativesSynchronized = 0;
  let derivativesUnchanged = 0;
  let assetsSynchronized = 0;
  let assetsUnchanged = 0;
  for (const entry of entries) {
    let assetChanged = false;
    for (const kind of DELIVERY_KINDS) {
      const derivative = entry.record.asset.derivatives[kind];
      const bytes = await options.preparedStore.readDerivative(
        derivative.storageKey,
        derivative.sha256,
      );
      verifyDerivative(bytes, derivative);
      const changed = await writeVerifiedObject(objectDirectory, derivative.sha256, bytes);
      if (changed) {
        assetChanged = true;
        derivativesSynchronized += 1;
      } else {
        derivativesUnchanged += 1;
      }
    }
    if (assetChanged) assetsSynchronized += 1;
    else assetsUnchanged += 1;
  }

  const manifest: ClientCacheManifest = {
    schemaVersion: 1,
    cacheProfile: options.cacheProfile,
    entries: entries.map(({ record }) => ({
      assetID: record.asset.assetID,
      derivationID: record.derivationID,
      derivatives: Object.fromEntries(
        DELIVERY_KINDS.map((kind) => {
          const derivative = record.asset.derivatives[kind];
          return [kind, { sha256: derivative.sha256, byteLength: derivative.byteLength }];
        }),
      ) as Record<CatalogDerivativeKind, CacheObjectReference>,
    })),
  };
  const serialized = canonicalJSON(manifest);
  await writeAtomically(join(cacheDirectory, "manifest.json"), serialized);
  const manifestSHA256 = sha256(new TextEncoder().encode(serialized));
  return {
    schemaVersion: 1,
    cacheProfile: options.cacheProfile,
    manifestSHA256,
    entries: manifest.entries.map((entry) => ({
      assetID: entry.assetID,
      derivationID: entry.derivationID,
      derivatives: Object.fromEntries(
        DELIVERY_KINDS.map((kind) => [kind, entry.derivatives[kind].sha256]),
      ) as Record<CatalogDerivativeKind, string>,
    })),
    counters: {
      assetsSynchronized,
      assetsUnchanged,
      derivativesSynchronized,
      derivativesUnchanged,
    },
  };
}

/** Reads only an atomically published local cache manifest and verified CAS objects. */
export async function createFilesystemLocalAssetCache(
  options: FilesystemLocalAssetCacheOptions,
): Promise<LocalAssetCache> {
  const root = requirePersistentDirectory(options.dataDirectory);
  const cachesDirectory = join(root, "catalog", "client-caches");
  return {
    read: async (request: LocalAssetCacheRequest): Promise<CachedAssetBinary | undefined> => {
      assertCacheProfile(request.cacheProfile);
      assertAssetID(request.assetID);
      if (!DELIVERY_KINDS.includes(request.derivative)) throw new Error("invalid_asset_derivative");
      const cacheDirectory = safeChild(cachesDirectory, request.cacheProfile);
      const manifestFile = Bun.file(join(cacheDirectory, "manifest.json"));
      if (!(await manifestFile.exists())) return undefined;
      const manifest = parseManifest(await manifestFile.text(), request.cacheProfile);
      const entry = manifest.entries.find((candidate) => candidate.assetID === request.assetID);
      if (entry === undefined) return undefined;
      const derivative = entry.derivatives[request.derivative];
      const objectFile = Bun.file(safeChild(join(cacheDirectory, "sha256"), derivative.sha256));
      if (!(await objectFile.exists())) throw new Error("cached_asset_missing");
      const bytes = new Uint8Array(await objectFile.arrayBuffer());
      verifyObject(bytes, derivative);
      return { bytes, sha256: derivative.sha256, byteLength: derivative.byteLength };
    },
  };
}

function normalizeRecords(
  records: readonly PreparedCatalogAssetRecord[],
  cacheProfile: string,
): { record: PreparedCatalogAssetRecord }[] {
  const byAssetID = new Map<string, PreparedCatalogAssetRecord>();
  for (const record of records) {
    if (!assessAssetInjectionReadiness(record.asset).ready)
      throw new Error("cache_sync_asset_not_injection_ready");
    if (!record.asset.cacheProfiles.includes(cacheProfile))
      throw new Error("cache_sync_profile_not_authorized");
    const existing = byAssetID.get(record.asset.assetID);
    if (existing !== undefined && existing.derivationID !== record.derivationID)
      throw new Error("cache_sync_asset_derivation_ambiguous");
    byAssetID.set(record.asset.assetID, record);
  }
  return [...byAssetID.values()]
    .sort((left, right) => left.asset.assetID.localeCompare(right.asset.assetID))
    .map((record) => ({ record }));
}

async function writeVerifiedObject(
  directory: string,
  expectedSHA256: string,
  bytes: Uint8Array,
): Promise<boolean> {
  const path = safeChild(directory, expectedSHA256);
  const file = Bun.file(path);
  if (await file.exists()) {
    verifyObject(new Uint8Array(await file.arrayBuffer()), {
      sha256: expectedSHA256,
      byteLength: bytes.byteLength,
    });
    return false;
  }
  await writeAtomically(path, bytes);
  return true;
}

function parseManifest(value: string, cacheProfile: string): ClientCacheManifest {
  let parsed: unknown;
  try {
    parsed = JSON.parse(value) as unknown;
  } catch {
    throw new Error("invalid_client_cache_manifest");
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed))
    throw new Error("invalid_client_cache_manifest");
  const manifest = parsed as Partial<ClientCacheManifest>;
  if (
    manifest.schemaVersion !== 1 ||
    manifest.cacheProfile !== cacheProfile ||
    !Array.isArray(manifest.entries)
  ) {
    throw new Error("invalid_client_cache_manifest");
  }
  const assetIDs = new Set<string>();
  for (const entry of manifest.entries) {
    if (typeof entry !== "object" || entry === null || Array.isArray(entry))
      throw new Error("invalid_client_cache_manifest");
    const candidate = entry as Partial<ClientCacheManifestEntry>;
    if (
      typeof candidate.assetID !== "string" ||
      !SAFE_IDENTIFIER.test(candidate.assetID) ||
      typeof candidate.derivationID !== "string" ||
      !SHA256.test(candidate.derivationID) ||
      candidate.derivatives === undefined ||
      typeof candidate.derivatives !== "object" ||
      Array.isArray(candidate.derivatives) ||
      assetIDs.has(candidate.assetID)
    ) {
      throw new Error("invalid_client_cache_manifest");
    }
    assetIDs.add(candidate.assetID);
    for (const kind of DELIVERY_KINDS) {
      const derivative = candidate.derivatives[kind];
      if (
        typeof derivative !== "object" ||
        derivative === null ||
        !SHA256.test(derivative.sha256) ||
        !Number.isSafeInteger(derivative.byteLength) ||
        derivative.byteLength <= 0
      ) {
        throw new Error("invalid_client_cache_manifest");
      }
    }
  }
  return manifest as ClientCacheManifest;
}

function verifyDerivative(bytes: Uint8Array, derivative: ValidatedCatalogDerivative): void {
  if (!derivative.validated || derivative.storageKey !== `sha256/${derivative.sha256}`)
    throw new Error("invalid_prepared_derivative_reference");
  verifyObject(bytes, derivative);
}

function verifyObject(bytes: Uint8Array, expected: CacheObjectReference): void {
  if (
    !SHA256.test(expected.sha256) ||
    !Number.isSafeInteger(expected.byteLength) ||
    expected.byteLength <= 0 ||
    bytes.byteLength !== expected.byteLength ||
    sha256(bytes) !== expected.sha256
  ) {
    throw new Error("cached_asset_hash_mismatch");
  }
}

function assertCacheProfile(value: string): void {
  if (!SAFE_IDENTIFIER.test(value) || value.includes("://"))
    throw new Error("invalid_cache_profile");
}

function assertAssetID(value: string): void {
  if (!SAFE_IDENTIFIER.test(value)) throw new Error("invalid_asset_id");
}

function requirePersistentDirectory(value: string): string {
  if (typeof value !== "string" || value.length === 0 || !value.startsWith(sep))
    throw new Error("invalid_catalog_data_directory");
  return resolve(value);
}

function safeChild(directory: string, filename: string): string {
  const root = resolve(directory);
  const candidate = resolve(join(root, filename));
  if (!candidate.startsWith(`${root}${sep}`)) throw new Error("invalid_catalog_storage_path");
  return candidate;
}

async function writeAtomically(path: string, data: string | Uint8Array): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  const temporaryPath = `${path}.${randomUUID()}.tmp`;
  try {
    await writeFile(temporaryPath, data, { flag: "wx" });
    await rename(temporaryPath, path);
  } finally {
    await rm(temporaryPath, { force: true });
  }
}

function sha256(value: Uint8Array): string {
  return createHash("sha256").update(value).digest("hex");
}

function canonicalJSON(value: unknown): string {
  return `${JSON.stringify(canonicalize(value))}\n`;
}

function canonicalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (typeof value !== "object" || value === null) return value;
  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, nested]) => [key, canonicalize(nested)]),
  );
}
