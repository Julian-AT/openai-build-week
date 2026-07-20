import { createHash } from "node:crypto";
import { join } from "node:path";
import { type PreparedCatalogAssetRecord, prepareCatalogAsset } from "./asset-preparation.ts";
import {
  BLENDER_NORMALIZER_SCRIPT_PATH,
  createBlenderAssetProcessor,
} from "./blender-asset-processor.ts";
import { createFilesystemAcquisitionStores } from "./filesystem-acquisition-store.ts";
import { createFilesystemPreparedAssetStore } from "./filesystem-prepared-asset-store.ts";
import { REFRAME_IKEA_US_AUTHORIZATION } from "./ikea-authorization.ts";
import { createIkeaGLBFetchTransport } from "./ikea-glb-transport.ts";
import { type IkeaUSSourceSmokeResult, runIkeaUSSourceSmoke } from "./ikea-source.ts";
import type { AssetSupportType, CatalogDimensionsM } from "./types.ts";

export interface IkeaSourceSmokeEnvironment {
  [name: string]: string | undefined;
  REFRAME_DATA_DIR?: string;
  REFRAME_IKEA_SMOKE_PRODUCT_URL?: string;
}

export interface IkeaPreparedSmokeEnvironment extends IkeaSourceSmokeEnvironment {
  REFRAME_IKEA_SMOKE_WIDTH_M?: string;
  REFRAME_IKEA_SMOKE_HEIGHT_M?: string;
  REFRAME_IKEA_SMOKE_DEPTH_M?: string;
  REFRAME_IKEA_SMOKE_CATEGORY?: string;
  REFRAME_IKEA_SMOKE_SUPPORT_TYPE?: string;
  REFRAME_IKEA_SMOKE_CACHE_PROFILES?: string;
  REFRAME_BLENDER_PATH?: string;
  REFRAME_USDZIP_PATH?: string;
  REFRAME_USDCHECKER_PATH?: string;
  REFRAME_ASSET_PROCESSOR_REVISION?: string;
}

export interface IkeaPreparedSmokeResult extends IkeaUSSourceSmokeResult {
  prepared: PreparedCatalogAssetRecord;
}

/** Executes one explicitly configured live source acquisition without broadening the frontier. */
export async function runIkeaSourceSmokeFromEnvironment(
  environment: IkeaSourceSmokeEnvironment,
): Promise<IkeaUSSourceSmokeResult> {
  const dataDirectory = environment.REFRAME_DATA_DIR;
  if (dataDirectory === undefined || dataDirectory.length === 0) {
    throw new Error("missing_reframe_data_dir");
  }
  const productURL = environment.REFRAME_IKEA_SMOKE_PRODUCT_URL;
  if (productURL === undefined || productURL.length === 0) {
    throw new Error("missing_reframe_ikea_smoke_product_url");
  }
  const stores = await createFilesystemAcquisitionStores({ dataDirectory });
  const result = await runIkeaUSSourceSmoke({
    authorization: REFRAME_IKEA_US_AUTHORIZATION,
    productURL,
    state: stores.state,
    content: stores.content,
    transport: createIkeaGLBFetchTransport(),
    nowMs: Date.now(),
  });
  if (result.acquisition.status !== "complete") throw new Error("ikea_source_smoke_incomplete");
  return result;
}

/**
 * Completes the real source-to-prepared-asset spine for one explicitly
 * configured product. It is intentionally bounded to one existing product.
 */
export async function runIkeaPreparedSmokeFromEnvironment(
  environment: IkeaPreparedSmokeEnvironment,
): Promise<IkeaPreparedSmokeResult> {
  const configuration = preparedSmokeConfiguration(environment);
  await assertProcessorPaths(configuration);
  const normalizerScriptSHA256 = hash(await Bun.file(BLENDER_NORMALIZER_SCRIPT_PATH).arrayBuffer());
  const processor = createBlenderAssetProcessor({
    blenderPath: configuration.blenderPath,
    usdzipPath: configuration.usdzipPath,
    usdcheckerPath: configuration.usdcheckerPath,
    scriptPath: BLENDER_NORMALIZER_SCRIPT_PATH,
    workDirectory: join(configuration.dataDirectory, "catalog", "processor-work"),
    timeoutMs: 120_000,
  });
  const preparedStore = await createFilesystemPreparedAssetStore({
    dataDirectory: configuration.dataDirectory,
  });
  const source = await runIkeaSourceSmokeFromEnvironment(environment);
  const content = source.acquisition.checkpoint.content;
  if (content === undefined) throw new Error("ikea_source_smoke_missing_content");
  const acquisitionStores = await createFilesystemAcquisitionStores({
    dataDirectory: configuration.dataDirectory,
  });
  const sourceGLB = await acquisitionStores.source.read(content);
  const prepared = await prepareCatalogAsset({
    product: {
      id: source.product.id,
      sourceProductID: source.product.sourceProductID,
      name: source.product.name,
    },
    source: { storageKey: content.storageKey, sha256: content.sha256, bytes: sourceGLB },
    authorization: {
      status: "authorized",
      reference: REFRAME_IKEA_US_AUTHORIZATION.authorizationReference,
    },
    category: configuration.category,
    supportType: configuration.supportType,
    expectedDimensionsM: configuration.dimensionsM,
    cacheProfiles: configuration.cacheProfiles,
    processor,
    processorRevision: configuration.processorRevision,
    processorConfiguration: {
      collision: "aabb",
      preview: "png-512",
      units: "meters",
      usdz: "arkit-usdzip",
      normalizerScriptSHA256,
    },
    content: preparedStore,
  });
  await preparedStore.savePreparedAsset(prepared);
  return { ...source, prepared };
}

function preparedSmokeConfiguration(environment: IkeaPreparedSmokeEnvironment): {
  dataDirectory: string;
  dimensionsM: CatalogDimensionsM;
  category: string;
  supportType: AssetSupportType;
  cacheProfiles: string[];
  blenderPath: string;
  usdzipPath: string;
  usdcheckerPath: string;
  processorRevision: string;
} {
  const dataDirectory = required(environment.REFRAME_DATA_DIR, "reframe_data_dir");
  const dimensionsM = {
    width: meter(environment.REFRAME_IKEA_SMOKE_WIDTH_M, "width_m"),
    height: meter(environment.REFRAME_IKEA_SMOKE_HEIGHT_M, "height_m"),
    depth: meter(environment.REFRAME_IKEA_SMOKE_DEPTH_M, "depth_m"),
  };
  const category = required(environment.REFRAME_IKEA_SMOKE_CATEGORY, "ikea_smoke_category");
  if (!/^[a-z][a-z0-9_]{1,63}$/u.test(category))
    throw new Error("invalid_reframe_ikea_smoke_category");
  const support = required(environment.REFRAME_IKEA_SMOKE_SUPPORT_TYPE, "ikea_smoke_support_type");
  if (!(["floor", "surface", "wall", "ceiling"] as const).includes(support as AssetSupportType))
    throw new Error("invalid_reframe_ikea_smoke_support_type");
  const cacheProfiles = (environment.REFRAME_IKEA_SMOKE_CACHE_PROFILES ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
  if (
    cacheProfiles.some((profile) => !/^[a-z0-9][a-z0-9._-]{1,127}$/u.test(profile)) ||
    new Set(cacheProfiles).size !== cacheProfiles.length
  ) {
    throw new Error("invalid_reframe_ikea_smoke_cache_profiles");
  }
  return {
    dataDirectory,
    dimensionsM,
    category,
    supportType: support as AssetSupportType,
    cacheProfiles,
    blenderPath: required(environment.REFRAME_BLENDER_PATH, "blender_path"),
    usdzipPath: required(environment.REFRAME_USDZIP_PATH, "usdzip_path"),
    usdcheckerPath: required(environment.REFRAME_USDCHECKER_PATH, "usdchecker_path"),
    processorRevision: required(
      environment.REFRAME_ASSET_PROCESSOR_REVISION,
      "asset_processor_revision",
    ),
  };
}

function required(value: string | undefined, name: string): string {
  if (value === undefined || value.trim().length === 0) throw new Error(`missing_reframe_${name}`);
  return value.trim();
}

function meter(value: string | undefined, name: string): number {
  const parsed = Number(required(value, `ikea_smoke_${name}`));
  if (!Number.isFinite(parsed) || parsed <= 0 || parsed >= 100)
    throw new Error(`invalid_reframe_ikea_smoke_${name}`);
  return parsed;
}

async function assertProcessorPaths(configuration: {
  blenderPath: string;
  usdzipPath: string;
  usdcheckerPath: string;
}): Promise<void> {
  const paths = [
    configuration.blenderPath,
    configuration.usdzipPath,
    configuration.usdcheckerPath,
    BLENDER_NORMALIZER_SCRIPT_PATH,
  ];
  if (!(await Promise.all(paths.map((path) => Bun.file(path).exists()))).every(Boolean))
    throw new Error("asset_processor_unavailable");
}

function hash(buffer: ArrayBuffer): string {
  return createHash("sha256").update(new Uint8Array(buffer)).digest("hex");
}
