# Phase 4: Target Grounding and Compositor Gate - Research

**Researched:** 2026-07-18
**Domain:** Native ARKit target grounding, RealityKit composition, and capability readiness
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Explicit target grounding and recovery
- Use an explicit native tap as the sole sprint target-selection ingress. A successful ARKit raycast against an estimated or detected horizontal surface creates one stable `object_*` target in the current `world_frame_id` and version; a miss or ambiguous result changes no canonical target and reports a clear retry reason.
- Keep the controlled target limited to one freestanding chair or small table with visible floor. The UI must identify the manual/frozen fallback and must never imply automatic semantic recognition.
- Persist a versioned, conservative frozen proxy for the selected target. Renderer/provider indices and transient anchor identities never become canonical object identity.
- Tracking loss, interruption, failure, or world reset immediately makes unsafe target-dependent operations unavailable in the next published UI state. The last committed edit may remain visible, but no stale transform may authorize a new mutation.
- Provide an explicit **Reseed target** action. Reseeding must either bind the same stable target identity into the current healthy world epoch or fail with a concrete reason; it never silently switches identity or invents a cross-epoch transform.

#### Independent capability readiness
- Expose separate readiness for `select`, `place`, `replace`, `remove`, and `restore` using the canonical readiness vocabulary (`unavailable`, `warming`, `ready`, `degraded`, `failed`) plus stable coded reasons.
- `select` becomes ready only for a healthy ARKit session with a usable raycast path. `place` continues to depend on healthy support. `replace` may become demo-ready with a grounded target plus conservative proxy, while `remove` remains unavailable until Phase 6 reveal evidence exists. `restore` remains transaction-derived and independent of target-provider readiness.
- Ambiguous, missed, stale, wrong-epoch, or unsupported selection never commits and never changes a scene revision. Readiness is presentation of deterministic state, not authorization by itself.

#### Local compositor and bounded fallbacks
- Use the existing native SwiftUI/ARKit surface and Apple frameworks already available in the project. Add no learned segmentation, depth, fusion, cloud, scripting bridge, or third-party renderer dependency.
- Render the live camera as background and only local overlay/proxy/UI content above it. Preserve the canonical order for layers that exist in this sprint; absent reveal/occlusion layers remain explicitly unavailable rather than fabricated.
- The render/update path must perform no synchronous network, model, worker, web-client, filesystem, or transaction-store wait. Cross-boundary work remains outside the high-rate callback and uses bounded/latest-useful state.
- Select the approved `GATE-004` manual tap/reseed fallback, `GATE-007` no-dense ARKit plane/proxy fallback, and `GATE-012` local/demo runtime fallback. Record those selections without marking the gates green.

#### Evidence and claim discipline
- Automate deterministic target lifecycle/readiness, raycast result handling, stale/world-reset rejection, reseed success/failure, render-layer ordering, and network/model independence checks wherever simulator/unit seams allow.
- A simulator or automated compositor harness may establish functional ordering only. It cannot satisfy the canonical eight-pose visual vote, four-minute signed-device FPS/memory/thermal campaign, semantic-provider benchmark, fast-geometry measurement, dense bake-off, or runtime-tier soak.
- Keep `GATE-003`, `GATE-004`, `GATE-005`, `GATE-007`, and `GATE-012` `PENDING` unless their exact real evidence is later supplied. Report the phase as an implemented sprint fallback slice, not P0-complete.

### the agent's Discretion
- Choose the smallest internal Swift type names, reducer boundaries, AR view wrapper, proxy geometry, overlay styling, test seams, and app-screen composition that preserve the decisions above and the frozen contracts.
- Prefer changes that avoid touching the Xcode project file. If a new source must be registered, preserve and exclude the user's existing signing/resource project changes from every phase commit.
- Keep the UI compact and demo-legible: camera/target surface, center reticle, tap/reseed guidance, target identity/epoch, per-operation readiness, and honest fallback/pending-gate labels.

### Deferred Ideas (OUT OF SCOPE)
- Learned semantic tracking, SAM provider selection/benchmarking, dense depth/fusion, provider/cloud deployment, Metal reveal post-processing, and automatic target identity recovery remain out of this sprint slice.
- Full `GATE-003`, `GATE-004`, `GATE-005`, `GATE-007`, and `GATE-012` campaigns remain in `.planning/SPRINT-CUT-36H.md` and must be completed before corresponding P0 or measured-performance claims.
- Full replacement compositing and asset validation remain Phase 5. Multi-surface reveal/removal and `GATE-006` remain Phase 6. Mode B0 remains Phase 7.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| `FR-TARGET-001` | Explicitly ground one chair/table target and expose independent operation readiness. | The existing AR session/controller, stable scene IDs, exact world epoch, and room-edit snapshot provide a closed native reducer and presentation seam. [VERIFIED: repository code and canonical contracts] |
| `NFR-RENDER-001` | Keep native rendering local and independent of network/model/worker/web waits. | A shared RealityKit `ARView` can own the single AR session while consuming immutable target/compositor snapshots; no new package or service is needed. [VERIFIED: existing Apple framework linkage and repository architecture] |
</phase_requirements>

## Summary

Implement this phase as three connected native seams: (1) a pure, deterministic target lifecycle/readiness reducer, (2) a single-session AR adapter that turns a tap/raycast plus tracking/world-epoch events into reducer input, and (3) a thin RealityKit/SwiftUI compositor that reads coarsened immutable snapshots. This matches ADR-003/005/008: ARKit owns healthy-session pose/world truth, stable prefixed IDs own semantic identity, and the renderer consumes state without becoming canonical authority. [VERIFIED: `docs/adr/ADR-003-arkit-authority-and-coordinates.md`, `ADR-005-realitykit-first-compositor.md`, `ADR-008-scene-identity-and-readiness.md`]

The current app already has nearly all required seams. `ARSessionController` owns tracking and world-reset events behind a test driver; `RoomEditModel` owns the four-operation snapshot and exact Phase 3 transactions; `RoomEditView` owns release routing and accessible operation controls. Extend those existing files and tests so no Xcode project-file registration is required. Create the `ARView` once, use its `ARSession` as the controller's `SystemARSessionDriver` session, and inject raycast output into model logic; never create a second automatically configured AR session. [VERIFIED: repository code inspection]

**Primary recommendation:** Add a tested target state machine and raycast boundary to existing Swift files, then layer one shared-session RealityKit camera/proxy surface behind the existing SwiftUI controls with all five formal gates still `PENDING`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Tap/raycast and AR tracking | Native client AR adapter | ARKit | Screen input and ARKit results enter through one main-actor boundary; ARKit remains pose/world authority. |
| Target identity/lifecycle/readiness | Deterministic native model | Scene contract | Stable object/world IDs and coded readiness are application state, never renderer indices. |
| Camera/proxy composition | Native renderer | SwiftUI presentation | RealityKit presents camera and local entities; SwiftUI presents controls/status without per-frame state. |
| Place/restore authority | Transaction core | Room edit model | Existing Phase 3 CAS/durability remains authoritative and must not move into renderer callbacks. |
| Gate evidence | Verification scripts/docs | Physical operator | Automation proves deterministic behavior; signed-device/human campaigns remain external pending work. |

## Project Constraints (from AGENTS.md)

- Read canonical authority before changing product meaning and preserve locked IDs/contracts. [VERIFIED: `AGENTS.md`]
- Keep Mode A native SwiftUI, ARKit sole healthy-session authority, and the base device free of rear-LiDAR requirements. [VERIFIED: `AGENTS.md`]
- The 60 Hz path never waits for network, model, worker, or web client; render only edit/reveal/occlusion/shadow/UI layers over the live camera. [VERIFIED: `AGENTS.md`]
- Stable prefixed IDs carry identity; capability readiness is independent; mask volume, mesh, OBB, occluder, and reveal artifacts remain distinct. [VERIFIED: `AGENTS.md`]
- Use TDD for behavior logic, validate untrusted boundary input, keep queues bounded, and preserve user worktree changes. [VERIFIED: `AGENTS.md`]
- Do not fabricate physical/human evidence or promote TARGET/HYPOTHESIS to MEASURED. [VERIFIED: `AGENTS.md`]

## Standard Stack

| Framework/module | Version boundary | Purpose | Evidence |
|------------------|------------------|---------|----------|
| Swift / SwiftUI / Observation | Existing Xcode project | `@MainActor @Observable` model and accessible native UI | [VERIFIED: project sources/build settings] |
| ARKit | Existing system framework | Tracking, planes, raycast results, camera/world transforms | [VERIFIED: `ARSessionController.swift`, ADR-003] |
| RealityKit | Existing Apple system framework | Shared-session camera presentation and local proxy entity | [VERIFIED: ADR-005 and current iOS target; no package install] |
| Swift Testing / XCTest UI | Existing targets | Pure reducer/adapter tests and simulator journey | [VERIFIED: current test targets] |
| ReRoomContracts / ReRoomTransactionCore | Existing local package | Stable IDs, world epoch, exact proposal/transaction types | [VERIFIED: local package and Phase 3 implementation] |

No external package, provider, credential, runtime, or install is required. `GATE-004`, `GATE-007`, and `GATE-012` deliberately use their canonical fallbacks. [VERIFIED: `.planning/SPRINT-CUT-36H.md`]

## Architecture Patterns

### Data flow

```text
tap location
  -> ARView raycast adapter (main actor, one shared ARSession)
  -> validated candidate snapshot (stable object ID + current world epoch)
  -> pure target/readiness reducer
  -> RoomEditModel immutable/coarsened snapshot
  -> RealityKit proxy + SwiftUI readiness/status

tracking/reset event
  -> reducer revokes unsafe readiness in same published UI update
  -> committed transaction projection remains intact
```

### Pattern 1: Pure reducer before AR glue

Represent selection input as small value types: candidate count, stable ID, world ID/version, transform, confidence/source, and current tracking health. The reducer returns either a new selected target/readiness snapshot or a typed nonmutating failure. Test zero/one/multiple candidates, stale epoch, tracking loss, reset, and reseed before wiring ARKit. [VERIFIED: repository RED/GREEN patterns and ADR-008]

### Pattern 2: One shared AR session

Construct one `ARView` with automatic configuration disabled, pass its `session` into `SystemARSessionDriver`, and let `ARSessionController` run the existing `ARWorldTrackingConfiguration`. The representable reuses that view; it never starts another session. Coordinator callbacks turn tap coordinates into raycast inputs. [VERIFIED: ADR-003/005 architectural requirement; API shape must be compiler-verified by the implementation build]

### Pattern 3: Coarsened renderer state

Keep per-frame transforms/entities inside RealityKit. Publish SwiftUI state only when meaningful lifecycle/readiness/target identity changes. `UIViewRepresentable.updateUIView` synchronizes the selected immutable proxy snapshot without filesystem, network, model, transaction, or frame-buffer work. [VERIFIED: `NFR-RENDER-001`, SwiftUI expert performance guidance]

### Pattern 4: Existing-file implementation

Put the target reducer/value types and model integration in `RoomEditModel.swift`, the shared AR session/raycast adapter in `ARSessionController.swift`, and the representable/status views in `RoomEditView.swift`. Extend the existing test files. This avoids all project-file edits and protects the user's dirty signing/resource changes. [VERIFIED: explicit PBX source registration and current worktree]

## Don't Hand-Roll

| Problem | Do not build | Use instead | Why |
|---------|--------------|-------------|-----|
| Pose/world tracking | Custom SLAM or renderer-derived coordinates | ARKit session/frame/raycast | Canonical authority is locked to ARKit. |
| Semantic identity | AR anchor/entity index as object ID | Stable `object_*` plus world epoch | Renderer/provider identities are transient. |
| Dense target geometry | Learned depth/fusion/mesh pipeline | Conservative frozen proxy + ARKit plane | Approved sprint fallback; geometry gate remains pending. |
| Per-frame observation bridge | Raw frame values in SwiftUI environment | RealityKit-owned updates + coarsened model state | Avoids invalidation storms and scripting/high-rate bridges. |
| Gate evidence | Synthetic “measured” metrics | Automated functional report plus explicit pending campaigns | Physical/human measurements cannot be fabricated. |

## Common Pitfalls

1. **Second AR session:** an automatically configured `ARView` beside the existing controller creates competing world authorities. Build the view/session/controller as one object graph and assert the shared session path. [HIGH]
2. **Silent nearest-target switch:** multiple semantic candidates or a wrong-epoch candidate must reject; only the explicit tap ray has a deterministic spatial nearest-hit policy inside the adapter. The reducer still tests ambiguity. [HIGH]
3. **Readiness coupled to one boolean:** replace/remove/restore have different evidence; publish a matrix with coded reasons. [HIGH]
4. **Reset reuses transforms:** a world reset advances/quarantines the epoch and revokes target mutation until explicit reseed; never relabel an old transform. [HIGH]
5. **Per-frame SwiftUI mutation:** publishing every AR frame causes UI invalidation and hides render waits. Keep high-rate state in ARKit/RealityKit. [HIGH]
6. **Accidental gate claim:** simulator ordering or a pleasant device view is not `GATE-003`; keep all five gate statuses pending. [HIGH]
7. **Project-file collateral:** new Swift files require PBX changes in a dirty user file. Prefer existing files/tests and stage explicit paths only. [HIGH]

## Code Examples

The plan should describe interfaces rather than copy implementation, but these signatures make the seams explicit:

```swift
@MainActor
typealias TargetRaycastProvider = @Sendable (CGPoint) -> [TargetRaycastCandidate]

@MainActor
func seedTarget(at point: CGPoint) async

func reducing(_ event: TargetGroundingEvent) -> TargetGroundingSnapshot
```

The AR adapter converts `ARRaycastResult.worldTransform` once at the boundary into the existing row-major `Matrix4`. The model never stores `ARAnchor`, `Entity`, or provider indices as canonical identity. [VERIFIED: RR-COORD-1 and existing `Matrix4(simdTransform:)`]

## Environment Availability

| Dependency | Required by | Available | Fallback |
|------------|-------------|-----------|----------|
| Xcode/iOS SDK with ARKit, RealityKit, SwiftUI | Native build/tests | Yes — existing Phase 3 builds pass | None needed |
| iOS Simulator | unit/UI automation | Yes | Functional only; no physical gate claim |
| Signed base iPhone | formal device campaigns | Not agent-operable while owner is away | Record as `PENDING` |
| Learned/cloud runtime | None in sprint slice | Not required | Manual/no-dense/local fallback |

## Validation Architecture

`.planning/config.json` explicitly sets `workflow.nyquist_validation` to `false`, so no separate `VALIDATION.md` is required. Still use the established per-task RED/GREEN commands:

- Target reducer/model: focused `xcodebuild test` against `RoomEditModelTests`.
- AR adapter/session: focused `xcodebuild test` against `ARSessionPolicyTests`.
- UI/compositor wiring: Debug and Release builds plus `RoomEditJourneyTests` on a uniquely booted simulator.
- Phase verification: a fail-closed script/report that distinguishes automated pass from each pending gate.

## Assumptions Log

None. The implementation must compile-check the exact installed RealityKit initializer/session API; no product decision depends on an unverified external package or service.

## Open Questions (RESOLVED)

1. **Learned semantic or dense provider?** RESOLVED: no; approved manual/no-dense fallbacks.
2. **Cloud/runtime tier?** RESOLVED: local/demo only; `GATE-012` remains pending.
3. **Can automation close compositor/device gates?** RESOLVED: no; it may only prove deterministic functional behavior.
4. **Where should code live?** RESOLVED: existing Swift/source-test files to avoid PBX collateral.

## Sources

### Primary (HIGH confidence)
- `AGENTS.md`
- `.planning/SPRINT-CUT-36H.md`, `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md`
- `docs/canonical/MASTER_TECHNICAL_SPEC.md`, `PRD.md`, `TEST_AND_EVALUATION_PLAN.md`, `RISK_AND_KILL_GATES.md`
- `docs/adr/ADR-003`, `ADR-005`, `ADR-006`, `ADR-007`, `ADR-008`, `ADR-014`
- `docs/contracts/scene-state.schema.json`, `edit-artifacts.schema.json`, `transaction.schema.json`
- `ios/ReRoomDeviceProof/ReRoomDeviceProof/ARSessionController.swift`, `RoomEditModel.swift`, `RoomEditView.swift`, and current tests

## Metadata

**Confidence breakdown:** Standard stack HIGH; architecture HIGH; exact RealityKit compiler surface MEDIUM until build-checked; physical performance/visual quality intentionally unmeasured.

**Research date:** 2026-07-18  
**Valid until:** End of the 36-hour sprint; canonical gate evidence supersedes fallback claims only when actually recorded.
