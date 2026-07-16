import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { loadFixture } from "../src/loader.mjs";
import { executeContractCase } from "../src/schema-validator.mjs";
import { executeJcsCase } from "../src/canonical-json.mjs";
import { canonicalDigest } from "../src/canonical-json.mjs";
import { executeCoordinateCase } from "../src/coordinate.mjs";
import { runFixture, validateRunnerResult } from "../src/runner.mjs";
import { executeWireCase } from "../src/wire-frame.mjs";

const REPO_ROOT = fileURLToPath(new URL("../../..", import.meta.url));
const CONTRACT_MANIFEST = `${REPO_ROOT}/fixtures/contracts/1.0.0/rev-001/manifest.json`;
const JCS_MANIFEST = `${REPO_ROOT}/fixtures/policies/RR-JCS-SHA256-1/rev-001/manifest.json`;
const COORD_MANIFEST = `${REPO_ROOT}/fixtures/policies/RR-COORD-1/rev-001/manifest.json`;

function expectedArtifacts(fixtureCase) {
  return fixtureCase.expected.artifacts.map((artifact) => {
    const result = {
      kind: artifact.kind,
      byte_length: artifact.byte_length,
      sha256: artifact.sha256,
    };
    if (artifact.value_sha256 !== undefined) {
      result.value_sha256 = artifact.value_sha256;
    }
    return result;
  });
}

function assertMatchesOracle(fixtureCase, actual) {
  assert.deepEqual(actual, {
    case_id: fixtureCase.case_id,
    verdict: fixtureCase.expected.verdict,
    rejection_class: fixtureCase.expected.rejection_class,
    output_artifacts: expectedArtifacts(fixtureCase),
  });
}

test("contract, JCS, wire, and path policies match the immutable oracle", async () => {
  const manifests = [CONTRACT_MANIFEST, JCS_MANIFEST, COORD_MANIFEST];
  const before = await Promise.all(manifests.map((path) => readFile(path)));

  const contractFixture = await loadFixture(CONTRACT_MANIFEST, { repoRoot: REPO_ROOT });
  for (const fixtureCase of contractFixture.manifest.cases) {
    assertMatchesOracle(fixtureCase, await executeContractCase(contractFixture, fixtureCase));
  }

  const jcsFixture = await loadFixture(JCS_MANIFEST, { repoRoot: REPO_ROOT });
  for (const fixtureCase of jcsFixture.manifest.cases) {
    assertMatchesOracle(fixtureCase, await executeJcsCase(jcsFixture, fixtureCase));
  }

  const coordinateFixture = await loadFixture(COORD_MANIFEST, { repoRoot: REPO_ROOT });
  for (const fixtureCase of coordinateFixture.manifest.cases.filter(({ case_id }) => case_id.startsWith("wire."))) {
    assertMatchesOracle(fixtureCase, await executeWireCase(coordinateFixture, fixtureCase));
  }

  const after = await Promise.all(manifests.map((path) => readFile(path)));
  assert.deepEqual(after, before, "the runner must never rewrite checked-in oracle data");
});

test("RR-COORD-1 operations match every immutable coordinate vector", async () => {
  const fixture = await loadFixture(COORD_MANIFEST, { repoRoot: REPO_ROOT });
  for (const fixtureCase of fixture.manifest.cases.filter(({ case_id }) => case_id.startsWith("coord."))) {
    assertMatchesOracle(fixtureCase, await executeCoordinateCase(fixture, fixtureCase));
  }
});

test("runner emits complete, ordered, closed RunnerResultV1 envelopes", async () => {
  const implementationRevision = `git:${"0".repeat(40)}`;
  for (const manifestPath of [CONTRACT_MANIFEST, JCS_MANIFEST, COORD_MANIFEST]) {
    const result = await runFixture(manifestPath, {
      repoRoot: REPO_ROOT,
      implementationRevision,
    });
    const expectedFixture = await loadFixture(manifestPath, { repoRoot: REPO_ROOT });
    assert.deepEqual(
      result.case_results.map(({ case_id }) => case_id),
      expectedFixture.manifest.cases.map(({ case_id }) => case_id),
    );
    assert.deepEqual(result.summary, {
      total: result.case_results.length,
      accepted: result.case_results.filter(({ verdict }) => verdict === "accept").length,
      rejected: result.case_results.filter(({ verdict }) => verdict === "reject").length,
    });
    const { result_digest_sha256: digest, ...unsigned } = result;
    assert.equal(digest, canonicalDigest(unsigned));
    assert.doesNotThrow(() => validateRunnerResult(result, expectedFixture));
  }
});
