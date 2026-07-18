---
phase: 07-separate-mode-b0-web-fallback
plan: "03"
subsystem: mode-b0-evidence
tags: [verification, evidence, nextjs, replay, http-smoke, fail-closed]

requires:
  - phase: 07-separate-mode-b0-web-fallback
    plan: "02"
    provides: Built local recorded-replay page, verified DTO inspection, and bounded in-memory timeline
provides:
  - Dependency-free fail-closed verifier for the Phase 7 source, evidence, identity, privacy, and claim boundary
  - One repeatable exact-lock command covering Phase 2 replay, web tests, typecheck, production build, source closure, and local HTTP rendering
  - Sanitized byte-stable preflight evidence with browser, retention, requirements, and GATE-008 explicitly pending
affects: [phase-08-hardening, FR-WEB-001, SEC-RETENTION-001, GATE-008]

tech-stack:
  added: []
  patterns:
    - Closed canonical JSON evidence with independent source-tree and self digests
    - Stable rejection IDs that never echo evidence bodies, temporary paths, response text, stacks, or secrets
    - Fixed PASS-token hashing so nondeterministic tool logs cannot enter or destabilize canonical evidence

key-files:
  created:
    - tools/verify/tests/test_phase_07_b0_gate.py
    - tools/verify/verify_phase_07_b0.py
    - scripts/verify-phase-07-b0
    - evidence/web/phase-07/automated-preflight.json
  modified: []

key-decisions:
  - "Treat local production-server markup as local_http_smoke only; browser_smoke remains PENDING without a separately bound real-browser artifact."
  - "Close the audited web capability surface through exact dependency maps and source checks for routes, live network/process behavior, persistence, uploads, and deferred action controls."
  - "Publish only stable IDs, exact versions, hashes, PASS outcomes, limitations, and the canonical deferred register; raw logs and HTTP markup remain temporary and are deleted."

patterns-established:
  - "Evidence promotion firewall: FR-WEB-001, SEC-RETENTION-001, GATE-008, and browser_smoke must remain PENDING in this artifact."
  - "Repeatable build evidence: save and restore Next-generated source edits around the build before calculating source closure."

requirements-completed: []
coverage:
  - id: D1
    description: "The independent verifier accepts only the exact closed Phase 7 evidence shape and rejects identity, check, claim, privacy, dependency, route, persistence, network, process, and action-surface mutations with sanitized stable IDs."
    verification:
      - kind: unit
        ref: "python3 -m unittest tools.verify.tests.test_phase_07_b0_gate -v"
        status: pass
    human_judgment: false
  - id: D2
    description: "One command installs both exact locks without package scripts, reruns Phase 2 replay and web tests, typechecks, builds, verifies source closure, starts the built app on loopback, and validates its local HTTP response."
    verification:
      - kind: integration
        ref: "scripts/verify-phase-07-b0 full"
        status: pass
    human_judgment: false
  - id: D3
    description: "The sanitized canonical evidence is byte-identical across two complete runs and independently re-verifies while browser smoke, FR-WEB-001, SEC-RETENTION-001, and GATE-008 remain PENDING."
    verification:
      - kind: integration
        ref: "two full runs plus cmp and scripts/verify-phase-07-b0 --verify-evidence"
        status: pass
    human_judgment: false

duration: 9min
completed: 2026-07-18
status: complete
---

# Phase 07 Plan 03: Reproducible B0 Preflight Evidence Summary

**The local Mode B0 slice now has a fail-closed one-command preflight and byte-stable source-bound evidence without fabricating browser, retention, requirement, or gate completion.**

## Performance

- **Duration:** 9 min
- **Started:** 2026-07-18T18:55:30Z
- **Completed:** 2026-07-18T19:04:15Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Added a dependency-free Python verifier that independently closes the evidence schema, exact versions and fixture/report identities, six required PASS checks, canonical pending claims, deferred register, privacy-safe content, source digest, and evidence self-digest.
- Added mutation coverage proving that missing or extra fields, wrong versions/identities, incomplete or failed checks, browser/gate/requirement promotion, unsafe evidence, dependency drift, API routes, browser persistence, live network/process calls, and deferred controls all fail closed.
- Added one executable that installs both frozen npm locks with scripts disabled, runs exact Phase 2 replay and web projection/timeline tests, typechecks, builds, scans the client boundary, serves on loopback, performs bounded local HTTP assertions, atomically publishes evidence, and independently verifies it.
- Published canonical evidence that records zero learned-provider call paths and keeps browser smoke, the complete browser/fault/ordinary-video/session/share/retention matrix, `FR-WEB-001`, `SEC-RETENTION-001`, and `GATE-008` pending.

## Task Commits

1. **Task 1 RED: Define the fail-closed evidence boundary** — `7e568af` (`test`)
2. **Task 1 GREEN: Add the independent source/evidence verifier** — `544845b` (`feat`)
3. **Task 2: Publish reproducible local-HTTP preflight evidence** — `f972f7d` (`feat`)

## Files Created/Modified

- `tools/verify/tests/test_phase_07_b0_gate.py` — Closed-shape, identity, claims, privacy, source-capability, dependency, and digest mutation suite.
- `tools/verify/verify_phase_07_b0.py` — Independent source/evidence generator and validator plus sanitized local HTTP assertion boundary.
- `scripts/verify-phase-07-b0` — Fail-fast exact-lock orchestration, isolated temporary state, production server lifecycle, atomic publication, and standalone verification.
- `evidence/web/phase-07/automated-preflight.json` — Canonical sanitized evidence for the automated local sprint slice.

## Decisions Made

- HTTP assertions bind the four locked mode labels, exact fixture/archive identity, initial authoritative event identity/type/timestamp, local-only retention state, memory-only session copy, and both absent scene/transaction statements. They do not claim browser execution or interaction.
- The verifier recomputes source closure from the audited web package/source/tests, exact replay package/source/tests, frozen capture fixture, verifier tests, and producer script. It separately recomputes the evidence self-digest.
- Check evidence hashes only fixed `{check_id}: PASS` tokens. Variable npm, test, compiler, build, server, curl, and verifier logs stay inside the isolated temporary directory and are never published.
- The built client chunks are scanned for child-process, exact replay source, and archive-manifest references before source closure passes.
- `browser_artifact` is closed to `null` for this preflight. A future browser claim requires a separate real-browser artifact and a different independently validated evidence path.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Verification Correctness] Replaced a visually contiguous timeline token with stable rendered accessibility data**

- **Found during:** Task 2 local HTTP smoke
- **Issue:** React inserted hydration boundaries between `EVENT` and `00`, so a literal `EVENT 00` raw-markup assertion failed even though the initial event rendered correctly.
- **Fix:** Bound the smoke to the exact initial `aria-valuetext`, stable event ID, type, and decimal timestamp, which are present as contiguous rendered attributes/data and prove the same initial timeline state.
- **Files modified:** `tools/verify/verify_phase_07_b0.py`
- **Verification:** Two full local-server runs and the standalone evidence verifier passed.
- **Committed in:** `f972f7d`

**2. [Rule 3 - Build Hygiene] Restored Next-generated source edits after every production build**

- **Found during:** Task 2 repeatability run
- **Issue:** Next 16.2.9 rewrote `next-env.d.ts` and reformatted/extended `tsconfig.json`, which dirtied the tracked source and changed source closure across runs.
- **Fix:** The verifier command snapshots both tracked files before building and restores their exact pre-run bytes on success, failure, interruption, and normal cleanup before calculating source closure.
- **Files modified:** `scripts/verify-phase-07-b0`
- **Verification:** Both complete runs left `web/next-env.d.ts` and `web/tsconfig.json` byte-identical to their committed state, and canonical evidence compared byte-for-byte.
- **Committed in:** `f972f7d`

---

**Total deviations:** 2 auto-fixed correctness/hygiene issues
**Impact on plan:** Both fixes make the planned checks stable and source-bound. Neither adds a product capability, external dependency, browser claim, service, or gate promotion.

## Issues Encountered

- A manual diagnostic server inherited Homebrew Node 26 when launched directly from the `web/` working directory; the exact replay correctly rejected it. The canonical command starts at repository root, validates Node `v22.22.3` and npm `10.9.8`, and launches the built app with that exact PATH. No diagnostic output entered evidence.

## Known Deferred Work

- General `.rrcap` upload/import and adversarial archive UI.
- MP4/MOV ordinary-video behavior and codec/geometry-unavailable coverage.
- Full browser interaction/visual smoke, two-run golden browser replay, supported-browser and camera/codec/quota/network fault matrices.
- Scene/artifact/transaction fixtures, typed B0 proposal forks, live phone connectivity, WebSockets, and acknowledged-commit fault campaigns.
- Sessions, authentication/authorization, sharing, deletion/TTL/audit lifecycle, cloud storage, deployment, learned providers, B1, and multi-user behavior.
- Full `FR-WEB-001`, `SEC-RETENTION-001`, and `GATE-008` acceptance remain `PENDING`.

## Verification Evidence

- `python3 -m unittest tools.verify.tests.test_phase_07_b0_gate -v` passed all 11 mutation/boundary tests.
- `scripts/verify-phase-07-b0 full` passed twice using exact Node `v22.22.3`, npm `10.9.8`, Next `16.2.9`, React `19.2.7`, and TypeScript `6.0.2`.
- `cmp /tmp/reroom-phase-07-preflight-first.json evidence/web/phase-07/automated-preflight.json` proved byte-identical evidence across the two complete runs.
- `scripts/verify-phase-07-b0 --verify-evidence` independently accepted the published source digest, evidence digest, identities, checks, claims, deferred register, and privacy boundary.
- Changed-file credential/private-evidence scanning and `git diff --check` passed. Pattern hits were limited to deliberate rejection-test sentinels and verifier denylist terms; none exist in the published evidence.

## User Setup Required

None. This slice adds no deployment, browser automation, credential, account, auth, upload, session, share link, database, provider, network API, or cloud resource.

## Next Phase Readiness

- Phase 8 can reuse `scripts/verify-phase-07-b0 full` as the deterministic local B0 regression/preflight boundary.
- Any future browser, fault, ordinary-video, session/share/retention, or full gate claim must add the separate real evidence listed above; this artifact cannot be promoted in place.

## Self-Check: PASSED

- All four declared Plan 07-03 artifacts exist and commits `7e568af`, `544845b`, and `f972f7d` exist.
- Focused mutations, exact replay reuse, web tests, strict typecheck, production build, source/client closure, loopback HTTP assertions, two-run byte comparison, standalone evidence verification, secret/private-data scan, and whitespace check passed.
- The artifact records `browser_smoke`, `FR-WEB-001`, `SEC-RETENTION-001`, and `GATE-008` exactly `PENDING` and records zero provider call paths.
- Concurrent config, Phase 5/8 planning, Xcode, Swift build, workspace, and user-data changes remained outside every Plan 07-03 commit.

---
*Phase: 07-separate-mode-b0-web-fallback*
*Completed: 2026-07-18*
