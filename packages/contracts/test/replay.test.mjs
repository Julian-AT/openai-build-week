import { test } from "bun:test";
import assert from "node:assert/strict";
import { cp, mkdir, mkdtemp, readdir, readFile, stat, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { canonicalDigest, canonicalizeBytes } from "../src/canonical-json.mjs";
import { EXACT_BUN_VERSION, runReplay } from "../src/replay.ts";

const REPO_ROOT = path.resolve(import.meta.dirname, "../../..");
const MANIFEST = path.join(REPO_ROOT, "fixtures/capture/1.0.0/rev-001/manifest.json");
const REVISION = "git:0123456789abcdef0123456789abcdef01234567";
const FIXTURE_SHA256 = "3b4519d2730e158df73e938f7b841664c6ce5f7d65ed2650c90ca8e89c7a7610";

async function temporaryDirectory() {
  return mkdtemp(path.join(os.tmpdir(), "reroom-bun-replay-test-"));
}

async function reportsAt(root) {
  const names = (await readdir(root)).sort();
  const reports = new Map();
  for (const name of names) reports.set(name, await readFile(path.join(root, name)));
  return reports;
}

function unsignedReport(report) {
  const value = structuredClone(report);
  delete value.report_sha256;
  return value;
}

test("exact Bun independently emits the complete closed replay corpus", async () => {
  assert.equal(process.versions.bun, EXACT_BUN_VERSION);
  const fixture = JSON.parse(await readFile(MANIFEST, "utf8"));
  const temporary = await temporaryDirectory();
  const output = path.join(temporary, "reports");

  await runReplay({
    manifestPath: MANIFEST,
    outputRoot: output,
    repoRoot: REPO_ROOT,
    implementationRevision: REVISION,
  });

  const reports = await reportsAt(output);
  const expectedCaseIDs = [
    ...fixture.archives.map(
      ({ archive_name }) => `archive.${archive_name.slice(0, -".rrcap".length)}`,
    ),
    ...fixture.edge_probes.map(({ case_id }) => case_id),
    "sec-consent.denied",
  ].sort();
  assert.deepEqual(
    [...reports.keys()],
    expectedCaseIDs.map((caseID) => `${caseID}.replay-report.json`),
  );

  for (const [name, bytes] of reports) {
    const report = JSON.parse(bytes);
    assert.deepEqual(bytes, canonicalizeBytes(report), `${name} is not exact JCS bytes`);
    assert.equal(report.report_version, "1.0.0");
    assert.deepEqual(report.evaluator, {
      name: "ReRoomReplayBun",
      platform: "javascript",
      version: "1.0.0",
    });
    assert.deepEqual(report.fixture, {
      fixture_id: "FX-CAPTURE-001",
      fixture_revision: "rev-001",
      manifest_sha256: FIXTURE_SHA256,
    });
    assert.deepEqual(report.implementation, {
      build_id: "ReRoomReplayBun-1.0.0",
      repository_revision: REVISION,
      runtime: "bun-v1.3.11",
    });
    assert.equal(report.report_sha256, canonicalDigest(unsignedReport(report)));
  }

  for (const descriptor of fixture.archives) {
    const caseID = `archive.${descriptor.archive_name.slice(0, -".rrcap".length)}`;
    const report = JSON.parse(reports.get(`${caseID}.replay-report.json`));
    assert.equal(report.verdict, descriptor.expected.verdict);
    assert.equal(report.rejection, null);
    assert.deepEqual(report.digests, {
      event_projection_sha256: descriptor.expected.event_projection_sha256,
      frame_projection_sha256: descriptor.expected.frame_projection_sha256,
      journal_tuple_sha256: descriptor.expected.journal_tuple_sha256,
      revision_trace_sha256: descriptor.expected.revision_trace_sha256,
    });
    assert.equal(report.archive.finalization_state, descriptor.expected.finalization_state);
    assert.equal(report.archive.accepted_frame_count, descriptor.expected.accepted_frame_count);
    assert.equal(report.archive.event_count, descriptor.expected.event_count);
    assert.equal(report.archive.journal_record_count, descriptor.expected.journal_record_count);
  }

  for (const probe of fixture.edge_probes) {
    const report = JSON.parse(reports.get(`${probe.case_id}.replay-report.json`));
    assert.equal(report.verdict, probe.expected.verdict);
    assert.equal(report.rejection?.rejection_class ?? null, probe.expected.rejection_class);
  }
  const consent = JSON.parse(reports.get("sec-consent.denied.replay-report.json"));
  assert.equal(consent.verdict, "reject");
  assert.equal(consent.rejection.rejection_class, "semantic_invariant");
});

test("sequential and concurrent isolated Bun runs are byte-identical", async () => {
  const temporary = await temporaryDirectory();
  const roots = ["first", "second", "concurrent-a", "concurrent-b"].map((name) =>
    path.join(temporary, name),
  );
  for (const outputRoot of roots.slice(0, 2)) {
    await runReplay({
      manifestPath: MANIFEST,
      outputRoot,
      repoRoot: REPO_ROOT,
      implementationRevision: REVISION,
    });
  }
  await Promise.all(
    roots.slice(2).map((outputRoot) =>
      runReplay({
        manifestPath: MANIFEST,
        outputRoot,
        repoRoot: REPO_ROOT,
        implementationRevision: REVISION,
      }),
    ),
  );

  const baseline = await reportsAt(roots[0]);
  for (const root of roots.slice(1)) {
    const candidate = await reportsAt(root);
    assert.deepEqual([...candidate.keys()], [...baseline.keys()]);
    for (const [name, bytes] of baseline)
      assert.deepEqual(candidate.get(name), bytes, `${name} drifted`);
  }
});

test("wrong runtime and pre-existing output fail before publication", async () => {
  const temporary = await temporaryDirectory();
  const wrongRuntimeOutput = path.join(temporary, "wrong-runtime");
  await assert.rejects(
    runReplay({
      manifestPath: MANIFEST,
      outputRoot: wrongRuntimeOutput,
      repoRoot: REPO_ROOT,
      implementationRevision: REVISION,
      runtimeVersion: "1.3.10",
    }),
    /Bun 1\.3\.11 is required/,
  );
  await assert.rejects(stat(wrongRuntimeOutput), { code: "ENOENT" });

  const preexisting = path.join(temporary, "preexisting");
  await mkdir(preexisting);
  await assert.rejects(
    runReplay({
      manifestPath: MANIFEST,
      outputRoot: preexisting,
      repoRoot: REPO_ROOT,
      implementationRevision: REVISION,
    }),
    /must not exist/,
  );
});

test("one-byte archive corruption fails closed without an output root", async () => {
  const temporary = await temporaryDirectory();
  const fixtureRoot = path.join(temporary, "rev-001");
  await cp(path.dirname(MANIFEST), fixtureRoot, { recursive: true });
  const corrupt = path.join(
    fixtureRoot,
    "archives/finalized-one-frame.rrcap/events/event_0000.json",
  );
  const original = await readFile(corrupt);
  const mutated = Buffer.from(original);
  mutated[0] ^= 1;
  await writeFile(corrupt, mutated);
  const output = path.join(temporary, "corrupt-output");

  await assert.rejects(
    runReplay({
      manifestPath: path.join(fixtureRoot, "manifest.json"),
      outputRoot: output,
      repoRoot: REPO_ROOT,
      implementationRevision: REVISION,
    }),
    /digest|fixture|inventory/,
  );
  await assert.rejects(stat(output), { code: "ENOENT" });
});
