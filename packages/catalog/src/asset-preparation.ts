import { createHash } from "node:crypto";

import { validateGLB, validateUSDZ } from "./asset-validator.ts";
import type {
  AssetSupportType,
  CatalogAssetRecord,
  CatalogCollisionDerivative,
  CatalogDimensionsM,
  ValidatedCatalogDerivative,
} from "./types.ts";

const SHA256 = /^[a-f0-9]{64}$/u;
const SAFE_IDENTIFIER = /^[a-z0-9][a-z0-9._-]{1,127}$/u;
const SAFE_CATEGORY = /^[a-z][a-z0-9_]{1,63}$/u;
const SAFE_PROCESSOR_REVISION = /^[A-Za-z0-9][A-Za-z0-9._+-]{1,127}$/u;
const SUPPORT_TYPES = new Set<AssetSupportType>(["floor", "surface", "wall", "ceiling"]);

export const DEFAULT_ASSET_PREPARATION_BUDGETS = {
  glbBytes: 25 * 1024 * 1024,
  usdzBytes: 15 * 1024 * 1024,
  collisionBytes: 4 * 1024 * 1024,
  previewBytes: 2 * 1024 * 1024,
} as const;

export interface AssetPreparationBudgets {
  glbBytes: number;
  usdzBytes: number;
  collisionBytes: number;
  previewBytes: number;
}

export interface CatalogAssetProcessorRequest {
  sourceGLB: Uint8Array;
  sourceSHA256: string;
  derivationID: string;
  expectedDimensionsM: CatalogDimensionsM;
  signal?: AbortSignal;
}

export interface CatalogAssetProcessorOutput {
  glb: Uint8Array;
  usdz: Uint8Array;
  collision: Uint8Array;
  preview: Uint8Array;
  dimensionsM: CatalogDimensionsM;
}

/** An isolated, bounded processor which never writes a prepared record itself. */
export interface CatalogAssetProcessor {
  process(request: CatalogAssetProcessorRequest): Promise<CatalogAssetProcessorOutput>;
}

export type AssetPreparationDerivativeKind = "glb" | "usdz" | "collision" | "preview";

export interface AssetPreparationContentStore {
  /**
   * Commit immutable bytes only after caller-side validation. The returned key
   * must remain an opaque content-addressed reference, never a delivery URL.
   */
  commitDerivative(request: {
    kind: AssetPreparationDerivativeKind;
    bytes: Uint8Array;
    sha256: string;
    sourceSHA256: string;
    derivationID: string;
  }): Promise<string>;
}

export interface PreparedCatalogAssetRecord {
  asset: CatalogAssetRecord;
  preview: ValidatedCatalogDerivative & { mediaType: "image/png"; width: number; height: number };
  source: {
    storageKey: string;
    sha256: string;
    byteLength: number;
  };
  processor: {
    revision: string;
    configurationDigest: string;
  };
  derivationID: string;
}

export interface PrepareCatalogAssetOptions {
  product: {
    id: string;
    sourceProductID: string;
    name: string;
  };
  source: {
    storageKey: string;
    sha256: string;
    bytes: Uint8Array;
  };
  authorization: CatalogAssetRecord["authorization"];
  category: string;
  supportType: AssetSupportType;
  expectedDimensionsM: CatalogDimensionsM;
  cacheProfiles: readonly string[];
  processor: CatalogAssetProcessor;
  processorRevision: string;
  processorConfiguration: unknown;
  content: AssetPreparationContentStore;
  budgets?: AssetPreparationBudgets;
  signal?: AbortSignal;
}

/**
 * Validates a processor result completely before exposing any derivative as a
 * prepared asset. CAS objects may be harmlessly orphaned after an interrupted
 * commit, but an invalid result can never create a prepared record.
 */
export async function prepareCatalogAsset(
  options: PrepareCatalogAssetOptions,
): Promise<PreparedCatalogAssetRecord> {
  assertInput(options);
  throwIfAborted(options.signal);

  const configurationDigest = sha256(canonicalJSON(options.processorConfiguration));
  const derivationID = sha256(
    canonicalJSON({
      processorConfigurationDigest: configurationDigest,
      processorRevision: options.processorRevision,
      sourceSHA256: options.source.sha256,
    }),
  );
  const output = await options.processor.process({
    sourceGLB: options.source.bytes,
    sourceSHA256: options.source.sha256,
    derivationID,
    expectedDimensionsM: options.expectedDimensionsM,
    ...(options.signal === undefined ? {} : { signal: options.signal }),
  });
  throwIfAborted(options.signal);

  const budgets = validatedBudgets(options.budgets ?? DEFAULT_ASSET_PREPARATION_BUDGETS);
  validateProcessorOutput(output, options.expectedDimensionsM, budgets);

  const glb = derivative(output.glb);
  const usdz = derivative(output.usdz);
  const collision = derivative(output.collision);
  const preview = previewDerivative(output.preview);
  if (glb.sha256 === collision.sha256) throw new Error("collision_matches_visible_geometry");

  const [glbKey, usdzKey, collisionKey, previewKey] = await Promise.all([
    commit(options.content, "glb", output.glb, glb.sha256, options.source.sha256, derivationID),
    commit(options.content, "usdz", output.usdz, usdz.sha256, options.source.sha256, derivationID),
    commit(
      options.content,
      "collision",
      output.collision,
      collision.sha256,
      options.source.sha256,
      derivationID,
    ),
    commit(
      options.content,
      "preview",
      output.preview,
      preview.sha256,
      options.source.sha256,
      derivationID,
    ),
  ]);

  const assetID = `${options.product.id}-${options.source.sha256.slice(0, 12)}`;
  return {
    asset: {
      assetID,
      authorization: options.authorization,
      category: options.category,
      dimensionsM: output.dimensionsM,
      supportType: options.supportType,
      normalization: {
        units: "meters",
        origin: "floor-contact-center",
        forwardAxis: "+z",
      },
      derivatives: {
        glb: { ...glb, storageKey: glbKey },
        usdz: { ...usdz, storageKey: usdzKey },
        collision: {
          ...collision,
          storageKey: collisionKey,
          representation: "aabb",
        } satisfies CatalogCollisionDerivative,
      },
      cacheProfiles: [...options.cacheProfiles],
    },
    preview: { ...preview, storageKey: previewKey, mediaType: "image/png" },
    source: {
      storageKey: options.source.storageKey,
      sha256: options.source.sha256,
      byteLength: options.source.bytes.byteLength,
    },
    processor: { revision: options.processorRevision, configurationDigest },
    derivationID,
  };
}

function assertInput(options: PrepareCatalogAssetOptions): void {
  if (!SAFE_IDENTIFIER.test(options.product.id)) throw new Error("invalid_catalog_product_id");
  if (!SAFE_IDENTIFIER.test(options.product.sourceProductID))
    throw new Error("invalid_source_product_id");
  if (options.product.name.trim().length === 0 || options.product.name.length > 512)
    throw new Error("invalid_catalog_product_name");
  if (
    options.authorization.status !== "authorized" ||
    !safeReference(options.authorization.reference)
  )
    throw new Error("asset_authorization_required");
  if (!SAFE_CATEGORY.test(options.category)) throw new Error("invalid_asset_category");
  if (!SUPPORT_TYPES.has(options.supportType)) throw new Error("invalid_asset_support_type");
  if (!validDimensions(options.expectedDimensionsM)) throw new Error("invalid_asset_dimensions");
  if (
    options.cacheProfiles.some(
      (profile) => !SAFE_IDENTIFIER.test(profile) || profile.includes("://"),
    ) ||
    new Set(options.cacheProfiles).size !== options.cacheProfiles.length
  ) {
    throw new Error("invalid_asset_cache_profiles");
  }
  if (!SAFE_PROCESSOR_REVISION.test(options.processorRevision))
    throw new Error("invalid_asset_processor_revision");
  if (!SHA256.test(options.source.sha256)) throw new Error("invalid_source_content_hash");
  if (options.source.storageKey !== `sha256/${options.source.sha256}`)
    throw new Error("invalid_source_storage_key");
  if (sha256(options.source.bytes) !== options.source.sha256)
    throw new Error("source_content_hash_mismatch");
  validateGLB(options.source.bytes);
}

function validateProcessorOutput(
  output: CatalogAssetProcessorOutput,
  expectedDimensionsM: CatalogDimensionsM,
  budgets: AssetPreparationBudgets,
): void {
  assertBytesWithinBudget(output.glb, budgets.glbBytes, "glb");
  assertBytesWithinBudget(output.usdz, budgets.usdzBytes, "usdz");
  assertBytesWithinBudget(output.collision, budgets.collisionBytes, "collision");
  assertBytesWithinBudget(output.preview, budgets.previewBytes, "preview");
  validateGLB(output.glb);
  validateUSDZ(output.usdz);
  validateGLB(output.collision);
  previewDimensions(output.preview);
  if (!validDimensions(output.dimensionsM)) throw new Error("invalid_processed_asset_dimensions");
  for (const axis of ["width", "height", "depth"] as const) {
    const expected = expectedDimensionsM[axis];
    const measured = output.dimensionsM[axis];
    if (Math.abs(expected - measured) / expected > 0.05)
      throw new Error("asset_dimension_mismatch");
  }
}

function validatedBudgets(budgets: AssetPreparationBudgets): AssetPreparationBudgets {
  for (const value of Object.values(budgets)) {
    if (!Number.isSafeInteger(value) || value <= 0)
      throw new Error("invalid_asset_processing_budget");
  }
  return budgets;
}

function assertBytesWithinBudget(bytes: Uint8Array, budget: number, kind: string): void {
  if (!(bytes instanceof Uint8Array) || bytes.byteLength === 0 || bytes.byteLength > budget)
    throw new Error(`invalid_${kind}_derivative`);
}

function derivative(bytes: Uint8Array): ValidatedCatalogDerivative {
  return {
    storageKey: "",
    sha256: sha256(bytes),
    byteLength: bytes.byteLength,
    validated: true,
  };
}

function previewDerivative(
  bytes: Uint8Array,
): ValidatedCatalogDerivative & { width: number; height: number } {
  const { width, height } = previewDimensions(bytes);
  return {
    storageKey: "",
    sha256: sha256(bytes),
    byteLength: bytes.byteLength,
    validated: true,
    width,
    height,
  };
}

function previewDimensions(bytes: Uint8Array): { width: number; height: number } {
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (
    bytes.byteLength < 29 ||
    !signature.every((byte, index) => bytes[index] === byte) ||
    bytes[12] !== 0x49 ||
    bytes[13] !== 0x48 ||
    bytes[14] !== 0x44 ||
    bytes[15] !== 0x52
  ) {
    throw new Error("invalid_preview_png");
  }
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const width = view.getUint32(16, false);
  const height = view.getUint32(20, false);
  if (width === 0 || height === 0 || width > 2_048 || height > 2_048)
    throw new Error("invalid_preview_dimensions");
  return { width, height };
}

async function commit(
  content: AssetPreparationContentStore,
  kind: AssetPreparationDerivativeKind,
  bytes: Uint8Array,
  sha256Value: string,
  sourceSHA256: string,
  derivationID: string,
): Promise<string> {
  const storageKey = await content.commitDerivative({
    kind,
    bytes,
    sha256: sha256Value,
    sourceSHA256,
    derivationID,
  });
  if (typeof storageKey !== "string" || !storageKey.startsWith(`sha256/${sha256Value}`))
    throw new Error("invalid_derivative_storage_key");
  return storageKey;
}

function validDimensions(dimensions: CatalogDimensionsM): boolean {
  return Object.values(dimensions).every(
    (value) => Number.isFinite(value) && value > 0 && value < 100,
  );
}

function safeReference(reference: string): boolean {
  return reference.trim().length > 0 && reference.length <= 256 && !reference.includes("://");
}

function throwIfAborted(signal: AbortSignal | undefined): void {
  if (signal?.aborted) throw new Error("asset_preparation_cancelled");
}

function sha256(value: Uint8Array | string): string {
  return createHash("sha256").update(value).digest("hex");
}

function canonicalJSON(value: unknown): string {
  return JSON.stringify(canonicalize(value));
}

function canonicalize(value: unknown): unknown {
  if (value === null || typeof value === "string" || typeof value === "boolean") return value;
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error("invalid_asset_processor_configuration");
    return value;
  }
  if (Array.isArray(value)) return value.map(canonicalize);
  if (typeof value !== "object") throw new Error("invalid_asset_processor_configuration");
  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, nested]) => [key, canonicalize(nested)]),
  );
}
