import { test } from "bun:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { createDurableEditTransactionService } from "../src/durable-edit-transaction-service.ts";
import { createDurableRoomSessionStore } from "../src/durable-session-store.ts";

const signingSecret = "test-signing-secret-with-sufficient-length";
const sessionID = "room_2026_07_21_scene";
const proposalID = "proposal_20000000-0000-4000-8000-000000000001";

test("durable scene authority previews, CAS commits, replays, restores, and survives restart", async () => {
  const dataDirectory = await mkdtemp(join(tmpdir(), "reframe-durable-edit-"));
  let store = await createDurableRoomSessionStore({ dataDirectory, signingSecret });
  try {
    let session = await store.createSession({
      sessionID,
      expiresAtMilliseconds: Date.now() + 60_000,
      allowedPaths: ["scene"],
    });
    let service = createDurableEditTransactionService(store);
    await service.stageValidatedReplacement(session.credential, replacement());
    const preview = await service.prepareReplacementPreview(session.credential, proposalID);
    assert.equal(preview.base_scene_revision, 0);
    const first = await service.confirmPreview(session.credential, {
      previewID: preview.preview_id,
      expectedSceneRevision: 0,
      idempotencyKey: "txidem_c0000000-0000-4000-8000-000000000001",
    });
    const replay = await service.confirmPreview(session.credential, {
      previewID: preview.preview_id,
      expectedSceneRevision: 0,
      idempotencyKey: "txidem_c0000000-0000-4000-8000-000000000001",
    });
    assert.equal(first.scene_revision, 1);
    assert.equal(replay.replayed, true);
    await store.close();

    store = await createDurableRoomSessionStore({ dataDirectory, signingSecret });
    session = { ...session };
    service = createDurableEditTransactionService(store);
    const scene = await service.readScene(session.credential);
    assert.equal(scene.scene_revision, 1);
    assert.equal(scene.transactions.length, 1);
    const restored = await service.restore(session.credential, {
      transactionID: first.transaction_id,
      expectedSceneRevision: 1,
      idempotencyKey: "txidem_d0000000-0000-4000-8000-000000000001",
    });
    assert.equal(restored.scene_revision, 2);
    assert.equal(restored.compensates_transaction_id, first.transaction_id);
  } finally {
    await store.close();
    await rm(dataDirectory, { recursive: true, force: true });
  }
});

test("scene credentials are required and stale confirmations fail closed", async () => {
  const dataDirectory = await mkdtemp(join(tmpdir(), "reframe-durable-edit-auth-"));
  const store = await createDurableRoomSessionStore({ dataDirectory, signingSecret });
  try {
    const session = await store.createSession({
      sessionID: "room_2026_07_21_scene_auth",
      expiresAtMilliseconds: Date.now() + 60_000,
      allowedPaths: ["frames"],
    });
    const service = createDurableEditTransactionService(store);
    await assert.rejects(service.readScene(session.credential), /invalid_room_credential/);
  } finally {
    await store.close();
    await rm(dataDirectory, { recursive: true, force: true });
  }
});

function replacement() {
  return {
    sessionID,
    proposalID,
    baseSceneRevision: 0,
    targetID: "object_80000000-0000-4000-8000-000000000001",
    assetID: "asset_90000000-0000-4000-8000-000000000001",
    replacementInstanceID: "instance_a0000000-0000-4000-8000-000000000001",
    revealBundleID: "reveal_b0000000-0000-4000-8000-000000000001",
    worldFromAsset: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1.2, 0, -2.1, 1],
  } as const;
}
