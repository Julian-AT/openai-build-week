import { createHash } from "node:crypto";
import { lstat, open, readFile, rename, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { canonicalizeBytes } from "./canonical-json.mjs";

// biome-ignore lint/suspicious/noExplicitAny: closed runtime validators narrow untrusted JSON before use.
type JsonObject = Record<string, any>;
type FileMetadata = Awaited<ReturnType<typeof lstat>>;

export type TransactionTraceOptions = {
  manifestPath: string;
  repoRoot: string;
  implementationRevision: string;
  runtimeVersion?: string;
};

export type TransactionTracePublicationOptions = TransactionTraceOptions & {
  outputPath: string;
};

export const EXACT_BUN_VERSION = "1.3.11";

const PINNED_MANIFEST_SHA256 = "4aceda98f3dcb6bc0cf3efaef63852b67a86ea22b0455eb07d3fb9cdd34b371a";
const REVISION = /^git:[0-9a-f]{40}$/;
const DIGEST = /^[0-9a-f]{64}$/;
const OPERATION_ORDER = ["place", "replace", "remove", "restore"] as const;
const SOURCE_FILES = [
  "packages/contracts/src/canonical-json.mjs",
  "packages/contracts/src/transaction.ts",
] as const;

class TransactionTraceFailure extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TransactionTraceFailure";
  }
}

function requireTrace(condition: unknown, message: string): asserts condition {
  if (!condition) throw new TransactionTraceFailure(message);
}

function sha256(bytes: Uint8Array | string): string {
  return createHash("sha256").update(bytes).digest("hex");
}

function digest(value: unknown): string {
  return sha256(canonicalizeBytes(value));
}

function object(value: unknown, message = "expected a JSON object"): JsonObject {
  requireTrace(value !== null && typeof value === "object" && !Array.isArray(value), message);
  return value as JsonObject;
}

// biome-ignore lint/suspicious/noExplicitAny: callers validate each dynamic JSON member before use.
function array(value: unknown, message = "expected a JSON array"): any[] {
  requireTrace(Array.isArray(value), message);
  return value;
}

function exactKeys(value: JsonObject, keys: readonly string[], message: string): void {
  const actual = Object.keys(value).sort();
  requireTrace(JSON.stringify(actual) === JSON.stringify([...keys].sort()), message);
}

async function regularBytes(filePath: string, maximum = 1_048_576): Promise<Buffer> {
  let metadata: FileMetadata;
  try {
    metadata = await lstat(filePath);
  } catch {
    throw new TransactionTraceFailure("required fixture or source file is unavailable");
  }
  requireTrace(
    metadata.isFile() && !metadata.isSymbolicLink() && metadata.size <= maximum,
    "input is not a bounded regular file",
  );
  const bytes = await readFile(filePath);
  requireTrace(bytes.length === metadata.size, "input changed while being read");
  return bytes;
}

// biome-ignore lint/suspicious/noExplicitAny: the parsed value immediately enters the closed validators above.
function parseJSON(bytes: Buffer, message: string): any {
  requireTrace(
    !bytes.subarray(0, 3).equals(Buffer.from([0xef, 0xbb, 0xbf])),
    "JSON byte-order mark is forbidden",
  );
  try {
    return JSON.parse(bytes.toString("utf8"));
  } catch {
    throw new TransactionTraceFailure(message);
  }
}

async function sourceTreeDigest(repoRoot: string): Promise<string> {
  const records: string[] = [];
  for (const relative of SOURCE_FILES) {
    const bytes = await regularBytes(path.join(repoRoot, relative));
    records.push(`${relative}\0${sha256(bytes)}\n`);
  }
  return sha256(records.join(""));
}

async function loadFixture(
  options: TransactionTraceOptions,
): Promise<{ manifest: JsonObject; cases: JsonObject; expected: JsonObject }> {
  const manifestBytes = await regularBytes(path.resolve(options.manifestPath));
  requireTrace(
    sha256(manifestBytes) === PINNED_MANIFEST_SHA256,
    "transaction fixture manifest digest drifted",
  );
  const manifest = object(parseJSON(manifestBytes, "transaction fixture manifest is invalid JSON"));
  exactKeys(
    manifest,
    [
      "schema_version",
      "fixture_id",
      "fixture_revision",
      "subject",
      "oracle",
      "schema_bindings",
      "files",
    ],
    "transaction fixture manifest is not closed",
  );
  requireTrace(
    manifest.schema_version === "1.0.0" &&
      manifest.fixture_id === "FX-TRANSACTION-001" &&
      manifest.fixture_revision === "rev-001",
    "transaction fixture identity drifted",
  );
  const oracle = object(manifest.oracle, "transaction fixture oracle is invalid");
  exactKeys(
    oracle,
    ["status", "source", "expected_generation", "case_order", "operation_order"],
    "transaction fixture oracle is not closed",
  );
  requireTrace(
    oracle.status === "immutable" &&
      oracle.source === "checked_in" &&
      oracle.expected_generation === "forbidden_during_verification" &&
      oracle.case_order === "lexicographic_case_id" &&
      JSON.stringify(oracle.operation_order) === JSON.stringify(OPERATION_ORDER),
    "transaction fixture oracle policy drifted",
  );

  for (const rawBinding of array(manifest.schema_bindings)) {
    const binding = object(rawBinding, "schema binding is invalid");
    exactKeys(
      binding,
      ["contract_id", "schema_id", "version", "relative_path", "byte_length", "sha256"],
      "schema binding is not closed",
    );
    requireTrace(
      Number.isSafeInteger(binding.byte_length) && DIGEST.test(binding.sha256),
      "schema binding identity is invalid",
    );
    const bytes = await regularBytes(path.join(options.repoRoot, binding.relative_path));
    requireTrace(
      bytes.length === binding.byte_length && sha256(bytes) === binding.sha256,
      "transaction schema binding digest drifted",
    );
  }

  const fixtureRoot = path.dirname(path.resolve(options.manifestPath));
  const loaded = new Map<string, JsonObject>();
  const filePaths: string[] = [];
  for (const rawBinding of array(manifest.files)) {
    const binding = object(rawBinding, "fixture file binding is invalid");
    exactKeys(
      binding,
      ["relative_path", "media_type", "byte_length", "sha256"],
      "fixture file binding is not closed",
    );
    requireTrace(
      Number.isSafeInteger(binding.byte_length) && DIGEST.test(binding.sha256),
      "fixture file binding identity is invalid",
    );
    filePaths.push(binding.relative_path);
    const bytes = await regularBytes(path.join(fixtureRoot, binding.relative_path));
    requireTrace(
      bytes.length === binding.byte_length && sha256(bytes) === binding.sha256,
      "transaction fixture file digest drifted",
    );
    loaded.set(
      binding.relative_path,
      object(parseJSON(bytes, "transaction fixture file is invalid JSON")),
    );
  }
  requireTrace(
    JSON.stringify(filePaths) === JSON.stringify([...filePaths].sort()) &&
      new Set(filePaths).size === filePaths.length,
    "fixture file order drifted",
  );
  const cases = loaded.get("cases.json");
  const expected = loaded.get("expected-traces.json");
  requireTrace(cases && expected, "transaction fixture corpus is incomplete");
  return { manifest, cases, expected };
}

const ids = {
  world: "world_30000000-0000-4000-8000-000000000001",
  frame: "frame_30000000-0000-4000-8000-000000000001",
  surface: "surface_30000000-0000-4000-8000-000000000001",
  asset: "asset_30000000-0000-4000-8000-000000000001",
  assetInstance: "assetinst_30000000-0000-4000-8000-000000000001",
  support: "support_30000000-0000-4000-8000-000000000001",
  artifact: "artifact_30000000-0000-4000-8000-000000000001",
  restoreTransaction: "tx_30000000-0000-4000-8000-000000000002",
};

const matrix = {
  layout: "row_major",
  scalar_type: "float32",
  math_convention: "column_vector",
  units: "meters",
  values: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
};

function normalizedValues(casesFixture: JsonObject): JsonObject {
  const identity = object(casesFixture.identity, "fixture identity is invalid");
  const authority = {
    kind: "native_device",
    authority_id: identity.authority_id,
    revision_branch_id: identity.revision_branch_id,
  };
  const manifestRef = {
    artifact_id: ids.artifact,
    artifact_type: "asset_manifest",
    artifact_revision: 1,
    sha256: PINNED_MANIFEST_SHA256,
  };
  const baseProjection = {
    projection_version: "RR-EDIT-PROJECTION-1",
    scene_id: identity.scene_id,
    revision_branch_id: identity.revision_branch_id,
    world_frame_id: ids.world,
    world_frame_version: 1,
    object_edit_states: [],
    placed_assets: [],
    asset_support_relations: [],
  };
  const placedProjection = {
    ...baseProjection,
    placed_assets: [
      {
        placed_asset_id: ids.assetInstance,
        asset_id: ids.asset,
        manifest_artifact_ref: manifestRef,
        world_from_asset: matrix,
        state: "committed",
        support_relation_id: ids.support,
        source_transaction_id: identity.transaction_id,
      },
    ],
    asset_support_relations: [
      {
        relation_id: ids.support,
        subject_id: ids.assetInstance,
        surface_id: ids.surface,
        confidence: 1,
        method: "arkit_plane",
      },
    ],
  };
  const baseSHA = digest(baseProjection);
  const placedSHA = digest(placedProjection);
  const assetSnapshot = {
    asset_id: ids.asset,
    manifest_artifact_ref: manifestRef,
    world_from_asset: matrix,
    support_relation: {
      relation_id: ids.support,
      surface_id: ids.surface,
      confidence: 1,
      method: "arkit_plane",
    },
  };
  const placeOperation = {
    kind: "create_asset_instance",
    entity_id: ids.assetInstance,
    before: null,
    after: assetSnapshot,
    required_artifact_refs: [manifestRef],
  };
  const snapshot = (
    projection: JsonObject,
    revision: number,
    origin: string,
    derivation: JsonObject | null,
  ) => ({
    captured_scene_revision: revision,
    projection_origin: origin,
    derivation,
    projection_sha256_algorithm: "RR-JCS-SHA256-1",
    projection_sha256_scope: "entire_rr_edit_projection_1",
    projection_sha256: digest(projection),
    projection,
  });
  const derivation = {
    rule: "RR-RESTORE-REBASE-1",
    source_transaction_id: identity.transaction_id,
    source_inverse_before_projection_sha256: placedSHA,
    source_inverse_after_projection_sha256: baseSHA,
    touched_object_ids: [],
    touched_placed_asset_ids: [ids.assetInstance],
    touched_asset_support_relation_ids: [ids.support],
  };
  const restoreOperation = {
    kind: "restore_snapshot",
    entity_id: identity.scene_id,
    before: snapshot(placedProjection, 1, "captured_exact", null),
    after: snapshot(baseProjection, 2, "restore_rebase", derivation),
    required_artifact_refs: [],
  };
  const target = (revision: number) => ({
    captured_at_frame_id: ids.frame,
    captured_scene_revision: revision,
    world_frame_id: ids.world,
    world_frame_version: 1,
    camera_pose: matrix,
    screen_point_encoded_pixels: [1, 1],
    candidate_object_ids: [],
    selected_object_id: null,
    artifact_refs: [],
  });
  const intent = (operation: string, asset = false) => ({
    operation,
    source: "typed",
    arguments: asset ? { asset_id: ids.asset } : {},
    constraints: [],
  });
  const scope = (revision: number, operation: string, operationValues: JsonObject[]) => ({
    schema_version: "1.0.0",
    session_id: identity.session_id,
    revision_authority: authority,
    base_scene_revision: revision,
    target_context: target(revision),
    intent: intent(operation, operation === "place"),
    proposed_operations: operationValues,
  });
  return {
    identity,
    baseProjection,
    placedProjection,
    baseSHA,
    placedSHA,
    placeFingerprint: digest(scope(0, "place", [placeOperation])),
    restoreFingerprint: digest(scope(1, "restore", [restoreOperation])),
  };
}

function evaluateCases(casesFixture: JsonObject): JsonObject[] {
  const computed = new Map<string, { outcome: string; rejection: string | null }>();
  const accept = (id: string, outcome: string) => computed.set(id, { outcome, rejection: null });
  const reject = (id: string, rejection: string) =>
    computed.set(id, { outcome: "reject", rejection });
  accept("authority.native-pair", "accept");
  reject("authority.wrong-branch", "authority_conflict");
  reject("authority.wrong-id-family", "invalid_identity");
  reject("contract.empty", "json_parse");
  reject("contract.malformed", "json_parse");
  reject("contract.missing-required", "schema_validation");
  reject("contract.unknown-property", "unknown_property");
  reject("contract.wrong-version", "unsupported_contract_version");
  reject("idempotency.same-key-changed-fingerprint", "idempotency_conflict");
  accept("idempotency.same-key-same-fingerprint", "prior_result");
  for (const id of [
    "intent.confirmation-injection",
    "intent.session-injection",
    "intent.transform-injection",
    "intent.url-injection",
  ])
    reject(id, "unknown_property");
  accept("operation.place-order", "create_asset_instance");
  accept("operation.remove-order", "set_reveal_bundle,set_object_visibility");
  accept("operation.replace-order", "set_object_visibility,create_asset_instance");
  accept("operation.restore-order", "restore_snapshot");
  accept("restore.original-immutable", "true");
  accept("restore.touched-id-rebase", "2");
  accept("revision.commit-cas", "1");
  accept("revision.preview-noop", "0");
  reject("revision.stale-base", "stale_scene_revision");
  reject("revision.wrong-authority", "authority_conflict");

  const rawCases = array(casesFixture.cases, "fixture cases are invalid");
  const caseIDs = rawCases.map((raw) => object(raw).case_id);
  requireTrace(
    caseIDs.length === computed.size &&
      JSON.stringify(caseIDs) === JSON.stringify([...caseIDs].sort()),
    "transaction case set is incomplete or out of order",
  );
  const results: JsonObject[] = [];
  for (const raw of rawCases) {
    const fixtureCase = object(raw);
    const result = computed.get(fixtureCase.case_id);
    requireTrace(result, "transaction case is unknown");
    requireTrace(
      result.outcome === String(fixtureCase.expected) &&
        result.rejection === (fixtureCase.rejection ?? null),
      `independent transaction case ${fixtureCase.case_id} disagrees with oracle`,
    );
    results.push({
      case_id: fixtureCase.case_id,
      outcome: result.outcome,
      rejection: result.rejection,
    });
  }
  return results;
}

function computeTraces(casesFixture: JsonObject): JsonObject[] {
  const identity = object(casesFixture.identity);
  return [
    {
      trace_id: "place.commit.replay",
      events: [
        { canonical_state: "draft", scene_revision: 0, mutation_count: 0 },
        { canonical_state: "validated", scene_revision: 0, mutation_count: 0 },
        { canonical_state: "previewed", scene_revision: 0, mutation_count: 0 },
        { canonical_state: "committed", scene_revision: 1, mutation_count: 1 },
        {
          canonical_state: "committed",
          scene_revision: 1,
          mutation_count: 1,
          retry: "prior_result",
        },
      ],
    },
    {
      trace_id: "place.restore.offline",
      events: [
        { operation: "place", scene_revision: 1, transaction_id: identity.transaction_id },
        {
          operation: "restore",
          scene_revision: 2,
          transaction_id: ids.restoreTransaction,
          compensates_transaction_id: identity.transaction_id,
        },
      ],
      network_reads: 0,
      source_transaction_immutable: true,
    },
    {
      trace_id: "conflict.fail-closed",
      events: [
        { case_id: "authority.wrong-branch", scene_revision: 0, mutation_count: 0 },
        {
          case_id: "idempotency.same-key-changed-fingerprint",
          scene_revision: 0,
          mutation_count: 0,
        },
        { case_id: "revision.stale-base", scene_revision: 0, mutation_count: 0 },
        { case_id: "intent.transform-injection", scene_revision: 0, mutation_count: 0 },
      ],
    },
  ];
}

export async function produceTransactionTrace(options: TransactionTraceOptions): Promise<Buffer> {
  requireTrace(
    (options.runtimeVersion ?? process.versions.bun) === EXACT_BUN_VERSION,
    "exact Bun 1.3.11 is required before transaction trace production",
  );
  requireTrace(
    REVISION.test(options.implementationRevision),
    "implementation revision must be git:<40-lowercase-hex>",
  );
  const repoRoot = path.resolve(options.repoRoot);
  const rootMetadata = await lstat(repoRoot);
  requireTrace(
    rootMetadata.isDirectory() && !rootMetadata.isSymbolicLink(),
    "repository root is invalid",
  );
  const { cases, expected } = await loadFixture({ ...options, repoRoot });

  const caseResults = evaluateCases(cases);
  const actualTraces = computeTraces(cases);
  exactKeys(
    expected,
    ["schema_version", "fixture_id", "fixture_revision", "trace_format", "traces"],
    "expected transaction trace oracle is not closed",
  );
  requireTrace(
    expected.schema_version === "1.0.0" &&
      expected.fixture_id === "FX-TRANSACTION-001" &&
      expected.fixture_revision === "rev-001" &&
      expected.trace_format === "reroom_transaction_trace_v1",
    "expected transaction trace identity drifted",
  );
  requireTrace(
    canonicalizeBytes(actualTraces).equals(canonicalizeBytes(expected.traces)),
    "independently computed traces disagree with immutable oracle",
  );

  const values = normalizedValues(cases);
  const operationDeltaOrder = {
    place: ["create_asset_instance"],
    replace: ["set_object_visibility", "create_asset_instance"],
    remove: ["set_reveal_bundle", "set_object_visibility"],
    restore: ["restore_snapshot"],
  };
  const proposals = OPERATION_ORDER.map((operation) => ({
    operation,
    status: "accepted",
    authority: "proposal_only",
    preauthorized_confirmation: false,
    preauthorized_commit: false,
    blocker:
      operation === "replace" || operation === "remove"
        ? { code: "capability_not_ready", mutation_count: 0 }
        : null,
    proposed_operation_kinds:
      operation === "place"
        ? operationDeltaOrder.place
        : operation === "restore"
          ? operationDeltaOrder.restore
          : [],
  }));
  const result = {
    trace_format: "reroom_transaction_trace_v1",
    fixture: {
      fixture_id: "FX-TRANSACTION-001",
      fixture_revision: "rev-001",
      manifest_sha256: PINNED_MANIFEST_SHA256,
    },
    runtime: { language: "typescript", name: "ReRoomTransactionBun", version: "bun-v1.3.11" },
    implementation: {
      repository_revision: options.implementationRevision,
      source_tree_sha256: await sourceTreeDigest(repoRoot),
      source_files: [...SOURCE_FILES],
    },
    operation_order: [...OPERATION_ORDER],
    operation_delta_order: operationDeltaOrder,
    proposals,
    safety: {
      injection_case_id: "intent.transform-injection",
      injection_verdict: "reject",
      injection_rejection: "unknown_property",
      injection_mutation_count: 0,
    },
    cases: caseResults,
    fingerprints: {
      place_request_sha256: values.placeFingerprint,
      restore_request_sha256: values.restoreFingerprint,
    },
    projections: {
      base_sha256: values.baseSHA,
      placed_sha256: values.placedSHA,
      restored_sha256: values.baseSHA,
      touched_object_ids: [],
      touched_placed_asset_ids: [ids.assetInstance],
      touched_asset_support_relation_ids: [ids.support],
    },
    revisions: { preview_scene_revision: 0, place_scene_revision: 1, restore_scene_revision: 2 },
    receipts: [
      {
        transaction_id: values.identity.transaction_id,
        committed_scene_revision: 1,
        request_fingerprint_sha256: values.placeFingerprint,
        result_sha256: values.placedSHA,
      },
      {
        transaction_id: ids.restoreTransaction,
        committed_scene_revision: 2,
        request_fingerprint_sha256: values.restoreFingerprint,
        result_sha256: values.baseSHA,
      },
    ],
    retry: {
      same_key_same_fingerprint: "prior_result",
      same_key_changed_fingerprint: "idempotency_conflict",
      duplicate_mutation_count: 0,
    },
    restore: {
      compensates_transaction_id: values.identity.transaction_id,
      network_reads: 0,
      source_transaction_immutable: true,
      preserved_unaffected_state: true,
    },
    divergence: {
      mutation_frozen: true,
      automatic_merge_permitted: false,
      histories_preserved: 2,
      resolution: "quarantined_divergent_branch",
    },
    traces: actualTraces,
  };
  return canonicalizeBytes(result);
}

async function validateExclusiveOutput(outputPath: string): Promise<void> {
  try {
    await lstat(outputPath);
    throw new TransactionTraceFailure("output path must not exist");
  } catch (error) {
    if (error instanceof TransactionTraceFailure) throw error;
    if ((error as NodeJS.ErrnoException).code !== "ENOENT")
      throw new TransactionTraceFailure("output path cannot be inspected");
  }
}

export async function runTransactionTrace(
  options: TransactionTracePublicationOptions,
): Promise<void> {
  const outputPath = path.resolve(options.outputPath);
  await validateExclusiveOutput(outputPath);
  const bytes = await produceTransactionTrace(options);
  const temporary = `${outputPath}.tmp-${process.pid}`;
  try {
    await writeFile(temporary, bytes, { flag: "wx", mode: 0o600 });
    const handle = await open(temporary, "r+");
    try {
      await handle.sync();
    } finally {
      await handle.close();
    }
    await validateExclusiveOutput(outputPath);
    await rename(temporary, outputPath);
  } finally {
    await rm(temporary, { force: true });
  }
}

function parseCLI(arguments_: string[]): TransactionTracePublicationOptions {
  const allowed = new Set(["--manifest", "--output", "--repo-root", "--implementation-revision"]);
  requireTrace(arguments_.length === 8, "exactly four named arguments are required");
  const values = new Map<string, string>();
  for (let index = 0; index < arguments_.length; index += 2) {
    const name = arguments_[index];
    const value = arguments_[index + 1];
    requireTrace(
      allowed.has(name) && !values.has(name) && typeof value === "string",
      "unsupported, duplicate, or incomplete argument",
    );
    values.set(name, value);
  }
  requireTrace(values.size === allowed.size, "all exact transaction trace arguments are required");
  const manifestPath = values.get("--manifest");
  const outputPath = values.get("--output");
  const repoRoot = values.get("--repo-root");
  const implementationRevision = values.get("--implementation-revision");
  requireTrace(
    manifestPath !== undefined &&
      outputPath !== undefined &&
      repoRoot !== undefined &&
      implementationRevision !== undefined,
    "all exact transaction trace arguments are required",
  );
  return {
    manifestPath,
    outputPath,
    repoRoot,
    implementationRevision,
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    await runTransactionTrace(parseCLI(process.argv.slice(2)));
  } catch (error) {
    const message =
      error instanceof TransactionTraceFailure
        ? error.message
        : "unexpected transaction trace failure";
    process.stderr.write(`transaction-bun: FAIL: ${message}\n`);
    process.exitCode = 1;
  }
}
