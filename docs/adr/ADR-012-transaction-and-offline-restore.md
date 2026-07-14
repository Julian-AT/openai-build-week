# ADR-012: Revisioned Transactions and Offline Restore

Status: Accepted  
Date: 2026-07-14

## Context

Preview, retry, reconnect, and local restoration are unsafe without a precise distinction between canonical transaction state and client synchronization state. Mutating a committed transaction into “undone” would destroy immutable history.

## Project constraints

- One editor is assumed for P0, but retries and stale revisions still occur.
- Every visible committed edit must remain renderable and restorable during active-session network loss.
- Exactly four product operations must map to deterministic internal deltas.

## Alternatives considered

1. Direct mutable scene commands with best-effort undo.
2. Change the original transaction state to undone.
3. Validate/preview/commit with compare-and-swap revisions, immutable history, inverse operations, and a compensating restore transaction.

## Decision

Adopt alternative 3. Each revision branch has exactly one writer. During a live Mode A session, the native device is canonical authority for its `revision_branch_id`; it can allocate `r+1` while offline, and the gateway is the validating durable replica/reconciliation authority rather than a competing writer. A B0 replay may fork a separately identified gateway-authoritative branch. Web input against an active phone branch is proposal-only. Canonical lifecycle is `draft → validated → previewed → committed`, or `rejected`/`cancelled`; preview does not increment the scene revision. The branch authority compares `base_scene_revision` and increments exactly once. The same idempotency key and RR-JCS-SHA256-1 request fingerprint returns the prior result; the same key with different content is a protocol conflict. Visibility and reveal mutate canonical object `edit_state`; asset creation atomically creates its placed-asset record, full manifest revision/digest reference, and asset support relation. Restore creates a new compensating transaction referencing the original. It verifies the locally persisted captured-exact RR-EDIT-PROJECTION-1 inverse, then RR-RESTORE-REBASE-1 applies only that inverse's operation-verified touched IDs atop the current complete projection. This preserves objects newly tracked after the edit and all unaffected edit state as well as tracking/readiness/surface evidence and immutable history. Restore emits a fresh higher-revision SceneState; it never reinstates an old whole-document revision or digest. Local `sync_state` is independent. Before showing a commit as durable, the phone persists the transaction, complete projection inverse, required artifacts, hashes, authority/branch, and activated revision.

## Evidence

- Record-first/offline invariants in the governing prompt.
- Immutable compensating transactions preserve replay and reconciliation better than rewriting history.

## Consequences

- Retry and replay behavior is deterministic.
- Active-session restore can occur without a network round trip.
- Reconnect reconciliation is explicit and testable.

## Risks

- An unexpected gateway/device branch divergence can require snapshot reconciliation.
- Partial artifact persistence could make an edit visible but not restorable.

## Fallback

If required artifacts/inverse operations are not durably activated, do not acknowledge commit locally. On reconnect, the gateway accepts the authority's ordered journal idempotently. If the gateway contains an unexpected divergent revision for the same branch, preserve both histories, stop further mutations, quarantine the unexpected history under a distinct branch ID, fetch a snapshot, and require deterministic reconciliation. Never automatically merge or silently overwrite either branch.

## Benchmark and kill gate

`GATE-009`: fixture sequence covers duplicate commit, changed-body idempotency conflict, stale base, preview cancellation, offline restore, crash after activation, and reconnect. Pass requires the exact expected scene revisions, no duplicate mutation, and restoration using only persisted local data. Failure blocks all edit commits.

## Requirements and contracts affected

`FR-PLACE-001`, `FR-REPLACE-001`, `FR-REMOVE-001`, `FR-RESTORE-001`, `FR-TRANSACTION-001`, CON-003, CON-004, and CON-005.

## Supersession

Supersedes archived lifecycle language that treated undo/restore as a terminal state of the original transaction. No canonical ADR is superseded.
