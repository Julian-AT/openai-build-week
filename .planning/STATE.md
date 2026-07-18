---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: 03
current_phase_name: Typed Place, Commit, and Offline Restore
status: planning
stopped_at: Phase 02 automated verification complete; human verification deferred under approved sprint cut
last_updated: "2026-07-18T12:58:00Z"
last_activity: 2026-07-18
last_activity_desc: Phase 02 verified 48/48 automated must-haves; GATE-001 remains pending while sprint sequencing advances to Phase 03
progress:
  total_phases: 2
  completed_phases: 1
  total_plans: 22
  completed_plans: 21
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-17)

**Core value:** Trustworthy camera-grounded room editing where users can place, replace, remove, and restore one controlled freestanding chair or small table while deterministic application code retains spatial, persistence, transaction, and replay authority.

**Current focus:** 36-hour demo sprint — deliver the four-operation native hero vertical and minimal B0 replay/inspection path while Phase 02 human verification remains explicitly deferred.

## Current Position

Phase: 03 (Typed Place, Commit, and Offline Restore) — PLANNING

Plan: Not yet planned

Status: Phase 02 automated/local slice verified; Phase 03 authorized by the human-approved sprint overlay

Last activity: 2026-07-18 — Phase 02 automated verification completed with GATE-001 still PENDING

Progress: [████████████████████] 15/15 planned tasks ([██████████] 95%)

## Performance Metrics

**Velocity:**

- Total plans completed: 15
- Average duration: N/A
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|

**Recent Trend:**

- Last 5 plans: None
- Trend: Not established

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
### Pending Todos

- Execute one signed-device queue-pressure/recovery smoke on the finalized Phase 2 revision.
- Drive the demo-critical delivery recorded in `.planning/SPRINT-CUT-36H.md`.
- Preserve every deferred physical/human gate as `PENDING`; do not convert implementation or smoke evidence into a full P0 claim.

### Blockers/Concerns

- Provisional ADR variants cannot be treated as selected or measured until their physical/fixture evidence and deadlines are satisfied.
- Remaining compositor/thermal, visual-vote, license, final-rules, and later physical-device gates require real human/device evidence and cannot be fabricated.

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Future/stretch | `STR-VOICE-001` optional Realtime/GPT semantic ingress | Nonblocking; not in P0 roadmap | Initial planning |
| Future/stretch | `STR-B1-001` isolated offline refinement | Frozen until all P0 gates are green and human-approved | Initial planning |
| 36-hour sprint | Full new-revision `GATE-001` consent plus 10-run physical matrix, videos, logs, and attestation | Deferred; one signed-device pressure/recovery smoke in sprint | Human-approved sprint cut, 2026-07-18 |
| 36-hour sprint | Formal `GATE-003`, `GATE-004`, `GATE-005`, `GATE-006`, `GATE-007`, `GATE-008`, `GATE-009`, `GATE-011`, `GATE-012`, and `OPS-GOLDEN-001` campaigns | Deferred as itemized in `.planning/SPRINT-CUT-36H.md`; canonical fallbacks active where defined | Human-approved sprint cut, 2026-07-18 |

## Deferred Verification

| Phase | State | Resume |
|-------|-------|--------|
| 02 | verification_deferred_human | `$gsd-verify-work 02` |

## Session Continuity

Last session: 2026-07-18T01:56:16.074Z

Stopped at: Completed 02-06-PLAN.md

Resume file: None

## Rebuild Log

- timestamp: 2026-07-17T16:01:35.254Z
  kind: by-phase-table-reconciled
  section: ## Performance Metrics
  before: | Phase | Plans | Total | Avg/Plan | \n |-------|-------|-------|----------| \n | - | 0 | 0 | - |
  after: | Phase | Plans | Total | Avg/Plan | \n |-------|-------|-------|----------| \n | 01 | 15 | - | - |
  reason: phase dirs on disk are canonical; rows for missing phases dropped, missing phases added
