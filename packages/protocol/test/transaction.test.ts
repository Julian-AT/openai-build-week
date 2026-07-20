import { describe, expect, test } from "bun:test";

import {
  commitProposal,
  createEmptyScene,
  IdempotencyConflictError,
  prepareProposal,
  type ReplaceOperation,
} from "../src/index.ts";

describe("scene transaction authority", () => {
  test("keeps preview revision-neutral and increments once after confirmation", () => {
    const scene = createEmptyScene("session_room");
    const operation: ReplaceOperation = {
      kind: "replace",
      targetId: "object_chair",
      assetId: "asset_ikea_chair",
    };

    const proposal = prepareProposal(scene, {
      proposalId: "proposal_replace_chair",
      sourceTurnId: "turn_replace_chair",
      operation,
    });

    expect(scene.revision).toBe(0);
    expect(proposal.baseSceneRevision).toBe(0);

    const committed = commitProposal(scene, proposal, {
      confirmationId: "confirmation_replace_chair",
      expectedRevision: 0,
      idempotencyKey: "commit_replace_chair",
    });

    expect(committed.scene.revision).toBe(1);
    expect(committed.transaction.operation).toEqual(operation);
    expect(committed.transaction.baseSceneRevision).toBe(0);
    expect(committed.transaction.committedSceneRevision).toBe(1);
  });

  test("rejects reuse of an idempotency key for changed proposal content", () => {
    const initialScene = createEmptyScene("session_room");
    const original = prepareProposal(initialScene, {
      proposalId: "proposal_replace_chair",
      sourceTurnId: "turn_replace_chair",
      operation: {
        kind: "replace",
        targetId: "object_chair",
        assetId: "asset_ikea_chair",
      },
    });
    const committed = commitProposal(initialScene, original, {
      confirmationId: "confirmation_replace_chair",
      expectedRevision: 0,
      idempotencyKey: "commit_replace_chair",
    });
    const changed = prepareProposal(committed.scene, {
      proposalId: "proposal_replace_chair",
      sourceTurnId: "turn_replace_chair",
      operation: {
        kind: "replace",
        targetId: "object_chair",
        assetId: "asset_ikea_table",
      },
    });

    expect(() =>
      commitProposal(committed.scene, changed, {
        confirmationId: "confirmation_replace_chair_again",
        expectedRevision: 1,
        idempotencyKey: "commit_replace_chair",
      }),
    ).toThrow(IdempotencyConflictError);
  });
});
