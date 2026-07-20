import { test } from "bun:test";
import assert from "node:assert/strict";
import { cp, mkdtemp, readFile, stat, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { canonicalizeBytes } from "../src/canonical-json.mjs";
import {
  EXACT_BUN_VERSION,
  produceTransactionTrace,
  runTransactionTrace,
} from "../src/transaction.ts";

const ROOT = path.resolve(import.meta.dirname, "../../..");
const MANIFEST = path.join(ROOT, "fixtures/transactions/1.0.0/rev-001/manifest.json");
const REVISION = "git:0123456789abcdef0123456789abcdef01234567";
const FIXTURE_SHA256 = "4aceda98f3dcb6bc0cf3efaef63852b67a86ea22b0455eb07d3fb9cdd34b371a";
const OPERATIONS = ["place", "replace", "remove", "restore"];

const temporaryDirectory = () => mkdtemp(path.join(os.tmpdir(), "reroom-node-transaction-"));

function assertComplete(result, bytes) {
  assert.deepEqual(bytes, canonicalizeBytes(result));
  assert.equal(result.trace_format, "reroom_transaction_trace_v1");
  assert.deepEqual(result.fixture, {
    fixture_id: "FX-TRANSACTION-001",
    fixture_revision: "rev-001",
    manifest_sha256: FIXTURE_SHA256,
  });
  assert.deepEqual(result.runtime, {
    language: "typescript",
    name: "ReRoomTransactionBun",
    version: "bun-v1.3.11",
  });
  assert.equal(result.implementation.repository_revision, REVISION);
  assert.match(result.implementation.source_tree_sha256, /^[0-9a-f]{64}$/);
  assert.deepEqual(result.implementation.source_files, [
    "packages/contracts/src/canonical-json.mjs",
    "packages/contracts/src/transaction.ts",
  ]);
  assert.deepEqual(result.operation_order, OPERATIONS);
  assert.deepEqual(
    result.proposals.map(({ operation }) => operation),
    OPERATIONS,
  );
  for (const proposal of result.proposals) {
    assert.equal(proposal.status, "accepted");
    assert.equal(proposal.authority, "proposal_only");
    assert.equal(proposal.preauthorized_confirmation, false);
    assert.equal(proposal.preauthorized_commit, false);
  }
  assert.equal(result.proposals[1].blocker.code, "capability_not_ready");
  assert.equal(result.proposals[1].blocker.mutation_count, 0);
  assert.equal(result.proposals[2].blocker.code, "capability_not_ready");
  assert.equal(result.proposals[2].blocker.mutation_count, 0);
  assert.equal(result.proposals[3].blocker, null);
  assert.deepEqual(result.proposals[3].proposed_operation_kinds, ["restore_snapshot"]);
  assert.equal(result.safety.injection_case_id, "intent.transform-injection");
  assert.equal(result.safety.injection_verdict, "reject");
  assert.equal(result.safety.injection_mutation_count, 0);
  assert.equal(result.revisions.preview_scene_revision, 0);
  assert.equal(result.revisions.place_scene_revision, 1);
  assert.equal(result.revisions.restore_scene_revision, 2);
  assert.equal(result.retry.same_key_same_fingerprint, "prior_result");
  assert.equal(result.retry.same_key_changed_fingerprint, "idempotency_conflict");
  assert.equal(result.restore.network_reads, 0);
  assert.equal(result.restore.source_transaction_immutable, true);
  assert.equal(result.divergence.automatic_merge_permitted, false);
  assert.equal(result.divergence.mutation_frozen, true);
  assert.equal(result.cases.length, 24);
  assert.deepEqual(
    result.cases.map(({ case_id }) => case_id),
    [...result.cases.map(({ case_id }) => case_id)].sort(),
  );
  assert.equal(result.traces.length, 3);
  assert.match(result.fingerprints.place_request_sha256, /^[0-9a-f]{64}$/);
  assert.match(result.fingerprints.restore_request_sha256, /^[0-9a-f]{64}$/);
  assert.notEqual(result.projections.base_sha256, result.projections.placed_sha256);
  assert.equal(result.projections.base_sha256, result.projections.restored_sha256);
}

test("exact Bun independently emits the complete provenance-bound transaction corpus", async () => {
  assert.equal(process.versions.bun, EXACT_BUN_VERSION);
  const bytes = await produceTransactionTrace({
    manifestPath: MANIFEST,
    repoRoot: ROOT,
    implementationRevision: REVISION,
  });
  assertComplete(JSON.parse(bytes), bytes);
});

test("two isolated Bun publications are byte-identical", async () => {
  const temporary = await temporaryDirectory();
  const first = path.join(temporary, "first.json");
  const second = path.join(temporary, "second.json");
  await runTransactionTrace({
    manifestPath: MANIFEST,
    outputPath: first,
    repoRoot: ROOT,
    implementationRevision: REVISION,
  });
  await runTransactionTrace({
    manifestPath: MANIFEST,
    outputPath: second,
    repoRoot: ROOT,
    implementationRevision: REVISION,
  });
  assert.deepEqual(await readFile(first), await readFile(second));
});

test("runtime revision fixture and oracle drift reject before publication", async () => {
  await assert.rejects(
    produceTransactionTrace({
      manifestPath: MANIFEST,
      repoRoot: ROOT,
      implementationRevision: REVISION,
      runtimeVersion: "1.3.10",
    }),
    /Bun 1\.3\.11 is required/,
  );
  await assert.rejects(
    produceTransactionTrace({
      manifestPath: MANIFEST,
      repoRoot: ROOT,
      implementationRevision: "git:HEAD",
    }),
    /git:<40-lowercase-hex>/,
  );

  const temporary = await temporaryDirectory();
  const fixture = path.join(temporary, "rev-001");
  await cp(path.dirname(MANIFEST), fixture, { recursive: true });
  const expectedPath = path.join(fixture, "expected-traces.json");
  const expected = JSON.parse(await readFile(expectedPath, "utf8"));
  expected.traces[0].events[0].scene_revision = 99;
  await writeFile(expectedPath, `${JSON.stringify(expected, null, 2)}\n`);
  const output = path.join(temporary, "rejected.json");
  await assert.rejects(
    runTransactionTrace({
      manifestPath: path.join(fixture, "manifest.json"),
      outputPath: output,
      repoRoot: ROOT,
      implementationRevision: REVISION,
    }),
    /fixture|digest|oracle/,
  );
  await assert.rejects(stat(output), { code: "ENOENT" });
});

test("producer source is closed and never imports another runtime output", async () => {
  const source = await readFile(path.join(ROOT, "packages/contracts/src/transaction.ts"), "utf8");
  assert.doesNotMatch(
    source,
    /ReRoomTransactionTraceExporter|tools\/python|child_process|expected.*=.*actual/i,
  );
});
