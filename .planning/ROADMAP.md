# Roadmap: ReRoom

## Overview

ReRoom advances through replayable dependency and risk slices: prove closed contracts and the physical base-device path; establish atomic capture and exact replay; complete typed place/commit/offline restore; retire target/compositor risk; deliver replacement; pass controlled multi-surface removal; complete provider-independent B0 web fallback; and consolidate resilience, security, license, golden-run, and submission evidence. Eight phases are retained despite the standard granularity default because the canonical delivery strategy makes replacement and removal separate locked gates and forbids horizontal layer phases.

This approved high-level roadmap initializes planning only. It does not authorize product implementation; every phase still requires discussion, a reviewed detailed plan, and its own verification. `STR-VOICE-001` and `STR-B1-001` remain future/stretch scope and have no P0 phase.

## 36-Hour Demo Sprint Overlay

The human project owner approved a demo-first sprint cut on 2026-07-18. The
authoritative scope, activated fallbacks, deferred evidence, and post-sprint
resume order are recorded in
[SPRINT-CUT-36H.md](SPRINT-CUT-36H.md). During this sprint, implementation and
demo smoke status must remain distinct from full P0 gate status; deferred gates
stay `PENDING` and their canonical definitions are unchanged.

## Phases

**Phase numbering:** Sequential integer IDs established during ingest remain the durable phase identifiers. Decimal IDs are reserved for later urgent insertions.

- [x] **Phase 1: Contract and Device Proof** - Prove shared closed contracts, coordinate fixtures, and the signed no-LiDAR base-device path before architecture-sensitive work. (completed 2026-07-17)
- [ ] **Phase 2: Atomic Capture and Exact Replay** - Make consented selected frames durable, recoverable, bounded, and exactly replayable before live inference.
- [ ] **Phase 3: Typed Place, Commit, and Offline Restore** - Complete the deterministic edit lifecycle without voice, learned geometry, or network dependence.
- [ ] **Phase 4: Target Grounding and Compositor Gate** - Establish explicit target readiness, fast proxies, and a measured viable base-device compositor with bounded provider fallbacks.
- [ ] **Phase 5: Curated Replacement Vertical** - Deliver the signature replacement journey with stable identity, supported-view compositing, and exact transaction behavior.
- [ ] **Phase 6: Controlled Multi-Surface Removal** - Pass the locked view-bounded removal gate and preserve remove/restore through replay.
- [ ] **Phase 7: Separate Mode B0 Web Fallback** - Provide provider-independent Next.js replay, inspection, sessions, sharing, typed proposals, and honest degradation.
- [ ] **Phase 8: P0 Hardening and Evidence** - Make all blocking gates, audits, distributions, 5/5 hero runs, and submission evidence green without unsupported claims.

## Phase Details

### Phase 1: Contract and Device Proof

**Goal**: The project has one verified contract/coordinate vocabulary and a signed physical base-iPhone path that works without rear LiDAR.
**Depends on**: Nothing (first phase)
**Requirements**: NFR-COORD-001, NFR-CONTRACT-001, OPS-DEVICE-001
**Gates**: GATE-002, GATE-013
**Success Criteria** (what must be TRUE):

  1. A signed minimal app installs and launches on the declared base iPhone; camera permission, ARKit tracking, and planes work without LiDAR semantics, with a repeatable build record.
  2. Swift, JavaScript, and Python consumers agree on the canonical coordinate/projection fixtures within one encoded pixel, including orientation, transformed intrinsics, RR-FLOAT-1 comparisons, and explicit world-epoch correction.
  3. Golden CON-001 through CON-005 schema, digest, and wire vectors agree across languages, while unknown fields/versions and malformed framing, paths, digests, branches, or identities reject before mutation.
  4. Device crop/orientation checks expose no swapped or silently reinterpreted camera geometry; unknown alignment is quarantined.

**Plans**: 15/15 plans executed

Plans:

- [x] 01-01-PLAN.md
- [x] 01-02-PLAN.md
- [x] 01-03-PLAN.md
- [x] 01-04-PLAN.md
- [x] 01-05-PLAN.md
- [x] 01-06-PLAN.md
- [x] 01-07-PLAN.md
- [x] 01-08-PLAN.md
- [x] 01-09-PLAN.md
- [x] 01-10-PLAN.md
- [x] 01-11-PLAN.md
- [x] 01-12-PLAN.md
- [x] 01-13-PLAN.md
- [x] 01-14-PLAN.md
- [x] 01-15-PLAN.md

**Wave 1**

- [x] 01-01 — Freeze closed fixture/result schemas and immutable contract/JCS/coordinate oracle.
- [x] 01-02 — Define canonical sanitized gate/checklist evidence, including human-only waiver rules.
- [x] 01-04 — Audit and obtain human approval for exact toolchain dependencies or fallbacks.

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 01-03 — Build the fail-closed comparator and stable Phase 1 verification modes.

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 01-05 — Implement the independent JavaScript contract and coordinate runner.
- [x] 01-06 — Implement the independent Python contract and coordinate runner.

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 01-07 — Prove JavaScript/Python parity with cross-runtime mutation gates.

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 01-08 — Resolve and implement Swift frozen-schema validation against all five schemas.

**Wave 6** *(blocked on Wave 5 completion)*

- [x] 01-09 — Implement Swift JCS, wire, path, and RR-COORD-1 policies.

**Wave 7** *(blocked on Wave 6 completion)*

- [x] 01-10 — Execute Swift/JavaScript/Python agreement and record bound evidence.

**Wave 8** *(blocked on Wave 7 completion)*

- [x] 01-11 — Create the narrow portrait-only iOS candidate device-proof seed and AR session policies.

**Wave 9** *(blocked on Wave 8 completion)*

- [x] 01-12 — Implement orientation, epoch correction/quarantine, and atomic FramePacket capture.

**Wave 10** *(blocked on Wave 9 completion)*

- [x] 01-13 — Add sanitized internal diagnostics and prove shipping UI exclusion.

**Wave 11** *(blocked on Wave 10 completion)*

- [x] 01-14 — Run automated preflight, obtain real signed GATE-013/GATE-002 evidence, and promote the candidate only on GATE-013 GREEN.

**Wave 12** *(gap closure; blocked on Wave 11 completion)*

- [x] 01-15 — Refresh byte-reproducible three-runtime agreement provenance for the finalized contract-source revision without changing signed physical evidence.

### Phase 2: Atomic Capture and Exact Replay

**Goal**: Consented selected frames become crash-safe, journal-authoritative replay inputs before they can be uploaded or coupled to live providers.
**Depends on**: Phase 1
**Requirements**: FR-CAPTURE-001, FR-B0-001, NFR-REPLAY-001, SEC-CONSENT-001
**Gates**: GATE-001
**Success Criteria** (what must be TRUE):

  1. No room image is selected before explicit consent; recording and upload state is visible, and denial leaves only a non-capture explanation.
  2. Each accepted frame follows the exact five-state lifecycle, validates RRFP-WIRE-1 and the image SHA, and crash injection at every durability edge leaves no frame or one hash-valid journaled frame; no upload references an unjournaled frame.
  3. Finalized and recovered-prefix `.rrcap` inputs replay twice with matching global-journal digest, exact frame/event projections, and expected trace; corrupt-suffix recovery stops at the valid prefix without a learned provider or live network.
  4. Stress never exceeds configured live queue capacity, stale drops are measured, durable sequences stay monotonic, and replay order is independent of live completion order.

**Plans**: 7/7 plans executed

- [x] 02-01-PLAN.md
- [x] 02-02-PLAN.md
- [x] 02-03-PLAN.md
- [x] 02-04-PLAN.md
- [x] 02-05-PLAN.md
- [x] 02-06-PLAN.md
- [x] 02-07-PLAN.md

**Wave 1**

- [x] 02-01 — Freeze the executable capture/replay oracle, synthetic archives, report schema, and shared package interfaces.

**Wave 2**

- [x] 02-02 — Implement the consent-bound five-state atomic archive writer and durability fault matrix.
- [x] 02-04 — Implement deterministic selection, bounded newest-useful work, pressure behavior, and offline acknowledgement echo.

**Wave 3**

- [x] 02-03 — Recover only the valid durable prefix and replay verified archives into exact reports and timelines.

**Wave 4**

- [x] 02-05 — Prove three-runtime replay agreement and publish revision-bound evidence atomically.
- [x] 02-06 — Connect the native seed to consent, lifecycle, truthful state, recovery, and the internal replay inspector.

**Wave 5**

- [ ] 02-07 — Run fail-closed verification and obtain or truthfully leave pending the human/device GATE-001 evidence.

**UI hint**: yes

**36-hour sprint note:** Close implementation after automated verification and
one signed-device queue-pressure/recovery smoke. The repeated new-revision
10-run physical `GATE-001` matrix is deferred to Phase 8 and remains `PENDING`.

### Phase 3: Typed Place, Commit, and Offline Restore

**Goal**: Users can complete a deterministic place/restore journey through typed/tap input while canonical revisions, inverses, and reconciliation remain exact offline and on replay.
**Depends on**: Phase 2
**Requirements**: FR-PLACE-001, FR-RESTORE-001, FR-TRANSACTION-001, FR-AGENT-001
**Gates**: GATE-009, GATE-010 (typed/agent safety; optional voice remains stretch)
**Success Criteria** (what must be TRUE):

  1. A user can place a validated curated asset on supported geometry, see a stable preview at the unchanged base revision, explicitly confirm one revision increment, survive interruption, and replay the committed result; missing support rejects commit.
  2. A user can restore the latest eligible edit offline through a new compensating transaction that verifies the captured-exact inverse, increments once, preserves new/unaffected state, and leaves original history immutable.
  3. Retries with the same key and fingerprint return the prior result without another revision; changed content, stale bases, or wrong authority reject, and divergent branches quarantine without automatic merge.
  4. Typed/tap controls can propose all four operations with network and learned providers disabled, while malformed, stale, oversized, or injected arguments cannot change target/session, supply transforms, authorize, confirm, or commit.

**Plans**: 6 plans

Plans:

**Wave 1**

- [ ] 03-01-PLAN.md — Freeze the immutable oracle and implement its exact transaction contract in one final-passing TDD task.

**Wave 2** *(blocked on Wave 1)*

- [ ] 03-03-PLAN.md — Implement RR-EDIT-PROJECTION-1 and offline RR-RESTORE-REBASE-1 compensation.

**Wave 3** *(blocked on Waves 1–2)*

- [ ] 03-02-PLAN.md — Implement strict typed/tap intent, exact fingerprinting, and place reduction through the shared projection engine.

**Wave 4** *(blocked on Wave 3)*

- [ ] 03-04-PLAN.md — Add pointer-last durable generations and one non-reentrant native branch authority.

**Wave 5** *(blocked on Wave 4)*

- [ ] 03-05-PLAN.md — Deliver the compact native four-operation place/restore proof surface.

**Wave 6** *(blocked on Waves 4–5)*

- [ ] 03-06-PLAN.md — Prove Swift/JavaScript/Python agreement with an executable Swift trace exporter and publish honest automated sprint evidence.
**UI hint**: yes

### Phase 4: Target Grounding and Compositor Gate

**Goal**: A user can ground and recover one explicit target while the base-device renderer and target-first provider path meet their measured gates or activate bounded canonical fallbacks.
**Depends on**: Phase 3
**Requirements**: FR-TARGET-001, NFR-RENDER-001
**Gates**: GATE-003, GATE-004, GATE-005, GATE-007, GATE-012
**Success Criteria** (what must be TRUE):

  1. A user can explicitly select one chair/table target; ambiguity never silently commits, tracking loss changes per-capability readiness within one UI update, and reseeding restores the target or reports a clear failure.
  2. Renderer ordering is correct at the prescribed poses and the four-minute signed base-device run has no render-thread network/model wait, crash, jetsam, or sustained serious/critical thermal state while meeting the current TARGET frame gate.
  3. The semantic benchmark produces no hero-target identity switch and records access/license/tier evidence; a tie or missed timebox selects SAM 2.1 Small with explicit reseeding rather than blocking the deterministic path.
  4. The dense-provider bake-off either qualifies a provider under `GATE-007` or records the no-dense fast path; dense output never rewrites ARKit authority, stable IDs, or committed history.

**Plans**: TBD
**UI hint**: yes

### Phase 5: Curated Replacement Vertical

**Goal**: Users can replace the controlled target with a validated curated asset reliably inside supported observations.
**Depends on**: Phase 4
**Requirements**: FR-REPLACE-001
**Gates**: GATE-011
**Success Criteria** (what must be TRUE):

  1. A ready target can be replaced with stable identity, conservative original masking/occlusion, deterministic support alignment, and exactly one committed revision even after retry.
  2. Five consecutive development runs complete without wrong target, duplicate revision, severe seam, or lost edit, and the result persists locally and through exact replay.
  3. Outside validated observations, the interface coaches for another view or restores safe content instead of exposing an invalid replacement composite.
  4. The selected asset's native/web derivatives, dimensions, origin, collision proxy, hashes, delivery state, and license evidence are bound by one stable asset manifest before it is used in the hero path.

**Plans**: TBD
**UI hint**: yes

### Phase 6: Controlled Multi-Surface Removal

**Goal**: Users can remove and restore the controlled target only inside a measured supported-view envelope, satisfying the locked P0 removal gate.
**Depends on**: Phase 5
**Requirements**: FR-REMOVE-001
**Gates**: GATE-006
**Success Criteria** (what must be TRUE):

  1. The controlled hero capture passes `GATE-006`: coverage p10 at least 0.95, median at least 0.98, no uncovered component over 1%, correct multi-surface order, no severe foreground overwrite, and at least 4/5 of exactly five blinded votes.
  2. A removal commit pins the validated reveal revision, persists through replay, and restores through the exact compensating transaction without rewriting the original commit.
  3. Outside the measured view envelope, the interface coaches for another view or keeps remove unavailable; it never exposes unbounded or undisclosed synthesis.
  4. A missed reveal threshold or timebox is recorded as a P0 blocker rather than silently demoting controlled removal.

**Plans**: TBD
**UI hint**: yes

### Phase 7: Separate Mode B0 Web Fallback

**Goal**: Users can replay, inspect, share, and safely operate on captured sessions in a separate provider-independent web experience with honest degradation.
**Depends on**: Phase 2 and Phase 3 (independent of Phases 4-6 once those prerequisites pass)
**Requirements**: FR-WEB-001, SEC-RETENTION-001
**Gates**: GATE-008
**Success Criteria** (what must be TRUE):

  1. Supported browsers can open and verify the golden capture, replay the exact journal, scrub events, inspect canonical scene/transaction state, and render available sparse/artifact data without a learned provider or live phone connection.
  2. Users can manage sessions, sharing, and typed proposals on an explicit B0 fork; camera denial, unsupported codec, quota, and network failures degrade without losing an acknowledged commit or claiming Mode A parity.
  3. Ordinary video provides deterministic decode/timeline replay and processing state without fabricating ARKit calibration, scale, pose, planes, trajectory, or geometry.
  4. Local-only is the default; server TTL and share state are explicit; deletion invalidates shares and queues source/derived deletion; audit logs retain stable IDs rather than room imagery.

**Plans**: TBD
**UI hint**: yes

### Phase 8: P0 Hardening and Evidence

**Goal**: The complete four-operation native journey and B0 replay are repeatable, secure, licensed, resilient, measured, and honestly documented for submission.
**Depends on**: Phase 6 and Phase 7
**Requirements**: NFR-LATENCY-001, NFR-RESILIENCE-001, SEC-CREDENTIAL-001, SEC-AGENT-001, OPS-LICENSE-001, OPS-GOLDEN-001, OPS-SUBMISSION-001
**Gates**: Revalidate every P0 gate; GATE-014 remains the global B1-isolation guard
**Success Criteria** (what must be TRUE):

  1. Tracking, network, reconnect, worker, and storage fault runs lose no acknowledged commit, leak no cross-session state, create no duplicate mutation, recover a valid capture prefix, and show explicit degraded/recovery UI.
  2. Evidence reports p50/p95/max for every required stage and mask age on the declared device/provider/tier; missed TARGET values activate the named degraded capability rather than becoming unsupported real-time claims.
  3. Secret, credential, prompt/tool-injection, retention, and shipping-license audits pass: no unknown/noncommercial shipped artifact, leaked credential, expanded tool set, unauthorized target/session change, or mutation bypass remains.
  4. OPS-GOLDEN-001 completes 5/5 consecutive signed base-device place/replace/remove/restore journeys plus matching B0 replay with all blocking gates green and controlled removal separately passing `GATE-006`.
  5. The rules checklist and evidence package are signed before the deadline; the public demo stays under the official limit, shows all four operations and B0 honestly, includes a representative Codex Session ID, and makes no unsupported performance or novelty claim.

**Plans**: TBD
**UI hint**: yes

## Dependency and Scope Notes

- The critical native path is Phase 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 8.
- The provider-independent web path is Phase 2 -> 3 -> 7 -> 8. Phase 7 does not depend on learned geometry or completion of native replacement/removal, though the final P0 gate requires both paths.
- No phase is assigned to a person. If later execution permits concurrency, at most two implementation-critical streams join through the frozen contracts and replay fixtures.
- `STR-VOICE-001` is not scheduled in P0. It may be considered only after typed proposals and transaction security pass, and failure must leave typed/tap complete.
- `STR-B1-001` has no P0 task. It remains frozen while any P0 gate is red and requires explicit human approval after P0.
- `GATE-014` applies throughout the roadmap: no B1 package, provider, worker, task, schema dependency, or resource may enter a P0 phase.

## Progress

**Execution order:** Follow the dependency paths above; sequential phase IDs remain the durable roadmap identifiers. Plans are intentionally TBD until each phase is separately discussed and approved.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Contract and Device Proof | 15/15 | Complete    | 2026-07-17 |
| 2. Atomic Capture and Exact Replay | 7/7 | In Progress|  |
| 3. Typed Place, Commit, and Offline Restore | 0/TBD | Not started | - |
| 4. Target Grounding and Compositor Gate | 0/TBD | Not started | - |
| 5. Curated Replacement Vertical | 0/TBD | Not started | - |
| 6. Controlled Multi-Surface Removal | 0/TBD | Not started | - |
| 7. Separate Mode B0 Web Fallback | 0/TBD | Not started | - |
| 8. P0 Hardening and Evidence | 0/TBD | Not started | - |
