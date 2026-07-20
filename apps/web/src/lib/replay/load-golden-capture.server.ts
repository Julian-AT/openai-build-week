import 'server-only';

import { execFile as execFileCallback } from "node:child_process";
import { existsSync } from "node:fs";
import { cp, mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

import {
  assertAcceptedGoldenReport,
  projectVerifiedReplay,
  type VerifiedProjectionInput,
} from "./project-verified-view.ts";
import type { GoldenReplayResult } from "./types.ts";

function resolveRepositoryRoot(): string {
  const candidates = [process.cwd(), path.resolve(process.cwd(), "../..")];
  for (const candidate of candidates) {
    if (
      existsSync(path.join(candidate, "fixtures/capture/1.0.0/rev-001/manifest.json")) &&
      existsSync(path.join(candidate, "packages/contracts/src/replay.ts"))
    ) {
      return candidate;
    }
  }
  throw new Error("ReRoom repository root is unavailable");
}

const REPOSITORY_ROOT = resolveRepositoryRoot();
const FIXTURE_ROOT = path.join(REPOSITORY_ROOT, "fixtures/capture/1.0.0/rev-001");
const REPLAY_RUNNER = path.join(REPOSITORY_ROOT, "packages/contracts/src/replay.ts");
const REPORT_NAME = "archive.finalized-one-frame.replay-report.json";
const IMPLEMENTATION_REVISION = "git:0d371bc1de9a057cbf61b70142729f6cbe620eec";
const ARCHIVE_RELATIVE_PATH = "archives/finalized-one-frame.rrcap";
const EVENT_PATHS = [
  "events/event_0000.json",
  "events/event_0001.json",
  "events/event_0002.json",
  "events/event_0003.json",
  "events/event_0004.json",
  "events/event_0005.json",
  "events/event_0006.json",
] as const;
const FRAME_PATH = "frames/frame_0001.json";
const IMAGE_PATH = "image/frame_0001.png";
const REJECTION_MESSAGE = "The local replay fixture could not be verified.";

type ExecFileOptions = {
  cwd: string;
  encoding: "utf8";
  maxBuffer: number;
  shell: false;
};

type Effects = {
  copy: typeof cp;
  mkdtemp: typeof mkdtemp;
  readFile: typeof readFile;
  remove: typeof rm;
  execFile: (executable: string, args: readonly string[], options: ExecFileOptions) => Promise<{ stdout: string; stderr: string }>;
};

function executeFile(executable: string, args: readonly string[], options: ExecFileOptions): Promise<{ stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    execFileCallback(executable, args, options, (error, stdout, stderr) => {
      if (error) reject(error);
      else resolve({ stdout, stderr });
    });
  });
}

const defaultEffects: Effects = {
  copy: cp,
  mkdtemp,
  readFile,
  remove: rm,
  execFile: executeFile,
};

function rejectedResult(): GoldenReplayResult {
  return {
    status: "rejected",
    error: { code: "verification_failed", message: REJECTION_MESSAGE },
  };
}

function parseJson(bytes: Buffer): unknown {
  return JSON.parse(bytes.toString("utf8"));
}

async function readProjectionInput(
  effects: Effects,
  copiedFixtureRoot: string,
  report: unknown,
): Promise<VerifiedProjectionInput> {
  const archiveRoot = path.join(copiedFixtureRoot, ARCHIVE_RELATIVE_PATH);
  const eventPayloads = await Promise.all(
    EVENT_PATHS.map(async (relativePath) => ({
      relativePath,
      value: parseJson(await effects.readFile(path.join(archiveRoot, relativePath))),
    })),
  );
  const framePacket = parseJson(await effects.readFile(path.join(archiveRoot, FRAME_PATH)));
  return {
    report,
    manifest: parseJson(await effects.readFile(path.join(archiveRoot, "manifest.json"))),
    eventPayloads,
    framePackets: [{ relativePath: FRAME_PATH, value: framePacket }],
    imagePayloads: [{ relativePath: IMAGE_PATH, bytes: await effects.readFile(path.join(archiveRoot, IMAGE_PATH)) }],
  };
}

async function loadWithEffects(effects: Effects): Promise<GoldenReplayResult> {
  let temporaryParent: string | undefined;
  let result = rejectedResult();
  try {
    temporaryParent = await effects.mkdtemp(path.join(tmpdir(), "reroom-mode-b0-"));
    const copiedFixtureRoot = path.join(temporaryParent, "fixture");
    const outputRoot = path.join(temporaryParent, "reports");
    await effects.copy(FIXTURE_ROOT, copiedFixtureRoot, { recursive: true, force: false, errorOnExist: true });
    const fixedArguments = [
      REPLAY_RUNNER,
      "--manifest",
      path.join(copiedFixtureRoot, "manifest.json"),
      "--output-root",
      outputRoot,
      "--repo-root",
      REPOSITORY_ROOT,
      "--implementation-revision",
      IMPLEMENTATION_REVISION,
    ] as const;
    await effects.execFile(process.execPath, fixedArguments, {
      cwd: REPOSITORY_ROOT,
      encoding: "utf8",
      maxBuffer: 1024 * 1024,
      shell: false,
    });

    const report = parseJson(await effects.readFile(path.join(outputRoot, REPORT_NAME)));
    assertAcceptedGoldenReport(report);
    const input = await readProjectionInput(effects, copiedFixtureRoot, report);
    result = { status: "verified", replay: projectVerifiedReplay(input) };
  } catch {
    result = rejectedResult();
  }

  if (temporaryParent !== undefined) {
    try {
      await effects.remove(temporaryParent, { recursive: true, force: true });
    } catch {
      return rejectedResult();
    }
  }
  return result;
}

export async function loadGoldenCapture(): Promise<GoldenReplayResult> {
  return loadWithEffects(defaultEffects);
}

export async function __loadGoldenCaptureForTesting(overrides: Partial<Effects>): Promise<GoldenReplayResult> {
  return loadWithEffects({ ...defaultEffects, ...overrides });
}
