# Phase 5: Curated Replacement Vertical - Context

**Gathered:** 2026-07-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver the smallest honest signature replacement journey for the approved 36-hour demo sprint. A manually grounded controlled target can preview and explicitly commit one locally bundled replacement proxy through the sole native branch authority, retry idempotently, persist/replay exactly, and restore through a new compensating transaction. Replacement is exposed only inside a deterministic supported-view fixture; outside it the app coaches or keeps replace unavailable. This phase does not claim physical compositing quality, catalog parity, or `GATE-011` completion.

</domain>

<decisions>
## Implementation Decisions

### Exact replace transaction
- Add a dedicated contract-first replace reducer rather than routing replace through place or presentation-only state.
- Use the canonical no-reveal replace order for the activated sprint fallback: `set_object_visibility`, then `create_asset_instance`. The original object changes `visible=true` to `false`; the replacement asset and support relation are created last and atomically in the pending scene.
- Do not invent an observed underlay or reveal bundle. The optional `set_reveal_bundle` variant remains unavailable until validated reveal evidence exists.
- Preview and cancel change no revision. Explicit confirmation performs the sole CAS `r -> r+1`; same-key/same-fingerprint retry returns the original receipt, while a changed fingerprint, stale base, wrong authority/world, target mismatch, or failed validation rejects without mutation.
- Persist one captured-exact RR-EDIT-PROJECTION-1 `restore_snapshot` inverse from committed content back to the exact pre-replace edit projection. Restore remains a new compensating transaction and never rewrites history.

### Target, support, and supported-view policy
- Bind replacement to the stable manually selected `object_*` identity and current world-frame epoch from Phase 4. Renderer or AR anchor indices never authorize the edit.
- Require a tracked, visible target, replace capability readiness, current support evidence, a locally available allowlisted asset artifact, collision pass, license/provenance pass, and artifact-integrity pass.
- Represent the sprint supported-view decision as deterministic local fixture state captured with the frozen manual proxy. It is a demo constraint, not a measured mask volume, OBB, or production view envelope.
- If tracking, target identity, support, asset evidence, or supported-view state becomes stale, freeze the last safe committed display and disable commit with actionable coaching. Never expose a newly hidden original from a failed or partial replace.

### Demo asset and compositor behavior
- Use only the repository-owned six-cube `proxy-chair.usda` already bundled with provenance. Record its exact digest, dimensions/origin/axis assumptions needed by deterministic local checks, and project-owned provenance without asserting a third-party license.
- Keep the artifact labeled `phase3_local_demo_proxy_only` (or an equally explicit successor label). Do not describe its USDA file as a validated USDZ/GLB pair or full CON-004 catalog manifest.
- Render the replacement proxy over the live camera using the existing one-session RealityKit path. The sprint fallback places the asset in front of/conservatively over the controlled original and does not claim empty removal or a validated reveal.
- Add no network fetch, runtime conversion, learned provider, cloud service, third-party dependency, or second AR session. Avoid Xcode project-file edits.

### Evidence and claims
- Automate exact reducer order, before/after matching, target/capability/view/support/asset rejection, preview/cancel immutability, idempotent retry, crash/recovery replay, restore, and deterministic UI journey checks.
- Run repeated automated development journeys where practical, but label them automated fixture runs. They do not substitute for five signed-device golden runs or human seam assessment.
- Keep `GATE-011` `PENDING`. Native/web derivative parity, device/web load, redistribution/attribution review, and shipping bill-of-materials audit remain deferred by `.planning/milestones/v1.0/SPRINT-CUT-36H.md`.
- Keep related physical `GATE-003`, `GATE-005`, `GATE-009`, and `OPS-GOLDEN-001` evidence pending. Report only implemented behavior and checks actually observed.

### the agent's Discretion
- Choose the smallest Swift type names, candidate/preview seeds, validation helpers, UI labels, test fixtures, and verification-script structure that preserve the decisions above.
- Reuse Phase 3 transaction/store patterns and Phase 4 target/compositor seams. Prefer new package sources and automatically discovered app sources so the user's existing signing/project changes remain untouched.
- Keep the demo legible: select/reseed target, choose Replace, preview, confirm, show one revision, retry safely, then Restore.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PlaceReducer` already provides the preview/confirm/cancel shape, deterministic asset/support policy outputs, validation records, exact projection diff verification, and captured-exact inverse construction that replace should mirror without duplicating place semantics.
- `NativeBranchAuthority` already owns idempotency, sole-branch CAS, durable activation, divergence freeze, restore, and recovery. Add replace entry points through this owner.
- `RestoreReducer.operationOrderMatchesIntent` already accepts both canonical replace delta sequences and verifies captured-exact touched content.
- `RoomEditModel` already owns stable manual target identity/readiness, current world epoch, one native transaction authority, and the four-operation UI surface. Replace is currently explicitly deferred.
- `RoomEditCompositorDescriptor` locks camera -> reveal -> occluder -> asset/proxy -> debug -> SwiftUI order; absent reveal/occluder evidence remains unavailable rather than fabricated.
- `Resources/Phase3Proxy/` contains the repository-owned proxy, digest record, and an intentionally incomplete demo manifest.

### Established Patterns
- Behavior-bearing Swift follows Swift Testing RED/GREEN commits, stable prefixed IDs, pure fail-closed reducers, explicit confirmations, and durable generation activation.
- Automated preflight evidence is revision-bound and lists every deferred gate as `PENDING`; physical and human observations are never fabricated.
- One ARKit session remains the healthy-session pose/world authority, and high-rate rendering waits on no network, model, worker, web client, or store operation.

### Integration Points
- Add replace reducer types and authority methods in `ReRoomTransactionCore`, then exercise them with focused reducer, authority, store recovery, and restore tests.
- Seed or synchronize the controlled hero object's canonical edit state with Phase 4's stable target ID without making selection itself a scene revision.
- Extend `RoomEditModel` preview/confirm/cancel/retry handling and `RoomEditView` coaching/replace presentation while preserving place and restore regressions.
- Add a Phase 5 verifier and revision-bound automated preflight that record functional sprint evidence while leaving `GATE-011` pending.

</code_context>

<specifics>
## Specific Ideas

- Optimize the demo story for one visible path: tap to seed the chair, Replace, preview the local chair proxy, Confirm once, retry without a second revision, and Restore.
- Use explicit labels such as “local demo proxy,” “supported view,” and “asset parity gate pending.”
- Preserve the approved fallback wording: the replacement sits conservatively in front of the original when no validated underlay exists; it must never be presented as empty removal.
- The user approved the sprint cut, accepted the recommended defaults, and requested autonomous execution while unavailable, so implementation should select the narrowest deterministic fallback without further questions.

</specifics>

<deferred>
## Deferred Ideas

- Full USDZ/GLB derivative generation and parity, shipping license/attribution audit, device/web asset-load proof, catalog expansion, runtime conversion, and remote asset delivery remain deferred under `GATE-011`.
- Measured mask volume/OBB/view envelope, semantic tracking, dense geometry, reveal underlay, blinded seam votes, and physical-device golden runs remain pending under their canonical gates.
- Empty multi-surface removal remains Phase 6. Separate provider-independent Mode B0 replay remains Phase 7.

</deferred>

---

*Phase: 05-curated-replacement-vertical*
*Context gathered: 2026-07-18*
