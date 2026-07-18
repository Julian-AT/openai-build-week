# Phase 3: Typed Place, Commit, and Offline Restore - Context

**Gathered:** 2026-07-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver the deterministic native edit lifecycle for typed/tap input: propose all four canonical operations, complete a validated `place` preview and explicit-confirm commit on the native-authoritative branch, and complete an offline `restore` as a new compensating transaction. The phase owns exact CON-003/CON-005 reduction, local durability, idempotency, CAS revision control, inverse capture, replay, and fail-closed reconciliation. It does not select learned providers, qualify the production compositor, implement target grounding, or claim `replace`/`remove` readiness; those controls remain nonmutating proposals with precise unavailable reasons until later phases provide their evidence.

</domain>

<decisions>
## Implementation Decisions

### Native place and restore journey
- Start from the existing ready native camera seed and expose a compact room-edit surface with exactly four operation choices: `place`, `replace`, `remove`, and `restore`; “undo” is only a user-facing alias for `restore` and never a fifth operation.
- For the Phase 3 golden journey, `place` uses a bundled, allowlisted demo asset identity and a deterministic support-surface candidate. Missing or stale support rejects before preview/commit; no learned geometry or network is required.
- Preview is visibly provisional, remains bound to the unchanged base scene revision, and offers explicit **Confirm placement** and **Cancel** actions. Only a human confirmation actor can request commit.
- After commit, show the new revision and an available **Restore** action. Restore remains usable in airplane/offline conditions and produces a fresh higher revision while the original committed transaction remains immutable.

### Transaction authority and durability
- Implement one Swift transaction/reducer module against the frozen CON-003 and CON-005 field/lifecycle authority; native, replay, and future gateway/web consumers must share golden vectors rather than invent parallel semantics.
- The live Mode A branch names the native device as sole revision authority. Preview never changes `scene_revision`; a successful explicit-confirm CAS changes `r` to `r+1` exactly once.
- Before visible commit acknowledgement, atomically persist the transaction, complete RR-EDIT-PROJECTION-1 inverse, required artifact references, hashes, authority/branch identity, and activated SceneState revision in an app-owned local store.
- Keep canonical transaction state separate from `sync_state`. Network absence yields `local_only`/`pending_sync` without weakening local commit or restore; unexpected same-branch divergence freezes mutation and enters explicit quarantine/reconciliation with no automatic merge.

### Idempotency and restore semantics
- Compute the request fingerprint from exactly the RR-JCS-SHA256-1 scope named by the glossary/schema. The same key plus fingerprint returns the prior result; the same key with changed content is `idempotency_conflict` and performs no mutation.
- Reject stale base revision, wrong branch/authority, invalid lifecycle order, missing required validation, or incomplete artifact/inverse durability atomically; no partial scene or transaction publication is visible.
- Persist every committed inverse as one captured-exact RR-EDIT-PROJECTION-1 restore snapshot. RR-RESTORE-REBASE-1 applies only verified touched IDs onto the current complete projection so newly tracked and unaffected edit state survives.
- Restore targets only the latest eligible uncompensated edit, creates its own immutable transaction and inverse, increments once, and never reinstates an old whole-document revision or digest.

### Typed/tap proposal safety
- Use one local, schema-validated, nonmutating `submit_user_intent` boundary for all four operations. Typed/tap input works with network, model, and learned providers disabled.
- Input may name only allowlisted semantic intent and curated asset/design choices. It cannot supply transforms, confirmation, authority, revision outcome, target/session substitution, URLs, or new tool names.
- Bind proposals to captured session, branch, base revision, and target context; reject malformed, oversized, injected, stale, or mismatched arguments before preview and without canonical mutation.
- `replace` and `remove` proposals are accepted only as safe intent records in this phase and return typed readiness blockers until later target/reveal/compositor evidence exists. Voice remains stretch-only and receives no Phase 3 implementation time.

### the agent's Discretion
- Choose internal Swift type/module names, local atomic-store layout, ID generation abstraction, test helper organization, and compact SwiftUI composition while preserving the exact schemas, stable ID families, digest scopes, reducer order, and offline guarantees.
- A deterministic proxy visual may be used to prove placement interaction before the later compositor gate, but it must be labeled as the Phase 3 demo asset/proxy and must not be presented as a GATE-003 or GATE-011 pass.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ReRoomContracts` already supplies strict Swift 6 validation, canonical JSON/JCS SHA-256, stable-ID checks, RR-COORD-1 math, and frozen-schema validation suitable for a new transaction core.
- `ReRoomCaptureCore` demonstrates the repository's actor-owned atomic durability, filesystem abstraction, exact replay, fault injection, immutable receipts, and bounded deterministic test patterns.
- The native seed already owns ARKit tracking/planes, world epochs, consented capture, off-main durable work, a SwiftUI diagnostic surface, release-mode routing, and Swift Testing/UI-test targets.
- Frozen `scene-state.schema.json` and `transaction.schema.json` are the field/lifecycle authority; no Phase 3 transaction implementation exists yet.

### Established Patterns
- Behavior-bearing Swift is written contract-first with RED/GREEN tests, deterministic in-memory fault injection, exact byte/digest assertions, and fail-closed boundary validation.
- Stable prefixed UUID strings carry identity; renderer/provider indices never become canonical state. All unknown schema fields, versions, codecs, IDs, and lifecycle transitions reject.
- Local durability and external synchronization are separate, user-visible concepts. Physical or visual evidence remains `PENDING` until real evidence exists.

### Integration Points
- Add transaction/reducer/storage capability beside `ReRoomContracts`/`ReRoomCaptureCore`, then connect it to the existing native app without weakening the capture/replay path.
- Use the ARKit plane/world epoch already surfaced by the native seed as the healthy-session support/world authority; Phase 3 may not invent learned pose, scale, or silent cross-epoch alignment.
- Extend provider-independent replay evidence with exact scene/transaction revision traces so the Phase 7 web client can consume the same records later.
- Planning and implementation must follow ADR-001, ADR-008, ADR-010, ADR-011, ADR-012, ADR-014, Master Spec §§11–13, PRD `FR-PLACE-001`/`FR-RESTORE-001`/`FR-TRANSACTION-001`/`FR-AGENT-001`, CON-003/CON-005, and GATE-009/GATE-010.

</code_context>

<specifics>
## Specific Ideas

- Optimize for a legible demo: operation selector, one placeable demo asset, visible base/current revision, preview state, explicit confirmation, offline/local durability state, and a restore action.
- Keep errors actionable and typed: missing support, stale revision, idempotency conflict, wrong authority, unavailable capability, and corrupt local inverse should be distinguishable without exposing private state.
- The user explicitly approved the recommended sprint defaults and asked for autonomous execution; decisions above therefore select the narrow deterministic path and retain all deferred gates in `.planning/SPRINT-CUT-36H.md`.

</specifics>

<deferred>
## Deferred Ideas

- Target grounding, semantic provider selection, renderer qualification, dense geometry, replacement compositing, and removal/reveal readiness remain Phases 4–6.
- The complete GATE-009/GATE-010 campaign, optional voice ingress, production asset-license/device-load gate, cloud gateway deployment, and full physical/human gate evidence remain deferred exactly as recorded in `.planning/SPRINT-CUT-36H.md`; automation must still cover the demo-critical deterministic fixtures now.
- Full Next.js sessions, sharing, typed web proposals, and polished B0 fallback remain Phase 7.

</deferred>

---

*Phase: 03-typed-place-commit-and-offline-restore*
*Context gathered: 2026-07-18*
