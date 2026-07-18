# Phase 4: Target Grounding and Compositor Gate - Context

**Gathered:** 2026-07-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver the smallest honest native target-and-compositor slice needed by the approved 36-hour demo sprint: explicitly seed and recover one freestanding chair or small-table target, expose independent operation readiness, keep ARKit as the sole healthy-session pose/world authority, and render only local camera/edit/proxy/UI layers without a network or learned-provider dependency. This phase activates the canonical manual target, no-dense, and local-only fallbacks. It does not claim that the deferred physical, semantic, geometry, or runtime-tier gate campaigns passed, and it does not implement the full replace or remove reducers owned by Phases 5 and 6.

</domain>

<decisions>
## Implementation Decisions

### Explicit target grounding and recovery
- Use an explicit native tap as the sole sprint target-selection ingress. A successful ARKit raycast against an estimated or detected horizontal surface creates one stable `object_*` target in the current `world_frame_id` and version; a miss or ambiguous result changes no canonical target and reports a clear retry reason.
- Keep the controlled target limited to one freestanding chair or small table with visible floor. The UI must identify the manual/frozen fallback and must never imply automatic semantic recognition.
- Persist a versioned, conservative frozen proxy for the selected target. Renderer/provider indices and transient anchor identities never become canonical object identity.
- Tracking loss, interruption, failure, or world reset immediately makes unsafe target-dependent operations unavailable in the next published UI state. The last committed edit may remain visible, but no stale transform may authorize a new mutation.
- Provide an explicit **Reseed target** action. Reseeding must either bind the same stable target identity into the current healthy world epoch or fail with a concrete reason; it never silently switches identity or invents a cross-epoch transform.

### Independent capability readiness
- Expose separate readiness for `select`, `place`, `replace`, `remove`, and `restore` using the canonical readiness vocabulary (`unavailable`, `warming`, `ready`, `degraded`, `failed`) plus stable coded reasons.
- `select` becomes ready only for a healthy ARKit session with a usable raycast path. `place` continues to depend on healthy support. `replace` may become demo-ready with a grounded target plus conservative proxy, while `remove` remains unavailable until Phase 6 reveal evidence exists. `restore` remains transaction-derived and independent of target-provider readiness.
- Ambiguous, missed, stale, wrong-epoch, or unsupported selection never commits and never changes a scene revision. Readiness is presentation of deterministic state, not authorization by itself.

### Local compositor and bounded fallbacks
- Use the existing native SwiftUI/ARKit surface and Apple frameworks already available in the project. Add no learned segmentation, depth, fusion, cloud, scripting bridge, or third-party renderer dependency.
- Render the live camera as background and only local overlay/proxy/UI content above it. Preserve the canonical order for layers that exist in this sprint; absent reveal/occlusion layers remain explicitly unavailable rather than fabricated.
- The render/update path must perform no synchronous network, model, worker, web-client, filesystem, or transaction-store wait. Cross-boundary work remains outside the high-rate callback and uses bounded/latest-useful state.
- Select the approved `GATE-004` manual tap/reseed fallback, `GATE-007` no-dense ARKit plane/proxy fallback, and `GATE-012` local/demo runtime fallback. Record those selections without marking the gates green.

### Evidence and claim discipline
- Automate deterministic target lifecycle/readiness, raycast result handling, stale/world-reset rejection, reseed success/failure, render-layer ordering, and network/model independence checks wherever simulator/unit seams allow.
- A simulator or automated compositor harness may establish functional ordering only. It cannot satisfy the canonical eight-pose visual vote, four-minute signed-device FPS/memory/thermal campaign, semantic-provider benchmark, fast-geometry measurement, dense bake-off, or runtime-tier soak.
- Keep `GATE-003`, `GATE-004`, `GATE-005`, `GATE-007`, and `GATE-012` `PENDING` unless their exact real evidence is later supplied. Report the phase as an implemented sprint fallback slice, not P0-complete.

### the agent's Discretion
- Choose the smallest internal Swift type names, reducer boundaries, AR view wrapper, proxy geometry, overlay styling, test seams, and app-screen composition that preserve the decisions above and the frozen contracts.
- Prefer changes that avoid touching the Xcode project file. If a new source must be registered, preserve and exclude the user's existing signing/resource project changes from every phase commit.
- Keep the UI compact and demo-legible: camera/target surface, center reticle, tap/reseed guidance, target identity/epoch, per-operation readiness, and honest fallback/pending-gate labels.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ARSessionController` already owns the single ARKit session, tracking events, plane observations, interruption/failure handling, explicit world reset, and current frame access behind a testable driver.
- `DeviceProofModel` and `WorldEpochController` already encode healthy-session and coordinate-epoch transitions; Phase 4 should extend these seams rather than introduce a second AR authority.
- `RoomEditModel` already owns the four-operation surface, exact transaction authority, local durability, support capture, place/restore behavior, and typed blockers. It is the natural integration point for target-derived readiness without weakening the Phase 3 reducer.
- `RoomEditView` already provides a release-routed SwiftUI demo surface and UI tests. The existing bundled provisional chair proxy and provenance record can remain a visibly labeled sprint proxy; it is not shipping-license or compositor-gate evidence.

### Established Patterns
- Behavior-bearing Swift uses Swift Testing RED/GREEN tests, deterministic adapters, stable prefixed IDs, explicit reason enums, and fail-closed mutation boundaries.
- ARKit remains sole pose/world authority. A reset creates a new world-frame version; unknown alignment is quarantined until explicit reseed.
- Physical/human evidence stays pending until performed. Automated scripts fail closed and publish no evidence on incomplete or unstable runs.

### Integration Points
- Extend the AR session seam with deterministic raycast requests/results and tracking/world-epoch signals, then feed a target lifecycle reducer owned by the native app model.
- Bind successful target context into later replace/remove proposals by stable object ID and current world epoch. Phase 3 place/restore transaction invariants and durability must remain unchanged.
- Add the smallest native compositor surface that can show the camera, reticle, conservative target proxy, and committed asset overlay while keeping high-rate rendering independent of network/model/storage.
- Planning and implementation must follow ADR-003, ADR-005, ADR-006, ADR-007, ADR-008, ADR-014, Master Spec target/compositor sections, PRD `FR-TARGET-001` and `NFR-RENDER-001`, CON-003/CON-004, and `GATE-003`/`004`/`005`/`007`/`012`.

</code_context>

<specifics>
## Specific Ideas

- Optimize for one understandable gesture: aim the reticle at the visible floor near the chair/table, tap to seed, then show a stable proxy and a readiness matrix.
- Make failure recovery visible and actionable: move slowly, find floor, tap again, or reseed after tracking recovers.
- Keep every status honest: “manual target,” “no-dense proxy,” “local renderer,” and “formal device gates pending.”
- The user approved the sprint cut, accepted the recommended defaults, and explicitly requested autonomous execution while unavailable; these decisions therefore resolve discussion in favor of the narrowest canonical fallback path.

</specifics>

<deferred>
## Deferred Ideas

- Learned semantic tracking, SAM provider selection/benchmarking, dense depth/fusion, provider/cloud deployment, Metal reveal post-processing, and automatic target identity recovery remain out of this sprint slice.
- Full `GATE-003`, `GATE-004`, `GATE-005`, `GATE-007`, and `GATE-012` campaigns remain in `.planning/SPRINT-CUT-36H.md` and must be completed before corresponding P0 or measured-performance claims.
- Full replacement compositing and asset validation remain Phase 5. Multi-surface reveal/removal and `GATE-006` remain Phase 6. Mode B0 remains Phase 7.

</deferred>

---

*Phase: 04-target-grounding-and-compositor-gate*
*Context gathered: 2026-07-18*
