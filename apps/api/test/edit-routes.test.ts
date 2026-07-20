import { test } from "bun:test";
import assert from "node:assert/strict";

import {
  type EditDelta,
  type EditTransactionService,
  type ReplacementPreview,
  RevisionConflictError,
  SessionCredentialError,
  TransactionConflictError,
} from "../src/edit-transaction-service.ts";
import { createGatewayApp } from "../src/server.ts";

const preview: ReplacementPreview = {
  type: "edit_preview",
  preview_id: "preview_10000000-0000-4000-8000-000000000001",
  proposal_id: "proposal_20000000-0000-4000-8000-000000000001",
  base_scene_revision: 4,
  intent: {
    operation: "replace",
    target_id: "object_30000000-0000-4000-8000-000000000001",
    asset_id: "asset_40000000-0000-4000-8000-000000000001",
  },
  ops: [],
  status: "pending_confirmation",
};

const delta: EditDelta = {
  type: "edit_delta",
  scene_revision: 5,
  base_scene_revision: 4,
  transaction_id: "tx_50000000-0000-4000-8000-000000000001",
  idempotency_key: "txidem_60000000-0000-4000-8000-000000000001",
  ops: [],
  inverse_ops: [],
  local_undo: {
    token: "undo_70000000-0000-4000-8000-000000000001",
    valid_for_committed_revision: 5,
  },
  replayed: false,
};

test("edit routes bind the bearer session and forward only closed action inputs", async () => {
  const calls: unknown[] = [];
  const service: EditTransactionService = {
    prepareReplacementPreview: (credential, proposalID) => {
      calls.push(["preview", credential, proposalID]);
      return preview;
    },
    confirmPreview: (credential, input) => {
      calls.push(["confirm", credential, input]);
      return delta;
    },
    restore: (credential, input) => {
      calls.push(["restore", credential, input]);
      return { ...delta, compensates_transaction_id: input.transactionID };
    },
  };
  const app = createGatewayApp({ gatewayToken: "gateway-token", editTransactionService: service });
  const request = (path: string, body: unknown) =>
    app.request(path, {
      method: "POST",
      headers: {
        authorization: "Bearer scoped-room-token",
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    });

  const previewResponse = await request("/v1/edit/previews", {
    proposal_id: preview.proposal_id,
  });
  const confirmationResponse = await request("/v1/edit/confirmations", {
    preview_id: preview.preview_id,
    expected_scene_revision: 4,
    idempotency_key: delta.idempotency_key,
  });
  const restoreResponse = await request("/v1/edit/restores", {
    transaction_id: delta.transaction_id,
    expected_scene_revision: 5,
    idempotency_key: "txidem_80000000-0000-4000-8000-000000000001",
  });

  assert.equal(previewResponse.status, 200);
  assert.deepEqual(await previewResponse.json(), preview);
  assert.equal(confirmationResponse.status, 200);
  assert.deepEqual(await confirmationResponse.json(), delta);
  assert.equal(restoreResponse.status, 200);
  assert.deepEqual(await restoreResponse.json(), {
    ...delta,
    compensates_transaction_id: delta.transaction_id,
  });
  assert.deepEqual(calls, [
    ["preview", "scoped-room-token", preview.proposal_id],
    [
      "confirm",
      "scoped-room-token",
      {
        previewID: preview.preview_id,
        expectedSceneRevision: 4,
        idempotencyKey: delta.idempotency_key,
      },
    ],
    [
      "restore",
      "scoped-room-token",
      {
        transactionID: delta.transaction_id,
        expectedSceneRevision: 5,
        idempotencyKey: "txidem_80000000-0000-4000-8000-000000000001",
      },
    ],
  ]);
});

test("edit routes reject client-supplied authority and unknown fields", async () => {
  let calls = 0;
  const service: EditTransactionService = {
    prepareReplacementPreview: () => {
      calls += 1;
      return preview;
    },
    confirmPreview: () => delta,
    restore: () => delta,
  };
  const app = createGatewayApp({ gatewayToken: "gateway-token", editTransactionService: service });
  const response = await app.request("/v1/edit/previews", {
    method: "POST",
    headers: {
      authorization: "Bearer scoped-room-token",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      proposal_id: preview.proposal_id,
      session_id: "session_attacker",
      base_scene_revision: 99,
    }),
  });

  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: "invalid_request" });
  assert.equal(calls, 0);
});

test("edit routes expose bounded authorization and conflict responses", async () => {
  const revisionConflict: EditTransactionService = {
    prepareReplacementPreview: () => preview,
    confirmPreview: () => {
      throw new RevisionConflictError(4, 7);
    },
    restore: () => delta,
  };
  const unauthorized: EditTransactionService = {
    prepareReplacementPreview: () => {
      throw new SessionCredentialError();
    },
    confirmPreview: () => delta,
    restore: () => delta,
  };
  const stateConflict: EditTransactionService = {
    prepareReplacementPreview: () => {
      throw new TransactionConflictError();
    },
    confirmPreview: () => delta,
    restore: () => delta,
  };
  const request = (service: EditTransactionService, path: string, body: unknown) =>
    createGatewayApp({ gatewayToken: "gateway-token", editTransactionService: service }).request(
      path,
      {
        method: "POST",
        headers: {
          authorization: "Bearer scoped-room-token",
          "content-type": "application/json",
        },
        body: JSON.stringify(body),
      },
    );

  const stale = await request(revisionConflict, "/v1/edit/confirmations", {
    preview_id: preview.preview_id,
    expected_scene_revision: 4,
    idempotency_key: delta.idempotency_key,
  });
  assert.equal(stale.status, 409);
  assert.deepEqual(await stale.json(), { error: "revision_conflict", scene_revision: 7 });

  const denied = await request(unauthorized, "/v1/edit/previews", {
    proposal_id: preview.proposal_id,
  });
  assert.equal(denied.status, 401);
  assert.deepEqual(await denied.json(), { error: "unauthorized" });

  const conflicted = await request(stateConflict, "/v1/edit/previews", {
    proposal_id: preview.proposal_id,
  });
  assert.equal(conflicted.status, 409);
  assert.deepEqual(await conflicted.json(), { error: "transaction_conflict" });
});

test("edit routes require a configured service, JSON, and a scoped bearer credential", async () => {
  const app = createGatewayApp({ gatewayToken: "gateway-token" });
  const unavailable = await app.request("/v1/edit/previews", {
    method: "POST",
    headers: {
      authorization: "Bearer scoped-room-token",
      "content-type": "application/json",
    },
    body: JSON.stringify({ proposal_id: preview.proposal_id }),
  });
  assert.equal(unavailable.status, 503);
  assert.deepEqual(await unavailable.json(), { error: "service_unavailable" });

  const noBearer = await app.request("/v1/edit/previews", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ proposal_id: preview.proposal_id }),
  });
  assert.equal(noBearer.status, 401);

  const wrongMedia = await app.request("/v1/edit/previews", {
    method: "POST",
    headers: { authorization: "Bearer scoped-room-token", "content-type": "text/plain" },
    body: JSON.stringify({ proposal_id: preview.proposal_id }),
  });
  assert.equal(wrongMedia.status, 415);
});
