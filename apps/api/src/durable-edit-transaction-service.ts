import type { Database } from "bun:sqlite";
import { randomUUID } from "node:crypto";
import type { DurableRoomSessionStore } from "./durable-session-store.ts";
import {
  type ConfirmPreviewInput,
  type EditDelta,
  type EditTransactionService,
  IdempotencyConflictError,
  type ReplacementOperation,
  type ReplacementPreview,
  type RestoreInput,
  RevisionConflictError,
  SessionCredentialError,
  TransactionConflictError,
  TransactionNotFoundError,
  type ValidatedReplacement,
} from "./edit-transaction-service.ts";

interface SceneRow {
  session_id: string;
  revision: number;
}

interface ReplacementRow {
  session_id: string;
  proposal_id: string;
  base_revision: number;
  target_id: string;
  asset_id: string;
  instance_id: string;
  reveal_id: string;
  world_json: string;
}

interface PreviewRow {
  session_id: string;
  preview_id: string;
  proposal_id: string;
  base_revision: number;
  ops_json: string;
  inverse_json: string;
  committed: number;
}

interface TransactionRow {
  session_id: string;
  transaction_id: string;
  scene_revision: number;
  base_revision: number;
  idempotency_key: string;
  fingerprint: string;
  delta_json: string;
  compensates_transaction_id: string | null;
}

export interface DurableEditTransactionService extends EditTransactionService {
  stageValidatedReplacement(credential: string, replacement: ValidatedReplacement): Promise<void>;
  stagePlacementPreview(
    credential: string,
    placement: {
      readonly proposalID: string;
      readonly baseSceneRevision: number;
      readonly assetID: string;
      readonly worldFromAsset: readonly number[];
    },
  ): Promise<void>;
  readScene(credential: string): Promise<{
    readonly scene_revision: number;
    readonly transactions: readonly EditDelta[];
  }>;
}

/** SQLite-backed edit authority sharing the durable room database and credential verifier. */
export function createDurableEditTransactionService(
  store: DurableRoomSessionStore,
): DurableEditTransactionService {
  const run = async <T>(
    credential: string,
    operation: (sessionID: string, database: Database) => T | Promise<T>,
  ): Promise<T> => await store.withAuthorizedScene(credential, operation);

  return {
    stageValidatedReplacement: async (credential, replacement) =>
      await run(credential, (sessionID, database) => {
        if (replacement.sessionID !== sessionID) throw new SessionCredentialError();
        validateReplacement(replacement);
        ensureSchema(database);
        transaction(database, () => {
          const revision = ensureScene(database, sessionID);
          if (replacement.baseSceneRevision !== revision) {
            throw new RevisionConflictError(replacement.baseSceneRevision, revision);
          }
          const existing = database
            .query<{ proposal_id: string }, [string, string]>(
              "SELECT proposal_id FROM scene_replacements WHERE session_id = ?1 AND proposal_id = ?2",
            )
            .get(sessionID, replacement.proposalID);
          if (existing !== null) throw new TransactionConflictError();
          database
            .prepare(
              "INSERT INTO scene_replacements (session_id, proposal_id, base_revision, target_id, asset_id, instance_id, reveal_id, world_json) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            )
            .run(
              sessionID,
              replacement.proposalID,
              replacement.baseSceneRevision,
              replacement.targetID,
              replacement.assetID,
              replacement.replacementInstanceID,
              replacement.revealBundleID,
              JSON.stringify(replacement.worldFromAsset),
            );
        });
      }),
    stagePlacementPreview: async (credential, placement) =>
      await run(credential, (sessionID, database) => {
        ensureSchema(database);
        transaction(database, () => {
          const revision = ensureScene(database, sessionID);
          if (placement.baseSceneRevision !== revision) {
            throw new RevisionConflictError(placement.baseSceneRevision, revision);
          }
          if (
            !/^proposal_[0-9a-f-]{36}$/u.test(placement.proposalID) ||
            !isSafeAssetID(placement.assetID) ||
            placement.worldFromAsset.length !== 16 ||
            !placement.worldFromAsset.every(Number.isFinite)
          ) {
            throw new TypeError("invalid placement preview");
          }
          const existing = database
            .query<{ committed: number }, [string, string]>(
              "SELECT committed FROM scene_previews WHERE session_id = ?1 AND proposal_id = ?2",
            )
            .get(sessionID, placement.proposalID);
          if (existing !== null) {
            if (existing.committed !== 0) throw new TransactionConflictError();
            return;
          }
          const previewID = generatedID("preview");
          const instanceID = `instance_${randomUUID()}`;
          const operations: readonly ReplacementOperation[] = [
            {
              op: "place_asset",
              asset_id: placement.assetID,
              instance_id: instanceID,
              world_from_asset: [...placement.worldFromAsset],
            },
          ];
          const inverseOperations: readonly ReplacementOperation[] = [
            { op: "remove_asset_instance", instance_id: instanceID },
          ];
          database
            .prepare(
              "INSERT INTO scene_previews (session_id, preview_id, proposal_id, base_revision, ops_json, inverse_json, committed) VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0)",
            )
            .run(
              sessionID,
              previewID,
              placement.proposalID,
              revision,
              JSON.stringify(operations),
              JSON.stringify(inverseOperations),
            );
        });
      }),
    prepareReplacementPreview: async (credential, proposalID) =>
      await run(credential, (sessionID, database) => {
        ensureSchema(database);
        return transaction(database, () => {
          const revision = ensureScene(database, sessionID);
          const existing = database
            .query<PreviewRow, [string, string]>(
              "SELECT session_id, preview_id, proposal_id, base_revision, ops_json, inverse_json, committed FROM scene_previews WHERE session_id = ?1 AND proposal_id = ?2",
            )
            .get(sessionID, proposalID);
          if (existing !== null) {
            if (existing.committed !== 0) throw new TransactionConflictError();
            return decodePreview(existing);
          }
          const replacement = database
            .query<ReplacementRow, [string, string]>(
              "SELECT session_id, proposal_id, base_revision, target_id, asset_id, instance_id, reveal_id, world_json FROM scene_replacements WHERE session_id = ?1 AND proposal_id = ?2",
            )
            .get(sessionID, proposalID);
          if (replacement === null) throw new TransactionNotFoundError();
          if (replacement.base_revision !== revision) {
            throw new RevisionConflictError(replacement.base_revision, revision);
          }
          const validated = replacementFromRow(replacement);
          const previewID = generatedID("preview");
          const ops = replacementOperations(validated);
          const inverseOps = inverseReplacementOperations(validated);
          const preview: ReplacementPreview = Object.freeze({
            type: "edit_preview",
            preview_id: previewID,
            proposal_id: proposalID,
            base_scene_revision: revision,
            intent: Object.freeze({
              operation: "replace",
              target_id: validated.targetID,
              asset_id: validated.assetID,
            }),
            ops: freezeOperations(ops),
            status: "pending_confirmation",
          });
          database
            .prepare(
              "INSERT INTO scene_previews (session_id, preview_id, proposal_id, base_revision, ops_json, inverse_json, committed) VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0)",
            )
            .run(
              sessionID,
              previewID,
              proposalID,
              revision,
              JSON.stringify(ops),
              JSON.stringify(inverseOps),
            );
          return preview;
        });
      }),
    confirmPreview: async (credential, input) =>
      await run(credential, (_sessionID, database) => {
        ensureSchema(database);
        return transaction(database, () => confirm(database, _sessionID, input));
      }),
    restore: async (credential, input) =>
      await run(credential, (_sessionID, database) => {
        ensureSchema(database);
        return transaction(database, () => restore(database, _sessionID, input));
      }),
    readScene: async (credential) =>
      await run(credential, (sessionID, database) => {
        ensureSchema(database);
        const revision = ensureScene(database, sessionID);
        const rows = database
          .query<TransactionRow, [string]>(
            "SELECT session_id, transaction_id, scene_revision, base_revision, idempotency_key, fingerprint, delta_json, compensates_transaction_id FROM scene_transactions WHERE session_id = ?1 ORDER BY scene_revision",
          )
          .all(sessionID);
        return Object.freeze({
          scene_revision: revision,
          transactions: Object.freeze(rows.map((row) => decodeDelta(row))),
        });
      }),
  };
}

function confirm(database: Database, sessionID: string, input: ConfirmPreviewInput): EditDelta {
  validateCommitInput(
    input.previewID,
    "preview",
    input.expectedSceneRevision,
    input.idempotencyKey,
  );
  const existingByKey = database
    .query<TransactionRow, [string, string]>(
      "SELECT session_id, transaction_id, scene_revision, base_revision, idempotency_key, fingerprint, delta_json, compensates_transaction_id FROM scene_transactions WHERE session_id = ?1 AND idempotency_key = ?2",
    )
    .get(sessionID, input.idempotencyKey);
  if (existingByKey !== null) {
    if (existingByKey.fingerprint !== `confirm:${input.previewID}`)
      throw new IdempotencyConflictError();
    return { ...decodeDelta(existingByKey), replayed: true };
  }
  const preview = database
    .query<PreviewRow, [string, string]>(
      "SELECT session_id, preview_id, proposal_id, base_revision, ops_json, inverse_json, committed FROM scene_previews WHERE session_id = ?1 AND preview_id = ?2",
    )
    .get(sessionID, input.previewID);
  if (preview === null) throw new TransactionNotFoundError();
  if (preview.committed !== 0) throw new TransactionConflictError();
  const revision = ensureScene(database, sessionID);
  if (revision !== preview.base_revision || input.expectedSceneRevision !== revision) {
    throw new RevisionConflictError(input.expectedSceneRevision, revision);
  }
  const delta = createDelta(
    revision,
    input.idempotencyKey,
    parseOperations(preview.ops_json),
    parseOperations(preview.inverse_json),
  );
  insertDelta(database, sessionID, delta, `confirm:${input.previewID}`);
  database
    .prepare("UPDATE scene_previews SET committed = 1 WHERE session_id = ?1 AND preview_id = ?2")
    .run(sessionID, input.previewID);
  setRevision(database, sessionID, delta.scene_revision);
  return delta;
}

function restore(database: Database, sessionID: string, input: RestoreInput): EditDelta {
  validateCommitInput(input.transactionID, "tx", input.expectedSceneRevision, input.idempotencyKey);
  const existingByKey = database
    .query<TransactionRow, [string, string]>(
      "SELECT session_id, transaction_id, scene_revision, base_revision, idempotency_key, fingerprint, delta_json, compensates_transaction_id FROM scene_transactions WHERE session_id = ?1 AND idempotency_key = ?2",
    )
    .get(sessionID, input.idempotencyKey);
  if (existingByKey !== null) {
    if (existingByKey.fingerprint !== `restore:${input.transactionID}`)
      throw new IdempotencyConflictError();
    return { ...decodeDelta(existingByKey), replayed: true };
  }
  const original = database
    .query<TransactionRow, [string, string]>(
      "SELECT session_id, transaction_id, scene_revision, base_revision, idempotency_key, fingerprint, delta_json, compensates_transaction_id FROM scene_transactions WHERE session_id = ?1 AND transaction_id = ?2",
    )
    .get(sessionID, input.transactionID);
  if (original === null) throw new TransactionNotFoundError();
  const compensated = database
    .query<{ transaction_id: string }, [string, string]>(
      "SELECT transaction_id FROM scene_transactions WHERE session_id = ?1 AND compensates_transaction_id = ?2 LIMIT 1",
    )
    .get(sessionID, input.transactionID);
  if (original.compensates_transaction_id !== null || compensated !== null)
    throw new TransactionConflictError();
  const revision = ensureScene(database, sessionID);
  if (input.expectedSceneRevision !== revision) {
    throw new RevisionConflictError(input.expectedSceneRevision, revision);
  }
  const source = decodeDelta(original);
  const delta = createDelta(
    revision,
    input.idempotencyKey,
    source.inverse_ops,
    source.ops,
    source.transaction_id,
  );
  insertDelta(database, sessionID, delta, `restore:${input.transactionID}`);
  setRevision(database, sessionID, delta.scene_revision);
  return delta;
}

function ensureSchema(database: Database): void {
  database.exec(`
    CREATE TABLE IF NOT EXISTS scene_state (session_id TEXT PRIMARY KEY, revision INTEGER NOT NULL) STRICT;
    CREATE TABLE IF NOT EXISTS scene_replacements (
      session_id TEXT NOT NULL, proposal_id TEXT NOT NULL, base_revision INTEGER NOT NULL,
      target_id TEXT NOT NULL, asset_id TEXT NOT NULL, instance_id TEXT NOT NULL,
      reveal_id TEXT NOT NULL, world_json TEXT NOT NULL,
      PRIMARY KEY (session_id, proposal_id)
    ) STRICT;
    CREATE TABLE IF NOT EXISTS scene_previews (
      session_id TEXT NOT NULL, preview_id TEXT NOT NULL, proposal_id TEXT NOT NULL,
      base_revision INTEGER NOT NULL, ops_json TEXT NOT NULL, inverse_json TEXT NOT NULL,
      committed INTEGER NOT NULL, PRIMARY KEY (session_id, preview_id),
      UNIQUE (session_id, proposal_id)
    ) STRICT;
    CREATE TABLE IF NOT EXISTS scene_transactions (
      session_id TEXT NOT NULL, transaction_id TEXT NOT NULL, scene_revision INTEGER NOT NULL,
      base_revision INTEGER NOT NULL, idempotency_key TEXT NOT NULL, fingerprint TEXT NOT NULL,
      delta_json TEXT NOT NULL, compensates_transaction_id TEXT,
      PRIMARY KEY (session_id, transaction_id), UNIQUE (session_id, idempotency_key)
    ) STRICT;
  `);
}

function ensureScene(database: Database, sessionID: string): number {
  database
    .prepare("INSERT OR IGNORE INTO scene_state (session_id, revision) VALUES (?1, 0)")
    .run(sessionID);
  const row = database
    .query<SceneRow, [string]>("SELECT session_id, revision FROM scene_state WHERE session_id = ?1")
    .get(sessionID);
  if (row === null || !Number.isSafeInteger(row.revision) || row.revision < 0)
    throw new Error("invalid_scene_state");
  return row.revision;
}

function setRevision(database: Database, sessionID: string, revision: number): void {
  database
    .prepare("UPDATE scene_state SET revision = ?1 WHERE session_id = ?2")
    .run(revision, sessionID);
}

function insertDelta(
  database: Database,
  sessionID: string,
  delta: EditDelta,
  fingerprint: string,
): void {
  database
    .prepare(
      "INSERT INTO scene_transactions (session_id, transaction_id, scene_revision, base_revision, idempotency_key, fingerprint, delta_json, compensates_transaction_id) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
    )
    .run(
      sessionID,
      delta.transaction_id,
      delta.scene_revision,
      delta.base_scene_revision,
      delta.idempotency_key,
      fingerprint,
      JSON.stringify(delta),
      delta.compensates_transaction_id ?? null,
    );
}

function createDelta(
  baseRevision: number,
  idempotencyKey: string,
  ops: readonly ReplacementOperation[],
  inverseOps: readonly ReplacementOperation[],
  compensatesTransactionID?: string,
): EditDelta {
  const sceneRevision = baseRevision + 1;
  const transactionID = generatedID("tx");
  return Object.freeze({
    type: "edit_delta",
    scene_revision: sceneRevision,
    base_scene_revision: baseRevision,
    transaction_id: transactionID,
    idempotency_key: idempotencyKey,
    ops: freezeOperations(ops),
    inverse_ops: freezeOperations(inverseOps),
    local_undo: Object.freeze({
      token: generatedID("undo"),
      valid_for_committed_revision: sceneRevision,
    }),
    ...(compensatesTransactionID === undefined
      ? {}
      : { compensates_transaction_id: compensatesTransactionID }),
    replayed: false,
  });
}

function decodePreview(row: PreviewRow): ReplacementPreview {
  const operations = parseOperations(row.ops_json);
  const targetID = operations.find((op) => op.op === "set_object_visibility")?.object_id ?? null;
  return Object.freeze({
    type: "edit_preview",
    preview_id: row.preview_id,
    proposal_id: row.proposal_id,
    base_scene_revision: row.base_revision,
    intent: Object.freeze({
      operation: targetID === null ? ("place" as const) : ("replace" as const),
      target_id: targetID,
      asset_id: operations.find((op) => op.op === "place_asset")?.asset_id ?? "",
    }),
    ops: freezeOperations(operations),
    status: "pending_confirmation",
  });
}

function decodeDelta(row: TransactionRow): EditDelta {
  const parsed = JSON.parse(row.delta_json) as EditDelta;
  if (parsed.transaction_id !== row.transaction_id || parsed.scene_revision !== row.scene_revision)
    throw new Error("invalid_scene_transaction");
  return Object.freeze({
    ...parsed,
    ops: freezeOperations(parsed.ops),
    inverse_ops: freezeOperations(parsed.inverse_ops),
  });
}

function parseOperations(value: string): readonly ReplacementOperation[] {
  const parsed = JSON.parse(value) as unknown;
  if (!Array.isArray(parsed)) throw new Error("invalid_scene_operations");
  return parsed as readonly ReplacementOperation[];
}

function replacementFromRow(row: ReplacementRow): ValidatedReplacement {
  const worldFromAsset = JSON.parse(row.world_json) as unknown;
  if (!Array.isArray(worldFromAsset)) throw new Error("invalid_scene_replacement");
  return {
    sessionID: row.session_id,
    proposalID: row.proposal_id,
    baseSceneRevision: row.base_revision,
    targetID: row.target_id,
    assetID: row.asset_id,
    replacementInstanceID: row.instance_id,
    revealBundleID: row.reveal_id,
    worldFromAsset: worldFromAsset as readonly number[],
  };
}

function replacementOperations(replacement: ValidatedReplacement): readonly ReplacementOperation[] {
  return [
    { op: "set_object_visibility", object_id: replacement.targetID, value: "hidden" },
    { op: "set_reveal_visibility", reveal_bundle_id: replacement.revealBundleID, value: true },
    {
      op: "place_asset",
      asset_id: replacement.assetID,
      instance_id: replacement.replacementInstanceID,
      world_from_asset: [...replacement.worldFromAsset],
    },
  ];
}

function inverseReplacementOperations(
  replacement: ValidatedReplacement,
): readonly ReplacementOperation[] {
  return [
    { op: "remove_asset_instance", instance_id: replacement.replacementInstanceID },
    { op: "set_reveal_visibility", reveal_bundle_id: replacement.revealBundleID, value: false },
    { op: "set_object_visibility", object_id: replacement.targetID, value: "visible" },
  ];
}

function validateReplacement(replacement: ValidatedReplacement): void {
  if (
    !/^room_[a-z0-9_]{3,120}$/u.test(replacement.sessionID) ||
    !/^proposal_[0-9a-f-]{36}$/u.test(replacement.proposalID) ||
    !/^object_[0-9a-f-]{36}$/u.test(replacement.targetID) ||
    !isSafeAssetID(replacement.assetID) ||
    !/^instance_[0-9a-f-]{36}$/u.test(replacement.replacementInstanceID) ||
    !/^reveal_[0-9a-f-]{36}$/u.test(replacement.revealBundleID) ||
    replacement.worldFromAsset.length !== 16 ||
    !replacement.worldFromAsset.every(Number.isFinite)
  )
    throw new TypeError("invalid validated replacement");
  if (!Number.isSafeInteger(replacement.baseSceneRevision) || replacement.baseSceneRevision < 0)
    throw new TypeError("invalid validated replacement");
}

function validateCommitInput(
  resourceID: string,
  prefix: "preview" | "tx",
  revision: number,
  key: string,
): void {
  if (
    !new RegExp(`^${prefix}_[0-9a-f-]{36}$`, "u").test(resourceID) ||
    !/^txidem_[0-9a-f-]{36}$/u.test(key) ||
    !Number.isSafeInteger(revision) ||
    revision < 0
  )
    throw new TypeError("invalid edit commit input");
}

function generatedID(prefix: "preview" | "tx" | "undo"): string {
  return `${prefix}_${randomUUID()}`;
}

function isSafeAssetID(value: string): boolean {
  return /^[A-Za-z0-9][A-Za-z0-9._-]{0,255}$/u.test(value);
}

function freezeOperations(
  operations: readonly ReplacementOperation[],
): readonly ReplacementOperation[] {
  return Object.freeze(
    operations.map((operation) =>
      operation.op === "place_asset"
        ? Object.freeze({
            ...operation,
            world_from_asset: Object.freeze([...operation.world_from_asset]),
          })
        : Object.freeze({ ...operation }),
    ),
  );
}

function transaction<T>(database: Database, operation: () => T): T {
  database.exec("BEGIN IMMEDIATE");
  try {
    const result = operation();
    database.exec("COMMIT");
    return result;
  } catch (error) {
    database.exec("ROLLBACK");
    throw error;
  }
}
