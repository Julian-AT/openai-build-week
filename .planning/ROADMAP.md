# Roadmap: ReRoom

## Overview

ReRoom advances through replayable dependency and risk slices: prove closed contracts and the physical base-device path; establish atomic capture and exact replay; complete typed place/commit/offline restore; retire target/compositor risk; deliver replacement; pass controlled multi-surface removal; complete provider-independent B0 web fallback; and consolidate resilience, security, license, golden-run, and submission evidence. Eight phases are retained despite the standard granularity default because the canonical delivery strategy makes replacement and removal separate locked gates and forbids horizontal layer phases.

This roadmap is a draft for approval and initializes planning only. It does not authorize product implementation. `STR-VOICE-001` and `STR-B1-001` remain future/stretch scope and have no P0 phase.

## Phases

**Phase numbering:** Sequential integer IDs are used because no `config.json` exists. Decimal IDs are reserved for later urgent insertions.

- [ ] **Phase 1: Contract and Device Proof** - Prove shared closed contracts, coordinate fixtures, and the signed no-LiDAR base-device path before architecture-sensitive work.
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
**Success Criteria** (what must be TRUE):
  1. A signed minimal app installs and launches on the declared base iPhone; camera permission, ARKit tracking, and planes work without LiDAR semantics, with a repeatable build record.
  2. Swift, JavaScript, and Python consumers agree on the canonical coordinate/projection fixtures within one encoded pixel, including orientation, transformed intrinsics, RR-FLOAT-1 comparisons, and explicit world-epoch correction.
  3. Golden CON-001 through CON-005 schema, digest, and wire vectors agree across languages, while unknown fields/versions and malformed framing, paths, digests, branches, or identities reject before mutation.
  4. Device crop/orientation checks expose no swapped or silently reinterpreted camera geometry; unknown alignment is quarantined.
**Plans**: TBD

### Phase 2: Atomic Capture and Exact Replay
**Goal**: Consented selected frames become crash-safe, journal-authoritative replay inputs before they can be uploaded or coupled to live providers.
**Depends on**: Phase 1
**Requirements**: FR-CAPTURE-001, FR-B0-001, NFR-REPLAY-001, SEC-CONSENT-001
**Success Criteria** (what must be TRUE):
  1. No room image is selected before explicit consent; recording and upload state is visible, and denial leaves only a non-capture explanation.
  2. Each accepted frame follows the exact five-state lifecycle, validates RRFP-WIRE-1 and the image SHA, and crash injection at every durability edge leaves no frame or one hash-valid journaled frame; no upload references an unjournaled frame.
  3. Finalized and recovered-prefix `.rrcap` inputs replay twice with matching global-journal digest, exact frame/event projections, and expected trace; corrupt-suffix recovery stops at the valid prefix without a learned provider or live network.
  4. Stress never exceeds configured live queue capacity, stale drops are measured, durable sequences stay monotonic, and replay order is independent of live completion order.
**Plans**: TBD
**UI hint**: yes

### Phase 3: Typed Place, Commit, and Offline Restore
**Goal**: Users can complete a deterministic place/restore journey through typed/tap input while canonical revisions, inverses, and reconciliation remain exact offline and on replay.
**Depends on**: Phase 2
**Requirements**: FR-PLACE-001, FR-RESTORE-001, FR-TRANSACTION-001, FR-AGENT-001
**Success Criteria** (what must be TRUE):
  1. A user can place a validated curated asset on supported geometry, see a stable preview at the unchanged base revision, explicitly confirm one revision increment, survive interruption, and replay the committed result; missing support rejects commit.
  2. A user can restore the latest eligible edit offline through a new compensating transaction that verifies the captured-exact inverse, increments once, preserves new/unaffected state, and leaves original history immutable.
  3. Retries with the same key and fingerprint return the prior result without another revision; changed content, stale bases, or wrong authority reject, and divergent branches quarantine without automatic merge.
  4. Typed/tap controls can propose all four operations with network and learned providers disabled, while malformed, stale, oversized, or injected arguments cannot change target/session, supply transforms, authorize, confirm, or commit.
**Plans**: TBD
**UI hint**: yes

### Phase 4: Target Grounding and Compositor Gate
**Goal**: A user can ground and recover one explicit target while the base-device renderer and target-first provider path meet their measured gates or activate bounded canonical fallbacks.
**Depends on**: Phase 3
**Requirements**: FR-TARGET-001, NFR-RENDER-001
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

## Progress

**Execution order:** Follow the dependency paths above; sequential phase IDs remain the durable roadmap identifiers. Plans are intentionally TBD until each phase is separately discussed and approved.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Contract and Device Proof | 0/TBD | Not started | - |
| 2. Atomic Capture and Exact Replay | 0/TBD | Not started | - |
| 3. Typed Place, Commit, and Offline Restore | 0/TBD | Not started | - |
| 4. Target Grounding and Compositor Gate | 0/TBD | Not started | - |
| 5. Curated Replacement Vertical | 0/TBD | Not started | - |
| 6. Controlled Multi-Surface Removal | 0/TBD | Not started | - |
| 7. Separate Mode B0 Web Fallback | 0/TBD | Not started | - |
| 8. P0 Hardening and Evidence | 0/TBD | Not started | - |
