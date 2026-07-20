import { Database } from "bun:sqlite";
import { createHash } from "node:crypto";
import { join, resolve, sep } from "node:path";

import { validateGLB } from "./asset-validator.ts";
import {
  assertIkeaSourceAuthorization,
  type IkeaSourceAuthorization,
} from "./ikea-authorization.ts";

/** External build-only acquisition tool; it is never shipped in a Reframe artifact. */
export const PINNED_IKEA_DOWNLOADER = {
  repository: "https://github.com/apinanaivot/IKEA-3d-model-batch-downloader",
  revision: "3a036f1820c44b470aded71e651a1e791fd5d022",
  license: "GPL-3.0-only",
  outputSchemaVersion: 1,
} as const;

const EXPECTED_COLUMNS = ["url", "name", "color", "glb_url", "downloaded"] as const;
const DEFAULT_MAX_SOURCE_BYTES = 250 * 1_024 * 1_024;

export interface IkeaDownloaderContentStore {
  /** Stores immutable bytes by SHA-256; this importer never indexes directly. */
  commitSourceContent(sha256: string, bytes: Uint8Array): Promise<string>;
}

export interface ImportPinnedIkeaDownloaderOutputOptions {
  authorization: IkeaSourceAuthorization;
  /** Operator-selected external SQLite output from exactly PINNED_IKEA_DOWNLOADER. */
  databasePath: string;
  /** Operator-selected external directory containing the upstream downloaded-files output. */
  downloadDirectory: string;
  content: IkeaDownloaderContentStore;
  maxSourceBytes?: number;
}

export interface ImportedIkeaDownloaderContent {
  storageKey: string;
  sha256: string;
  byteLength: number;
}

export type ImportedIkeaDownloaderRecord =
  | {
      status: "imported";
      productURL: string;
      name: string;
      color: string;
      glbURL: string;
      content: ImportedIkeaDownloaderContent;
    }
  | {
      status: "quarantined";
      productURL: string;
      name: string;
      color: string;
      glbURL: string;
      reason: string;
    };

export interface IkeaDownloaderImportReport {
  schemaVersion: 1;
  downloader: typeof PINNED_IKEA_DOWNLOADER;
  counters: {
    discovered: number;
    imported: number;
    withoutDownloadedModel: number;
    quarantined: number;
    deduplicated: number;
  };
  records: ImportedIkeaDownloaderRecord[];
}

interface UpstreamRow {
  url: unknown;
  name: unknown;
  color: unknown;
  glb_url: unknown;
  downloaded: unknown;
}

interface UpstreamColumn {
  cid: number;
  name: string;
  type: string;
  pk: number;
}

/**
 * Reads only the five documented upstream fields, validates every discovered GLB
 * by bytes, and emits CAS-backed discovery records. No Qdrant type is accepted
 * here, so importer output cannot bypass preparation or eligibility.
 */
export async function importPinnedIkeaDownloaderOutput(
  options: ImportPinnedIkeaDownloaderOutputOptions,
): Promise<IkeaDownloaderImportReport> {
  assertIkeaSourceAuthorization(options.authorization);
  const maxSourceBytes = options.maxSourceBytes ?? DEFAULT_MAX_SOURCE_BYTES;
  if (!Number.isSafeInteger(maxSourceBytes) || maxSourceBytes < 24) {
    throw new Error("invalid_ikea_downloader_max_source_bytes");
  }
  const databasePath = requireAbsolutePath(
    options.databasePath,
    "invalid_ikea_downloader_database_path",
  );
  const downloadDirectory = requireAbsolutePath(
    options.downloadDirectory,
    "invalid_ikea_downloader_download_directory",
  );

  const database = new Database(databasePath, { readonly: true, strict: true });
  try {
    validateUpstreamSchema(database);
    const rows = database
      .query<UpstreamRow, []>(
        "SELECT url, name, color, glb_url, downloaded FROM products ORDER BY url",
      )
      .all();
    return await importRows(rows, downloadDirectory, options.content, maxSourceBytes);
  } finally {
    database.close();
  }
}

async function importRows(
  rows: readonly UpstreamRow[],
  downloadDirectory: string,
  content: IkeaDownloaderContentStore,
  maxSourceBytes: number,
): Promise<IkeaDownloaderImportReport> {
  const records: ImportedIkeaDownloaderRecord[] = [];
  const committed = new Map<string, ImportedIkeaDownloaderContent>();
  let imported = 0;
  let withoutDownloadedModel = 0;
  let quarantined = 0;
  let deduplicated = 0;

  for (const row of rows) {
    const productURL = requireProductURL(row.url);
    const name = requireText(row.name, "invalid_ikea_downloader_name");
    const color = requireText(row.color, "invalid_ikea_downloader_color");
    if (row.downloaded === 0) {
      withoutDownloadedModel += 1;
      continue;
    }
    if (row.downloaded !== 1) throw new Error("invalid_ikea_downloader_downloaded");
    const glbURL = requireGLBURL(row.glb_url);

    try {
      const bytes = await readValidatedOutputGLB(
        downloadDirectory,
        upstreamFilename(name, color),
        maxSourceBytes,
      );
      const sha256 = sha256hex(bytes);
      const existing = committed.get(sha256);
      if (existing !== undefined) {
        deduplicated += 1;
        imported += 1;
        records.push({ status: "imported", productURL, name, color, glbURL, content: existing });
        continue;
      }
      const storageKey = await content.commitSourceContent(sha256, bytes);
      if (storageKey !== `sha256/${sha256}`) throw new Error("invalid_content_address");
      const stored = { storageKey, sha256, byteLength: bytes.byteLength };
      committed.set(sha256, stored);
      imported += 1;
      records.push({ status: "imported", productURL, name, color, glbURL, content: stored });
    } catch (error) {
      if (error instanceof Error && isQuarantineReason(error.message)) {
        quarantined += 1;
        records.push({
          status: "quarantined",
          productURL,
          name,
          color,
          glbURL,
          reason: error.message,
        });
        continue;
      }
      throw error;
    }
  }

  return {
    schemaVersion: 1,
    downloader: PINNED_IKEA_DOWNLOADER,
    counters: {
      discovered: rows.length,
      imported,
      withoutDownloadedModel,
      quarantined,
      deduplicated,
    },
    records,
  };
}

function validateUpstreamSchema(database: Database): void {
  const userVersion = database.query<{ user_version: unknown }, []>("PRAGMA user_version").get();
  if (userVersion?.user_version !== 0) throw new Error("unsupported_ikea_downloader_schema");
  const columns = database.query<UpstreamColumn, []>("PRAGMA table_info(products)").all();
  if (
    columns.length !== EXPECTED_COLUMNS.length ||
    columns.some((column, index) => column.name !== EXPECTED_COLUMNS[index]) ||
    columns.some((column) => !["TEXT", "INTEGER"].includes(column.type.toUpperCase())) ||
    columns[0]?.pk !== 1
  ) {
    throw new Error("unsupported_ikea_downloader_schema");
  }
}

async function readValidatedOutputGLB(
  downloadDirectory: string,
  filename: string,
  maxSourceBytes: number,
): Promise<Uint8Array> {
  const root = resolve(downloadDirectory);
  const path = resolve(join(root, filename));
  if (!path.startsWith(`${root}${sep}`)) throw new Error("invalid_ikea_downloader_filename");
  const file = Bun.file(path);
  if (!(await file.exists())) throw new Error("missing_ikea_downloader_glb");
  if (file.size > maxSourceBytes) throw new Error("ikea_downloader_glb_too_large");
  const bytes = new Uint8Array(await file.arrayBuffer());
  validateGLB(bytes);
  return bytes;
}

function upstreamFilename(name: string, color: string): string {
  const filename = `${name} - ${color}.glb`.replace(/[<>:"/\\|?*]/gu, "");
  if (filename.length === 0 || filename === ".glb")
    throw new Error("invalid_ikea_downloader_filename");
  return filename;
}

function requireProductURL(value: unknown): string {
  if (typeof value !== "string") throw new Error("invalid_ikea_downloader_product_url");
  const url = new URL(value);
  if (
    url.protocol !== "https:" ||
    url.hostname !== "www.ikea.com" ||
    url.username !== "" ||
    url.password !== "" ||
    url.search !== "" ||
    !/^\/us\/en\/p\/[a-z0-9-]+\/$/u.test(url.pathname)
  ) {
    throw new Error("invalid_ikea_downloader_product_url");
  }
  return url.toString();
}

function requireGLBURL(value: unknown): string {
  if (typeof value !== "string") throw new Error("invalid_ikea_downloader_glb_url");
  const url = new URL(value);
  if (
    url.protocol !== "https:" ||
    url.hostname !== "web-api.ikea.com" ||
    url.username !== "" ||
    url.password !== "" ||
    !url.pathname.endsWith(".glb")
  ) {
    throw new Error("invalid_ikea_downloader_glb_url");
  }
  return url.toString();
}

function requireText(value: unknown, reason: string): string {
  if (typeof value !== "string") throw new Error(reason);
  const normalized = value.replace(/\s+/gu, " ").trim();
  if (normalized.length === 0 || normalized.length > 512 || normalized.includes("\u0000")) {
    throw new Error(reason);
  }
  return normalized;
}

function requireAbsolutePath(path: string, reason: string): string {
  if (typeof path !== "string" || path.length === 0 || !path.startsWith(sep))
    throw new Error(reason);
  return path;
}

function sha256hex(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

function isQuarantineReason(reason: string): boolean {
  return new Set([
    "missing_ikea_downloader_glb",
    "ikea_downloader_glb_too_large",
    "invalid_glb_header",
    "unsupported_glb_version",
    "invalid_glb_length",
    "invalid_glb_chunk_header",
    "invalid_glb_chunk_length",
    "missing_glb_json_chunk",
    "invalid_glb_chunks",
  ]).has(reason);
}
