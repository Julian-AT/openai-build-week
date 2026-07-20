import { test } from "bun:test";
import assert from "node:assert/strict";

import {
  IdempotencyConflictError,
  InMemoryEditTransactionService,
  RevisionConflictError,
  TransactionConflictError,
} from "../src/edit-transaction-service.ts";

const sessionID = "session_10000000-0000-4000-8000-000000000001";
const proposalID = "proposal_20000000-0000-4000-8000-000000000001";
const previewID = "preview_30000000-0000-4000-8000-000000000001";
const transactionID = "tx_40000000-0000-4000-8000-000000000001";
const undoToken = "undo_50000000-0000-4000-8000-000000000001";
const restoreTransactionID = "tx_60000000-0000-4000-8000-000000000001";
const restoreUndoToken = "undo_70000000-0000-4000-8000-000000000001";

function createService() {
  const ids = [previewID, transactionID, undoToken, restoreTransactionID, restoreUndoToken];
  const service = new InMemoryEditTransactionService({
    nextID: () => {
      const id = ids.shift();
      assert.ok(id);
      return id;
    },
  });
  service.createSession({ credential: "room-token", sessionID });
  service.stageValidatedReplacement({
    sessionID,
    proposalID,
    baseSceneRevision: 0,
    targetID: "object_80000000-0000-4000-8000-000000000001",
    assetID: "asset_90000000-0000-4000-8000-000000000001",
    replacementInstanceID: "instance_a0000000-0000-4000-8000-000000000001",
    revealBundleID: "reveal_b0000000-0000-4000-8000-000000000001",
    worldFromAsset: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1.2, 0, -2.1, 1],
  });
  return service;
}

test("preparing a validated replacement preview is revision-neutral", () => {
  const service = createService();

  const preview = service.prepareReplacementPreview("room-token", proposalID);

  assert.equal(preview.preview_id, previewID);
  assert.equal(preview.base_scene_revision, 0);
  assert.equal(preview.status, "pending_confirmation");
  assert.equal(service.readScene("room-token").scene_revision, 0);
  assert.deepEqual(service.readScene("room-token").transactions, []);
});

test("confirmation performs one compare-and-swap commit and replays idempotently", () => {
  const service = createService();
  service.prepareReplacementPreview("room-token", proposalID);

  const first = service.confirmPreview("room-token", {
    previewID,
    expectedSceneRevision: 0,
    idempotencyKey: "txidem_c0000000-0000-4000-8000-000000000001",
  });
  const replay = service.confirmPreview("room-token", {
    previewID,
    expectedSceneRevision: 0,
    idempotencyKey: "txidem_c0000000-0000-4000-8000-000000000001",
  });

  assert.equal(first.scene_revision, 1);
  assert.equal(first.base_scene_revision, 0);
  assert.equal(first.transaction_id, transactionID);
  assert.equal(first.replayed, false);
  assert.equal(replay.replayed, true);
  assert.equal(replay.transaction_id, transactionID);
  assert.equal(service.readScene("room-token").scene_revision, 1);
  assert.equal(service.readScene("room-token").transactions.length, 1);
});

test("confirmation rejects stale revisions and reused idempotency keys", () => {
  const service = createService();
  service.prepareReplacementPreview("room-token", proposalID);

  assert.throws(
    () =>
      service.confirmPreview("room-token", {
        previewID,
        expectedSceneRevision: 1,
        idempotencyKey: "txidem_c0000000-0000-4000-8000-000000000001",
      }),
    RevisionConflictError,
  );

  service.confirmPreview("room-token", {
    previewID,
    expectedSceneRevision: 0,
    idempotencyKey: "txidem_c0000000-0000-4000-8000-000000000001",
  });
  assert.throws(
    () =>
      service.restore("room-token", {
        transactionID,
        expectedSceneRevision: 1,
        idempotencyKey: "txidem_c0000000-0000-4000-8000-000000000001",
      }),
    IdempotencyConflictError,
  );
});

test("restore appends a compensating transaction without rewriting history", () => {
  const service = createService();
  service.prepareReplacementPreview("room-token", proposalID);
  const committed = service.confirmPreview("room-token", {
    previewID,
    expectedSceneRevision: 0,
    idempotencyKey: "txidem_c0000000-0000-4000-8000-000000000001",
  });

  const restored = service.restore("room-token", {
    transactionID: committed.transaction_id,
    expectedSceneRevision: 1,
    idempotencyKey: "txidem_d0000000-0000-4000-8000-000000000001",
  });

  assert.equal(restored.scene_revision, 2);
  assert.equal(restored.base_scene_revision, 1);
  assert.equal(restored.transaction_id, restoreTransactionID);
  assert.equal(restored.compensates_transaction_id, transactionID);
  assert.deepEqual(restored.ops, committed.inverse_ops);
  assert.deepEqual(restored.inverse_ops, committed.ops);
  const scene = service.readScene("room-token");
  assert.equal(scene.transactions.length, 2);
  assert.equal(scene.transactions[0]?.transaction_id, transactionID);
  assert.equal(scene.transactions[1]?.transaction_id, restoreTransactionID);
});

test("restore fails closed when the transaction is already compensated", () => {
  const service = createService();
  service.prepareReplacementPreview("room-token", proposalID);
  service.confirmPreview("room-token", {
    previewID,
    expectedSceneRevision: 0,
    idempotencyKey: "txidem_c0000000-0000-4000-8000-000000000001",
  });
  service.restore("room-token", {
    transactionID,
    expectedSceneRevision: 1,
    idempotencyKey: "txidem_d0000000-0000-4000-8000-000000000001",
  });

  assert.throws(
    () =>
      service.restore("room-token", {
        transactionID,
        expectedSceneRevision: 2,
        idempotencyKey: "txidem_e0000000-0000-4000-8000-000000000001",
      }),
    TransactionConflictError,
  );
});

test("credentials bind every operation to its authoritative session", () => {
  const service = createService();
  service.createSession({
    credential: "other-room-token",
    sessionID: "session_f0000000-0000-4000-8000-000000000001",
  });

  assert.throws(
    () => service.prepareReplacementPreview("other-room-token", proposalID),
    TransactionConflictError,
  );
  assert.equal(service.readScene("room-token").scene_revision, 0);
  assert.equal(service.readScene("other-room-token").scene_revision, 0);
});
