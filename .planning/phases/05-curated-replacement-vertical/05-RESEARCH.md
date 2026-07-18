# Phase 5: Curated Replacement Vertical - Research

**Researched:** 2026-07-18
**Domain:** Deterministic Swift replace transactions, bounded native composition, and honest demo-asset qualification
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Exact replace transaction
- Add a dedicated contract-first replace reducer rather than routing replace through place or presentation-only state.
- Use the canonical no-reveal replace order for the activated sprint fallback: `set_object_visibility`, then `create_asset_instance`. The original object changes `visible=true` to `false`; the replacement asset and support relation are created last and atomically in the pending scene.
- Do not invent an observed underlay or reveal bundle. The optional `set_reveal_bundle` variant remains unavailable until validated reveal evidence exists.
- Preview and cancel change no revision. Explicit confirmation performs the sole CAS `r -> r+1`; same-key/same-fingerprint retry returns the original receipt, while a changed fingerprint, stale base, wrong authority/world, target mismatch, or failed validation rejects without mutation.
- Persist one captured-exact RR-EDIT-PROJECTION-1 `restore_snapshot` inverse from committed content back to the exact pre-replace edit projection. Restore remains a new compensating transaction and never rewrites history.

#### Target, support, and supported-view policy
- Bind replacement to the stable manually selected `object_*` identity and current world-frame epoch from Phase 4. Renderer or AR anchor indices never authorize the edit.
- Require a tracked, visible target, replace capability readiness, current support evidence, a locally available allowlisted asset artifact, collision pass, license/provenance pass, and artifact-integrity pass.
- Represent the sprint supported-view decision as deterministic local fixture state captured with the frozen manual proxy. It is a demo constraint, not a measured mask volume, OBB, or production view envelope.
- If tracking, target identity, support, asset evidence, or supported-view state becomes stale, freeze the last safe committed display and disable commit with actionable coaching. Never expose a newly hidden original from a failed or partial replace.

#### Demo asset and compositor behavior
- Use only the repository-owned six-cube `proxy-chair.usda` already bundled with provenance. Record its exact digest, dimensions/origin/axis assumptions needed by deterministic local checks, and project-owned provenance without asserting a third-party license.
- Keep the artifact labeled `phase3_local_demo_proxy_only` (or an equally explicit successor label). Do not describe its USDA file as a validated USDZ/GLB pair or full CON-004 catalog manifest.
- Render the replacement proxy over the live camera using the existing one-session RealityKit path. The sprint fallback places the asset in front of/conservatively over the controlled original and does not claim empty removal or a validated reveal.
- Add no network fetch, runtime conversion, learned provider, cloud service, third-party dependency, or second AR session. Avoid Xcode project-file edits.

#### Evidence and claims
- Automate exact reducer order, before/after matching, target/capability/view/support/asset rejection, preview/cancel immutability, idempotent retry, crash/recovery replay, restore, and deterministic UI journey checks.
- Run repeated automated development journeys where practical, but label them automated fixture runs. They do not substitute for five signed-device golden runs or human seam assessment.
- Keep `GATE-011` `PENDING`. Native/web derivative parity, device/web load, redistribution/attribution review, and shipping bill-of-materials audit remain deferred by `.planning/SPRINT-CUT-36H.md`.
- Keep related physical `GATE-003`, `GATE-005`, `GATE-009`, and `OPS-GOLDEN-001` evidence pending. Report only implemented behavior and checks actually observed.

### the agent's Discretion
- Choose the smallest Swift type names, candidate/preview seeds, validation helpers, UI labels, test fixtures, and verification-script structure that preserve the decisions above.
- Reuse Phase 3 transaction/store patterns and Phase 4 target/compositor seams. Prefer new package sources and automatically discovered app sources so the user's existing signing/project changes remain untouched.
- Keep the demo legible: select/reseed target, choose Replace, preview, confirm, show one revision, retry safely, then Restore.

### Deferred Ideas (OUT OF SCOPE)
- Full USDZ/GLB derivative generation and parity, shipping license/attribution audit, device/web asset-load proof, catalog expansion, runtime conversion, and remote asset delivery remain deferred under `GATE-011`.
- Measured mask volume/OBB/view envelope, semantic tracking, dense geometry, reveal underlay, blinded seam votes, and physical-device golden runs remain pending under their canonical gates.
- Empty multi-surface removal remains Phase 6. Separate provider-independent Mode B0 replay remains Phase 7.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| `FR-REPLACE-001` | Replace the selected hero target with a curated asset while masking the original only within supported observations. | The existing operation types, projection engine, restore reducer, durable branch authority, manual target context, and one-session renderer already provide every seam except a dedicated replace reducer, a canonical controlled object, and replacement-specific native state. [VERIFIED: `docs/canonical/PRD.md`, transaction core, and Phase 4 source] |
</phase_requirements>

## Summary

Implement Phase 5 as one extension of the proven Phase 3 transaction architecture: a pure `ReplaceReducer` mirrors the place preview/cancel/confirm lifecycle but emits exactly `set_object_visibility` followed by `create_asset_instance`; `NativeBranchAuthority` performs idempotency lookup, captured-exact inverse construction, durable pointer-last activation, and publication; `RestoreReducer` already recognizes this replace order. The reducer must validate the selected stable target, its visible canonical edit state, current support/world/revision, explicit degraded demo readiness, local supported-view fixture, and demo-asset qualification before it creates any pending scene. [VERIFIED: Master Spec §§9–11, ADR-012, `PlaceReducer.swift`, `EditProjection.swift`, `RestoreReducer.swift`, `TransactionAuthority.swift`]

The one material integration gap is canonical target presence. Phase 4 retains the grounded target in `TargetGroundingSnapshot`, while `RoomEditFactory.bootstrap` currently creates `SceneState.objects: []`; `PlaceReducer.validateContext` therefore tolerates only nil selection, and a conforming replace reducer cannot pass `target_exists` until the controlled `RoomEditIdentity.targetObjectID` also exists in the canonical scene. For the sprint, seed that one controlled, visible, tracked scene object in a versioned Phase 5 store/bootstrap and bind manual selection to the same ID. Do not treat an older recovered Phase 3 generation with no object as replace-ready. [VERIFIED: `RoomEditModel.swift:235-254`, `RoomEditModel.swift:1326-1363`, `TransactionModels.swift`]

The bundled USDA is sufficient only for an honest local demo qualification: exact source hash, project-authored six-cube recipe, metres/Y-up/floor-contact assumptions, local availability, and no command-time network. It is not a full CON-004 asset manifest, validated USDZ/GLB derivative pair, shipping-license decision, or `GATE-011` pass. Replacement may use it only with persistent UI/evidence wording such as “local demo proxy” and `GATE-011 PENDING`. [VERIFIED: `Resources/Phase3Proxy/PROVENANCE.md`, `asset-manifest.json`, `proxy-chair.usda`, ADR-010, sprint cut]

**Primary recommendation:** Build reducer → authority/store/restart/restore → native supported-view journey → fail-closed evidence, reusing the existing package and app files with no dependency, cloud, provider, Xcode project, or contract-schema change.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Replace validation and ordered deltas | Deterministic transaction core | Frozen CON-005 types | Pure code owns target, support, capability, asset, and exact operation order. [VERIFIED: Master Spec §11] |
| CAS, idempotency, local durability | Native branch authority actor | Transaction store | The existing single mutable owner already prevents reentrant/interleaved commits and activates generations pointer-last. [VERIFIED: `TransactionAuthority.swift`, `TransactionStore.swift`] |
| Target and supported-view input | Native app model | Phase 4 target reducer | App state captures the manual target/view fixture; it supplies immutable deterministic candidate values but cannot commit. [VERIFIED: Phase 4 source/context] |
| Camera and replacement rendering | Existing RealityKit `ARView` | SwiftUI status/actions | One retained session renders local entities; SwiftUI consumes coarsened snapshots and provides explicit confirmation. [VERIFIED: `RoomEditView.swift`, `ARSessionController.swift`] |
| Demo asset qualification | Bundled resource loader | Reducer candidate | The loader verifies local bytes/provenance; the reducer consumes only checked policy output. [VERIFIED: `Phase3ProxyManifest.load`, `PlaceReducer.ProxyAssetCandidate`] |
| Formal gate decision | Verification evidence | Human/device campaign | Automation may prove functional invariants but cannot supply derivative parity, device/web loading, redistribution review, or physical seam votes. [VERIFIED: `GATE-011`, sprint cut] |

## Project Constraints (from AGENTS.md)

- Preserve the human-locked four operations, native SwiftUI Mode A, ARKit world authority, live-camera background, stable prefixed IDs, capability-specific readiness, exact transaction semantics, and offline restore. [VERIFIED: `AGENTS.md`, canonical README]
- Build contract-first vertical slices with TDD for behavior-bearing Swift and regression tests for fixed bugs; validate untrusted boundary input and fail closed before mutation. [VERIFIED: `AGENTS.md`]
- The render loop cannot wait on network, model, worker, web client, filesystem, or transaction actor; high-rate state must remain bounded/coarsened. [VERIFIED: `AGENTS.md`, NFR-RENDER-001]
- Preserve the user's dirty Xcode signing/project/workspace files, use `apply_patch`, avoid unrelated refactors, and commit only scoped files. [VERIFIED: `AGENTS.md`, current `git status --short`]
- Never fabricate signed-device, human visual, license, parity, or measured evidence; keep TARGET/HYPOTHESIS/MEASURED language exact. [VERIFIED: `AGENTS.md`, Test and Evaluation Plan]

## Existing Code Inventory

| Seam | Current behavior | Phase 5 consequence |
|------|------------------|---------------------|
| `TransactionOperation` | Already models visibility, asset creation, reveal, transform, and restore snapshot variants. [VERIFIED: `TransactionModels.swift`] | Add no contract type; construct existing typed operations. |
| `EditProjectionEngine` | Builds sorted edit projections, validates allowed delta orders, diffs touched IDs, verifies operation coverage, applies projections, and derives required artifact union. [VERIFIED: `EditProjection.swift`] | Reuse it before preview publication and again during confirm replay. |
| `PlaceReducer` | Defines deterministic asset/support candidate, preview seed, exact checks, cancel replay, confirm, and captured-exact inverse. [VERIFIED: `PlaceReducer.swift`] | Mirror its lifecycle but do not route replace through place. |
| `NativeBranchAuthority` | Owns same-key replay, changed-fingerprint conflict, divergence freeze, undo-token check, durable activation, restore, and restart recovery. [VERIFIED: `TransactionAuthority.swift`] | Add `previewReplace`/`commitReplace`; share private commit construction/activation. |
| `RestoreReducer` | Accepts both canonical replace orders and replays touched visibility/asset/support state before captured-exact compensation. [VERIFIED: `RestoreReducer.swift:303-370,386-406`] | Add replace/restart/restore fixtures; no new restore algorithm. |
| `TargetGroundingSnapshot` | Produces stable selected object/current epoch only under healthy tracking; replace is currently `degraded` with `providerUnavailable`. [VERIFIED: `RoomEditModel.swift:235-254,374-443`] | Replace demo policy may consume degraded fallback only when all explicit local checks pass. |
| `RoomEditFactory.bootstrap` | Seeds one floor surface but zero scene objects. [VERIFIED: `RoomEditModel.swift:1326-1363`] | Seed the canonical controlled object before replace is enabled; fail closed for incompatible old store state. |
| Render snapshot | Holds one proxy and prioritizes the grounded target over placed content; live rendering currently generates one translucent box. [VERIFIED: `RoomEditModel.swift:447-510`, `RoomEditView.swift:417-447`] | Represent target coverage and replacement separately, make committed replacement opaque/visible, and retain last safe state on rejection. |
| Demo resource | USDA is six cubes with `metersPerUnit=1`, Y-up, exact source SHA, and project-owned demo provenance. [VERIFIED: resource files] | Preload/validate once outside the high-rate update path; no runtime conversion/network. |

## Standard Stack

| Framework/module | Version boundary | Purpose | Why this stack |
|------------------|------------------|---------|----------------|
| Swift | Package tools 6.1, Swift language mode 6; installed compiler 6.3 | Pure reducers, value snapshots, actor authority | Existing pinned project mode; no migration required. [VERIFIED: `Package.swift`, `swift --version`] |
| ReRoomTransactionCore | Repository source | Exact deltas, projections, fingerprints, durable authority, restore | Already implements the authoritative Phase 3 invariants. [VERIFIED: package source/tests] |
| Swift Testing | Existing package test target | Reducer/authority/store/recovery tests | Current unit-test convention; parallel-safe isolated stores. [VERIFIED: package tests and project skill] |
| XCTest UI | Existing Xcode UI target | One deterministic replace/retry/restore journey | UI automation remains the supported XCTest-only layer. [VERIFIED: existing UI tests and project skill] |
| ARKit + RealityKit + SwiftUI | Xcode 26.4 system SDK | One-session live camera, retained local replacement entity, accessible controls | Existing linked Apple frameworks and retained session graph. [VERIFIED: source, `xcodebuild -version`] |

**Installation:** none. Add no package, product dependency, runtime service, credential, or generated project file. [VERIFIED: locked context]

## Package Legitimacy Audit

Not applicable: Phase 5 installs no external package. The existing exact `swift-json-schema` dependency is inherited and unchanged; the demo USDA is repository-authored data, not a downloaded package. [VERIFIED: `Package.swift`, proxy provenance]

## Architecture Patterns

### System data flow

```text
manual target + current world/revision + local supported-view fixture
                              |
typed/tap Replace(asset_id) --+--> ReplaceReducer.preview (pure)
                                    | reject: no mutation / actionable blocker
                                    v
                      exact visibility -> asset-create projection
                                    |
                         immutable preview at revision r
                                    |
                       native explicit Confirm button
                                    v
 NativeBranchAuthority: idempotency -> replay reduction -> persist generation
                                    |
                    publish canonical scene r+1 only after activation
                         /                              \
           RealityKit replacement snapshot       captured-exact inverse
                                                          |
                                             RestoreReducer compensation r+2
```

This keeps user/model input nonmutating, reducer logic deterministic, and render state downstream of durable canonical activation. [VERIFIED: ADR-011, ADR-012, existing Phase 3 architecture]

### Recommended project structure

```text
ios/Packages/ReRoomContracts/
├── Sources/ReRoomTransactionCore/ReplaceReducer.swift
└── Tests/ReRoomTransactionCoreTests/
    ├── ReplaceReducerTests.swift
    └── TransactionAuthorityTests.swift      # replace retry/restart/restore additions

ios/ReRoomDeviceProof/
├── ReRoomDeviceProof/RoomEditModel.swift    # canonical target seed + app flow/snapshots
├── ReRoomDeviceProof/RoomEditView.swift     # replacement entity + coaching/actions
├── ReRoomDeviceProofTests/RoomEditModelTests.swift
└── ReRoomDeviceProofUITests/RoomEditJourneyTests.swift

scripts/verify-phase-05-replacement
tools/verify/tests/test_phase_05_replacement.py
evidence/replacement/phase-05/automated-preflight.json
```

SwiftPM and the Xcode app's synchronized source groups discover these paths without editing the user's `.pbxproj`; verify this assumption with compilation before committing. [VERIFIED: Phase 3/4 file-discovery pattern; MEDIUM confidence for any newly added app file, so prefer extending current app files]

### Pattern 1: Replayable pure replace reducer

Validate the complete immutable proposal/candidate against the current scene, then derive the provisional scene and verify its touched-ID set against the ordered operations before returning a preview. On confirm, replay `preview(...)` and require structural equality before creating `r+1`. [VERIFIED: `PlaceReducer.preview/cancel/confirm`]

The minimum no-reveal operation sequence is:

```swift
[
    .setObjectVisibility(
        entityID: selectedObjectID,
        before: .init(visible: true),
        after: .init(visible: false),
        requiredArtifactRefs: []
    ),
    .createAssetInstance(
        entityID: replacementInstanceID,
        before: nil,
        after: replacementSnapshot,
        requiredArtifactRefs: [manifestArtifactRef]
    )
]
```

Source: canonical Master Spec replace row and existing `TransactionOperation` model. No reveal operation is legal in this sprint candidate. [VERIFIED: `MASTER_TECHNICAL_SPEC.md:244-253`, `EditProjection.validateOperationOrder`]

### Pattern 2: Candidate values are policy outputs, not intent bytes

Define a deterministic candidate containing asset qualification, current support, selected target ID, capability verdict, and supported-view fixture identity. `TransactionIntent.arguments.asset_id` may select only the allowlisted demo asset; it cannot supply target IDs, transforms, support IDs, readiness, view verdicts, or pass booleans. [VERIFIED: ADR-011, existing `ProxyAssetCandidate`/`DeterministicSupportCandidate`, transaction schema]

Validation should include the canonical required checks (`scene_revision`, `artifact_integrity`, `target_exists`, `capability_ready`, `support`, `collision_proxy`, `asset_license`) plus `view_envelope` as the closed contract ID for the explicit local supported-view decision. The report must label the latter a deterministic demo fixture, not MEASURED geometry. [VERIFIED: `transaction.schema.json:198-204,690-699`; locked context]

### Pattern 3: Durable publication before visible replacement

The app may show a provisional replacement while the original remains canonically visible, but a committed replacement snapshot becomes authoritative only after `TransactionStore.activate` succeeds and `NativeBranchAuthority.active` changes. An error leaves the prior safe render snapshot and revision intact. [VERIFIED: ADR-012, existing authority activation]

### Pattern 4: Versioned bootstrap compatibility

Use the same `RoomEditIdentity.targetObjectID` in both `SceneState.objects` and `TargetGroundingSnapshot`. For this sprint, initialize a new versioned Phase 5 local store containing the controlled visible object; do not silently recover a Phase 3 generation with no canonical object and synthesize `target_exists=true`. Persistence/restart tests must reopen that Phase 5 store without resetting it. [VERIFIED: current empty bootstrap/recovery behavior; recommended implementation derived from locked fail-closed target policy]

### Pattern 5: Retained asset entity outside the hot path

Validate/read the bundled resource once during runtime setup or first bounded preview preparation, retain the loaded entity/prototype, and let `updateUIView` only apply immutable transform/visibility/material state. A load/hash failure sets asset readiness unavailable and prevents preview/commit; do not substitute a remote asset or runtime conversion. [VERIFIED: NFR-RENDER-001, Phase 4 snapshot-diff renderer, locked context]

### Anti-patterns to avoid

- **Replace-through-place:** misses canonical object visibility and produces the wrong touched IDs/inverse. [VERIFIED: Master Spec replace row]
- **Presentation-only hiding:** renderer flags do not mutate `object.edit_state.visible` and cannot replay/restore. [VERIFIED: Master Spec §8]
- **Commit then persist:** can expose a hidden original/asset without durable inverse. [VERIFIED: ADR-012]
- **Target only in app state:** makes `target_exists` unverifiable by the transaction core. [VERIFIED: current integration gap]
- **Empty replace arguments:** CON-005 replace requires an asset selector; set the allowlisted `asset_id`. [VERIFIED: transaction schema `assetIntentArguments`]
- **Claiming the USDA is USDZ or a full asset manifest:** conflicts with provenance and deferred `GATE-011`. [VERIFIED: resource provenance, sprint cut]
- **Loading/parsing asset bytes from every SwiftUI/RealityKit update:** violates the coarsened render boundary and risks main-thread stalls. [VERIFIED: NFR-RENDER-001, SwiftUI project skill]
- **Five loop iterations labeled golden evidence:** automated fixtures are not signed-device/human evidence. [VERIFIED: `TST-GOLDEN-001`, sprint cut]

## Don't Hand-Roll

| Problem | Don't build | Use instead | Why |
|---------|-------------|-------------|-----|
| Operation ordering/touched coverage | A second diff/order system | `EditProjectionEngine.diff/verify/apply` | It already enforces the closed canonical orders and stable-ID projection. [VERIFIED: source] |
| Request identity | Ad hoc string/hash | `TransactionFingerprint.digest` | The RR-JCS scope is already exact and tested. [VERIFIED: source/contracts] |
| Retry synchronization | View-level flags or locks | `NativeBranchAuthority` idempotency records | Same-key replay and changed-body conflict are already durable. [VERIFIED: source] |
| Restore | Hide/show callbacks | Existing captured-exact `restore_snapshot` and `RestoreReducer` | It preserves immutable history and rebase semantics offline. [VERIFIED: ADR-012/source] |
| AR authority | A new session/anchor manager | `SharedRealityKitSession` and Phase 4 target session | A second session can drift from the selected world epoch. [VERIFIED: Phase 4] |
| Asset conversion/parity | Runtime USDA→USDZ/GLB workflow | Existing local USDA demo qualification with gate pending | Conversion/parity is explicitly deferred and cannot enter the command path. [VERIFIED: ADR-010/sprint cut] |

## Common Pitfalls

### Pitfall 1: Projection before-state does not contain the selected object
**What goes wrong:** visibility reduction or touched-ID verification rejects, or code is tempted to bypass `target_exists`.
**Prevention:** seed the controlled canonical object with `visible=true`, require selected ID equality and current lifecycle/world/revision, and test missing/hidden/wrong-ID cases. [VERIFIED: current bootstrap plus projection engine]

### Pitfall 2: Retry checks occur after stale preview validation
**What goes wrong:** an exact retry after commit sees a stale base and rejects instead of returning its original receipt.
**Prevention:** in authority commit, compute fingerprint and look up the idempotency key before divergence/base replay, exactly as `commitPlaceCritical` does. [VERIFIED: `TransactionAuthority.swift`]

### Pitfall 3: Restore misses the visibility delta
**What goes wrong:** the asset disappears but the original remains hidden.
**Prevention:** build the inverse from the complete pre/post RR-EDIT-PROJECTION-1 and add a replace→restore test asserting original visible, replacement/support absent, source transaction byte-immutable. [VERIFIED: ADR-012, restore engine]

### Pitfall 4: Renderer still prioritizes the old target proxy
**What goes wrong:** canonical replace succeeds while the UI keeps drawing `.frozenTarget`, because current render derivation selects target first.
**Prevention:** represent original coverage and replacement asset separately; derive committed state from canonical object visibility and placed asset rather than `target != nil`. [VERIFIED: `RoomEditSnapshot.render` current ordering]

### Pitfall 5: Asset boolean overclaims shipping readiness
**What goes wrong:** `assetLicensePassed=true` or an artifact type is mistaken for GATE-011 evidence.
**Prevention:** bind the boolean to the explicit repository-authored local-demo provenance decision only, publish exact resource digests/qualification, and keep derivative parity, redistribution/attribution review, native/web loads, BOM, and gate state PENDING. [VERIFIED: sprint cut/context]

### Pitfall 6: Fixture supported view becomes “measured envelope”
**What goes wrong:** test booleans are promoted to geometry or physical quality claims.
**Prevention:** name the policy and evidence `deterministic_supported_view_fixture`, label it HYPOTHESIS/demo-only, and reject any evidence document that says MEASURED, physical, parity, or gate green. [VERIFIED: evidence discipline]

## Code Examples

### Idempotent authority entry order

```swift
let fingerprint = try TransactionFingerprint.digest(
    proposal: preview.proposal,
    proposedOperations: preview.proposedOperations
)
if let prior = active.idempotencyRecords.first(where: {
    $0.idempotencyKey == request.idempotencyKey
}) {
    guard prior.requestFingerprintSHA256 == fingerprint else {
        throw TransactionAuthorityError.idempotencyConflict
    }
    return prior.receipt
}
// Then enforce frozen authority, replay current preview, and activate durably.
```

Source: existing `NativeBranchAuthority.commitPlaceCritical`; duplicate this ordering for replace, preferably through a shared narrow private helper only if tests preserve behavior. [VERIFIED: repository source]

### Replace readiness boundary

```swift
guard proposal.targetContext.selectedObjectID == candidate.targetObjectID,
      proposal.targetContext.candidateObjectIDs == [candidate.targetObjectID],
      target.lifecycle == "tracked",
      target.editState.visible,
      candidate.capabilityReady,
      candidate.supportedView,
      candidate.asset.allowlisted,
      candidate.asset.collisionProxyPassed,
      candidate.asset.assetLicensePassed,
      candidate.asset.artifactIntegrityPassed
else { throw ReplaceRejection.validationFailed }
```

Source: canonical replace checks plus Phase 4 stable target policy. Use typed rejection cases rather than one generic error in implementation/tests. [VERIFIED: Master Spec, CON-005, existing reducer patterns]

## State of the Art

| Previous repository state | Phase 5 target state | Impact |
|---------------------------|----------------------|--------|
| Replace operation visible but explicitly deferred | Dedicated validated replace preview/commit/retry/restore | The signature operation becomes canonical and replayable. [VERIFIED: current app model/context] |
| Target identity only in `TargetGroundingSnapshot` | Same stable ID also present in canonical scene edit projection | Transaction core can verify and restore visibility. [VERIFIED: current gap] |
| One generic translucent proxy | Separate bounded target coverage and retained replacement entity snapshots | UI reflects canonical replace instead of only target selection. [VERIFIED: current renderer] |
| Demo source digest/provenance only | Additional explicit dimensions/origin/axis/local-delivery assumptions, still demo-only | Deterministic checks improve without fabricating CON-004/GATE-011. [VERIFIED: locked context] |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| — | No unverified external claim is required. Recommendations derive from locked context, canonical repository authority, current source, and installed tool versions. | All | — |

## Open Questions

1. **Can the USDA itself load on the target device through the retained RealityKit path?**
   - What we know: the bytes are bundled and hash-verified; official format capability was already recorded as CLM-007, but load support does not establish this file's device behavior. [VERIFIED: resource loader and Research Ledger]
   - Recommendation: make local load a fail-closed runtime/automated smoke check; keep device-load and GATE-011 evidence pending even if simulator loading passes.

2. **How should older Phase 3 local generations be handled?**
   - What we know: recovery accepts the old scene and ignores bootstrap content beyond identity checks, so it can recover with no canonical target object. [VERIFIED: `NativeBranchAuthority.init`]
   - Recommendation: use a versioned Phase 5 demo-store directory for sprint speed and deterministic bootstrap. Do not silently mutate/relabel older persisted content; document this as demo-state versioning.

3. **What counts as the supported view?**
   - What we know: measured geometry is deferred; context locks a deterministic local fixture only. [VERIFIED: context/sprint cut]
   - Recommendation: keep one closed fixture verdict tied to current target/revision/world; any mismatch coaches/reseeds. Never emit numerical coverage/pose claims.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Xcode | App build/UI test | Yes | 26.4 (17E192) | None required [VERIFIED: local command] |
| Swift compiler | Package unit tests | Yes | Apple Swift 6.3 | Package remains Swift 6 mode [VERIFIED: local command/manifest] |
| ARKit/RealityKit/SwiftUI | Native renderer | Yes | Xcode system SDK | Existing deterministic no-AR fixture for automation; physical claims remain pending [VERIFIED: builds/Phase 4] |
| Bundled proxy USDA | Replace demo | Yes | Source SHA `afdd38d8713f7e02fb91b15709094c9a0f990d91cedddf8812ea7e4ae5e32379` | Fail closed; no download/conversion [VERIFIED: manifest and bytes] |

**Missing dependencies with no fallback:** none for automated implementation.

**Missing evidence with a bounded sprint fallback:** physical device load/compositor judgment, web derivative/parity, redistribution/attribution/BOM review, and five signed-device journeys remain pending and cannot be generated by implementation automation. [VERIFIED: sprint cut]

## Validation Architecture

Skipped because `.planning/config.json` explicitly sets `workflow.nyquist_validation` to `false`. TDD is still mandatory under repository instructions. [VERIFIED: config and `AGENTS.md`]

Recommended execution checks for planning:

- Reducer task: focused `swift test --filter ReplaceReducerTests` from `ios/Packages/ReRoomContracts`.
- Authority/store task: focused `swift test --filter TransactionAuthorityTests` plus replace-specific crash/restart coverage.
- Native task: focused `RoomEditModelTests` and a serialized `RoomEditJourneyTests` replace path, then Debug/Release simulator builds.
- Phase gate: quick/full Phase 5 verifier, Python mutation suite, source/provenance binding, tracked-secret scan, and `git diff --check`; evidence must list `GATE-003`, `GATE-005`, `GATE-009`, `GATE-011`, and `OPS-GOLDEN-001` as `PENDING` where represented.

## Sources

### Primary (HIGH confidence)
- `docs/canonical/README.md`, `MASTER_TECHNICAL_SPEC.md`, `PRD.md`, `TEST_AND_EVALUATION_PLAN.md`, `RISK_AND_KILL_GATES.md`, and `GLOSSARY_AND_ID_REGISTRY.md` — requirement, operation, validation, evidence, and terminology authority.
- `docs/adr/ADR-005-realitykit-first-compositor.md`, `ADR-008-scene-identity-and-readiness.md`, `ADR-010-asset-contract.md`, `ADR-011-agent-and-deterministic-boundary.md`, and `ADR-012-transaction-and-offline-restore.md` — accepted/provisional architecture constraints.
- `docs/contracts/transaction.schema.json`, `edit-artifacts.schema.json`, and contracts README — exact closed field/check/delta/artifact rules.
- `.planning/SPRINT-CUT-36H.md` and Phase 5 context — approved implementation/evidence cut.
- Current Swift package/app/test source and Phase 4 artifacts — verified reusable seams and concrete gaps.

### Secondary (MEDIUM confidence)
- None required. CLM-007 in the canonical Research Ledger already records official RealityKit USD/USDZ and Three.js GLB capability while explicitly withholding file-level parity/load conclusions.

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — existing installed toolchain and linked project modules; no new dependency.
- Architecture: HIGH — exact canonical operation semantics and established Phase 3 implementation patterns.
- Integration gaps: HIGH — directly observed in current bootstrap, target snapshot, proposal arguments, and renderer derivation.
- Asset visual/device behavior: MEDIUM — local bytes/provenance are verified, but physical loading/compositing and parity remain deliberately unmeasured.
- Pitfalls: HIGH — each follows from current source or a canonical fail-closed invariant.

**Research date:** 2026-07-18
**Valid until:** 2026-08-17 for the frozen sprint/canonical source revision; re-run if contracts, context, or transaction core changes.
