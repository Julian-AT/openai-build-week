# Phase 3: Typed Place, Commit, and Offline Restore - Research

**Researched:** 2026-07-18
**Domain:** Native Swift deterministic transaction reduction, atomic local activation, typed intent safety, and SwiftUI proof surface
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

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

### Deferred Ideas (OUT OF SCOPE)
- Target grounding, semantic provider selection, renderer qualification, dense geometry, replacement compositing, and removal/reveal readiness remain Phases 4–6.
- The complete GATE-009/GATE-010 campaign, optional voice ingress, production asset-license/device-load gate, cloud gateway deployment, and full physical/human gate evidence remain deferred exactly as recorded in `.planning/SPRINT-CUT-36H.md`; automation must still cover the demo-critical deterministic fixtures now.
- Full Next.js sessions, sharing, typed web proposals, and polished B0 fallback remain Phase 7.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| `FR-PLACE-001` | Place one curated validated asset on an estimated support surface and preview it before commit. | Pure place reducer, deterministic proxy support, explicit confirmation, atomic activation, restart/replay tests, and a compact native proof surface. |
| `FR-RESTORE-001` | Restore the latest eligible committed edit through a new offline compensating transaction. | Complete edit projections, persisted captured-exact inverse, touched-ID derivation, drift rejection, fresh revision envelope, and immutable source history. |
| `FR-TRANSACTION-001` | Enforce one branch authority, CAS revisions, exact fingerprinting/idempotency, local durability, inverses, and explicit reconciliation. | Sole-writer actor, pure reducer, activation-pointer store, persisted idempotency index, schema plus semantic validation, and fault-injection seams. |
| `FR-AGENT-001` | Typed/tap controls propose all four operations without model/network and cannot authorize canonical mutation. | Bounded strict JSON ingress, allowlisted typed DTOs, context binding, blocked nonmutating replace/remove results, and adversarial fixture tests. |
</phase_requirements>

## Summary

Phase 3 should add one `ReRoomTransactionCore` SwiftPM product beside the existing contract and capture modules. Its center should be a pure, synchronous reducer over typed CON-003/CON-005 values, wrapped by one actor that owns the live branch revision, idempotency index, immutable transaction history, and atomic local activation. The existing `ReRoomContracts` canonicalizer and frozen schema validator should remain the wire/shape authority; semantic invariants that span records must be checked by the reducer before any durable publication. [VERIFIED: `docs/contracts/scene-state.schema.json`, `docs/contracts/transaction.schema.json`, `ios/Packages/ReRoomContracts/Sources/ReRoomContracts/ContractValidation.swift`]

The safest sprint implementation is a content-addressed generation bundle with an activation pointer written last: serialize and schema-validate the new SceneState and committed transaction, verify projection/commit/request digests and required artifact references, durably write and synchronize every generation member, then atomically replace and synchronize one small active-generation record. Startup accepts only a fully hash-valid activated generation; incomplete generations remain inactive and diagnosable. This follows the repository's existing synchronous filesystem plus sole-writer actor pattern and avoids suspension/reentrancy inside the CAS/durability critical section. [VERIFIED: `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureFileSystem.swift`, `CaptureArchiveStore.swift`; `docs/adr/ADR-012-transaction-and-offline-restore.md`]

The app proof surface should be deliberately narrow: exactly four operation buttons, a bundled/provenance-recorded proxy asset, base/current revision labels, provisional preview, explicit confirm/cancel, local sync status, and restore. `replace` and `remove` stop at safe nonmutating proposals with typed blockers. This is enough to prove the Phase 3 local contract journey while leaving target grounding and rendering claims to Phases 4–6. [VERIFIED: `.planning/phases/03-typed-place-commit-and-offline-restore/03-CONTEXT.md`; `.planning/SPRINT-CUT-36H.md`]

**Primary recommendation:** Build pure contract models/reducer first, actor-owned durable activation second, and the SwiftUI journey last; do not put transaction semantics or filesystem writes in the view model.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Strict typed/tap proposal parsing | Native client transaction core | SwiftUI ingress | Input is local and provider-free; the UI only supplies an allowlisted operation/design choice. |
| Request fingerprint and validation | Pure transaction core | `ReRoomContracts` | The core selects the exact closed member scope; existing JCS/schema code supplies canonical bytes and shape validation. |
| Preview | Native client UI | Pure reducer | Reducer computes a provisional candidate at base revision `r`; UI renders it without publishing canonical state. |
| CAS commit and idempotency | Native branch-authority actor | Durable store | The native device is the sole live Mode A writer and serializes every revision allocation. |
| Scene/transaction durability | App-owned local storage | Branch-authority actor | Storage publishes a complete validated generation before the actor acknowledges it. |
| Offline restore | Pure reducer + native authority actor | Local storage | Restore needs only persisted source transaction/inverse/current activated scene and emits fresh `r+1`. |
| Divergence handling | Native authority actor | Future gateway replica | Phase 3 freezes mutation and records quarantine state; it does not merge or deploy gateway infrastructure. |
| UI state and accessibility | SwiftUI `@MainActor` owner/views | Transaction actor | Observation presents snapshots and sends explicit commands; it never owns canonical revision semantics. |

## Project Constraints (from AGENTS.md)

- Treat the canonical README and accepted ADRs as higher authority than planning artifacts; glossary owns terms/IDs and JSON Schemas own fields/lifecycle. [VERIFIED: `AGENTS.md`; `docs/canonical/README.md`]
- Preserve exactly four operations; restore is compensating and “undo” is only an alias. [VERIFIED: `AGENTS.md`; `ADR-001`]
- Native SwiftUI/ARKit owns Mode A; ARKit remains healthy-session pose/world authority and no rear-LiDAR dependency may enter the base path. [VERIFIED: `AGENTS.md`]
- Preview changes no revision; one declared authority performs CAS and increments once; divergence never auto-merges. [VERIFIED: `AGENTS.md`; `ADR-012`]
- Deterministic code owns target/spatial/revision/persistence/confirmation/commit/reconciliation/restore; models may only propose typed semantic intent, and typed/tap remains complete offline. [VERIFIED: `AGENTS.md`; `ADR-011`]
- Build contract-first vertical slices, validate every untrusted boundary, fail closed, use TDD for behavior-bearing logic, and keep deterministic state/storage/rendering/provider concerns behind typed seams. [VERIFIED: `AGENTS.md`]
- Maintain shared Swift/JavaScript/Python golden vectors for transaction/revision/replay semantics; do not change frozen contract meaning silently. [VERIFIED: `AGENTS.md`; `TST-TX-001`/`002`]
- Add no dependency without exact compatible version, license/artifact evidence, current documentation, concrete need, and tested fallback. [VERIFIED: `AGENTS.md`]
- Preserve unrelated dirty/untracked files; use `rg` and `apply_patch`; run scoped checks, secret scan, and `git diff --check`; physical/human gates remain pending without real evidence. [VERIFIED: `AGENTS.md`]

## Standard Stack

### Core

| Library/tool | Version | Purpose | Why Standard Here |
|--------------|---------|---------|-------------------|
| Swift language mode | Package `.v6`; app `SWIFT_VERSION=6.0` | Typed values, actors, Sendable boundaries | Already enforced by both SwiftPM and Xcode project. [VERIFIED: `Package.swift`, `project.pbxproj`] |
| `ReRoomContracts` | repository-local | RFC 8785 canonicalization, SHA-256, stable contract registration, frozen CON-003/CON-005 validation | Existing measured contract authority; do not fork digest/schema logic. [VERIFIED: source and `CLM-040`] |
| `ReRoomCaptureCore` filesystem seam | repository-local | Bounded path-safe synchronous writes, file/directory synchronization, atomic replace, deterministic before/after fault observers | Existing sole-writer durability pattern can support a Phase 3 store without a new package. [VERIFIED: `CaptureFileSystem.swift`] |
| Foundation + CryptoKit | Apple SDK in Xcode 26.4 | Codable/JSON bytes, filesystem URLs, timestamps, SHA-256 implementation behind existing helpers | Already used by shipping targets; no dependency added. [VERIFIED: source imports; local `xcodebuild -version`] |
| Observation + SwiftUI | Apple SDK, deployment target iOS 26 | `@MainActor @Observable` presentation owner and accessible native controls | Matches the existing app and project SwiftUI skill rules. [VERIFIED: `App.swift`; `project.pbxproj`] |
| Swift Testing | bundled with current toolchain | Parallel-safe unit, parameterized reducer/injection/fault tests | Existing package and app tests already use `Testing`. [VERIFIED: test sources; `swift test list`] |

### Supporting

| Library/tool | Version | Purpose | When to Use |
|--------------|---------|---------|-------------|
| `swift-json-schema` | exact `0.13.1` | Draft 2020-12 engine behind `ReRoomContracts` fail-closed wrapper | Use only through `ContractValidator`; do not call it directly from transaction code. [VERIFIED: `Package.swift`, `Package.resolved`, `CLM-040`] |
| ARKit app seed | pinned Apple SDK | Supplies current world/frame/support context and camera background | Read a captured immutable context; do not put ARKit types into the pure reducer. [VERIFIED: existing app source; Phase context] |
| Existing verification scripts | repository-local | Contract and release-surface regression checks | Extend with a Phase 3 script rather than creating a second test harness convention. [VERIFIED: `scripts/verify-phase-01-contracts`, `verify-phase-02-capture-replay`, `verify-reroom-release-surface`] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| New transaction-core target | Put logic directly in the app target | Faster initial typing but prevents SwiftPM tests/replay reuse and couples canonical semantics to SwiftUI; reject. |
| Generation bundle + activation pointer | Mutate `scene.json` and transaction files in place | Fewer files but creates mixed-generation crash states and weakens acknowledged-commit guarantees; reject. |
| Existing synchronous filesystem seam | Add SQLite/SwiftData/new database | Adds dependency/schema/migration work with no measured need in this local single-writer slice; reject under ADR-014/YAGNI. |
| Strict local DTO + canonical round-trip equality | Plain `JSONDecoder` | `JSONDecoder` ignores unknown keys by default, so injected forbidden fields could disappear silently; reject for ingress. |

**Installation:** None. This phase should add no external package or product dependency. [VERIFIED: current package already resolves all required capabilities]

## Architecture Patterns

### System Architecture Diagram

```text
Tap / bounded typed JSON
          |
          v
Strict submit_user_intent decoder ---- malformed/stale/forbidden ----> typed rejection
          |
          v
Captured immutable context + allowlisted asset/support
          |
          v
Pure proposal validator/reducer ---- replace/remove not ready --------> safe blocker (no mutation)
          |
          v
Provisional preview at base revision r
       | cancel                              | explicit human confirm
       v                                     v
 no canonical change              NativeBranchAuthority actor
                                             |
                                idempotency lookup / CAS / exact checks
                                  | retry same | conflict/stale/wrong authority
                                  v            v
                              prior result   typed rejection/freeze
                                             |
                                             v
                              Pure reducer builds SceneState r+1,
                              committed tx, captured-exact inverse
                                             |
                                             v
                              durable generation write + hash/schema checks
                                             |
                                             v
                              atomic active-generation pointer (last)
                                             |
                                             v
                              UI acknowledgement / local_only status
                                             |
                                             v
                              Restore: verify latest source + inverse,
                              derive touched IDs, rebase current projection,
                              persist fresh compensating tx at r+2
```

### Recommended Project Structure

```text
ios/Packages/ReRoomContracts/
├── Sources/ReRoomTransactionCore/
│   ├── TransactionModels.swift          # exact Codable CON-003/CON-005 value types
│   ├── IntentBoundary.swift             # bounded strict nonmutating ingress
│   ├── EditProjection.swift             # RR-EDIT-PROJECTION-1 build/diff/validation
│   ├── TransactionReducer.swift         # pure ordered place/restore reduction
│   ├── TransactionAuthority.swift       # sole-writer actor, CAS/idempotency/freeze
│   └── TransactionStore.swift           # generation activation and recovery
└── Tests/ReRoomTransactionCoreTests/
    ├── IntentBoundaryTests.swift
    ├── TransactionReducerTests.swift
    ├── RestoreRebaseTests.swift
    ├── TransactionAuthorityTests.swift
    └── TransactionStoreCrashTests.swift

ios/ReRoomDeviceProof/ReRoomDeviceProof/
├── RoomEditModel.swift                  # @MainActor @Observable presentation adapter
└── RoomEditView.swift                   # compact four-operation proof surface

fixtures/transactions/1.0.0/rev-001/    # immutable shared transaction/revision traces
scripts/verify-phase-03-transactions     # one scoped deterministic verification entry
```

### Pattern 1: Schema Validity Followed by Semantic Validity

**What:** Encode typed SceneState/transaction values, validate their exact bytes against frozen schemas, then run cross-record reducer invariants. Do not treat schema acceptance as permission to commit. [VERIFIED: schemas encode closed shape/conditional lifecycle; Master Spec §11 adds reducer/branch/reference rules]

**Required semantic checks:** authority kind/id/branch equality; target context session/world/base equality; operation-specific exact list/order; every `before` exact-match; asset/support referential integrity; lexicographic unique projection arrays; exact required-artifact union; preview/confirmation binding; CAS `r -> r+1`; commit/inverse/request hashes; and current activated generation consistency.

### Pattern 2: One Non-Reentrant Branch-Authority Actor

**What:** All idempotency and revision decisions occur inside one actor method. Keep the critical path synchronous after entering the actor: compute/validate, perform synchronous filesystem calls, update in-memory snapshot only after durable activation, return receipt. Do not `await` network/model/UI work between CAS check and activation because actor state may change across suspension. [VERIFIED: existing `CaptureArchiveStore` pattern; Swift concurrency project skill]

### Pattern 3: Durable Generation Activated Last

**What:** Write immutable `generations/<digest>/scene.json`, `transaction.json`, and an inventory/hash record; synchronize every file and directory; then atomically replace `active.json` and synchronize its parent. Recovery follows `active.json`, verifies every byte/schema/digest/link, and returns the last active bundle or a sanitized corruption state. Partial generations never become visible.

**Why:** A single pointer is the commit point and provides a deterministic fault matrix before/after every write/sync/activation boundary. This is the local equivalent of the atomic activation rule already used by capture evidence publication. [VERIFIED: `CaptureFileSystem` observers and synchronization methods; `TST-PERSIST-001`]

### Pattern 4: Exact Idempotency Before New Mutation

**What:** Persist `txidem_… -> {request_fingerprint_sha256, transaction_id, committed_scene_revision, result_sha256}` in the activated generation. On every request, recompute the exact fingerprint from the closed scope. Same key/same fingerprint returns the stored result without running another reducer; same key/different fingerprint returns `idempotency_conflict`; no revision changes in either case. [VERIFIED: glossary RR-JCS scope; CON-005; ADR-012]

### Pattern 5: Restore as Projection Rebase, Not Document Rewind

**What:** For the latest eligible source transaction, verify its captured-exact inverse (`before = source committed projection`, `after = source pre-edit projection`), derive sorted touched IDs by diff, verify those IDs against the source operation list, verify current touched values have not drifted unexpectedly, then apply only source inverse after-values to the current complete projection. Wrap the derived result in a new full SceneState envelope and append a new immutable restore transaction. [VERIFIED: Master Spec §11; RR-RESTORE-REBASE-1 glossary; CON-005]

### Pattern 6: Strict Nonmutating Intent Ingress

**What:** Accept a small byte-bounded JSON DTO containing only operation plus allowlisted asset/design values. First pass bytes through `CanonicalJSON.canonicalize` to reject duplicate keys/invalid Unicode/depth/size, decode exact `Codable` types, re-encode, and require canonical input bytes equal canonical re-encoded bytes so unknown fields cannot be ignored. Attach session/branch/revision/target context from trusted local state after decoding; never accept those values from user/model input. Construct the complete draft CON-005 record from that trusted context and validate it with the frozen `ContractValidator` before returning an accepted proposal. This DTO proposes only; explicit confirmation is a separate UI event. [VERIFIED: `CanonicalJSON.swift`; `ContractValidation.swift`; ADR-011; Phase context]

### Pattern 7: Presentation Snapshots, Not UI-Owned Authority

**What:** A `@MainActor @Observable` owner stores an `Equatable` presentation snapshot and calls actor commands. SwiftUI views use `Button`, `Picker`/segmented controls, native text styles, visible disabled reasons, and accessibility identifiers. The view never edits SceneState arrays or increments revisions. [VERIFIED: existing app patterns; SwiftUI project skill]

### Anti-Patterns to Avoid

- **A generic command dictionary:** It permits tool/field expansion and weakens compile-time operation ordering. Use closed enums and operation-specific associated values.
- **Plain `JSONDecoder` at the hostile boundary:** Unknown fields are silently discarded. Require canonical round-trip equality and exact key/byte limits.
- **Preview persistence as canonical state:** Preview belongs to transaction-local presentation and leaves `scene_revision` unchanged.
- **Whole-document undo:** Restoring an old SceneState deletes new tracking/readiness/evidence and violates immutable history. Use RR-RESTORE-REBASE-1.
- **Mutating the original transaction to “undone”:** Compensation is a new committed transaction; source history stays immutable.
- **Actor method with network/model awaits in the CAS section:** Actor reentrancy can invalidate the checked revision. All Phase 3 commit inputs must already be local.
- **Acknowledging after `Data.write(.atomic)` alone:** Multi-file transaction/scene/inverse/artifact state still needs per-file and directory synchronization plus an activation record written last.
- **Treating the proxy asset as licensed/renderer qualified:** Label it as a Phase 3 proxy and keep `GATE-003`/`GATE-011` pending.
- **Implementing replace/remove reducers as “temporarily usable”:** This phase only accepts their safe proposals and returns blockers until later evidence exists.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JCS/SHA-256 | A new JSON sorter or hash encoder | `CanonicalJSON.canonicalize/digest/sha256Hex` | Exact cross-language policy and rejection behavior already have golden evidence. |
| CON-003/CON-005 shape validation | Ad-hoc required-key checks | Existing pinned `ContractValidator` with bundled frozen schemas | Schema IDs, exact version, unknown fields, limits, and conditional lifecycle are already centralized. |
| Filesystem traversal/durability primitives | Raw URL concatenation and scattered `FileHandle` code | Existing `CaptureFileSystem` seam or a very thin transaction-named adapter over it | It already bounds paths/bytes, synchronizes files/directories, atomically replaces, and injects deterministic faults. |
| Restore diff semantics | Generic JSON patch/full snapshot rewind | Typed RR-EDIT-PROJECTION-1 diff over the three stable-ID collections | Only exact touched IDs may change; every other edit/live field must survive. |
| UI controls | Gesture-driven custom controls | SwiftUI `Button`, `Picker`, native alerts/dialogs and accessibility modifiers | Native semantics, VoiceOver, disabled state, and test identifiers come for free. |
| Persistence framework | New SQLite/SwiftData abstraction | Immutable files + activation pointer for this single-writer sprint slice | No measured need justifies schema/migration/dependency work; ADR-014 forbids speculative infrastructure. |

**Key insight:** The difficult parts already have authorities—schemas, JCS, filesystem fault seams, and exact reducer prose. Phase 3 should compose those authorities and add only the missing typed semantic reducer/store, not replace them.

## Common Pitfalls

### Pitfall 1: Schema-Passing but Semantically Invalid Commit
**What goes wrong:** CON-005 can be shape-valid while the `before` value, branch, target context, operation order, artifact union, or SceneState link is wrong.
**How to avoid:** Run schema validation and a separate reducer invariant validator before persistence and again during recovery.
**Warning signs:** Tests assert only `ContractValidationVerdict.accepted` or only JSON snapshots.

### Pitfall 2: Fingerprinting the Transaction Object
**What goes wrong:** Including transaction ID, idempotency key, timestamps, validation/results, preview, commit, inverse, sync, or reconciliation makes retries unstable; omitting one named request member allows changed content to alias.
**How to avoid:** Build a dedicated fingerprint-scope value with exactly the seven named members and golden toggle tests for every included/excluded field.
**Warning signs:** Fingerprint code accepts arbitrary dictionaries or uses encoded full transaction bytes.

### Pitfall 3: Partial Activation Survives Restart
**What goes wrong:** Scene revision advances while its transaction/inverse/artifacts are missing, or a transaction exists without active SceneState.
**How to avoid:** Immutable generation, synchronized inventory, activation pointer last, recovery validation, and a fault at every pre/post filesystem observer boundary.
**Warning signs:** UI acknowledgement happens before the active pointer is durable, or recovery scans “newest timestamp” instead of following a verified pointer.

### Pitfall 4: Restore Deletes New State
**What goes wrong:** Loading the source transaction's old whole document removes objects/readiness updates tracked after the edit.
**How to avoid:** Project only edit-managed fields, derive/verify touched IDs, apply only inverse values for those IDs to current projection, and preserve all excluded SceneState members.
**Warning signs:** Restore assigns `scene = oldScene` or replaces all projection arrays from the source inverse.

### Pitfall 5: Unexpected Touched-Entity Drift Is Overwritten
**What goes wrong:** A later change to a touched asset/object is silently erased by restore.
**How to avoid:** Compare each current touched value with the source inverse `before`; mismatch rejects with a typed non-destructive error.
**Warning signs:** Restore rebase checks IDs but not current values/source hashes.

### Pitfall 6: UI Confirmation Becomes a Boolean
**What goes wrong:** A model/service or stale preview can set `confirmed=true` without a user event bound to the displayed preview.
**How to avoid:** Create an explicit confirmation record with `user_…`, `preview_…`, `event_…`, timestamp, and exact preview/base revision binding only from the confirm button action.
**Warning signs:** Commit API accepts a bare Boolean or accepts confirmation inside typed intent JSON.

### Pitfall 7: Replace/Remove Accidentally Mutate During Phase 3
**What goes wrong:** A “temporary” reducer hides/reveals content without the later target/compositor evidence.
**How to avoid:** Return typed `capability_not_ready`/specific readiness blockers from proposal evaluation and assert unchanged scene/history/store bytes.
**Warning signs:** Operation buttons are hidden rather than safely explainable, or blocker tests omit state digest comparison.

### Pitfall 8: Swift Actor Reentrancy Splits CAS
**What goes wrong:** An `await` after checking revision lets another request commit before the first request writes.
**How to avoid:** No suspension inside the authority's check/reduce/persist/activate/update sequence; UI/network work happens before or after.
**Warning signs:** Validator/store APIs are async despite doing only local synchronous work, or the actor calls a network replica before local activation.

## Code Examples

These are planner-level interface sketches grounded in repository APIs; exact names are at the agent's discretion.

### Exact Fingerprint Scope

```swift
struct TransactionFingerprintScope: Encodable, Sendable {
    let schemaVersion: String
    let sessionID: String
    let revisionAuthority: RevisionAuthority
    let baseSceneRevision: UInt64
    let targetContext: TargetContext
    let intent: TransactionIntent
    let proposedOperations: [TransactionOperation]
}

let bytes = try JSONEncoder.contractExact.encode(scope)
let fingerprint = try CanonicalJSON.digest(jsonData: bytes)
```

Source: RR-JCS-SHA256-1 glossary and CON-005 request fingerprint scope. [VERIFIED: `GLOSSARY_AND_ID_REGISTRY.md`; `transaction.schema.json`]

### Non-Reentrant Authority Shape

```swift
public actor NativeBranchAuthority {
    public func commit(_ request: ConfirmedPreview) throws -> CommitReceipt {
        // No await in this method.
        let fingerprint = try fingerprint(request.proposal)
        if let prior = idempotency[request.idempotencyKey] {
            guard prior.fingerprint == fingerprint else { throw .idempotencyConflict }
            return prior.receipt
        }
        guard request.baseRevision == active.scene.sceneRevision else { throw .staleRevision }
        let next = try reducer.commit(request, from: active)
        try store.activate(next) // synchronous durable transaction
        active = next
        idempotency[request.idempotencyKey] = next.idempotencyRecord
        return next.receipt
    }
}
```

Source: existing sole-writer actor pattern and ADR-012. [VERIFIED: `CaptureArchiveStore.swift`; `ADR-012`]

### Strict Proposal Round Trip

```swift
func decodeProposal(_ data: Data) throws -> UserIntentDTO {
    guard data.count <= maximumIntentBytes else { throw IntentError.oversized }
    let canonicalInput = try CanonicalJSON.canonicalize(
        jsonData: data,
        maximumBytes: maximumIntentBytes,
        maximumDepth: maximumIntentDepth
    )
    let value = try JSONDecoder().decode(UserIntentDTO.self, from: canonicalInput)
    let canonicalOutput = try CanonicalJSON.canonicalize(
        jsonData: JSONEncoder.contractExact.encode(value),
        maximumBytes: maximumIntentBytes,
        maximumDepth: maximumIntentDepth
    )
    guard canonicalInput == canonicalOutput else { throw IntentError.unknownOrNoncanonicalField }
    return value
}
```

Source: existing duplicate/Unicode/depth-safe canonicalizer plus ADR-011 exact allowlist. [VERIFIED: `CanonicalJSON.swift`; `ADR-011`]

## Suggested Plan Decomposition

1. **Contract models and golden trace fixtures:** add `ReRoomTransactionCore`, exact Codable types, schema adapter, deterministic IDs/clock, and frozen place/restore/rejection traces. Do not edit CON-003/CON-005.
2. **Pure intent/reducer slice:** strict `submit_user_intent`, exact fingerprint scope, place preview/confirm/cancel, ordered reducer, projection builder, and semantic invariant tests. Replace/remove return typed blockers.
3. **Restore slice:** captured-exact inverse, touched-ID derivation, eligibility/compensation graph, drift rejection, fresh restore inverse, and new/unaffected state preservation tests.
4. **Durable authority slice:** non-reentrant actor, persistent idempotency, generation store, activation recovery, fault matrix, divergence freeze/quarantine metadata, and replay revision trace.
5. **Native proof surface:** existing release routing plus room edit owner/view, proxy asset labeling, explicit confirmation/cancel, revision/local status, restart recovery, restore, accessibility/UI tests.
6. **Verification/evidence:** one Phase 3 script running transaction-core tests, relevant contract/JCS regressions, Debug/Release app tests/build, deterministic rerun comparison, secret scan/diff check, and an honest report that full GATE-009/010 campaigns and device evidence remain pending.

## State of the Art in This Repository

| Existing Approach | Phase 3 Use | Impact |
|-------------------|-------------|--------|
| Closed JSON Schemas plus pinned fail-closed validator | Reuse for every serialized SceneState/transaction at write and recovery | Avoids generated-binding drift while preserving exact 1.0 rejection policy. |
| Actor-owned capture ordering with synchronous filesystem operations | Apply to one native revision authority | Prevents actor reentrancy from splitting CAS/activation. |
| Before/after filesystem fault observers | Reuse for transaction activation crash matrix | Makes every durability edge deterministic in tests. |
| Immutable replay receipts and hash-bound evidence | Emit immutable commit receipts/revision trace | Enables Phase 7 consumers without making them revision authorities. |
| `@MainActor @Observable` app owners and SwiftUI Buttons | Use for presentation only | Keeps UI responsive/testable without leaking canonical authority into views. |

**Deprecated/outdated for this phase:** mutable undo flags, whole-document rollback, global `editable`, provider/renderer indices, network-first commit, model-provided transforms/confirmation, and user intent that carries trusted target/session/authority fields are all explicitly superseded by accepted ADRs. [VERIFIED: ADR-008, ADR-011, ADR-012]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| — | None. Recommendations are derived from locked context, canonical local authority, measured repository evidence, and the inspected toolchain/code. | — | — |

## Open Questions

1. **Where should the single demo proxy asset live?**
   - What we know: Phase 3 requires one bundled allowlisted identity; full derivative/license/device-load evidence remains deferred under the sprint cut. [VERIFIED: context; sprint cut]
   - Recommendation: use the smallest repository-owned generated geometric proxy (for example a labeled box/chair proxy) with an explicit provenance note and stable `asset_…`/manifest reference. Do not import a third-party binary or mark `GATE-011` green.

2. **Should the transaction module depend directly on `ReRoomCaptureCore` for its filesystem protocol?**
   - What we know: the needed path/durability/fault seam is public there, and extracting a new general storage module would expand the sprint. [VERIFIED: `CaptureFileSystem.swift`; sprint cut]
   - Recommendation: for Phase 3, depend on `ReRoomCaptureCore` or provide a transaction-named adapter over `any CaptureFileSystem`; defer a generalized durability-core extraction until there are two stable consumers and no deadline pressure.

3. **How much of GATE-009/GATE-010 is claimed now?**
   - What we know: the owner-approved overlay requires demo-critical deterministic automation now but defers the complete campaign and physical/human proof. [VERIFIED: `.planning/SPRINT-CUT-36H.md`]
   - Recommendation: implement and report exact automated place/restore/idempotency/injection/fault fixtures, label the result “automated sprint slice passed,” and retain both gates as `RUNNING`/`PENDING` until their canonical evidence records are complete.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Swift compiler/runtime | package core/tests | Yes | Apple Swift `6.3`; package language mode `.v6` | None needed |
| Xcode | iOS app/tests/build | Yes | Xcode `26.4` (`17E192`) | SwiftPM core can continue if a simulator run is temporarily unavailable |
| iOS Simulator scheme | app unit/UI checks | Yes | `ReRoomDeviceProof` scheme resolves local products | Release build plus package tests; physical evidence remains pending |
| Frozen schema resources | app write/recovery validation | Yes | CON-001–CON-005 bundled in app/test resources | Fail setup closed; do not bypass validation |
| `swift-json-schema` | contract validation | Yes | exact `0.13.1` resolved | Existing bounded local wrapper/fail-closed behavior only |
| Network/model/cloud | none in Phase 3 golden path | Not required | — | Typed/tap local path is the required path |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** No current external dependency is missing. The full physical gate evidence is unavailable to autonomous execution and remains explicitly pending rather than blocking local implementation sequencing.

## Validation Architecture

Skipped because `.planning/config.json` explicitly sets `workflow.nyquist_validation` to `false`. Plans should still use the repository's required TDD discipline and scoped commands from AGENTS.md.

### Recommended Requirement-to-Test Coverage

| Requirement | Minimum automated proof in this phase | Command family |
|-------------|----------------------------------------|----------------|
| `FR-PLACE-001` | preview at unchanged `r`; support rejection; explicit confirm gives one `r+1`; restart/replay retains commit | `swift test --package-path ios/Packages/ReRoomContracts --filter ReRoomTransactionCoreTests` |
| `FR-RESTORE-001` | source inverse integrity; latest eligibility; touched-ID rebase; new/unaffected state survives; offline fresh revision/history | same transaction-core suite |
| `FR-TRANSACTION-001` | same-key retry, changed-key conflict, stale/wrong authority, exact hashes/order, crash activation matrix, divergence freeze | transaction-core suite plus Phase 3 verification script |
| `FR-AGENT-001` | four safe proposals offline; malformed/duplicate-key/unknown/oversized/stale/transform/URL/confirmation/session injection rejects with no mutation | intent-boundary suite plus app UI tests |

## Security and Safety Notes

Although GSD `security_enforcement` is explicitly disabled, this phase has a load-bearing untrusted-input boundary. Treat typed JSON, asset metadata, and future model output as untrusted data; apply byte/depth limits, duplicate-key rejection, exact allowlists, local context attachment, and state-digest equality on every rejection test. Never log raw room input or user text in durable transaction evidence; log stable IDs and typed error codes. [VERIFIED: AGENTS.md; ADR-011; `TST-INJECTION-001`]

## Sources

### Primary (HIGH confidence)

- `docs/canonical/README.md` — precedence and human locks.
- `docs/adr/ADR-001-product-modes-and-p0-scope.md` — exact operation inventory and scope.
- `docs/adr/ADR-008-scene-identity-and-readiness.md` — stable identity/readiness separation.
- `docs/adr/ADR-010-asset-contract.md` — curated asset identity and deferred qualification boundary.
- `docs/adr/ADR-011-agent-and-deterministic-boundary.md` — nonmutating typed ingress and authority split.
- `docs/adr/ADR-012-transaction-and-offline-restore.md` — CAS, idempotency, durability, compensation, and divergence.
- `docs/adr/ADR-014-service-topology-and-hardware-tiers.md` — minimal local topology and no speculative datastore.
- `docs/canonical/MASTER_TECHNICAL_SPEC.md` §§11–13 — exact reducer/projection/rebase semantics.
- `docs/canonical/PRD.md` — Phase 3 requirement statements and acceptance criteria.
- `docs/canonical/GLOSSARY_AND_ID_REGISTRY.md` — digest scopes, terms, states, and stable ID patterns.
- `docs/contracts/scene-state.schema.json`, `transaction.schema.json`, and contracts README — frozen field/lifecycle authority.
- `docs/canonical/TEST_AND_EVALUATION_PLAN.md` — TST-TX-001/002/003, TST-PERSIST-001, TST-OFFLINE-001, TST-AGENT-001, and TST-INJECTION-001.
- `docs/canonical/RISK_AND_KILL_GATES.md` — GATE-009 and GATE-010 operational rules.
- `ios/Packages/ReRoomContracts` and `ios/ReRoomDeviceProof` inspected source/tests — current canonicalizer, schema validator, actor/filesystem patterns, app routing, and test infrastructure.
- `.planning/SPRINT-CUT-36H.md` and `03-CONTEXT.md` — human-approved sequencing and locked implementation boundary.

### Secondary (MEDIUM confidence)

- Project-local SwiftUI, Swift Concurrency, and Swift Testing skills — reviewed advisory implementation patterns; they do not override canonical product authority.

### Tertiary (LOW confidence)

- None. No training-only or web-only claim is needed for the recommended plan.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — exact local package/project configuration and installed toolchain were inspected.
- Architecture: HIGH — reducer, authority, projection, durability, and restore behavior are explicitly governed by accepted ADRs, schemas, and Master Spec.
- Pitfalls: HIGH — each is tied to canonical negative fixtures or an existing tested repository seam.
- UI composition: HIGH for data-flow/accessibility pattern; visual qualification remains intentionally outside this phase.

**Research date:** 2026-07-18
**Valid until:** 2026-08-17 for this frozen contract version; re-research if CON-003/CON-005, ADR-011/012, package topology, or the sprint overlay changes.
