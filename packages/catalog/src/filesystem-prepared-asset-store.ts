import { createHash, randomUUID } from "node:crypto";
import { link, mkdir, rename, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve, sep } from "node:path";

import type {
  AssetPreparationContentStore,
  PreparedCatalogAssetRecord,
} from "./asset-preparation.ts";
import { assessAssetInjectionReadiness } from "./catalog-eligibility.ts";

const SHA256 = /^[a-f0-9]{64}$/u;
const SAFE_IDENTIFIER = /^[a-z0-9][a-z0-9._-]{1,127}$/u;
const DERIVATIVE_KINDS = new Set(["glb", "usdz", "collision", "preview"]);

export interface FilesystemPreparedAssetStoreOptions {
  /** Absolute persistent Reframe data directory, never a repository path. */
  dataDirectory: string;
}

export interface FilesystemPreparedAssetStore extends AssetPreparationContentStore {
  readDerivative(storageKey: string, sha256: string): Promise<Uint8Array>;
  savePreparedAsset(record: PreparedCatalogAssetRecord): Promise<void>;
  loadPreparedAsset(
    assetID: string,
    derivationID: string,
  ): Promise<PreparedCatalogAssetRecord | undefined>;
}

/**
 * Catalog authority storage. Derivatives and records are immutable and live on
 * the configured persistent volume, never beside source code or in Qdrant.
 */
export async function createFilesystemPreparedAssetStore(
  options: FilesystemPreparedAssetStoreOptions,
): Promise<FilesystemPreparedAssetStore> {
  const root = requirePersistentDirectory(options.dataDirectory);
  const derivativeDirectory = join(root, "catalog", "derived", "sha256");
  const preparedDirectory = join(root, "catalog", "prepared");
  await Promise.all([
    mkdir(derivativeDirectory, { recursive: true }),
    mkdir(preparedDirectory, { recursive: true }),
  ]);

  const readDerivative = async (storageKey: string, sha256: string): Promise<Uint8Array> => {
    assertContentReference(storageKey, sha256);
    const file = Bun.file(safeChild(derivativeDirectory, sha256));
    if (!(await file.exists())) throw new Error("prepared_derivative_missing");
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (hash(bytes) !== sha256) throw new Error("prepared_derivative_hash_mismatch");
    return bytes;
  };

  return {
    commitDerivative: async (request) => {
      if (!DERIVATIVE_KINDS.has(request.kind)) throw new Error("invalid_prepared_derivative_kind");
      if (!SHA256.test(request.sha256) || !SHA256.test(request.sourceSHA256))
        throw new Error("invalid_prepared_derivative_hash");
      if (!SHA256.test(request.derivationID)) throw new Error("invalid_prepared_derivation_id");
      if (hash(request.bytes) !== request.sha256)
        throw new Error("prepared_derivative_hash_mismatch");
      const path = safeChild(derivativeDirectory, request.sha256);
      const existing = Bun.file(path);
      if (await existing.exists()) {
        const existingBytes = new Uint8Array(await existing.arrayBuffer());
        if (hash(existingBytes) !== request.sha256)
          throw new Error("prepared_derivative_collision");
      } else {
        await writeAtomically(path, request.bytes);
      }
      return `sha256/${request.sha256}`;
    },
    readDerivative,
    savePreparedAsset: async (record) => {
      validatePreparedRecord(record);
      await Promise.all([
        readDerivative(
          record.asset.derivatives.glb.storageKey,
          record.asset.derivatives.glb.sha256,
        ),
        readDerivative(
          record.asset.derivatives.usdz.storageKey,
          record.asset.derivatives.usdz.sha256,
        ),
        readDerivative(
          record.asset.derivatives.collision.storageKey,
          record.asset.derivatives.collision.sha256,
        ),
        readDerivative(record.preview.storageKey, record.preview.sha256),
      ]).then((derivatives) => {
        const expected = [
          record.asset.derivatives.glb.byteLength,
          record.asset.derivatives.usdz.byteLength,
          record.asset.derivatives.collision.byteLength,
          record.preview.byteLength,
        ];
        if (derivatives.some((bytes, index) => bytes.byteLength !== expected[index]))
          throw new Error("prepared_derivative_length_mismatch");
      });
      const path = preparedPath(preparedDirectory, record.asset.assetID, record.derivationID);
      const serialized = canonicalJSON(record);
      const existing = Bun.file(path);
      if (await existing.exists()) {
        if ((await existing.text()) !== serialized)
          throw new Error("prepared_asset_derivation_collision");
        return;
      }
      if (!(await writeImmutably(path, serialized))) {
        if ((await Bun.file(path).text()) !== serialized)
          throw new Error("prepared_asset_derivation_collision");
      }
    },
    loadPreparedAsset: async (assetID, derivationID) => {
      const path = preparedPath(preparedDirectory, assetID, derivationID);
      const file = Bun.file(path);
      if (!(await file.exists())) return undefined;
      let record: unknown;
      try {
        record = JSON.parse(await file.text()) as unknown;
      } catch {
        throw new Error("invalid_prepared_asset_record");
      }
      validatePreparedRecord(record);
      return record;
    },
  };
}

function validatePreparedRecord(value: unknown): asserts value is PreparedCatalogAssetRecord {
  if (typeof value !== "object" || value === null || Array.isArray(value))
    throw new Error("invalid_prepared_asset_record");
  const record = value as PreparedCatalogAssetRecord;
  if (
    !SHA256.test(record.derivationID) ||
    !SHA256.test(record.processor.configurationDigest) ||
    !SHA256.test(record.source.sha256) ||
    record.source.storageKey !== `sha256/${record.source.sha256}` ||
    !Number.isSafeInteger(record.source.byteLength) ||
    record.source.byteLength <= 0 ||
    !SAFE_IDENTIFIER.test(record.asset.assetID)
  ) {
    throw new Error("invalid_prepared_asset_record");
  }
  if (assessAssetInjectionReadiness(record.asset).ready !== true) {
    throw new Error("prepared_asset_not_injection_ready");
  }
  const derivatives = [
    record.asset.derivatives.glb,
    record.asset.derivatives.usdz,
    record.asset.derivatives.collision,
    record.preview,
  ];
  if (
    derivatives.some(
      (derivative) =>
        !SHA256.test(derivative.sha256) ||
        derivative.storageKey !== `sha256/${derivative.sha256}` ||
        !Number.isSafeInteger(derivative.byteLength) ||
        derivative.byteLength <= 0 ||
        derivative.validated !== true,
    ) ||
    record.preview.mediaType !== "image/png" ||
    !Number.isSafeInteger(record.preview.width) ||
    !Number.isSafeInteger(record.preview.height) ||
    record.preview.width <= 0 ||
    record.preview.height <= 0
  ) {
    throw new Error("invalid_prepared_asset_record");
  }
}

function assertContentReference(storageKey: string, sha256: string): void {
  if (!SHA256.test(sha256) || storageKey !== `sha256/${sha256}`)
    throw new Error("invalid_prepared_derivative_reference");
}

function requirePersistentDirectory(value: string): string {
  if (typeof value !== "string" || value.length === 0 || !value.startsWith(sep))
    throw new Error("invalid_catalog_data_directory");
  return resolve(value);
}

function preparedPath(directory: string, assetID: string, derivationID: string): string {
  if (!SAFE_IDENTIFIER.test(assetID) || !SHA256.test(derivationID))
    throw new Error("invalid_prepared_asset_identity");
  return safeChild(safeChild(directory, assetID), `${derivationID}.json`);
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

/** Returns false if another writer won the same immutable record path. */
async function writeImmutably(path: string, data: string): Promise<boolean> {
  await mkdir(dirname(path), { recursive: true });
  const temporaryPath = `${path}.${randomUUID()}.tmp`;
  try {
    await writeFile(temporaryPath, data, { flag: "wx" });
    try {
      await link(temporaryPath, path);
      return true;
    } catch (error) {
      if (isAlreadyExists(error)) return false;
      throw error;
    }
  } finally {
    await rm(temporaryPath, { force: true });
  }
}

function isAlreadyExists(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    (error as { code?: unknown }).code === "EEXIST"
  );
}

function hash(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
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
