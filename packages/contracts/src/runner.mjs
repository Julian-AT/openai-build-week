#!/usr/bin/env node

import { execFile } from "node:child_process";
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import Ajv2020 from "ajv/dist/2020.js";
import { canonicalDigest, canonicalizeBytes, executeJcsCase } from "./canonical-json.mjs";
import { executeCoordinateCase } from "./coordinate.mjs";
import { loadFixture, RunnerFailure, readJsonStrict } from "./loader.mjs";
import { executeContractCase } from "./schema-validator.mjs";
import { executeWireCase } from "./wire-frame.mjs";

const executeFile = promisify(execFile);
const IMPLEMENTATION_REVISION = /^git:[0-9a-f]{40}$/;

async function resolveRevision(repoRoot, explicit) {
  if (explicit !== undefined) {
    if (!IMPLEMENTATION_REVISION.test(explicit))
      throw new RunnerFailure(
        "schema_validation",
        "implementation revision must be git:<40 lowercase hex>",
      );
    return explicit;
  }
  try {
    const { stdout } = await executeFile("git", ["rev-parse", "HEAD"], {
      cwd: repoRoot,
      encoding: "utf8",
      maxBuffer: 1_024,
    });
    const revision = `git:${stdout.trim()}`;
    if (!IMPLEMENTATION_REVISION.test(revision)) throw new Error("unexpected revision shape");
    return revision;
  } catch (error) {
    throw new RunnerFailure("schema_validation", "a valid implementation revision is required", {
      cause: error,
    });
  }
}

async function dispatch(fixture, fixtureCase) {
  if (fixture.manifest.fixture_id === "FX-CONTRACT-001")
    return executeContractCase(fixture, fixtureCase);
  if (fixture.manifest.fixture_id === "FX-JCS-001") return executeJcsCase(fixture, fixtureCase);
  if (fixture.manifest.fixture_id === "FX-COORD-001") {
    return fixtureCase.case_id.startsWith("wire.")
      ? executeWireCase(fixture, fixtureCase)
      : executeCoordinateCase(fixture, fixtureCase);
  }
  throw new RunnerFailure("schema_validation", "unknown fixture family");
}

export async function validateRunnerResult(result, fixture) {
  const schema = await readJsonStrict(
    path.join(fixture.repoRoot, "fixtures/runner-result.schema.json"),
  );
  const validate = new Ajv2020({
    allErrors: true,
    strictSchema: true,
    strictTypes: false,
    strictTuples: false,
  }).compile(schema);
  if (!validate(result))
    throw new RunnerFailure("schema_validation", "result does not satisfy RunnerResultV1");
  const expectedIds = fixture.manifest.cases.map(({ case_id: caseId }) => caseId);
  const actualIds = result.case_results.map(({ case_id: caseId }) => caseId);
  if (
    actualIds.length !== expectedIds.length ||
    actualIds.some((caseId, index) => caseId !== expectedIds[index])
  ) {
    throw new RunnerFailure("semantic_invariant", "result cases are incomplete or out of order");
  }
  const accepted = result.case_results.filter(({ verdict }) => verdict === "accept").length;
  const expectedSummary = {
    total: actualIds.length,
    accepted,
    rejected: actualIds.length - accepted,
  };
  if (JSON.stringify(result.summary) !== JSON.stringify(expectedSummary))
    throw new RunnerFailure("semantic_invariant", "result summary does not agree with cases");
  if (
    result.fixture.fixture_id !== fixture.manifest.fixture_id ||
    result.fixture.fixture_revision !== fixture.manifest.fixture_revision ||
    result.fixture.manifest_sha256 !== fixture.manifestSha256
  ) {
    throw new RunnerFailure(
      "digest_mismatch",
      "result fixture identity does not match the loaded oracle",
    );
  }
  const { result_digest_sha256: digest, ...unsigned } = result;
  if (digest !== canonicalDigest(unsigned))
    throw new RunnerFailure("digest_mismatch", "result digest does not match its exact scope");
}

export async function runFixture(manifestPath, { repoRoot, implementationRevision } = {}) {
  const fixture = await loadFixture(manifestPath, { repoRoot });
  const revision = await resolveRevision(fixture.repoRoot, implementationRevision);
  const caseResults = [];
  for (const fixtureCase of fixture.manifest.cases)
    caseResults.push(await dispatch(fixture, fixtureCase));
  const accepted = caseResults.filter(({ verdict }) => verdict === "accept").length;
  const unsigned = {
    schema_version: "1.0.0",
    runner: {
      runtime: "javascript",
      name: "reroom-javascript-reference",
      version: "1.0.0",
      implementation_revision: revision,
    },
    fixture: {
      fixture_id: fixture.manifest.fixture_id,
      fixture_revision: fixture.manifest.fixture_revision,
      manifest_sha256: fixture.manifestSha256,
    },
    case_order: "lexicographic_case_id",
    case_results: caseResults,
    summary: { total: caseResults.length, accepted, rejected: caseResults.length - accepted },
    oracle_unchanged: true,
    result_digest_algorithm: "RR-JCS-SHA256-1",
    result_digest_scope: "entire_runner_result_with_result_digest_sha256_omitted",
  };
  const result = { ...unsigned, result_digest_sha256: canonicalDigest(unsigned) };
  await validateRunnerResult(result, fixture);
  return result;
}

function parseArguments(argumentsList) {
  const options = {};
  for (let index = 0; index < argumentsList.length; index += 1) {
    const argument = argumentsList[index];
    if (
      argument === "--manifest" ||
      argument === "--output" ||
      argument === "--repo-root" ||
      argument === "--implementation-revision"
    ) {
      if (index + 1 >= argumentsList.length)
        throw new RunnerFailure("schema_validation", `missing value for ${argument}`);
      options[argument.slice(2).replaceAll("-", "_")] = argumentsList[++index];
    } else if (!argument.startsWith("-") && options.manifest === undefined) {
      options.manifest = argument;
    } else {
      throw new RunnerFailure("schema_validation", "unsupported runner argument");
    }
  }
  if (!options.manifest)
    throw new RunnerFailure(
      "schema_validation",
      "usage: runner.mjs --manifest <path> [--output <path>] [--implementation-revision git:<sha>]",
    );
  return options;
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const result = await runFixture(options.manifest, {
    repoRoot: options.repo_root,
    implementationRevision: options.implementation_revision,
  });
  const bytes = Buffer.concat([canonicalizeBytes(result), Buffer.from("\n")]);
  if (options.output) await writeFile(options.output, bytes, { flag: "wx" });
  else process.stdout.write(bytes);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    const message = error instanceof RunnerFailure ? error.message : "unexpected runner failure";
    process.stderr.write(`runner: FAIL: ${message}\n`);
    process.exitCode = 1;
  });
}
