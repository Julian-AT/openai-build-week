# Phase 6: Controlled Multi-Surface Removal - Research

**Researched:** 2026-07-18
**Domain:** Deterministic Swift remove/restore transactions and explicitly degraded bounded reveal-fixture rendering
**Confidence:** HIGH for transaction architecture; MEDIUM for demo visual quality (intentionally unmeasured)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

### Exact remove and restore semantics
- Add a dedicated remove reducer and native-authority entry points; do not implement removal as renderer-only hiding, replacement, destructive deletion, or a special restore shortcut.
- The only forward order is `set_reveal_bundle`, then `set_object_visibility`. Reveal activation changes the selected object's canonical `active_reveal` first; visibility changes `true -> false` second. Both deltas apply atomically to the pending scene.
- Preview and cancel change no revision. Explicit confirmation is the sole CAS `r -> r+1`. Same-key/same-fingerprint retry returns the original receipt; changed content, stale revision, wrong authority/branch/world, target mismatch, unsupported view, missing artifact, or failed validation rejects without mutation.
- Persist one captured-exact RR-EDIT-PROJECTION-1 `restore_snapshot` inverse. Restore is a later compensating transaction, restores `active_reveal` and visibility exactly, preserves unrelated/new objects, and never rewrites the source remove record.

### Honest sprint demo boundary
- Do not set canonical remove readiness to `ready`, publish a CON-004 ready reveal bundle, or claim `GATE-006` success. No automated value or fixture is a physical coverage measurement or human vote.
- Keep the ordinary app path remove-unavailable with `reveal_quality_failed`. Permit the complete remove transaction only behind an explicit development/demo-fixture launch mode with persistent copy such as `DEMO REVEAL FIXTURE - GATE-006 PENDING`.
- The demo fixture is a repository-owned deterministic multi-surface visual proxy with exact bytes/digests and `degraded` classification. It is not observed background, a provider output, a measured view envelope, a foreground-occlusion proof, or a release-valid CON-004 ready artifact.
- The demo validator must identify itself separately (for example `RR-DEMO-REMOVE-VALIDATOR-1`) and record `degraded_demo_fixture`; verification must reject any wording that promotes it to ready, measured, provider-produced, physically validated, or gate-passing.
- Keep the demo fixture out of release claims and gate evidence. It exists to exercise operation order, persistence, replay, UI state, and exact restore during the sprint; formal P0 removal remains blocked.

### Bounded view and compositor behavior
- Bind the demo fixture to the stable manually selected `object_*`, frozen seed camera pose, current scene revision, branch/world epoch, and one stable `envelope_*` ID. Use deterministic translation/rotation bounds around the seed pose as HYPOTHESIS/demo policy only.
- Evaluate the current camera pose outside the render loop's mutation path. Outside the fixture bound, tracking loss, world reset, or stale revision, freeze/restore the last safe display and coach the user back; never stretch the reveal proxy or hide the original.
- Render at least two retained local surface layers in canonical order: camera -> reveal surfaces -> available foreground occluder -> asset/proxy -> debug -> SwiftUI. Missing real occluder evidence remains explicitly unavailable; do not manufacture an occluder/provider result.
- Load and retain local demo resources once. The 60 Hz path must not wait on disk, store, network, model, worker, or web client. Add no learned provider, cloud service, network fetch, runtime conversion, third-party dependency, or second AR session.

### Evidence and claims
- Automate reducer order, exact before/after matching, artifact/reference union, target/capability/envelope/world rejection, preview/cancel immutability, retry/idempotency, crash recovery, replay, and remove -> restore preservation.
- Add deterministic app/UI coverage for the explicit demo launch mode, in-envelope preview/confirm/retry/restore, out-of-envelope coaching, tracking/world invalidation, and resource-load failure. Label simulator runs as fixture wiring only.
- Automated preflight may report only `automated sprint removal transaction and bounded demo fixture passed`. It must keep `GATE-006`, `GATE-003`, `GATE-005`, `GATE-009`, and `OPS-GOLDEN-001` exactly `PENDING`.
- Do not create ballot, physical coverage, observed-atlas, provider, foreground-overwrite, seam, or thermal evidence. Those require the real fixture/device/evaluators and remain in the deferred register.

### the agent's Discretion
- Choose the smallest Swift types, stable IDs, local fixture encoding, conservative pose thresholds, retained RealityKit geometry/materials, UI layout/copy, and verification-script structure that preserve the boundaries above.
- Reuse Phase 3 authority/store/restore, Phase 4 target/session/compositor, and Phase 5 canonical target/object integration. Prefer automatically discovered package/app sources and avoid the user's Xcode project/signing files.
- Keep the demo path legible: select target, explicitly enable the labeled demo fixture, preview Remove, confirm once, retry without another revision, then Restore.

### Deferred Ideas (OUT OF SCOPE)
- Real observed atlas capture, background reconstruction/fill, provider selection, foreground occluder generation, measured supported-view envelope, eight-pose coverage computation, seam/order scoring, and exactly five blinded votes remain deferred under `GATE-006`, `GATE-003`, and `GATE-005`.
- A full ready CON-004 reveal bundle and release enablement remain deferred until those artifacts/evidence exist. No placeholder can be promoted in place.
- Physical-device golden runs, disconnect/reconnect campaign, thermal/performance campaign, and P0 claim remain pending under `OPS-GOLDEN-001`, `GATE-009`, and related gates.
- Separate Mode B0 replay remains Phase 7; final integration/submission remains Phase 8.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FR-REMOVE-001 | Remove the controlled target only when reveal and foreground-occlusion evidence is ready for the current supported view envelope; full acceptance is `GATE-006`. | The production path stays unavailable. This phase implements exact transaction machinery and an isolated degraded demo fixture without closing the requirement or gate. [VERIFIED: `.planning/REQUIREMENTS.md`, PRD FR-REMOVE-001, sprint cut] |
</phase_requirements>

## Summary

Canonical removal has two inseparable halves: an exact deterministic edit transaction and independently earned reveal evidence. The transaction half is already well prepared: `TransactionOperation` models reveal and visibility deltas, `EditProjectionEngine` accepts their exact order and artifact union, and `RestoreReducer` verifies that order during compensation. A new `RemoveReducer` should mirror the proven pure preview/cancel/confirm shape, while the sole `NativeBranchAuthority` owns retry, CAS, activation, recovery, and later restore. [VERIFIED: Master Spec §§9-11; `TransactionModels.swift`, `EditProjection.swift`, `RestoreReducer.swift`, ADR-012]

The evidence half cannot be completed from automation. A `ready` CON-004 reveal bundle requires thresholded coverage/foreground/order values and exactly five human votes; the repository contains no real reveal payload, physical trajectory evidence, or ballot. The sprint cut therefore authorizes only a bounded demonstration and explicitly keeps `GATE-006` pending. The safest implementation is an unmistakable development/demo launch mode using deterministic local multi-surface proxy geometry, `degraded` status, exact digest binding, and persistent pending-gate copy. The ordinary path remains remove-unavailable. [VERIFIED: `edit-artifacts.schema.json`, ADR-009, Test Plan `TST-REVEAL-001`, `.planning/SPRINT-CUT-36H.md`]

This split prevents the demo from laundering fixture values into a release claim: the exact transaction can be committed, recovered, replayed, retried, and restored in the explicitly isolated demo path, but neither `FR-REMOVE-001` nor `GATE-006` is checked off. [VERIFIED: approved sprint overlay and Phase 6 context]

**Primary recommendation:** Implement RemoveReducer -> authority/store/restart/restore -> explicit degraded two-surface demo fixture/UI -> fail-closed evidence, with normal remove readiness and all physical/human gates unchanged.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Remove validation and ordered deltas | Deterministic transaction core | Frozen transaction contract types | Pure code owns target, world, envelope, artifact reference, order, projection diff, and inverse. [VERIFIED: Master Spec §11] |
| CAS/idempotency/durable publication | Native branch authority actor | Transaction store | Existing sole-writer/pointer-last machinery prevents duplicate or partially visible commits. [VERIFIED: ADR-012; `TransactionAuthority.swift`, `TransactionStore.swift`] |
| Demo fixture policy | App model, explicit development mode | Pure candidate values | Launch mode and camera/target snapshots select the degraded fixture; UI/render code cannot authorize a normal remove. [VERIFIED: Phase 4 architecture; context decision] |
| Bounded camera-pose decision | Shared AR session/app model | Pure pose-envelope helper | The existing session exposes current AR camera pose; deterministic code compares it to the frozen seed without a second AR authority. [VERIFIED: `ARSessionController.swift`, `RoomEditModel.swift`] |
| Reveal proxy rendering | Existing retained RealityKit `ARView` | SwiftUI coaching/banner | Retained local layers render after camera and before later overlays; no command-time I/O is needed. [VERIFIED: compositor descriptor and Master Spec §6] |
| Formal removal readiness | Physical evidence plus five evaluators | CON-004/gate report validation | Automation cannot create observed coverage, foreground safety, or blinded human votes. [VERIFIED: ADR-009, `GATE-006`, artifact schema] |

## Project Constraints (from AGENTS.md)

- Preserve exactly four product operations, stable IDs, native ARKit authority, camera-as-background, independent readiness, exact revisions/idempotency, immutable history, and captured-exact restore. [VERIFIED: `AGENTS.md`, canonical README]
- Use contract-first TDD and regression tests; validate every untrusted boundary fail-closed before mutation. [VERIFIED: `AGENTS.md`]
- The 60 Hz path cannot wait on network, model, worker, web, filesystem, or transaction persistence; queues/state updates remain bounded/coarsened. [VERIFIED: `AGENTS.md`, NFR-RENDER-001]
- Preserve dirty Xcode/signing/workspace files, avoid dependency/project-file edits, use `apply_patch`, and keep commits scoped. [VERIFIED: `AGENTS.md`, current `git status --short`]
- Never fabricate room data, physical traces, human votes, signing results, measurements, or provider evidence; keep `TARGET`, `HYPOTHESIS`, and `MEASURED` labels exact. [VERIFIED: `AGENTS.md`, canonical evidence discipline]

## Existing Code Inventory

| Seam | Current behavior | Phase 6 consequence |
|------|------------------|---------------------|
| `TransactionOperation` | Models `set_reveal_bundle`, `set_object_visibility`, and `restore_snapshot` with typed `ArtifactReference` values. [VERIFIED: `TransactionModels.swift`] | Add no transaction-contract type; construct existing operations. |
| `EditProjectionEngine` | Requires active reveal only on a hidden object, validates reveal artifact refs, admits exact remove order, diffs touched IDs, and computes required artifact unions. [VERIFIED: `EditProjection.swift`] | Reuse for preview and confirmation replay; do not write a second diff engine. |
| `RestoreReducer` | Accepts only reveal-then-visibility for remove and replays both touched fields before compensation. [VERIFIED: `RestoreReducer.swift:300-405`] | Add remove -> restore tests; do not change restore semantics unless a regression is exposed. |
| `ReplaceReducer` | Pure preview/cancel/confirm, current-target checks, deterministic candidate, exact projection inverse, zero network reads. [VERIFIED: commit `300931f`, `ReplaceReducer.swift`] | Copy lifecycle structure, not replace semantics. Remove has no asset/support creation. |
| `NativeBranchAuthority` | At the research revision, place owns the complete authority path; Phase 5 plans add replace next. [VERIFIED: current source and Phase 5 plans] | Phase 6 depends on completed Phase 5 authority consolidation and extends the same private commit/activation pattern. |
| `TargetGroundingSnapshot` | Stable target/current epoch exists; remove is always unavailable with `reveal_quality_failed`. [VERIFIED: `RoomEditModel.swift`] | Preserve this normal state and derive a separate launch-gated demo capability. |
| Shared AR session | Exposes current AR camera transform and one retained `ARView` session. [VERIFIED: `ARSessionController.swift`, `RoomEditModel.swift`] | Pose-bound demo evaluation needs no new session/provider. |
| Compositor descriptor | Locks camera -> reveal -> occluder -> asset/proxy -> debug -> SwiftUI; reveal and occluder are currently unavailable. [VERIFIED: `RoomEditModel.swift:103-143`] | Activate only demo reveal layers; keep real occluder unavailable and visible in diagnostics. |
| Reveal resources/evidence | No tracked reveal payload or valid physical `GATE-006` evidence exists. [VERIFIED: repository `rg`/file inventory] | Create only clearly named local demo fixture resources/metadata; no ready CON-004 artifact or gate report. |

## Standard Stack

| Framework/module | Version boundary | Purpose | Why this stack |
|------------------|------------------|---------|----------------|
| Swift | Package tools 6.1, Swift 6 mode; installed compiler 6.3 | Pure reducers, immutable snapshots, actor authority | Existing project mode and source patterns. [VERIFIED: `Package.swift`, `swift --version`] |
| ReRoomTransactionCore | Repository source | Remove delta, projection, fingerprint, store, restore | Already owns authoritative Phase 3/5 transaction invariants. [VERIFIED: package source/tests] |
| Swift Testing | Existing package/app unit targets | Reducer/authority/recovery/pose policy tests | Current unit-test convention; use isolated temp stores and `#require` prerequisites. [VERIFIED: existing tests and project skill] |
| XCTest UI | Existing Xcode UI target | Explicit demo-mode remove/retry/restore journey | UI automation remains XCTest-only. [VERIFIED: `RoomEditJourneyTests.swift`, project skill] |
| ARKit + RealityKit + SwiftUI | Xcode 26.4 system SDK | Shared camera pose, retained local reveal planes, accessible controls | Existing system frameworks; no package/install needed. [VERIFIED: source, `xcodebuild -version`] |

**Installation:** none. Add no package, plugin, provider, service, credential, runtime converter, or generated Xcode project entry. [VERIFIED: context and AGENTS constraints]

## Package Legitimacy Audit

Not applicable: the phase installs no package. The inherited exact `swift-json-schema` dependency remains unchanged and the proposed demo fixture is repository-owned data/code. [VERIFIED: `Package.swift`, context]

## Architecture Patterns

### System data flow

```text
normal launch ------------------------------------> remove unavailable / coach

explicit demo-fixture launch + manual target + current camera pose
                              |
                              v
                 pure bounded-pose policy
                    | outside/stale -> reject; original stays visible
                    v inside
typed/tap Remove -> RemoveReducer.preview (pure, revision r)
                    | exact operations:
                    | 1. set_reveal_bundle
                    | 2. set_object_visibility true -> false
                    v
              explicit native Confirm
                    v
 NativeBranchAuthority: idempotency -> replay reduction -> durable activation
                    |
           canonical demo scene r+1 + pinned demo artifact ref
              /                                  \
 retained RealityKit reveal surfaces       captured-exact inverse
                                                     |
                                      RestoreReducer compensation r+2
```

The launch-mode boundary is part of safety, not merely UI copy: normal runtime must have no candidate capable of passing the demo validator. [VERIFIED: locked context]

### Recommended project structure

```text
ios/Packages/ReRoomContracts/
├── Sources/ReRoomTransactionCore/RemoveReducer.swift
└── Tests/ReRoomTransactionCoreTests/
    ├── RemoveReducerTests.swift
    └── TransactionAuthorityTests.swift        # remove retry/recovery/restore

ios/ReRoomDeviceProof/
├── ReRoomDeviceProof/RoomEditModel.swift       # demo-mode policy + operation flow
├── ReRoomDeviceProof/RoomEditView.swift        # retained reveal layers + banner/coaching
├── ReRoomDeviceProof/Resources/Phase6DemoReveal/  # exact local fixture bytes/digests
├── ReRoomDeviceProofTests/RoomEditModelTests.swift
└── ReRoomDeviceProofUITests/RoomEditJourneyTests.swift

scripts/verify-phase-06-removal
tools/verify/tests/test_phase_06_removal.py
evidence/removal/phase-06/automated-preflight.json
```

Prefer extending already synchronized app sources/resources so the user's `.pbxproj` stays untouched; verify resource discovery by a build before relying on it. [VERIFIED: Phase 3-5 repository pattern; MEDIUM confidence for new resource discovery]

### Pattern 1: Pure reveal-first remove reducer

Validate the complete proposal/candidate and current scene before building a provisional scene. Use exactly one reveal ref throughout the operation, projection, local artifact set, transaction, renderer snapshot, and persisted inverse. [VERIFIED: Master Spec §11, transaction schema]

```swift
let operations: [TransactionOperation] = [
    .setRevealBundle(
        entityID: targetID,
        before: target.editState.activeReveal,
        after: candidate.revealReference,
        requiredArtifactRefs: [candidate.revealReference]
    ),
    .setObjectVisibility(
        entityID: targetID,
        before: .init(contractVisible: true),
        after: .init(contractVisible: false),
        requiredArtifactRefs: []
    ),
]
```

Source: exact canonical remove order plus existing `TransactionOperation` cases. [VERIFIED: Master Spec §11, `TransactionModels.swift`]

### Pattern 2: Demo policy is a closed authority input

The typed intent carries no artifact ID, target ID, pass boolean, pose, or threshold. Deterministic app code constructs a candidate only when explicit demo launch mode, current target/world/revision, local resource digest, and pose bound all match. The reducer accepts only the exact demo policy label and validator version; arbitrary caller strings fail. [VERIFIED: ADR-011, existing Place/Replace candidate pattern]

### Pattern 3: Bound pose without claiming measurement

Use a pure helper that compares current and frozen camera transforms against fixed conservative translation/rotation bounds. Store the bounds as `HYPOTHESIS` demo constants and include them in the candidate fingerprint/evidence. Do not name the result `measured_supported_view_envelope`; use `deterministic_demo_pose_bound`. [VERIFIED: evidence discipline; current camera/frozen pose availability]

### Pattern 4: Safe publication and render derivation

Preview may render only a clearly provisional demo reveal while canonical target visibility remains true. Committed reveal/hidden-original state becomes authoritative only after durable store activation. Any load/hash/pose/authority failure retains the last safe state. The RealityKit coordinator owns retained reveal entities; update callbacks apply only immutable transforms/visibility. [VERIFIED: ADR-012, Phase 4 renderer pattern]

### Pattern 5: Exact remove -> restore projection

The remove inverse's `before` snapshot is the committed projection with the reveal ref active and target hidden; `after` is the exact pre-remove projection. Its required artifact union is computed for the after projection, normally excluding the demo reveal after restoration. Restore rebase verifies touched IDs and preserves unrelated objects/state. [VERIFIED: RR-EDIT-PROJECTION-1 and RR-RESTORE-REBASE-1; `RestoreReducer.swift`]

### Anti-patterns to avoid

- **Renderer-only disappearance:** leaves canonical object visible and produces nothing replayable/restorable. [VERIFIED: Master Spec §§9-11]
- **Visibility before reveal:** can expose a hole/real target and violates the closed transaction order. [VERIFIED: transaction schema]
- **Normal readiness promoted to degraded demo pass:** leaks the demo fallback into ordinary runtime. Require the explicit launch-mode policy in both app and reducer. [VERIFIED: context]
- **Synthetic gate metrics or ballot:** even plausible fixture values can be mistaken for evidence; do not emit them as observations. [VERIFIED: AGENTS evidence discipline]
- **One oversized plane called multi-surface:** violates the demo's own label; retain at least two surface entities and describe them as proxies. [VERIFIED: context]
- **Filesystem/store work in `updateUIView`:** risks high-rate stalls; preload once and pass snapshots. [VERIFIED: NFR-RENDER-001, SwiftUI skill]
- **A second ARSession for pose checks:** creates competing world authority. [VERIFIED: ADR-003/Phase 4 architecture]

## Don't Hand-Roll

| Problem | Don't build | Use instead | Why |
|---------|-------------|-------------|-----|
| Operation order/touched coverage | Another diff/order implementation | `EditProjectionEngine.diff/verify/apply` | Already enforces the closed remove order and stable projection. [VERIFIED: source] |
| Request fingerprint/idempotency | View booleans or ad hoc hash strings | `TransactionFingerprint` plus `NativeBranchAuthority` records | Existing same-key/same-body semantics survive restart. [VERIFIED: source/ADR-012] |
| Restore | Toggle visibility/remove reveal in the renderer | Captured-exact `restore_snapshot` and `RestoreReducer` | Preserves immutable history and unrelated current state. [VERIFIED: source/ADR-012] |
| Camera authority | New session/pose manager | Existing shared session/current frame | Maintains one world epoch and one retained ARView. [VERIFIED: Phase 4] |
| Gate report | Local JSON that resembles physical evidence | Existing evidence schemas only when real device/evaluator inputs exist | Prevents fabricated measurements/votes. [VERIFIED: evidence discipline] |
| Runtime texture/provider pipeline | New network/model/conversion stack | Tiny repository-owned deterministic demo geometry/material | Sprint path remains bounded and dependency-free. [VERIFIED: sprint cut/context] |

## Common Pitfalls

### Pitfall 1: Active reveal becomes valid while object is still visible
**What goes wrong:** the provisional projection violates the scene invariant, or ordering is hidden inside one renderer update.
**How to avoid:** build both operations, derive the final provisional projection, and verify the exact list atomically before publishing preview. [VERIFIED: scene-state schema, projection engine]

### Pitfall 2: Demo mode is only cosmetic
**What goes wrong:** tests or callers invoke the degraded validator during normal launch.
**How to avoid:** make demo mode a closed candidate field/factory capability, include it in fingerprints, and add negative tests proving normal launch cannot construct or commit it. [VERIFIED: context]

### Pitfall 3: Restore cannot find the reveal artifact after restart
**What goes wrong:** store activation persisted the transaction but not the exact required artifact/reference set.
**How to avoid:** stage the local fixture reference/bytes with the generation, activate pointer-last, reopen the store, replay, then restore without network reads. [VERIFIED: ADR-012 and store architecture]

### Pitfall 4: Out-of-envelope transition occurs after preview
**What goes wrong:** confirmation reuses a stale in-envelope boolean and hides the target.
**How to avoid:** replay the reducer against a fresh immutable candidate captured from current pose/revision, or invalidate/cancel preview whenever pose policy becomes false; confirmation equality must fail. [VERIFIED: reducer replay pattern]

### Pitfall 5: Product copy overclaims the fixture
**What goes wrong:** screenshots say “remove ready” or “validated reveal” while formal evidence is absent.
**How to avoid:** persistent demo/pending banner, normal readiness unchanged, verifier scans forbidden claim strings and requires all gates PENDING. [VERIFIED: sprint cut]

### Pitfall 6: Phase 6 races unfinished Phase 5 authority work
**What goes wrong:** two plans independently refactor `NativeBranchAuthority`/`RoomEditModel`, causing duplicate pathways or conflicts.
**How to avoid:** Phase 6 begins only after Phase 5 summaries/tests are present; extend the consolidated API and rebase plan details to actual source before editing. [VERIFIED: roadmap dependency and current Phase 5 execution state]

## Code Examples

### Preserve normal remove-unavailable state

```swift
let normalRemoveReadiness: TargetReadinessValue = .unavailable
let normalRemoveReasons: [TargetReadinessReasonCode] = [.revealQualityFailed]

guard environment.explicitDemoRevealFixtureEnabled else {
    return .unavailable(normalRemoveReasons)
}
```

Source: existing target readiness plus locked demo boundary. [VERIFIED: `RoomEditModel.swift`, context]

### Fail closed on stale pose candidate

```swift
guard candidate.capturedSceneRevision == scene.sceneRevision,
      candidate.worldFrameID == scene.worldFrame.worldFrameID,
      candidate.worldFrameVersion == scene.worldFrame.worldFrameVersion,
      candidate.insideDeterministicDemoPoseBound
else { throw RemoveRejection.unsupportedOrStaleView }
```

Source: established ReplaceReducer context validation adapted to remove-specific pose policy. [VERIFIED: `ReplaceReducer.swift`, context]

## State of the Art

No external library or provider decision is needed. The phase deliberately uses the repository's existing transaction core and Apple system frameworks; provider research would broaden scope and contradict the sprint fallback. [VERIFIED: context]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| — | None. Implementation claims are grounded in canonical documents/current source. Demo visual quality is explicitly unmeasured rather than assumed. | — | — |

## Open Questions

All implementation-shaping questions were resolved in `06-CONTEXT.md`:

1. Normal remove remains unavailable until real `GATE-006` evidence exists.
2. No synthetic coverage or vote values are emitted as evidence.
3. The demo uses at least two retained proxy surfaces and never calls itself observed/validated removal.
4. Failure retains/restores safe original content; post-commit return uses exact compensation.
5. Sprint completion does not close `FR-REMOVE-001` or `GATE-006`.

The only intentionally unresolved outcome is physical visual quality; by authority it can be answered only by the deferred device/evaluator campaign. [VERIFIED: ADR-009]

## Validation Note

`.planning/config.json` explicitly sets `workflow.nyquist_validation` to `false`, so the formal GSD Validation Architecture section is omitted. Plans must still use repository-mandated TDD and focused Swift/UI/verifier checks. Security enforcement is also explicitly false; normal input validation, artifact integrity, and fail-closed authority boundaries remain required by AGENTS/canonical contracts. [VERIFIED: config and AGENTS]

## Sources

### Primary (HIGH confidence)
- `docs/canonical/README.md` and `AGENTS.md` - authority, product invariants, evidence discipline.
- `docs/canonical/MASTER_TECHNICAL_SPEC.md` §§6, 8-11 - compositor, reveal readiness, exact remove order, inverse.
- `docs/adr/ADR-005-realitykit-first-compositor.md` - renderer boundary and physical gate.
- `docs/adr/ADR-009-multi-surface-reveal.md` - reveal bundle, supported envelope, `GATE-006`, fallback.
- `docs/adr/ADR-012-transaction-and-offline-restore.md` - CAS, idempotency, durable activation, compensation.
- `docs/contracts/edit-artifacts.schema.json`, `transaction.schema.json`, `scene-state.schema.json` - field/order/readiness invariants.
- Current Swift source under `ReRoomTransactionCore` and `ReRoomDeviceProof` - reusable implementation seams.
- `.planning/SPRINT-CUT-36H.md` and Phase 5 artifacts - authorized sprint boundary and dependency state.

### Secondary (MEDIUM confidence)
- None. No external ecosystem assertion is load-bearing for this codebase-only phase.

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - versions and frameworks were read from the local project/toolchain.
- Transaction architecture: HIGH - exact contracts and implemented reducers/store/restore were inspected.
- Demo compositor implementation: HIGH for boundaries/order, MEDIUM for appearance - physical quality is deliberately not claimed or measured.
- Gate outcome: HIGH that it remains PENDING - required observations/votes are absent and explicitly deferred.

**Research date:** 2026-07-18
**Valid until:** 2026-08-17 for canonical architecture; re-check source after Phase 5 execution before planning implementation details.
