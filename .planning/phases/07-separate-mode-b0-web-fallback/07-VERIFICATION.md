---
phase: 07-separate-mode-b0-web-fallback
verified: 2026-07-18T19:09:30Z
status: human_needed
score: 10/14 must-haves verified
behavior_unverified: 0
overrides_applied: 0
human_verification:
  - test: "Real supported-browser replay interaction and visual smoke"
    expected: "The verified fixed capture renders with the locked B0/pending labels; range, keyboard, previous/next, focus, narrow layout, and rejection surfaces behave clearly without exposing unverified data."
    why_human: "The retained local HTTP check proves server output, not hydration, keyboard interaction, focus, responsive rendering, or visual quality in a browser."
  - test: "Complete canonical FR-WEB-001 and GATE-008 campaign"
    expected: "Two supported-browser runs cover scene/artifact/transaction inspection, a typed distinct fork, ordinary video without fabricated spatial facts, and camera/codec/quota/network failures with zero provider calls or lost acknowledged commits."
    why_human: "The approved sprint slice intentionally implements only one fixed golden capture and records browser/full-gate claims as PENDING."
  - test: "Complete SEC-RETENTION-001 lifecycle"
    expected: "Server TTL, share expiry/invalidation, source-and-derived deletion queues, completion evidence, and ID-only audit logging pass the canonical retention tests."
    why_human: "The sprint slice is local and memory-only; no server session, share, deletion queue, audit, auth, or cloud lifecycle exists to exercise."
---

# Phase 7: Separate Mode B0 Web Fallback Verification Report

**Phase Goal:** Users can replay, inspect, share, and safely operate on captured sessions in a separate provider-independent web experience with honest degradation.

**Verified:** 2026-07-18T19:09:30Z

**Status:** `human_needed`

**Re-verification:** No — initial verification

## Goal Achievement

The approved 36-hour sprint slice is real, substantive, source-bound, and fail-closed: a separate Next.js server runs the exact Phase 2 replay over one fixed golden `.rrcap`, projects a closed serializable DTO only after acceptance, and renders an in-memory provider-independent inspector with honest absence/degradation messages. Its evidence independently binds the current source tree and prevents local HTTP output from being promoted to browser, FR-WEB-001, SEC-RETENTION-001, or GATE-008 completion.

The canonical Phase 7 goal is **not complete**. General capture import, actual browser evidence, scene/transaction/artifact inspection for a fixture containing those records, sessions, sharing, typed proposals/forks, ordinary video, fault campaigns, and server retention/deletion/audit behavior remain PENDING under the human-approved sprint overlay. `human_needed` therefore means “the automated sprint slice is clean but canonical acceptance remains open,” not that Phase 7 or P0 is green.

### Observable Truths

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | Supported browsers can open and verify a golden capture, replay the exact journal, scrub events, and inspect canonical scene/transaction/artifact state without providers or a live phone. | ? UNCERTAIN / CANONICAL PENDING | Exact replay, fixed-capture timeline/frame inspection, and provider/live-phone absence are implemented. No real browser artifact exists, and this fixture explicitly has no scene, transaction, sparse geometry, reveal, or asset records to inspect. |
| 2 | Users can manage sessions, sharing, and typed proposals on an explicit B0 fork while camera/codec/quota/network faults preserve acknowledged commits and Mode A parity. | ? UNCERTAIN / CANONICAL PENDING | Sessions, sharing, typed proposals/forks, gateway authority, and the fault matrix are explicitly deferred and unavailable in the current UI. |
| 3 | Ordinary video has deterministic decode/timeline behavior while never fabricating ARKit calibration, scale, pose, planes, trajectory, or geometry. | ? UNCERTAIN / CANONICAL PENDING | Ordinary video is explicitly unavailable; no MP4/MOV decoder or ordinary-video test fixture is present. |
| 4 | Local-only is the default, while explicit server TTL/share/deletion/audit behavior satisfies SEC-RETENTION-001. | ? UNCERTAIN / CANONICAL PENDING | Local/memory-only behavior is verified. The server lifecycle, invalidation, source/derived deletion queue, completion evidence, and ID-only audit are intentionally absent. |
| 5 | The server exposes capture data only after the existing exact Phase 2 replay accepts the fixed golden archive. | ✓ VERIFIED | `load-golden-capture.server.ts` invokes `tools/javascript/src/replay.ts` through fixed arguments and `execFile(..., shell: false)` before calling `projectVerifiedReplay`; the focused real-runner test passed. |
| 6 | The accepted result is a serializable stable-ID timeline/frame/privacy DTO with explicit absent scene/transaction state. | ✓ VERIFIED | The closed DTO and projection validate manifest/report/archive identities, ordering, counts, bytes, digests, stable IDs, empty provider lock, privacy facts, and explicit `not_present` states. |
| 7 | A runner/report/archive/projection mismatch returns one sanitized rejection with no trusted replay payload. | ✓ VERIFIED | The loader catches runner/read/projection failures, returns only the closed rejected variant, cleans temporary output, and mutation tests reject identity/content/path/image/report drift. |
| 8 | The UI unmistakably identifies recorded B0, provider independence, the local fixture, and GATE-008 PENDING rather than claiming Mode A. | ✓ VERIFIED | The server page renders the locked labels and explicitly says this slice does not close browser, ordinary-video, retention, or fault evidence. |
| 9 | The verified timeline can be selected by range/keyboard and previous/next without mutating canonical replay state. | ✓ VERIFIED | `ReplayExplorer` keeps only `selectedIndex` in state, derives event/frame from immutable props, uses native range semantics and functional bounded transitions; the independent transition test passed without mutation. Real-browser interaction remains a human smoke item. |
| 10 | Privacy/capability panels show exact local-only/share/delete facts and honest absent/unavailable states. | ✓ VERIFIED | The DTO carries manifest-derived privacy fields; scene/transactions/sparse geometry are `not_present`, while sharing, typed proposals, ordinary video, providers, and live phone are `unavailable` with explicit explanations. |
| 11 | Verification failure renders a sanitized closed surface with no trusted timeline or preview. | ✓ VERIFIED | `page.tsx` branches on the discriminated result and renders `ReplayExplorer` only for `verified`; the rejected branch contains generic failure copy and no replay prop. |
| 12 | One command proves exact replay, web tests, typecheck, production build, source closure, and local HTTP output. | ✓ VERIFIED | The retained evidence has six closed PASS checks. This pass independently revalidated the evidence and source closure; the full command was not rerun because it had already passed twice. |
| 13 | Evidence contains only sanitized stable identities, hashes, exact versions, outcomes, limitations, and honest pending states. | ✓ VERIFIED | The report is closed/self-digested, source-tree-bound, contains no raw private fields or machine paths, and records exact toolchain/fixture identities and limitations. |
| 14 | HTTP evidence cannot be promoted to browser or canonical requirement/gate completion. | ✓ VERIFIED | `browser_artifact` is `null`; browser, FR-WEB-001, SEC-RETENTION-001, and GATE-008 claims are exactly `PENDING`; mutation tests reject every attempted promotion. |

**Score:** 10/14 must-haves verified; four broader roadmap truths remain explicitly pending rather than inferred from the fixed-fixture sprint slice.

## Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `web/src/lib/replay/types.ts` | Closed server result and serializable replay DTO | ✓ VERIFIED | Stable-ID event/frame/privacy/content/capability types are bounded to the UI’s needs. |
| `web/src/lib/replay/load-golden-capture.server.ts` | Server-only exact-runner orchestration | ✓ VERIFIED | `server-only`, fixed repository paths/arguments, `execFile`, `shell: false`, bounded temporary copy, sanitized rejection, and cleanup are substantive. |
| `web/src/lib/replay/project-verified-view.ts` | Pure accepted-report/archive projection | ✓ VERIFIED | Rechecks identities, counts, order, digest/byte agreement, provider lock, and honest absent/unavailable capabilities before returning data. |
| `web/src/components/replay-explorer.tsx` | In-memory timeline/frame/privacy/capability inspector | ✓ VERIFIED | One local selection state, derived event/frame, range and bounded buttons, live region, stable IDs/digests, and no storage/network effect. |
| `web/src/app/page.tsx` | Server entry with verified/rejected branch | ✓ VERIFIED | Calls the loader directly; only the verified branch crosses the RSC boundary into `ReplayExplorer`; locked limitations remain visible. |
| `web/src/app/globals.css` | Responsive accessible local styling | ✓ VERIFIED BY SOURCE | Focus-visible, narrow breakpoints, reduced-motion and increased-contrast handling are present. Actual rendering remains a browser/human item. |
| `web/test/golden-replay.test.mjs` | Exact runner/projection/loader mismatch coverage | ✓ VERIFIED | Exercises the real Phase 2 runner plus identity, archive, payload, frame, image, invocation, cleanup, and sanitized-failure cases. |
| `web/test/timeline.test.mjs` | Pure bounded selection coverage | ✓ VERIFIED | Covers clamping, movement, zero-event/nonfinite input, and immutability. |
| `scripts/verify-phase-07-b0` | Closed Phase 7 sprint verifier | ✓ VERIFIED | Pins runtime/package state, runs the six checks, bounds loopback HTTP, restores generated tracked files, and generates/verifies evidence. |
| `tools/verify/verify_phase_07_b0.py` | Independent package/source/claim verifier | ✓ VERIFIED | Enforces exact dependencies, source scope, closed evidence, honest claims, source digest, and self-digest. |
| `evidence/web/phase-07/automated-preflight.json` | Sanitized source-bound sprint evidence | ✓ VERIFIED | Six PASS checks; source digest `3bda8a…e0a2`; self-digest `8829ce…c6db`; browser artifact null and canonical claims pending. |

## Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `load-golden-capture.server.ts` | `tools/javascript/src/replay.ts` | fixed `REPLAY_RUNNER` inside `fixedArguments`, then `execFile(process.execPath, fixedArguments, { shell: false })` | ✓ WIRED | Manual trace and focused execution test prove the link. The plan-query regex missed it only because path construction and `execFile` are on different lines. |
| `load-golden-capture.server.ts` | `project-verified-view.ts` | projection after accepted report is read | ✓ WIRED | The only verified result construction calls `projectVerifiedReplay` inside the guarded server flow. |
| `page.tsx` | `load-golden-capture.server.ts` | direct async Server Component call | ✓ WIRED | No client fetch/API route is introduced. |
| `page.tsx` | `ReplayExplorer` | verified DTO prop only | ✓ WIRED | The rejected branch never mounts the inspector or forwards replay data. |
| `ReplayExplorer` | `timeline.ts` | pure initial selection and functional bounded movement | ✓ WIRED | Selection is local UI state; the canonical DTO is never mutated. |
| `verify-phase-07-b0` | `verify_phase_07_b0.py` | generate and independently verify closed evidence | ✓ WIRED | Current evidence and current source closure both passed standalone validation. |

## Data-Flow and Boundary Trace

| Stage | Input → output | Boundary property | Status |
|---|---|---|---|
| Fixed fixture | repository golden `.rrcap` → temporary bounded copy | No upload, picker, session, or user-controlled path | ✓ FLOWING |
| Exact replay | copied archive → Phase 2 accept report | Existing authoritative Node runner, fixed args, no shell | ✓ FLOWING |
| Projection | accepted report + copied archive → `VerifiedReplayView` | Revalidates identity/order/count/bytes/digests/provider lock | ✓ FLOWING |
| Server render | discriminated loader result → verified page or closed rejection | Rejected branch forwards no replay payload | ✓ FLOWING |
| RSC/client boundary | one serializable bounded DTO → `ReplayExplorer` | No Node import, request data global, fetch, route, persistence, or provider path in the client | ✓ FLOWING |
| Interaction | immutable DTO + `selectedIndex` → derived selected event/frame | Functional bounded update; no canonical mutation | ✓ FLOWING |
| Evidence | exact source set + six outcome digests → sealed JSON | Source digest and evidence self-digest are independently enforced | ✓ FLOWING |

The relevant React/Next guidance influenced this audit: the boundary passes only the closed fields used by the client, request data stays local to the render tree, selected details are derived during render, state transitions use functional updates, and no nested component definitions or mutable module-level request state were found. The fixed filesystem paths are intentionally explicit and closed by the verifier.

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Retained evidence validation | `scripts/verify-phase-07-b0 --verify-evidence` | `phase_07_b0_evidence: PASS` | ✓ PASS |
| Current source closure | `python3 -m tools.verify.verify_phase_07_b0 --verify-source` | `source_closure: PASS` | ✓ PASS |
| Mutation/fail-closed enforcement | `python3 -m unittest tools.verify.tests.test_phase_07_b0_gate -v` | 11 tests passed | ✓ PASS |
| Exact loader invocation/cleanup | focused Node test by name | 1 test passed | ✓ PASS |
| Bounded immutable timeline transition | focused Node test by name | 1 test passed | ✓ PASS |

The full production build/local-server preflight was not rerun in this pass because it had already passed twice. The retained evidence’s source digest was recomputed against the current closed source set, so this verification does not rely only on its historical implementation revision.

## Probe Execution

No phase-specific `probe-*.sh` scripts are declared. The standalone source/evidence validators and focused mutation/behavior tests above were used instead; no server was started.

## Requirements and Gate Coverage

| Requirement / gate | Canonical expectation | Status | Evidence |
|---|---|---|---|
| `FR-WEB-001` | Separate B0 session/timeline, `.rrcap` and ordinary-video replay, inspection, sharing, typed proposals, supported-browser and degradation behavior | ? PARTIAL / PENDING | The fixed golden exact-replay/inspection seed is verified. General import, ordinary video, sessions, sharing, proposals/forks, actual browser proof, and degradation campaigns are absent and explicitly deferred. |
| `SEC-RETENTION-001` | Local default plus explicit server TTL, deletion/share invalidation, source/derived cleanup, and ID-only audit | ? PARTIAL / PENDING | Local/memory-only default and manifest facts are verified. All server retention/share/delete/audit behavior remains unimplemented and PENDING. |
| `GATE-008` | Two supported-browser provider/GPU/network-disabled runs plus scene/artifact/transaction, typed-fork, ordinary-video, and fault evidence | ? PENDING | Only exact replay, web unit/type/build checks, source closure, and local HTTP output are retained. `browser_artifact` is null and the full matrix is explicitly deferred. |

`REQUIREMENTS.md` correctly keeps both Phase 7 requirements pending. The sprint overlay changes delivery sequencing and sprint acceptance only; it does not weaken or green these canonical obligations.

## Scope, Security, and Anti-Pattern Scan

No API route, `fetch`, WebSocket, browser storage/database/service worker, file picker, remote font/asset, upload/share/auth/cloud action, provider call path, or client-side Node import was found in `web/src`. The only process spawn is the locked server loader. No shared mutable request state, effect-derived state, nested component definition, console logging, placeholder implementation, or unresolved TODO/FIXME/TBD marker was found.

The three `return null` scan hits are legitimate: absent structured event details and empty/unselected timeline cases. The UI’s `not_present` and `unavailable` values are honest degradation signals, not stubs disguised as success.

### Disconfirmation pass

1. **Partially met requirement:** `FR-WEB-001` has only a fixed-fixture replay/inspection seed; most canonical web behavior is deliberately absent.
2. **Limited passing test:** `timeline.test.mjs` proves pure bounded transitions but not React hydration, native range keyboard dispatch, focus behavior, or detail updates in a real supported browser.
3. **Uncovered runtime surface:** Loader rejection is deeply tested and source-wired to a closed page, but the rejected page and unexpected Next error retry surface have not been exercised visually in a real browser.

## Human Verification Required

### 1. Real supported-browser replay interaction and visual smoke

**Test:** Build/start the web app locally, open it in each canonical supported browser, and exercise range/keyboard/previous/next selection at desktop and narrow widths; also force the verified loader rejection and unexpected error surfaces.

**Expected:** Locked B0/provider-independent/local-fixture/GATE-008-pending labels remain visible; event/frame details track selection; focus is visible; the layout remains readable; failures reveal no timeline, preview, paths, or raw error details.

**Why human:** Local HTTP token checks do not execute hydration or establish browser interaction and visual behavior.

### 2. Complete FR-WEB-001 and GATE-008 campaign

**Test:** Resume the canonical matrix with providers/GPU/network disabled: two browser runs over a representative capture, scene/artifact/transaction inspection, a typed distinct fork, ordinary video, and camera/codec/quota/network faults.

**Expected:** Exact authoritative replay, no fabricated ordinary-video spatial facts, explicit unavailable/degraded states, zero provider calls, and no lost acknowledged commit or Mode A parity break.

**Why human:** Those capabilities and fixtures are outside the approved sprint slice and cannot be inferred from the fixed capture.

### 3. Complete SEC-RETENTION-001 lifecycle

**Test:** Implement and exercise explicit server TTL/share/deletion/audit behavior under `TST-RETENTION-001`.

**Expected:** Expired/deleted shares fail closed; source and derived artifacts are queued and completion is evidenced; audit records contain stable IDs and outcomes rather than imagery.

**Why human:** No server session/share/auth/cloud/retention system exists in the current slice.

## Pending Summary

No implementation defect was found in the authorized automated sprint slice. The exact replay path, DTO projection, server/client boundary, local-only behavior, honest degradation/absence messages, source-bound evidence, and enforcement against provider/upload/share/auth/cloud scope creep all verify cleanly.

Phase 7’s canonical goal nevertheless remains open. A real browser artifact and the full FR-WEB-001, SEC-RETENTION-001, and GATE-008 work are pending; this report must not be used as Phase 7, GATE-008, or P0 completion evidence.

---

_Verified: 2026-07-18T19:09:30Z_

_Verifier: the agent (gsd-verifier)_
