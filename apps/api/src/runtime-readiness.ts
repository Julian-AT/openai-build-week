import { Database } from "bun:sqlite";
import { mkdir, open, unlink } from "node:fs/promises";
import { dirname, isAbsolute, relative, resolve } from "node:path";

import type { GatewayRuntimeReadiness, GatewayRuntimeSnapshot } from "./server.ts";

const CATALOG_DATABASE_RELATIVE_PATH = "catalog/catalog.sqlite";
const ASSET_STORAGE_RELATIVE_PATH = "assets";
const WRITE_PROBE_NAME = ".reframe-write-probe";

export interface LocalRuntimeReadinessOptions {
  dataDirectory: string;
  qdrantURL: string;
  qdrantAPIKey?: string;
  fetch?: RuntimeFetch;
  qdrantTimeoutMilliseconds?: number;
}

export type RuntimeFetch = (
  input: Parameters<typeof globalThis.fetch>[0],
  init?: Parameters<typeof globalThis.fetch>[1],
) => ReturnType<typeof globalThis.fetch>;

/**
 * Initializes only durable local prerequisites. Qdrant remains independently
 * observable so local capture and already-committed edits degrade safely when
 * catalog search is unavailable.
 */
export async function createLocalRuntimeReadiness(
  options: LocalRuntimeReadinessOptions,
): Promise<GatewayRuntimeReadiness> {
  const locations = resolveLocations(options.dataDirectory);
  const qdrantURL = parseQdrantURL(options.qdrantURL);
  const fetch = options.fetch ?? globalThis.fetch;
  const timeoutMilliseconds = boundedTimeout(options.qdrantTimeoutMilliseconds);

  await mkdir(locations.dataDirectory, { recursive: true });
  await initializeCatalogStore(locations.catalogDatabasePath);
  await verifyWritableDirectory(locations.assetStorageDirectory);

  return {
    snapshot: async () =>
      await snapshotRuntime({
        locations,
        qdrantURL,
        fetch,
        timeoutMilliseconds,
        ...(options.qdrantAPIKey === undefined ? {} : { qdrantAPIKey: options.qdrantAPIKey }),
      }),
  };
}

export function runtimeReadinessFromEnvironment(
  environment: Record<string, string | undefined>,
): Promise<GatewayRuntimeReadiness> {
  const dataDirectory = environment.REFRAME_DATA_DIR?.trim();
  const qdrantURL = environment.REFRAME_QDRANT_URL?.trim();
  if (dataDirectory === undefined || dataDirectory.length === 0) {
    throw new Error("missing_reframe_data_dir");
  }
  if (qdrantURL === undefined || qdrantURL.length === 0) {
    throw new Error("missing_reframe_qdrant_url");
  }
  return createLocalRuntimeReadiness({
    dataDirectory,
    qdrantURL,
    ...(environment.QDRANT_API_KEY === undefined
      ? {}
      : { qdrantAPIKey: environment.QDRANT_API_KEY }),
  });
}

interface RuntimeLocations {
  dataDirectory: string;
  catalogDatabasePath: string;
  assetStorageDirectory: string;
}

interface RuntimeSnapshotOptions {
  locations: RuntimeLocations;
  qdrantURL: URL;
  qdrantAPIKey?: string;
  fetch: RuntimeFetch;
  timeoutMilliseconds: number;
}

async function snapshotRuntime(options: RuntimeSnapshotOptions): Promise<GatewayRuntimeSnapshot> {
  const [catalogStore, assetStorage, qdrant] = await Promise.all([
    checkCatalogStore(options.locations.catalogDatabasePath),
    checkWritableDirectory(options.locations.assetStorageDirectory),
    checkQdrant(options),
  ]);
  const dependencies = {
    gateway: { status: "ready" as const },
    catalog_store: { status: catalogStore ? ("ready" as const) : ("unavailable" as const) },
    asset_storage: { status: assetStorage ? ("ready" as const) : ("unavailable" as const) },
    qdrant: { status: qdrant ? ("ready" as const) : ("unavailable" as const) },
  };
  return {
    status: catalogStore && assetStorage && qdrant ? "ok" : "degraded",
    dependencies,
  };
}

function resolveLocations(dataDirectory: string): RuntimeLocations {
  if (!isAbsolute(dataDirectory)) throw new Error("invalid_reframe_data_dir");
  const resolvedDataDirectory = resolve(dataDirectory);
  const catalogDatabasePath = resolve(resolvedDataDirectory, CATALOG_DATABASE_RELATIVE_PATH);
  const assetStorageDirectory = resolve(resolvedDataDirectory, ASSET_STORAGE_RELATIVE_PATH);
  for (const path of [catalogDatabasePath, assetStorageDirectory]) {
    if (relative(resolvedDataDirectory, path).startsWith("..")) {
      throw new Error("invalid_reframe_data_dir");
    }
  }
  return {
    dataDirectory: resolvedDataDirectory,
    catalogDatabasePath,
    assetStorageDirectory,
  };
}

async function initializeCatalogStore(catalogDatabasePath: string): Promise<void> {
  await mkdir(dirname(catalogDatabasePath), { recursive: true });
  const database = new Database(catalogDatabasePath, { create: true });
  try {
    database.exec("PRAGMA journal_mode = WAL;");
    database.exec(
      "CREATE TABLE IF NOT EXISTS runtime_store_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT;",
    );
    database
      .prepare(
        "INSERT INTO runtime_store_metadata (key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = excluded.value;",
      )
      .run("schema_version", "1");
  } finally {
    database.close();
  }
}

async function checkCatalogStore(catalogDatabasePath: string): Promise<boolean> {
  try {
    const database = new Database(catalogDatabasePath, { readonly: true });
    try {
      const result = database.prepare("PRAGMA quick_check;").get() as { quick_check?: unknown };
      return result.quick_check === "ok";
    } finally {
      database.close();
    }
  } catch {
    return false;
  }
}

async function verifyWritableDirectory(directory: string): Promise<void> {
  await mkdir(directory, { recursive: true });
  const probePath = resolve(directory, WRITE_PROBE_NAME);
  const handle = await open(probePath, "w", 0o600);
  try {
    await handle.writeFile("ready");
    await handle.sync();
  } finally {
    await handle.close();
    await unlink(probePath).catch(() => undefined);
  }
}

async function checkWritableDirectory(directory: string): Promise<boolean> {
  try {
    await verifyWritableDirectory(directory);
    return true;
  } catch {
    return false;
  }
}

async function checkQdrant(options: RuntimeSnapshotOptions): Promise<boolean> {
  const signal = AbortSignal.timeout(options.timeoutMilliseconds);
  try {
    const response = await options.fetch(new URL("readyz", options.qdrantURL), {
      method: "GET",
      headers: options.qdrantAPIKey === undefined ? {} : { "api-key": options.qdrantAPIKey },
      signal,
    });
    return response.ok;
  } catch {
    return false;
  }
}

function parseQdrantURL(value: string): URL {
  const url = new URL(value);
  if (
    (url.protocol !== "http:" && url.protocol !== "https:") ||
    url.username.length > 0 ||
    url.password.length > 0
  ) {
    throw new Error("invalid_reframe_qdrant_url");
  }
  return new URL(url.toString().endsWith("/") ? url.toString() : `${url.toString()}/`);
}

function boundedTimeout(value: number | undefined): number {
  if (value === undefined) return 750;
  if (!Number.isSafeInteger(value) || value < 50 || value > 10_000) {
    throw new Error("invalid_qdrant_timeout");
  }
  return value;
}
