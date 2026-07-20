import { createHash } from "node:crypto";
import { mkdir, mkdtemp, rm, stat, writeFile } from "node:fs/promises";
import { isAbsolute, join, resolve } from "node:path";
import type {
  AssetPreparationBudgets,
  CatalogAssetProcessor,
  CatalogAssetProcessorRequest,
} from "./asset-preparation.ts";
import { DEFAULT_ASSET_PREPARATION_BUDGETS } from "./asset-preparation.ts";
import { validateGLB, validateUSDZ } from "./asset-validator.ts";
import type { CatalogDimensionsM } from "./types.ts";

const SHA256 = /^[a-f0-9]{64}$/u;
const MIN_TIMEOUT_MS = 1_000;
const MAX_TIMEOUT_MS = 5 * 60_000;

/** Package-relative build-only script; callers may override only with an absolute path. */
export const BLENDER_NORMALIZER_SCRIPT_PATH = join(
  import.meta.dir,
  "..",
  "processors",
  "blender-normalize.py",
);

export interface AssetProcessorCommandRunner {
  run(request: {
    command: string;
    arguments: readonly string[];
    cwd: string;
    timeoutMs: number;
    signal?: AbortSignal;
  }): Promise<{ exitCode: number }>;
}

export interface BlenderAssetProcessorOptions {
  blenderPath: string;
  usdzipPath: string;
  usdcheckerPath: string;
  /** Optional package-local normalization script. Supply only an absolute path when overriding it. */
  scriptPath?: string;
  /** Absolute external scratch directory; all worker artifacts are removed after every run. */
  workDirectory: string;
  timeoutMs: number;
  budgets?: AssetPreparationBudgets;
  runner?: AssetProcessorCommandRunner;
}

/**
 * Build-time processor adapter. Blender and the Apple USD tools stay outside
 * the app artifact and execute in a per-job external scratch directory.
 */
export function createBlenderAssetProcessor(
  options: BlenderAssetProcessorOptions,
): CatalogAssetProcessor {
  const configuration = validateConfiguration(options);
  const runner = options.runner ?? systemCommandRunner;
  return {
    process: async (request) => {
      validateRequest(request);
      await mkdir(configuration.workDirectory, { recursive: true });
      const jobDirectory = await mkdtemp(join(configuration.workDirectory, "reframe-asset-"));
      try {
        const sourcePath = join(jobDirectory, "source.glb");
        const glbPath = join(jobDirectory, "delivery.glb");
        const usdzPath = join(jobDirectory, "delivery.usdz");
        const collisionPath = join(jobDirectory, "collision.glb");
        const previewPath = join(jobDirectory, "preview.png");
        const manifestPath = join(jobDirectory, "manifest.json");
        await writeFile(sourcePath, request.sourceGLB, { flag: "wx" });
        await runOrThrow(runner, {
          command: configuration.blenderPath,
          arguments: [
            "--factory-startup",
            "--background",
            "--python",
            configuration.scriptPath,
            "--",
            "--source",
            sourcePath,
            "--glb",
            glbPath,
            "--usdz",
            usdzPath,
            "--collision",
            collisionPath,
            "--preview",
            previewPath,
            "--manifest",
            manifestPath,
            "--usdzip",
            configuration.usdzipPath,
          ],
          cwd: jobDirectory,
          timeoutMs: configuration.timeoutMs,
          ...(request.signal === undefined ? {} : { signal: request.signal }),
        });
        await runOrThrow(runner, {
          command: configuration.usdcheckerPath,
          arguments: ["--arkit", usdzPath],
          cwd: jobDirectory,
          timeoutMs: configuration.timeoutMs,
          ...(request.signal === undefined ? {} : { signal: request.signal }),
        });
        await runOrThrow(runner, {
          command: configuration.usdzipPath,
          arguments: [usdzPath, "--list", "-"],
          cwd: jobDirectory,
          timeoutMs: configuration.timeoutMs,
          ...(request.signal === undefined ? {} : { signal: request.signal }),
        });

        const [glb, usdz, collision, preview, manifest] = await Promise.all([
          readBounded(glbPath, configuration.budgets.glbBytes),
          readBounded(usdzPath, configuration.budgets.usdzBytes),
          readBounded(collisionPath, configuration.budgets.collisionBytes),
          readBounded(previewPath, configuration.budgets.previewBytes),
          readManifest(manifestPath),
        ]);
        validateGLB(glb);
        validateUSDZ(usdz);
        validateGLB(collision);
        return { glb, usdz, collision, preview, dimensionsM: manifest.dimensionsM };
      } catch (error) {
        if (request.signal?.aborted) throw new Error("asset_processor_cancelled");
        if (error instanceof Error && error.message.startsWith("asset_processor_")) throw error;
        throw new Error("asset_processor_failed");
      } finally {
        await rm(jobDirectory, { recursive: true, force: true });
      }
    },
  };
}

const systemCommandRunner: AssetProcessorCommandRunner = {
  run: async ({ command, arguments: arguments_, cwd, timeoutMs, signal }) => {
    if (signal?.aborted) throw new Error("asset_processor_cancelled");
    const process = Bun.spawn([command, ...arguments_], {
      cwd,
      stdout: "ignore",
      stderr: "ignore",
    });
    let timeout: ReturnType<typeof setTimeout> | undefined;
    let removeAbortListener: (() => void) | undefined;
    try {
      const result = await Promise.race([
        process.exited,
        new Promise<number>((resolveTimeout) => {
          timeout = setTimeout(() => {
            process.kill();
            resolveTimeout(-1);
          }, timeoutMs);
        }),
        new Promise<number>((resolveAbort) => {
          if (signal === undefined) return;
          const onAbort = () => {
            process.kill();
            resolveAbort(-2);
          };
          signal.addEventListener("abort", onAbort, { once: true });
          removeAbortListener = () => signal.removeEventListener("abort", onAbort);
        }),
      ]);
      if (result === -1) throw new Error("asset_processor_timeout");
      if (result === -2) throw new Error("asset_processor_cancelled");
      return { exitCode: result };
    } finally {
      if (timeout !== undefined) clearTimeout(timeout);
      removeAbortListener?.();
    }
  },
};

function validateConfiguration(options: BlenderAssetProcessorOptions): {
  blenderPath: string;
  usdzipPath: string;
  usdcheckerPath: string;
  scriptPath: string;
  workDirectory: string;
  timeoutMs: number;
  budgets: AssetPreparationBudgets;
} {
  const scriptPath = options.scriptPath ?? BLENDER_NORMALIZER_SCRIPT_PATH;
  for (const path of [
    options.blenderPath,
    options.usdzipPath,
    options.usdcheckerPath,
    scriptPath,
    options.workDirectory,
  ]) {
    if (typeof path !== "string" || !isAbsolute(path) || path.includes("\0"))
      throw new Error("invalid_asset_processor_path");
  }
  if (
    !Number.isSafeInteger(options.timeoutMs) ||
    options.timeoutMs < MIN_TIMEOUT_MS ||
    options.timeoutMs > MAX_TIMEOUT_MS
  ) {
    throw new Error("invalid_asset_processor_timeout");
  }
  const budgets = options.budgets ?? DEFAULT_ASSET_PREPARATION_BUDGETS;
  if (Object.values(budgets).some((value) => !Number.isSafeInteger(value) || value <= 0))
    throw new Error("invalid_asset_processing_budget");
  return {
    blenderPath: resolve(options.blenderPath),
    usdzipPath: resolve(options.usdzipPath),
    usdcheckerPath: resolve(options.usdcheckerPath),
    scriptPath: resolve(scriptPath),
    workDirectory: resolve(options.workDirectory),
    timeoutMs: options.timeoutMs,
    budgets,
  };
}

function validateRequest(request: CatalogAssetProcessorRequest): void {
  if (!SHA256.test(request.sourceSHA256) || !SHA256.test(request.derivationID))
    throw new Error("invalid_asset_processor_request");
  if (hash(request.sourceGLB) !== request.sourceSHA256)
    throw new Error("source_content_hash_mismatch");
  validateGLB(request.sourceGLB);
}

async function runOrThrow(
  runner: AssetProcessorCommandRunner,
  request: Parameters<AssetProcessorCommandRunner["run"]>[0],
): Promise<void> {
  const result = await runner.run(request);
  if (result.exitCode !== 0) throw new Error("asset_processor_failed");
}

async function readBounded(path: string, limit: number): Promise<Uint8Array> {
  const metadata = await stat(path);
  if (!metadata.isFile() || metadata.size <= 0 || metadata.size > limit)
    throw new Error("asset_processor_invalid_output");
  return new Uint8Array(await Bun.file(path).arrayBuffer());
}

async function readManifest(path: string): Promise<{ dimensionsM: CatalogDimensionsM }> {
  const metadata = await stat(path);
  if (!metadata.isFile() || metadata.size <= 0 || metadata.size > 16 * 1024)
    throw new Error("asset_processor_invalid_manifest");
  let value: unknown;
  try {
    value = JSON.parse(await Bun.file(path).text()) as unknown;
  } catch {
    throw new Error("asset_processor_invalid_manifest");
  }
  if (typeof value !== "object" || value === null || Array.isArray(value))
    throw new Error("asset_processor_invalid_manifest");
  const dimensions = (value as Record<string, unknown>).dimensions_m;
  if (typeof dimensions !== "object" || dimensions === null || Array.isArray(dimensions))
    throw new Error("asset_processor_invalid_manifest");
  const dimensionsM = dimensions as CatalogDimensionsM;
  if (
    !Object.values(dimensionsM).every(
      (dimension) => Number.isFinite(dimension) && dimension > 0 && dimension < 100,
    )
  ) {
    throw new Error("asset_processor_invalid_manifest");
  }
  return { dimensionsM };
}

function hash(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}
