import assert from "node:assert/strict";
import { execFile as execFileCallback } from "node:child_process";
import { access, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { mock, test } from "bun:test";
import { promisify } from "node:util";

import { runReplay } from "@reroom/contracts/replay";
import { projectVerifiedReplay } from "../src/lib/replay/project-verified-view.ts";

const execFile = promisify(execFileCallback);
const REPO_ROOT = path.resolve(import.meta.dirname, "../../..");
const FIXTURE_ROOT = path.join(REPO_ROOT, "fixtures/capture/1.0.0/rev-001");
const ARCHIVE_ROOT = path.join(FIXTURE_ROOT, "archives/finalized-one-frame.rrcap");
const FIXTURE_MANIFEST = path.join(FIXTURE_ROOT, "manifest.json");
const REPORT_NAME = "archive.finalized-one-frame.replay-report.json";
const IMPLEMENTATION_REVISION = "git:0d371bc1de9a057cbf61b70142729f6cbe620eec";
const SANITIZED_REJECTION = {
  status: "rejected",
  error: {
    code: "verification_failed",
    message: "The local replay fixture could not be verified.",
  },
};

mock.module("server-only", () => ({}));

const {
  __loadGoldenCaptureForTesting,
  loadGoldenCapture,
} = await import("../src/lib/replay/load-golden-capture.server.ts");

async function readJson(filePath) {
  return JSON.parse(await readFile(filePath, "utf8"));
}

async function acceptedReport() {
  const temporaryParent = await mkdtemp(path.join(os.tmpdir(), "reroom-web-projection-test-"));
  try {
    const outputRoot = path.join(temporaryParent, "reports");
    await runReplay({
      manifestPath: FIXTURE_MANIFEST,
      outputRoot,
      repoRoot: REPO_ROOT,
      implementationRevision: IMPLEMENTATION_REVISION,
    });
    return readJson(path.join(outputRoot, REPORT_NAME));
  } finally {
    await rm(temporaryParent, { recursive: true, force: true });
  }
}

async function projectionInput() {
  const manifest = await readJson(path.join(ARCHIVE_ROOT, "manifest.json"));
  const eventPayloads = await Promise.all(
    manifest.events.map(async ({ payload_path: relativePath }) => ({
      relativePath,
      value: await readJson(path.join(ARCHIVE_ROOT, relativePath)),
    })),
  );
  const framePackets = await Promise.all(
    manifest.accepted_frame_order.map(async ({ packet_path: relativePath }) => ({
      relativePath,
      value: await readJson(path.join(ARCHIVE_ROOT, relativePath)),
    })),
  );
  const imagePayloads = await Promise.all(
    framePackets.map(async ({ value }) => ({
      relativePath: value.image.payload.relative_path,
      bytes: await readFile(path.join(ARCHIVE_ROOT, value.image.payload.relative_path)),
    })),
  );
  return {
    report: await acceptedReport(),
    manifest,
    eventPayloads,
    framePackets,
    imagePayloads,
  };
}

test("accepted exact replay projects one serializable authoritative view", async () => {
  const input = await projectionInput();
  const replay = projectVerifiedReplay(input);

  assert.deepEqual(replay.labels, {
    mode: "MODE B0 — RECORDED REPLAY",
    provider: "PROVIDER-INDEPENDENT",
    fixture: "LOCAL DEMO FIXTURE",
    gate: "GATE-008 PENDING",
  });
  assert.equal(replay.verification.verdict, "accept");
  assert.equal(replay.verification.reportSha256, input.report.report_sha256);
  assert.equal(replay.archive.archiveName, "finalized-one-frame.rrcap");
  assert.equal(replay.archive.finalizationState, "finalized");
  assert.equal(replay.events.length, 7);
  assert.deepEqual(
    replay.events.map(({ eventSequence, durableJournalSequence }) => [eventSequence, durableJournalSequence]),
    [[0, 0], [1, 1], [2, 2], [3, 4], [4, 5], [5, 6], [6, 7]],
  );
  assert.equal(replay.events[0].eventId, "event_00000002-0000-4000-8000-000000000001");
  assert.equal(replay.events[0].monotonicTimestampNs, "1000002000");
  assert.deepEqual(replay.events[0].payload, {
    details: { consent_granted: true },
    event_version: "1.0.0",
    session_id: "session_00000002-0000-4000-8000-000000000001",
    type: "session_started",
  });
  assert.equal(replay.frames.length, 1);
  assert.equal(replay.frames[0].frameId, "frame_00000002-0000-4000-8000-000000000001");
  assert.equal(replay.frames[0].monotonicTimestampNs, "1000002003");
  assert.equal(replay.frames[0].preview.mediaType, "image/png");
  assert.equal(
    replay.frames[0].preview.dataUrl,
    `data:image/png;base64,${input.imagePayloads[0].bytes.toString("base64")}`,
  );
  assert.deepEqual(replay.privacy, {
    captureConsentRecorded: true,
    containsRoomImagery: true,
    deletionState: "none",
    retentionPolicy: "local_only_until_share",
    shareAccessState: "not_shared",
    browserPersistence: "none",
  });
  assert.equal(replay.content.scene, "not_present");
  assert.equal(replay.content.transactions, "not_present");
  assert.equal(replay.capabilities.find(({ id }) => id === "providers").state, "unavailable");
  assert.equal(replay.capabilities.find(({ id }) => id === "scene").state, "not_present");
  assert.deepEqual(JSON.parse(JSON.stringify(replay)), replay);
  assert.deepEqual(structuredClone(replay), replay);
});

test("report and archive identity mismatches reject before a view exists", async () => {
  const mutations = [
    ["verdict", (input) => { input.report.verdict = "reject"; }],
    ["rejection", (input) => { input.report.rejection = { rejection_class: "semantic_invariant", detail: "private" }; }],
    ["fixture id", (input) => { input.report.fixture.fixture_id = "FX-CAPTURE-999"; }],
    ["fixture revision", (input) => { input.report.fixture.fixture_revision = "rev-999"; }],
    ["fixture digest", (input) => { input.report.fixture.manifest_sha256 = "0".repeat(64); }],
    ["report digest", (input) => { input.report.report_sha256 = "0".repeat(64); }],
    ["archive case", (input) => { input.report.archive.case_id = "archive.finalized-empty"; }],
    ["archive name", (input) => { input.report.archive.archive_name = "finalized-empty.rrcap"; }],
    ["finalization", (input) => { input.report.archive.finalization_state = "recovered_prefix"; }],
    ["frame count", (input) => { input.report.archive.accepted_frame_count = 2; }],
    ["event count", (input) => { input.report.archive.event_count = 8; }],
    ["journal count", (input) => { input.report.archive.journal_record_count = 9; }],
    ["archive digest", (input) => { input.report.archive.manifest_sha256 = "0".repeat(64); }],
    ["projection digest", (input) => { input.report.digests.event_projection_sha256 = "0".repeat(64); }],
    ["implementation revision", (input) => { input.report.implementation.repository_revision = "git:0000000000000000000000000000000000000000"; }],
  ];

  for (const [name, mutate] of mutations) {
    const input = await projectionInput();
    mutate(input);
    assert.throws(() => projectVerifiedReplay(input), undefined, name);
  }
});

test("missing or changed verified members reject instead of producing partial data", async () => {
  const mutations = [
    ["privacy", (input) => { delete input.manifest.privacy; }],
    ["event path", (input) => { input.manifest.events[0].payload_path = "events/other.json"; }],
    ["event payload", (input) => { input.eventPayloads[0].value.type = "session_finalized"; }],
    ["frame path", (input) => { input.manifest.accepted_frame_order[0].packet_path = "frames/other.json"; }],
    ["packet digest", (input) => { input.manifest.accepted_frame_order[0].packet_sha256 = "0".repeat(64); }],
    ["image path", (input) => { input.framePackets[0].value.image.payload.relative_path = "image/other.png"; }],
    ["image digest", (input) => { input.framePackets[0].value.image.payload.sha256 = "0".repeat(64); }],
    ["image bytes", (input) => { input.imagePayloads[0].bytes = Buffer.from("not the verified png"); }],
  ];

  for (const [name, mutate] of mutations) {
    const input = await projectionInput();
    mutate(input);
    assert.throws(() => projectVerifiedReplay(input), undefined, name);
  }
});

async function runLoaderProbe(scenario) {
  let temporaryParent = null;
  let invocation = null;
  const result = await __loadGoldenCaptureForTesting({
    mkdtemp: async (prefix) => {
      temporaryParent = await mkdtemp(prefix);
      return temporaryParent;
    },
    execFile: async (executable, args, options) => {
      invocation = { executable, args, options };
      if (scenario === "runner_failure") throw new Error("private /tmp/runner-secret");
      const outputRoot = args[args.indexOf("--output-root") + 1];
      if (scenario === "missing_report") return { stdout: "", stderr: "" };
      if (scenario === "malformed_report") {
        await mkdir(outputRoot);
        await writeFile(path.join(outputRoot, REPORT_NAME), "{not json");
        return { stdout: "", stderr: "" };
      }
      return execFile(executable, args, options);
    },
    remove: async (target, options) => {
      await rm(target, options);
      if (scenario === "cleanup_failure") throw new Error("private /tmp/cleanup-secret");
    },
  });
  let temporaryParentExists = false;
  if (temporaryParent !== null) {
    try {
      await access(temporaryParent);
      temporaryParentExists = true;
    } catch {}
  }
  return { result, invocation, temporaryParentExists, publicArity: loadGoldenCapture.length };
}

test("server-only loader invokes the exact fixed CLI and cleans temporary output", async () => {
  const probe = await runLoaderProbe("success");
  const temporaryParent = path.dirname(path.dirname(probe.invocation.args[2]));
  assert.equal(probe.publicArity, 0);
  assert.equal(probe.result.status, "verified");
  assert.equal(probe.invocation.executable, process.execPath);
  assert.deepEqual(probe.invocation.args, [
    path.join(REPO_ROOT, "packages/contracts/src/replay.ts"),
    "--manifest",
    path.join(temporaryParent, "fixture/manifest.json"),
    "--output-root",
    path.join(temporaryParent, "reports"),
    "--repo-root",
    REPO_ROOT,
    "--implementation-revision",
    IMPLEMENTATION_REVISION,
  ]);
  assert.equal(probe.invocation.options.cwd, REPO_ROOT);
  assert.equal(probe.invocation.options.shell, false);
  assert.equal(probe.temporaryParentExists, false);
});

test("runner, report, JSON, and cleanup failures return one sanitized rejection", async () => {
  for (const scenario of ["runner_failure", "missing_report", "malformed_report", "cleanup_failure"]) {
    const probe = await runLoaderProbe(scenario);
    assert.deepEqual(probe.result, SANITIZED_REJECTION, scenario);
    assert.equal(probe.temporaryParentExists, false, scenario);
    const exposed = JSON.stringify(probe.result);
    assert.doesNotMatch(exposed, /private|\/tmp|runner-secret|cleanup-secret|stack|\.rrcap/i, scenario);
  }
});
