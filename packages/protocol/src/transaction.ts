import { createHash } from "node:crypto";

export type EditOperationKind = "place" | "remove" | "replace" | "restore";

export interface PlaceOperation {
  readonly kind: "place";
  readonly assetId: string;
  readonly supportSurfaceId: string;
}

export interface ReplaceOperation {
  readonly kind: "replace";
  readonly targetId: string;
  readonly assetId: string;
}

export interface RemoveOperation {
  readonly kind: "remove";
  readonly targetId: string;
}

export interface RestoreOperation {
  readonly kind: "restore";
  readonly transactionId: string;
}

export type EditOperation = PlaceOperation | RemoveOperation | ReplaceOperation | RestoreOperation;

export interface SceneState {
  readonly sessionId: string;
  readonly revision: number;
  readonly transactions: readonly CommittedTransaction[];
}

export interface EditProposal {
  readonly proposalId: string;
  readonly sourceTurnId: string;
  readonly baseSceneRevision: number;
  readonly operation: EditOperation;
  readonly requestFingerprint: string;
  readonly status: "pending_confirmation";
}

export interface CommittedTransaction {
  readonly transactionId: string;
  readonly proposalId: string;
  readonly confirmationId: string;
  readonly idempotencyKey: string;
  readonly baseSceneRevision: number;
  readonly committedSceneRevision: number;
  readonly operation: EditOperation;
  readonly requestFingerprint: string;
}

export interface CommitResult {
  readonly scene: SceneState;
  readonly transaction: CommittedTransaction;
  readonly replayed: boolean;
}

export class RevisionConflictError extends Error {
  constructor(
    readonly expectedRevision: number,
    readonly actualRevision: number,
  ) {
    super(`scene revision conflict: expected ${expectedRevision}, found ${actualRevision}`);
    this.name = "RevisionConflictError";
  }
}

export class IdempotencyConflictError extends Error {
  constructor(readonly idempotencyKey: string) {
    super(`idempotency key is already bound to a different proposal: ${idempotencyKey}`);
    this.name = "IdempotencyConflictError";
  }
}

export function createEmptyScene(sessionId: string): SceneState {
  requireIdentifier(sessionId, "sessionId");
  return { sessionId, revision: 0, transactions: [] };
}

export function prepareProposal(
  scene: SceneState,
  input: {
    readonly proposalId: string;
    readonly sourceTurnId: string;
    readonly operation: EditOperation;
  },
): EditProposal {
  requireIdentifier(input.proposalId, "proposalId");
  requireIdentifier(input.sourceTurnId, "sourceTurnId");
  validateOperation(input.operation);
  return {
    proposalId: input.proposalId,
    sourceTurnId: input.sourceTurnId,
    baseSceneRevision: scene.revision,
    operation: input.operation,
    requestFingerprint: fingerprintProposal({
      proposalId: input.proposalId,
      sourceTurnId: input.sourceTurnId,
      baseSceneRevision: scene.revision,
      operation: input.operation,
    }),
    status: "pending_confirmation",
  };
}

export function commitProposal(
  scene: SceneState,
  proposal: EditProposal,
  confirmation: {
    readonly confirmationId: string;
    readonly expectedRevision: number;
    readonly idempotencyKey: string;
  },
): CommitResult {
  requireIdentifier(confirmation.confirmationId, "confirmationId");
  requireIdentifier(confirmation.idempotencyKey, "idempotencyKey");

  const existing = scene.transactions.find(
    (transaction) => transaction.idempotencyKey === confirmation.idempotencyKey,
  );
  if (existing) {
    if (
      existing.proposalId !== proposal.proposalId ||
      existing.requestFingerprint !== proposal.requestFingerprint
    ) {
      throw new IdempotencyConflictError(confirmation.idempotencyKey);
    }
    return { scene, transaction: existing, replayed: true };
  }

  if (
    confirmation.expectedRevision !== scene.revision ||
    proposal.baseSceneRevision !== scene.revision
  ) {
    throw new RevisionConflictError(confirmation.expectedRevision, scene.revision);
  }

  const committedSceneRevision = scene.revision + 1;
  const transaction: CommittedTransaction = {
    transactionId: `transaction_${proposal.proposalId.slice("proposal_".length)}`,
    proposalId: proposal.proposalId,
    confirmationId: confirmation.confirmationId,
    idempotencyKey: confirmation.idempotencyKey,
    baseSceneRevision: scene.revision,
    committedSceneRevision,
    operation: proposal.operation,
    requestFingerprint: proposal.requestFingerprint,
  };
  return {
    scene: {
      ...scene,
      revision: committedSceneRevision,
      transactions: [...scene.transactions, transaction],
    },
    transaction,
    replayed: false,
  };
}

function validateOperation(operation: EditOperation): void {
  if (operation.kind === "restore") {
    requireIdentifier(operation.transactionId, "transactionId");
    return;
  }
  if (operation.kind === "place") {
    requireIdentifier(operation.assetId, "assetId");
    requireIdentifier(operation.supportSurfaceId, "supportSurfaceId");
    return;
  }
  requireIdentifier(operation.targetId, "targetId");
  if (operation.kind === "replace") requireIdentifier(operation.assetId, "assetId");
}

function requireIdentifier(value: string, field: string): void {
  if (!/^[a-z][a-z0-9]*(?:_[a-z0-9]+)+$/.test(value)) {
    throw new TypeError(`${field} must be a stable prefixed identifier`);
  }
}

function fingerprintProposal(input: {
  readonly proposalId: string;
  readonly sourceTurnId: string;
  readonly baseSceneRevision: number;
  readonly operation: EditOperation;
}): string {
  const operation =
    input.operation.kind === "place"
      ? {
          assetId: input.operation.assetId,
          kind: input.operation.kind,
          supportSurfaceId: input.operation.supportSurfaceId,
        }
      : input.operation.kind === "replace"
        ? {
            assetId: input.operation.assetId,
            kind: input.operation.kind,
            targetId: input.operation.targetId,
          }
        : input.operation.kind === "remove"
          ? { kind: input.operation.kind, targetId: input.operation.targetId }
          : { kind: input.operation.kind, transactionId: input.operation.transactionId };
  const canonical = JSON.stringify({
    baseSceneRevision: input.baseSceneRevision,
    operation,
    proposalId: input.proposalId,
    sourceTurnId: input.sourceTurnId,
  });
  return createHash("sha256").update(canonical).digest("hex");
}
