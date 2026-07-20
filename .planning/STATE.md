---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: 02
current_phase_name: Atomic Capture and Exact Replay
status: implementing
stopped_at: Owner-authorized finish overlay; workspace/API/worker/native/quality slices committed, documentation and final verification in progress
last_updated: "2026-07-20T11:51:20Z"
last_activity: 2026-07-20
last_activity_desc: Bun/Hono/Vercel AI SDK/private worker/native voice-state/CI slices committed; 80 workspace tests, strict checks, builds, secret scan, and GSD health pass locally
progress:
  total_phases: 10
  completed_phases: 1
  total_plans: 51
  completed_plans: 51
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-17)

**Core value:** Trustworthy camera-grounded room editing where users can place, replace, remove, and restore one controlled freestanding chair or small table while deterministic application code retains spatial, persistence, transaction, and replay authority.

**Current focus:** Finish documentation and clean-revision verification for the
owner-authorized hackathon overlay, then hand provider/device/browser/human
execution to the owner without altering Phase 2 verification findings. Phase
02.1 and Phase 09 have no unexecuted historical plans.

## Current Position

Phase: 02 (Atomic Capture and Exact Replay) — VERIFICATION DEFERRED HUMAN

Plan: Phase 02.1 is 4/4 and Phase 09 is 1/1. The directly authorized
[`AUTONOMOUS-FINISH-PLAN-2026-07-20.md`](milestones/v1.0/AUTONOMOUS-FINISH-PLAN-2026-07-20.md)
implementation overlay is active; it does not close historical verification.

Status: Workspace, Hono/Vercel AI SDK, private worker/proxy, native activity
state, and repository quality slices are committed. Complete the documentation
and final clean-source verification, then `$gsd-next` must return to Phase 2
verification. All unresolved Phase 2 findings remain open; push, branch
protection, provider credentials, device/browser observations, and publication
remain owner actions.

Last activity: 2026-07-20 — implemented and committed the Bun/Turborepo
workspace, Hono gateway, Vercel AI SDK provider boundary, private bounded
FastAPI worker and Hono proxy, native voice-to-preview activity-state cleanup,
Biome/Ruff/Husky enforcement, and SHA-pinned GitHub CI. The current local
workspace gate passes 80 Bun/Python tests, strict types, production builds,
lockfile policy, tracked-secret scanning, and GSD health. Historical signed
device/browser evidence remains bound only to candidate
`476d88f25d0455aea7394ffa72c3188cdb6113ca`.

Progress: [████████████████████] 51/51 implementation plans executed ([██████████] 100%). Canonical verification and gates are not complete.

## Performance Metrics

**Velocity:**

- Total plans completed: 51
- Average duration: N/A
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 15 | not normalized | - |
| 02 | 7 | not normalized | - |
| 02.1 | 4 | 2h 59m | 45m |
| 03 | 7 | not normalized | - |
| 04 | 4 | not normalized | - |
| 05 | 4 | not normalized | - |
| 06 | 4 | not normalized | - |
| 07 | 3 | not normalized | - |
| 08 | 2 | not normalized | - |
| 09 | 1 | not recorded | - |

**Recent Trend:**

- Last 5 plans: Phase 02.1 P01–P04 and Phase 09 P01
- Trend: Two narrow sprint overlays completed; continuation is evidence-first.

*Updated after each approved plan completion.*
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 01 P01 | 10min | 2 tasks | 84 files |
| Phase 01 P02 | 10min | 2 tasks | 24 files |
| Phase 01 P04 | 22min | 2 tasks | 8 files |
| Phase 01 P03 | 10min | 2 tasks | 3 files |
| Phase 01 P05 | 16min | 2 tasks | 7 files |
| Phase 01 P06 | 16min | 2 tasks | 8 files |
| Phase 01 P07 | 12min | 2 tasks | 4 files |
| Phase 01 P08 | 21min | 2 tasks | 6 files |
| Phase 01 P09 | 15min | 2 tasks | 7 files |
| Phase 01 P10 | 18min | 2 tasks | 7 files |
| Phase 01 P11 | 23min | 2 tasks | 7 files |
| Phase 01 P12 | 33min | 2 tasks | 8 files |
| Phase 01 P13 | 27min | 2 tasks | 9 files |
| Phase 01 P15 | 9min | 2 tasks | 4 files |
| Phase 02 P01 | 33min | 2 tasks | 29 files |
| Phase 02 P02 | 28min | 2 tasks | 5 files |
| Phase 02 P04 | 16 min | 2 tasks | 7 files |
| Phase 02 P03 | 32min | 3 tasks | 9 files |
| Phase 02 P05 | 32min | 3 tasks | 8 files |
| Phase 02 P06 | 1h35m | 2 tasks | 11 files |
| Phase 03 P01 | 15min | 1 tasks | 7 files |
| Phase 03 P03 | 11min | 2 tasks | 4 files |
| Phase 03 P02 | 9min | 2 tasks | 5 files |
| Phase 03 P04 | 17min | 2 tasks | 5 files |
| Phase 03 P05 | 25min | 2 tasks | 9 files |
| Phase 03 P06 | 20min | 2 tasks | 8 files |
| Phase 03 P07 | 22min | 2 tasks | 5 files |
| Phase 04 P01 | 8min | 1 tasks | 2 files |
| Phase 04 P02 | 9min | 2 tasks | 2 files |
| Phase 04 P03 | 22min | 2 tasks | 4 files |
| Phase 04 P04 | 18min | 2 tasks | 3 files |
| Phase 02.1 P01 | 31m | 2 tasks | 6 files |
| Phase 02.1 P02 | 30m | 2 tasks | 5 files |
| Phase 02.1 P03 | 1h 7m | 2 tasks | 5 files |
| Phase 02.1 P04 | 51m | 3 tasks | 7 files |
| Phase 09 P01 | not recorded | 3 tasks | multi-surface AI slice |

## Accumulated Context

### Decisions

Full locked and provisional decision blocks are in PROJECT.md.

- P0 is exactly place, replace, remove, and restore; controlled removal remains a blocking release gate.
- Native SwiftUI/ARKit owns Mode A; a separate Next.js client owns guaranteed provider-independent B0.
- Deterministic application code owns spatial checks, branch revisions, persistence, commit, reconciliation, and compensating restore.
- RealityKit/compositor, semantic/depth providers, and multi-surface reveal remain provisional behind `GATE-003`, `GATE-004`/`GATE-007`, and `GATE-006` respectively.
- Phase boundaries follow canonical dependency/risk slices and never person assignments.
- [Phase 02]: Pin the complete capture fixture manifest digest outside the generated corpus. — Prevents regenerated expected output from redefining its own oracle.
- [Phase 02]: Keep ReplayReportV1 evidence-only with explicit archive/finalization identity. — Preserves frozen CON-001/CON-002 authority without minting CON-006.
- [Phase 02]: Reject denied CaptureSessionAuthorization and bind packet plus image digests in durable receipts. — Consent and local durability must be explicit before storage or transport boundaries.
- [Phase 02]: Run typed filesystem fault observers after validation and before synchronous mutation. — Enables deterministic crash testing without suspension inside the future sole-writer actor.
- [Phase 02]: Keep capture sequence allocation and filesystem mutation in one synchronous actor transaction. — Prevents reentrancy from splitting journal authority or exposing a partial frame.
- [Phase 02]: Return a network receipt only after exact frame and lifecycle journal durability. — Makes authoritative journal order the sole publication and transport boundary.
- [Phase 02]: Treat gateway acknowledgement as an exact fifth event independent of local replay and finalization. — Server availability cannot weaken local durability or block explicit stop.
- [Phase 02]: Preserve pre-operation fault observation and add a backward-compatible post-operation observer. — Tests can terminate on both sides of each durability edge without changing existing integrations.
- [Phase 02]: Merge ordinary and reserved admission lanes only by monotonic admission sequence; reserved capacity never creates replay order.
- [Phase 02]: Count queued plus the sole writer lease as outstanding and release either lane only at terminal writer completion.
- [Phase 02]: Use the same injected HYPOTHESIS/TARGET pressure policy for admission and post-durability queues in the locked degradation order.
- [Phase 02]: Keep acknowledgement scheduling receipt-bound and offline so completion order cannot mutate durable journal authority.
- [Phase 02]: Accept only the longest physically present contiguous global-journal prefix. — Gaps, reordering, invalid records, and mismatched bindings fail closed without repair.
- [Phase 02]: Publish interrupted capture recovery as a new immutable recovered-prefix sibling. — The original archive is never mutated or resumed and quarantine diagnostics remain outside accepted inventory.
- [Phase 02]: Derive exact replay only from the verified authoritative global journal. — Frozen journal, frame, event, and revision digests make replay independent of filename order, renderer, provider, model, and network.
- [Phase 02]: Execute the complete 16-case replay evidence set in the local Swift runner. — Atomic publication prevents partial evidence and keeps the shipping runner independent of Node and Python.
- [Phase 02]: Bind all three replay runners to one exact implementation revision and closed source-tree digest. — Separate comparator and publisher content hashes keep the evidence reproducible without dynamic-HEAD or self-reference ambiguity.
- [Phase 02]: Validate every report against its immutable oracle, closed schema, runtime identity, canonical bytes, and self-digest before semantic normalization. — No runtime output may define another runtime's replay authority or hide a mismatch through normalization.
- [Phase 02]: Publish replay agreement through a recoverable prepared/committed transaction. — Replacement faults and interrupted restarts expose the complete prior or complete new evidence generation, never an accepted mixed state.
- [Phase 02]: Accept a per-frame encoding profile so each durable packet's image, intrinsics, projection, and pose originate from the same ARFrame callback. — A session-static encoding profile could pair fresh imagery and calibration with stale camera pose.
- [Phase 02]: Expose recovery candidates only as immutable verified snapshots or sanitized failure snapshots; rejected records never enter the inspector. — Presentation must not turn an unverified recovery candidate into replay-visible state.
- [Phase 02]: Resolve the pinned draft meta-schema resource bundle explicitly under iOS static linking and retain full fail-closed meta-schema validation. — The resource is embedded in the app but the dependency public bundle accessor cannot discover it in the iOS static-link host.
- [Phase 03]: Preserve frozen CON-003 and CON-005 schema bytes and bind them through existing strict validator registrations. — Avoids schema drift while making the transaction boundary executable.
- [Phase 03]: Keep the operation inventory exactly place, replace, remove, restore and keep transaction, idempotency, and branch identities distinct. — Maintains the approved P0 vocabulary and deterministic authority semantics.
- [Phase 03]: Require canonicalization, frozen-schema validation, typed decode, and canonical typed round-trip equality at ingress. — Fails closed against hostile bytes and silent field loss.
- [Phase 03]: Hash and compare only the complete closed RR-EDIT-PROJECTION-1 member; keep revision, readiness, tracking, surfaces, history, and timestamps outside. — Matches the frozen digest scope and prevents restore from rewinding live semantic evidence.
- [Phase 03]: Restore replays and verifies the source ordered operations against its captured inverse before rebasing touched IDs onto the current projection. — Makes source hashes, operation identity, touched sets, and current-before equality fail closed as one pure reduction.
- [Phase 03]: Require local artifacts for both the restore result and the fresh inverse returned for later compensation. — A successful offline restore must remain renderable and compensable without network access.
- [Phase 03]: Parse only semantic operation, arguments, and ordered typed constraints from untrusted bytes; attach identity, revision, target, and world values from trusted native context. — Prevents typed, tap, voice, model, or replay input from acquiring deterministic mutation authority.
- [Phase 03]: Represent the request fingerprint as a dedicated seven-member Codable value. — Prevents lifecycle, result, transaction ID, idempotency ID, or generic dictionary drift from changing the frozen RR-JCS scope.
- [Phase 03]: Replay immutable deterministic preview inputs before cancel or confirm and return pending r+1 content only. — Keeps preview revision-neutral and leaves persistence plus canonical CAS activation to the later sole-writer plan.
- [Phase 03]: Publish every canonical generation member and inventory durably before atomically replacing and synchronizing the sole active-generation pointer. — Prevents partial multi-file state from becoming visible or recoverable as active.
- [Phase 03]: Keep CAS, fingerprint/idempotency decisions, pure reduction, store activation, and actor state publication in synchronous actor-isolated critical functions with no suspension point. — Prevents actor reentrancy from admitting a second revision writer inside the canonical transaction.
- [Phase 03]: Return an existing durable receipt before current-revision validation for an exact same-key/same-fingerprint retry. — Exactly-once retries remain stable after the original base revision has advanced; changed fingerprints still conflict.
- [Phase 03]: Represent unexpected same-branch divergence as two preserved typed snapshots plus explicit manual quarantine. — Future mutation freezes and neither history is automatically merged or overwritten.
- [Phase 03]: Keep the native room-edit surface presentation-only and route every canonical preview, confirmation, restart, and restore decision through the sole NativeBranchAuthority. — SwiftUI state cannot edit scene arrays or allocate revisions.
- [Phase 03]: Expose exactly place, replace, remove, and restore while keeping later replace/remove capabilities visible as typed nonmutating blockers. — The sprint demo remains honest without hiding the complete P0 vocabulary.
- [Phase 03]: Bind the repository-owned generated chair through a closed digest/provenance manifest and label it local demo proxy only. — Implementation evidence cannot promote compositor, catalog, quality, or deferred human/device gates.
- [Phase 03]: Keep transaction trace producers independent and compare semantics only after each runtime validates the immutable oracle and computes its own output. — Prevents one runtime or generated output from becoming another runtime's authority.
- [Phase 03]: Use the frozen-contract-valid `arkit_plane` support method across all producers. — Shipping-core activation and independent references must hash the same contract-valid projection.
- [Phase 03]: Validate every runtime's canonical raw result against the pinned closed schema and an independent fixture/pinned oracle before accepting cross-runtime equality. — Equal wrong outputs must fail rather than become a new oracle.
- [Phase 03]: Publish Phase 3 evidence only after the complete full check inventory passes atomically. — Quick checks and partial full runs cannot replace prior evidence or promote deferred gates.
- [Phase 04]: Keep manual target selection and reseeding revision-neutral and outside NativeBranchAuthority.
- [Phase 04]: Preserve stable semantic target identity across reseeds while replacing only exact-epoch spatial evidence.
- [Phase 04]: Fail closed on invalid AR evidence and expose operation readiness independently while formal Phase 4 gates remain pending.
- [Phase 04]: Preserve DeviceProofModel onEvent compatibility while additive ordered observers share one synchronous AR safety stream.
- [Phase 04]: Prefer finite detected horizontal raycasts, then inspect a bounded estimated-plane fallback, returning no semantic identity.
- [Phase 04]: Construct one auto-configuration-disabled RealityKit ARView and inject its own ARSession into the sole driver.
- [Phase 04]: Retain one live ARView/session/controller/device-proof/model graph; deterministic fixture graphs request no AR tracking.
- [Phase 04]: Keep compositor order exactly camera, reveal, occluder, asset/proxy, debug, SwiftUI; reveal and occluder remain explicitly unavailable.
- [Phase 04]: Expose only immutable render snapshots to SwiftUI and synchronize RealityKit entities by snapshot differences.
- [Phase 04]: Automated evidence is bound to product commit 4d268ba and keeps GATE-003/004/005/007/012 PENDING.
- [Phase 02.1]: Admit replay only through an opaque pinned `VerifiedArchive` capability and recheck bounded member bytes at consumption.
- [Phase 02.1]: Recover the physically present contiguous journal prefix, then publish one immutable content-addressed generation with pointer-last crash/race safety.
- [Phase 02.1]: Limit exact-source automated closeout to `CR-03`, `CR-04`, and `CR-12`; keep 17 other Phase 2 findings, Phase 2, `GATE-001`, and v1.0 open.
- [Phase 09]: Use Sol and optional Realtime only for closed CON-006 semantic proposals; no model tool or response owns geometry, confirmation, revision, persistence, or commit.
- [Phase 09]: Bind trusted native context after inference, arbitrate exactly one visible preview, and require a separate deterministic confirmation.
- [Phase 09]: Ship three deterministic local CON-004 demo assets with canonical digest-bound USDZ/GLB/collision delivery while `GATE-011` remains pending.

### Pending Todos

- Rerun the final clean-source gate, commit the documentation handoff, and
  preserve the local Xcode simulator-runner startup failure as pending rather
  than claiming selected-zero or crashed workers passed.
- Let the owner decide whether to push and require the new GitHub checks; no
  push, PR, branch-protection change, deployment, or submission is performed by
  this overlay.
- Run the timeboxed live Sol/one-frame-vision rubric and optional five-turn
  Realtime rubric; disable optional provider controls on a miss.
- Install the current signed candidate and run the exact camera/catalog/place/
  replace/restore rehearsal plus physical gate campaigns. Historical signed
  build evidence does not transfer to the new source revision.
- Run current-revision B0 in a real supported browser, complete the short honest
  demo recording, and finish the human submission checklist.
- After the finish decision, resume `$gsd-verify-work 02`, formally judge the
  three Phase 02.1 candidates, then work the remaining nine blocker and eight
  warning findings without promoting `GATE-001` early.
- Continue Phase 3 through Phase 8 verification and the formal gate campaigns in dependency order; preserve every incomplete gate as `PENDING`.
- Complete signed-device derivative parity, human visual review, and the final shipping BOM before `GATE-011` or a shipping claim.

### Blockers/Concerns

- Provisional ADR variants cannot be treated as selected or measured until their physical/fixture evidence and deadlines are satisfied.
- Remaining compositor/thermal, visual-vote, license, final-rules, and later physical-device gates require real human/device evidence and cannot be fabricated.

### Roadmap Evolution

- Phase 02.1 inserted after Phase 2: Close Phase 2 capture and recovery trust boundary — CR-03 CR-04 CR-12 (URGENT)

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Future/stretch | `STR-VOICE-001` optional Realtime/GPT semantic ingress | Nonblocking; not in P0 roadmap | Initial planning |
| Future/stretch | `STR-B1-001` isolated offline refinement | Frozen until all P0 gates are green and human-approved | Initial planning |
| Completed 36-hour sprint | Full new-revision `GATE-001` consent plus 10-run physical matrix, videos, logs, and attestation | Reactivated; run after current-revision software audit/fixes | Human resumed canonical QA, 2026-07-18 |
| Completed 36-hour sprint | Formal `GATE-003`, `GATE-004`, `GATE-005`, `GATE-006`, `GATE-007`, `GATE-008`, `GATE-009`, `GATE-011`, `GATE-012`, and `OPS-GOLDEN-001` campaigns | Reactivated in canonical dependency order; fallbacks remain active until replaced by passing evidence | Human resumed canonical QA, 2026-07-18 |

## Deferred Verification

| Phase | State | Resume |
|-------|-------|--------|
| 02 | verification_deferred_human | `$gsd-verify-work 02` |
| 02.1 | verification_deferred_human | Review the three exact-source candidates during `$gsd-verify-work 02` |
| 03 | verification_deferred_canonical_campaigns | Resume formal GATE-009/GATE-010/GATE-011 and physical/human evidence in the sprint-cut resume order |
| 04 | verification_deferred_human | `$gsd-verify-work 04` |
| 05 | verification_deferred_human | `$gsd-verify-work 05` |
| 06 | verification_deferred_human | `$gsd-verify-work 06` |
| 07 | verification_deferred_human | `$gsd-verify-work 07` |
| 08 | verification_deferred_human | `$gsd-verify-work 08` |
| 09 | verification_deferred_human_live | Run the fixed Phase 09 live/provider/device rubric; typed fallback remains complete |

## Session Continuity

Last session: 2026-07-20T11:51:20Z

Stopped at: Direct finish overlay is completing documentation and final
verification after five implementation commits. `$gsd-next` must then return to
Phase 2 formal review; provider/device/formal-browser/human gates remain.

Resume file: None

## Rebuild Log

- timestamp: 2026-07-17T16:01:35.254Z
  kind: by-phase-table-reconciled
  section: ## Performance Metrics
  before: | Phase | Plans | Total | Avg/Plan | \n |-------|-------|-------|----------| \n | - | 0 | 0 | - |
  after: | Phase | Plans | Total | Avg/Plan | \n |-------|-------|-------|----------| \n | 01 | 15 | - | - |
  reason: phase dirs on disk are canonical; rows for missing phases dropped, missing phases added
