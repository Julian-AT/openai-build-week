# Phase 6: Controlled Multi-Surface Removal - Context

**Gathered:** 2026-07-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver the narrowest honest removal slice for the approved 36-hour demo sprint. Implement the exact deterministic `remove` transaction (`set_reveal_bundle`, then `set_object_visibility`), durable replay, idempotent retry, and captured-exact compensating restore. Add an explicitly labeled, launch-gated local demo fixture that can exercise the complete transaction and render a bounded multi-surface reveal proxy. The normal product path remains remove-unavailable because no physical reveal/provider campaign or human vote exists. `FR-REMOVE-001` and `GATE-006` remain pending.

</domain>

<decisions>
## Implementation Decisions

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

</decisions>

<resolved_questions>
## Resolved Open Questions

1. **Can normal remove become ready while `GATE-006` is pending?** No. Normal readiness remains unavailable; only an unmistakable development/demo-fixture path exercises the transaction.
2. **Can synthetic numbers stand in for coverage or five votes?** No. No synthetic coverage/ballot record is emitted or accepted as gate evidence.
3. **Can a one-plane/color punch be called multi-surface removal?** No. The demo visual uses at least two retained surface layers and calls itself a deterministic reveal proxy, not credible empty-room evidence.
4. **Can failed/out-of-envelope content stay hidden?** No. Failure before durable activation leaves the original visible; invalidation after preview cancels/freezes safely; exact restore is the only post-commit return path.
5. **Does the sprint demo close `FR-REMOVE-001`?** No. It proves implementation wiring only. The requirement and gate remain pending until the canonical physical measurements and exactly five human votes exist.

</resolved_questions>

<code_context>
## Existing Code Insights

- `ReplaceReducer` now establishes the pure preview/cancel/confirm pattern and deterministic candidate validation; remove must mirror lifecycle structure but use reveal-first visibility semantics.
- `EditProjectionEngine` and `RestoreReducer` already allow/verify the canonical remove order and projection-scoped artifact union.
- `NativeBranchAuthority`/`TransactionStore` own sole-writer CAS, idempotency, pointer-last activation, recovery, replay, and restore. Phase 5 is extending the same owner for replace; Phase 6 should extend, not fork, it.
- `TargetGroundingSnapshot` intentionally keeps remove unavailable with `reveal_quality_failed`; this is the correct normal state to preserve.
- `RoomEditCompositorDescriptor` already locks layer order and marks reveal/occluder unavailable. Phase 6 may activate local demo reveal layers only while retaining honest occluder status and one AR session.
- `ARSessionController` exposes the shared session's current camera frame/pose, so deterministic pose-bound evaluation needs no second authority.

</code_context>

<deferred>
## Deferred Ideas

- Real observed atlas capture, background reconstruction/fill, provider selection, foreground occluder generation, measured supported-view envelope, eight-pose coverage computation, seam/order scoring, and exactly five blinded votes remain deferred under `GATE-006`, `GATE-003`, and `GATE-005`.
- A full ready CON-004 reveal bundle and release enablement remain deferred until those artifacts/evidence exist. No placeholder can be promoted in place.
- Physical-device golden runs, disconnect/reconnect campaign, thermal/performance campaign, and P0 claim remain pending under `OPS-GOLDEN-001`, `GATE-009`, and related gates.
- Separate Mode B0 replay remains Phase 7; final integration/submission remains Phase 8.

</deferred>

---

*Phase: 06-controlled-multi-surface-removal*
*Context gathered: 2026-07-18*
