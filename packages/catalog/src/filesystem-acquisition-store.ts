import { createHash, randomUUID } from "node:crypto";
import { mkdir, open, rename, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve, sep } from "node:path";

import type {
  AcquiredContentReference,
  AcquisitionCheckpoint,
  AcquisitionContentStore,
  AcquisitionStateStore,
} from "./acquisition.ts";

const SAFE_ACQUISITION_ID = /^[a-z0-9][a-z0-9._-]{1,127}$/u;
const SHA256 = /^[a-f0-9]{64}$/u;

export interface FilesystemAcquisitionStoreOptions {
  /** Absolute persistent Reframe data directory, never a repository path. */
  dataDirectory: string;
}

export interface FilesystemAcquisitionStores {
  state: AcquisitionStateStore;
  content: AcquisitionContentStore;
  /** Read-only access to immutable validated source objects. */
  source: {
    read(reference: AcquiredContentReference): Promise<Uint8Array>;
  };
}

/**
 * Durable source-acquisition ports backed by the configured persistent volume.
 * Raw partials remain separate from immutable content-addressed source objects.
 */
export async function createFilesystemAcquisitionStores(
  options: FilesystemAcquisitionStoreOptions,
): Promise<FilesystemAcquisitionStores> {
  const root = requirePersistentDirectory(options.dataDirectory);
  const stateDirectory = join(root, "catalog", "acquisition", "state");
  const partialDirectory = join(root, "catalog", "acquisition", "partials");
  const objectDirectory = join(root, "catalog", "source", "sha256");
  await Promise.all([
    mkdir(stateDirectory, { recursive: true }),
    mkdir(partialDirectory, { recursive: true }),
    mkdir(objectDirectory, { recursive: true }),
  ]);

  return {
    state: {
      load: async (acquisitionID) => {
        const path = acquisitionStatePath(stateDirectory, acquisitionID);
        const file = Bun.file(path);
        if (!(await file.exists())) return undefined;
        let value: unknown;
        try {
          value = JSON.parse(await file.text()) as unknown;
        } catch {
          throw new Error("invalid_acquisition_state_json");
        }
        if (!isCheckpoint(value)) throw new Error("invalid_acquisition_state_json");
        return value;
      },
      save: async (checkpoint) => {
        const path = acquisitionStatePath(stateDirectory, checkpoint.acquisitionID);
        await writeAtomically(path, canonicalJSON(checkpoint));
      },
    },
    content: {
      partialSize: async (acquisitionID) => {
        const file = Bun.file(acquisitionPartialPath(partialDirectory, acquisitionID));
        if (!(await file.exists())) return 0;
        return file.size;
      },
      appendPartial: async (acquisitionID, expectedOffset, bytes) => {
        if (!Number.isSafeInteger(expectedOffset) || expectedOffset < 0) {
          throw new Error("invalid_acquisition_partial_offset");
        }
        const path = acquisitionPartialPath(partialDirectory, acquisitionID);
        const handle = await open(path, "a+");
        try {
          const current = await handle.stat();
          if (current.size !== expectedOffset) throw new Error("acquisition_partial_mismatch");
          await handle.write(bytes);
          await handle.sync();
        } finally {
          await handle.close();
        }
      },
      replacePartial: async (acquisitionID, bytes) => {
        await writeAtomically(acquisitionPartialPath(partialDirectory, acquisitionID), bytes);
      },
      readPartial: async (acquisitionID) => {
        const path = acquisitionPartialPath(partialDirectory, acquisitionID);
        const file = Bun.file(path);
        if (!(await file.exists())) return new Uint8Array();
        return new Uint8Array(await file.arrayBuffer());
      },
      commitContent: async (sha256, bytes) => {
        if (!SHA256.test(sha256)) throw new Error("invalid_content_hash");
        const actual = hash(bytes);
        if (actual !== sha256) throw new Error("content_hash_mismatch");
        const path = sourceObjectPath(objectDirectory, sha256);
        const existing = Bun.file(path);
        if (await existing.exists()) {
          const existingBytes = new Uint8Array(await existing.arrayBuffer());
          if (hash(existingBytes) !== sha256) throw new Error("content_address_collision");
          return `sha256/${sha256}`;
        }
        await writeAtomically(path, bytes);
        return `sha256/${sha256}`;
      },
      discardPartial: async (acquisitionID) => {
        await rm(acquisitionPartialPath(partialDirectory, acquisitionID), { force: true });
      },
    },
    source: {
      read: async (reference) => {
        if (
          !SHA256.test(reference.sha256) ||
          reference.storageKey !== `sha256/${reference.sha256}` ||
          !Number.isSafeInteger(reference.byteLength) ||
          reference.byteLength <= 0
        ) {
          throw new Error("invalid_source_content_reference");
        }
        const file = Bun.file(sourceObjectPath(objectDirectory, reference.sha256));
        if (!(await file.exists())) throw new Error("source_content_missing");
        const bytes = new Uint8Array(await file.arrayBuffer());
        if (bytes.byteLength !== reference.byteLength || hash(bytes) !== reference.sha256)
          throw new Error("source_content_hash_mismatch");
        return bytes;
      },
    },
  };
}

function requirePersistentDirectory(value: string): string {
  if (typeof value !== "string" || value.length === 0 || !value.startsWith(sep)) {
    throw new Error("invalid_catalog_data_directory");
  }
  return resolve(value);
}

function acquisitionStatePath(directory: string, acquisitionID: string): string {
  return safeChild(directory, `${safeID(acquisitionID)}.json`);
}

function acquisitionPartialPath(directory: string, acquisitionID: string): string {
  return safeChild(directory, `${safeID(acquisitionID)}.partial`);
}

function sourceObjectPath(directory: string, sha256: string): string {
  return safeChild(directory, sha256);
}

function safeID(value: string): string {
  if (!SAFE_ACQUISITION_ID.test(value)) throw new Error("invalid_acquisition_id");
  return value;
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

function isCheckpoint(value: unknown): value is AcquisitionCheckpoint {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
