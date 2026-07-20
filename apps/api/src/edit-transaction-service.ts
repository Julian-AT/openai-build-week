import { randomUUID } from "node:crypto";

export type ReplacementOperation =
  | {
      readonly op: "set_object_visibility";
      readonly object_id: string;
      readonly value: "hidden" | "visible";
    }
  | {
      readonly op: "set_reveal_visibility";
      readonly reveal_bundle_id: string;
      readonly value: boolean;
    }
  | {
      readonly op: "place_asset";
      readonly asset_id: string;
      readonly instance_id: string;
      readonly world_from_asset: readonly number[];
    }
  | { readonly op: "remove_asset_instance"; readonly instance_id: string };

export interface ReplacementPreview {
  readonly type: "edit_preview";
  readonly preview_id: string;
  readonly proposal_id: string;
  readonly base_scene_revision: number;
  readonly intent: {
    readonly operation: "replace";
    readonly target_id: string;
    readonly asset_id: string;
  };
  readonly ops: readonly ReplacementOperation[];
  readonly status: "pending_confirmation";
}

export interface EditDelta {
  readonly type: "edit_delta";
  readonly scene_revision: number;
  readonly base_scene_revision: number;
  readonly transaction_id: string;
  readonly idempotency_key: string;
  readonly ops: readonly ReplacementOperation[];
  readonly inverse_ops: readonly ReplacementOperation[];
  readonly local_undo: {
    readonly token: string;
    readonly valid_for_committed_revision: number;
  };
  readonly compensates_transaction_id?: string;
  readonly replayed: boolean;
}

export interface SceneTransactionState {
  readonly scene_revision: number;
  readonly transactions: readonly EditDelta[];
}

export interface ValidatedReplacement {
  readonly sessionID: string;
  readonly proposalID: string;
  readonly baseSceneRevision: number;
  readonly targetID: string;
  readonly assetID: string;
  readonly replacementInstanceID: string;
  readonly revealBundleID: string;
  readonly worldFromAsset: readonly number[];
}

export interface ConfirmPreviewInput {
  readonly previewID: string;
  readonly expectedSceneRevision: number;
  readonly idempotencyKey: string;
}

export interface RestoreInput {
  readonly transactionID: string;
  readonly expectedSceneRevision: number;
  readonly idempotencyKey: string;
}

export interface EditTransactionService {
  prepareReplacementPreview(credential: string, proposalID: string): ReplacementPreview;
  confirmPreview(credential: string, input: ConfirmPreviewInput): EditDelta;
  restore(credential: string, input: RestoreInput): EditDelta;
}

interface SessionRecord {
  readonly sessionID: string;
  revision: number;
  readonly transactions: EditDelta[];
  readonly idempotency: Map<string, { fingerprint: string; result: EditDelta }>;
  readonly compensatedTransactions: Set<string>;
}

interface PreviewRecord {
  readonly sessionID: string;
  readonly preview: ReplacementPreview;
  readonly inverseOperations: readonly ReplacementOperation[];
  committed: boolean;
}

export class SessionCredentialError extends Error {
  constructor() {
    super("invalid session credential");
    this.name = "SessionCredentialError";
  }
}

export class TransactionNotFoundError extends Error {
  constructor() {
    super("transaction resource not found");
    this.name = "TransactionNotFoundError";
  }
}

export class RevisionConflictError extends Error {
  constructor(
    readonly expectedRevision: number,
    readonly actualRevision: number,
  ) {
    super("scene revision conflict");
    this.name = "RevisionConflictError";
  }
}

export class IdempotencyConflictError extends Error {
  constructor() {
    super("idempotency key conflict");
    this.name = "IdempotencyConflictError";
  }
}

export class TransactionConflictError extends Error {
  constructor() {
    super("transaction state conflict");
    this.name = "TransactionConflictError";
  }
}

export class InMemoryEditTransactionService implements EditTransactionService {
  readonly #nextID: (prefix: string) => string;
  readonly #sessionsByCredential = new Map<string, SessionRecord>();
  readonly #sessionsByID = new Map<string, SessionRecord>();
  readonly #replacements = new Map<string, ValidatedReplacement>();
  readonly #previews = new Map<string, PreviewRecord>();
  readonly #previewByProposal = new Map<string, string>();

  constructor(options: { readonly nextID?: (prefix: string) => string } = {}) {
    this.#nextID = options.nextID ?? ((prefix) => `${prefix}_${randomUUID()}`);
  }

  createSession(input: { readonly credential: string; readonly sessionID: string }): void {
    requireOpaqueCredential(input.credential);
    requireID(input.sessionID, "session");
    if (
      this.#sessionsByCredential.has(input.credential) ||
      this.#sessionsByID.has(input.sessionID)
    ) {
      throw new TransactionConflictError();
    }
    const session: SessionRecord = {
      sessionID: input.sessionID,
      revision: 0,
      transactions: [],
      idempotency: new Map(),
      compensatedTransactions: new Set(),
    };
    this.#sessionsByCredential.set(input.credential, session);
    this.#sessionsByID.set(input.sessionID, session);
  }

  stageValidatedReplacement(replacement: ValidatedReplacement): void {
    validateReplacement(replacement);
    const session = this.#sessionsByID.get(replacement.sessionID);
    if (!session || replacement.baseSceneRevision !== session.revision) {
      throw new TransactionConflictError();
    }
    if (this.#replacements.has(replacement.proposalID)) {
      throw new TransactionConflictError();
    }
    this.#replacements.set(replacement.proposalID, {
      ...replacement,
      worldFromAsset: [...replacement.worldFromAsset],
    });
  }

  prepareReplacementPreview(credential: string, proposalID: string): ReplacementPreview {
    const session = this.#authorize(credential);
    requireID(proposalID, "proposal");
    const replacement = this.#replacements.get(proposalID);
    if (!replacement) throw new TransactionNotFoundError();
    if (replacement.sessionID !== session.sessionID) throw new TransactionConflictError();

    const existingPreviewID = this.#previewByProposal.get(proposalID);
    if (existingPreviewID) {
      const existing = this.#previews.get(existingPreviewID);
      if (!existing || existing.committed) throw new TransactionConflictError();
      return existing.preview;
    }
    if (replacement.baseSceneRevision !== session.revision) {
      throw new RevisionConflictError(replacement.baseSceneRevision, session.revision);
    }

    const previewID = this.#validatedGeneratedID("preview");
    const operations = replacementOperations(replacement);
    const preview: ReplacementPreview = {
      type: "edit_preview",
      preview_id: previewID,
      proposal_id: proposalID,
      base_scene_revision: session.revision,
      intent: {
        operation: "replace",
        target_id: replacement.targetID,
        asset_id: replacement.assetID,
      },
      ops: operations,
      status: "pending_confirmation",
    };
    this.#previews.set(previewID, {
      sessionID: session.sessionID,
      preview,
      inverseOperations: inverseReplacementOperations(replacement),
      committed: false,
    });
    this.#previewByProposal.set(proposalID, previewID);
    return preview;
  }

  confirmPreview(credential: string, input: ConfirmPreviewInput): EditDelta {
    const session = this.#authorize(credential);
    validateCommitInput(
      input.previewID,
      "preview",
      input.expectedSceneRevision,
      input.idempotencyKey,
    );
    const previewRecord = this.#previews.get(input.previewID);
    if (!previewRecord) throw new TransactionNotFoundError();
    if (previewRecord.sessionID !== session.sessionID) throw new TransactionConflictError();

    const fingerprint = `confirm:${input.previewID}`;
    const replay = replayIdempotent(session, input.idempotencyKey, fingerprint);
    if (replay) return { ...replay, replayed: true };
    if (previewRecord.committed) throw new TransactionConflictError();
    assertRevision(session, previewRecord.preview.base_scene_revision, input.expectedSceneRevision);

    const delta = this.#createDelta(session, {
      idempotencyKey: input.idempotencyKey,
      operations: previewRecord.preview.ops,
      inverseOperations: previewRecord.inverseOperations,
    });
    previewRecord.committed = true;
    recordDelta(session, input.idempotencyKey, fingerprint, delta);
    return delta;
  }

  restore(credential: string, input: RestoreInput): EditDelta {
    const session = this.#authorize(credential);
    validateCommitInput(
      input.transactionID,
      "tx",
      input.expectedSceneRevision,
      input.idempotencyKey,
    );
    const fingerprint = `restore:${input.transactionID}`;
    const replay = replayIdempotent(session, input.idempotencyKey, fingerprint);
    if (replay) return { ...replay, replayed: true };

    const original = session.transactions.find(
      (transaction) => transaction.transaction_id === input.transactionID,
    );
    if (!original) throw new TransactionNotFoundError();
    if (
      original.compensates_transaction_id !== undefined ||
      session.compensatedTransactions.has(input.transactionID)
    ) {
      throw new TransactionConflictError();
    }
    assertRevision(session, session.revision, input.expectedSceneRevision);

    const delta = this.#createDelta(session, {
      idempotencyKey: input.idempotencyKey,
      operations: original.inverse_ops,
      inverseOperations: original.ops,
      compensatesTransactionID: original.transaction_id,
    });
    session.compensatedTransactions.add(original.transaction_id);
    recordDelta(session, input.idempotencyKey, fingerprint, delta);
    return delta;
  }

  readScene(credential: string): SceneTransactionState {
    const session = this.#authorize(credential);
    return { scene_revision: session.revision, transactions: [...session.transactions] };
  }

  #authorize(credential: string): SessionRecord {
    const session = this.#sessionsByCredential.get(credential);
    if (!session) throw new SessionCredentialError();
    return session;
  }

  #validatedGeneratedID(prefix: "preview" | "tx" | "undo"): string {
    const id = this.#nextID(prefix);
    requireID(id, prefix);
    return id;
  }

  #createDelta(
    session: SessionRecord,
    input: {
      readonly idempotencyKey: string;
      readonly operations: readonly ReplacementOperation[];
      readonly inverseOperations: readonly ReplacementOperation[];
      readonly compensatesTransactionID?: string;
    },
  ): EditDelta {
    const baseRevision = session.revision;
    const sceneRevision = baseRevision + 1;
    const delta: EditDelta = {
      type: "edit_delta",
      scene_revision: sceneRevision,
      base_scene_revision: baseRevision,
      transaction_id: this.#validatedGeneratedID("tx"),
      idempotency_key: input.idempotencyKey,
      ops: input.operations,
      inverse_ops: input.inverseOperations,
      local_undo: {
        token: this.#validatedGeneratedID("undo"),
        valid_for_committed_revision: sceneRevision,
      },
      ...(input.compensatesTransactionID
        ? { compensates_transaction_id: input.compensatesTransactionID }
        : {}),
      replayed: false,
    };
    session.revision = sceneRevision;
    session.transactions.push(delta);
    return delta;
  }
}

function replacementOperations(replacement: ValidatedReplacement): readonly ReplacementOperation[] {
  return [
    { op: "set_object_visibility", object_id: replacement.targetID, value: "hidden" },
    {
      op: "set_reveal_visibility",
      reveal_bundle_id: replacement.revealBundleID,
      value: true,
    },
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
    {
      op: "set_reveal_visibility",
      reveal_bundle_id: replacement.revealBundleID,
      value: false,
    },
    { op: "set_object_visibility", object_id: replacement.targetID, value: "visible" },
  ];
}

function validateReplacement(replacement: ValidatedReplacement): void {
  requireID(replacement.sessionID, "session");
  requireID(replacement.proposalID, "proposal");
  requireID(replacement.targetID, "object");
  requireID(replacement.assetID, "asset");
  requireID(replacement.replacementInstanceID, "instance");
  requireID(replacement.revealBundleID, "reveal");
  if (
    !Number.isSafeInteger(replacement.baseSceneRevision) ||
    replacement.baseSceneRevision < 0 ||
    replacement.worldFromAsset.length !== 16 ||
    !replacement.worldFromAsset.every(Number.isFinite)
  ) {
    throw new TypeError("invalid validated replacement");
  }
}

function validateCommitInput(
  resourceID: string,
  resourcePrefix: "preview" | "tx",
  expectedRevision: number,
  idempotencyKey: string,
): void {
  requireID(resourceID, resourcePrefix);
  requireID(idempotencyKey, "txidem");
  if (!Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
    throw new TypeError("invalid expected scene revision");
  }
}

function requireID(value: string, prefix: string): void {
  if (
    !new RegExp(
      `^${prefix}_[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`,
      "u",
    ).test(value)
  ) {
    throw new TypeError(`invalid ${prefix} identifier`);
  }
}

function requireOpaqueCredential(value: string): void {
  if (value.length < 8 || value.length > 512 || value.trim() !== value) {
    throw new TypeError("invalid session credential");
  }
}

function assertRevision(
  session: SessionRecord,
  proposalRevision: number,
  expectedRevision: number,
): void {
  if (proposalRevision !== session.revision || expectedRevision !== session.revision) {
    throw new RevisionConflictError(expectedRevision, session.revision);
  }
}

function replayIdempotent(
  session: SessionRecord,
  idempotencyKey: string,
  fingerprint: string,
): EditDelta | undefined {
  const existing = session.idempotency.get(idempotencyKey);
  if (!existing) return undefined;
  if (existing.fingerprint !== fingerprint) throw new IdempotencyConflictError();
  return existing.result;
}

function recordDelta(
  session: SessionRecord,
  idempotencyKey: string,
  fingerprint: string,
  result: EditDelta,
): void {
  session.idempotency.set(idempotencyKey, { fingerprint, result });
}
