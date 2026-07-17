import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { cp, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { runFixture } from "../src/runner.mjs";
import { executeCoordinateOperation } from "../src/coordinate.mjs";


const REPO_ROOT = fileURLToPath(new URL("../../..", import.meta.url));
const REVISION = `git:${"0".repeat(40)}`;
const MANIFESTS = {
  contract: "fixtures/contracts/1.0.0/rev-001/manifest.json",
  jcs: "fixtures/policies/RR-JCS-SHA256-1/rev-001/manifest.json",
  coord: "fixtures/policies/RR-COORD-1/rev-001/manifest.json",
};

test("frozen RR-COORD runtime boundaries match JavaScript", async () => {
  const fixture = await readJson(path.join(
    REPO_ROOT,
    "tools/verify/fixtures/rr-coord-runtime-boundaries.json",
  ));
  for (const fixtureCase of fixture.cases) {
    if (fixtureCase.expected === "accept") {
      assert.doesNotThrow(() => executeCoordinateOperation(fixtureCase.input), fixtureCase.case_id);
    } else {
      assert.throws(() => executeCoordinateOperation(fixtureCase.input), fixtureCase.case_id);
    }
  }
});


async function copiedRepository(operation) {
  const temporary = await mkdtemp(path.join(tmpdir(), "reroom-js-mutations-"));
  const root = path.join(temporary, "repo");
  await mkdir(root);
  await cp(path.join(REPO_ROOT, "fixtures"), path.join(root, "fixtures"), { recursive: true });
  await mkdir(path.join(root, "docs"));
  await cp(path.join(REPO_ROOT, "docs/contracts"), path.join(root, "docs/contracts"), { recursive: true });
  try {
    return await operation(root);
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}


function digest(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}


async function readJson(filePath) {
  return JSON.parse(await readFile(filePath, "utf8"));
}


async function writeManifest(manifestPath, manifest) {
  await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}


async function pointAcceptedCaseAtRejectedCase(root, family, targetId, sourceId) {
  const manifestPath = path.join(root, MANIFESTS[family]);
  const manifest = await readJson(manifestPath);
  const target = manifest.cases.find(({ case_id: caseId }) => caseId === targetId);
  const source = manifest.cases.find(({ case_id: caseId }) => caseId === sourceId);
  assert.ok(target && source, `mutation case mapping is absent: ${targetId}/${sourceId}`);
  target.case_kind = source.case_kind;
  target.input = structuredClone(source.input);
  await writeManifest(manifestPath, manifest);
  return { manifestPath, targetId };
}


async function mutateAcceptedCoordinate(root, targetId, mutate) {
  const manifestPath = path.join(root, MANIFESTS.coord);
  const manifest = await readJson(manifestPath);
  const target = manifest.cases.find(({ case_id: caseId }) => caseId === targetId);
  assert.ok(target, `coordinate mutation target is absent: ${targetId}`);
  const inputPath = path.join(path.dirname(manifestPath), target.input.relative_path);
  const input = await readJson(inputPath);
  mutate(input);
  const bytes = Buffer.from(`${JSON.stringify(input)}\n`);
  await writeFile(inputPath, bytes);
  target.input.byte_length = bytes.length;
  target.input.sha256 = digest(bytes);
  await writeManifest(manifestPath, manifest);
  return { manifestPath, targetId };
}


async function assertMutationRejected(config) {
  await copiedRepository(async (root) => {
    const prepared = config.mutate
      ? await mutateAcceptedCoordinate(root, config.target, config.mutate)
      : await pointAcceptedCaseAtRejectedCase(
          root,
          config.family,
          config.target,
          config.source,
        );
    const result = await runFixture(prepared.manifestPath, {
      repoRoot: root,
      implementationRevision: REVISION,
    });
    const row = result.case_results.find(({ case_id: caseId }) => caseId === prepared.targetId);
    assert.deepEqual(
      { verdict: row?.verdict, rejection_class: row?.rejection_class },
      { verdict: "reject", rejection_class: config.rejection },
      config.name,
    );
  });
}


async function treeHashes(root) {
  const hashes = {};
  async function visit(directory) {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      const absolute = path.join(directory, entry.name);
      if (entry.isDirectory()) await visit(absolute);
      else if (entry.isFile()) hashes[path.relative(root, absolute)] = digest(await readFile(absolute));
    }
  }
  await visit(root);
  return hashes;
}


test("JavaScript runtime kills contract, JCS, RRFP, path, and coordinate mutations", async () => {
  const before = await treeHashes(path.join(REPO_ROOT, "fixtures"));
  const mutations = [
    {
      name: "closed contract schema",
      family: "contract",
      target: "contract.con001.valid",
      source: "contract.extra-property",
      rejection: "unknown_property",
    },
    {
      name: "unsafe archive path",
      family: "contract",
      target: "contract.con002.valid",
      source: "contract.con002.unsafe-path",
      rejection: "invalid_path",
    },
    {
      name: "payload digest",
      family: "contract",
      target: "contract.con001.valid",
      source: "contract.hash-mismatch",
      rejection: "digest_mismatch",
    },
    {
      name: "JCS duplicate-name bytes",
      family: "jcs",
      target: "jcs.basic-object",
      source: "jcs.duplicate-name",
      rejection: "duplicate_name",
    },
    ...[
      ["RRFP magic", "wire.bad-magic", "wire_magic"],
      ["RRFP version", "wire.bad-version", "wire_version"],
      ["RRFP flags", "wire.nonzero-flags", "wire_flags"],
      ["RRFP length", "wire.header-length-mismatch", "wire_length"],
      ["RRFP sequence", "wire.sequence-mismatch", "wire_sequence"],
      ["RRFP payload SHA", "wire.payload-tamper", "digest_mismatch"],
      ["RRFP truncation", "wire.truncated", "wire_truncated"],
      ["RRFP trailing bytes", "wire.trailing-byte", "wire_trailing_bytes"],
    ].map(([name, source, rejection]) => ({
      name,
      family: "coord",
      target: "wire.valid",
      source,
      rejection,
    })),
    {
      name: "coordinate reflected correction matrix",
      target: "coord.correction-forward",
      rejection: "coordinate_invalid",
      mutate: (input) => {
        input.to_from_from_transform[0] = -1;
      },
    },
    {
      name: "coordinate orientation",
      target: "coord.crop-scale-rotate",
      rejection: "coordinate_invalid",
      mutate: (input) => {
        input.orientation = "sideways";
      },
    },
    {
      name: "coordinate correction direction",
      target: "coord.correction-forward",
      rejection: "coordinate_invalid",
      mutate: (input) => {
        input.to_world_frame_version = input.from_world_frame_version;
      },
    },
  ];

  for (const mutation of mutations) {
    await assertMutationRejected(mutation);
  }

  await copiedRepository(async (root) => {
    const manifestPath = path.join(root, MANIFESTS.jcs);
    const manifest = await readJson(manifestPath);
    const inputPath = path.join(path.dirname(manifestPath), manifest.cases[0].input.relative_path);
    await writeFile(inputPath, Buffer.concat([await readFile(inputPath), Buffer.from("x")]));
    await assert.rejects(
      runFixture(manifestPath, { repoRoot: root, implementationRevision: REVISION }),
      (error) => error?.rejectionClass === "digest_mismatch",
      "fixture hash mutation must fail before execution",
    );
  });

  assert.deepEqual(
    await treeHashes(path.join(REPO_ROOT, "fixtures")),
    before,
    "JavaScript mutation tests changed the immutable repository fixture corpus",
  );
});
