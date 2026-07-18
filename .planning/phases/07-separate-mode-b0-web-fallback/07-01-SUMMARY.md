---
phase: 07-separate-mode-b0-web-fallback
plan: "01"
subsystem: mode-b0-replay-boundary
tags: [nextjs, react, typescript, replay, server-only, fail-closed]

requires:
  - phase: 02-atomic-capture-and-exact-replay
    provides: Exact Node v22.22.3 replay runner, immutable capture corpus, and closed replay reports
provides:
  - Separate exact-version Next.js package for the local Mode B0 fallback
  - Server-only fixed-fixture orchestration through the existing Phase 2 verifier
  - Closed serializable verified/rejected replay DTO with timeline, frame, privacy, and capability facts
affects: [07-02-mode-b0-interface, FR-WEB-001, GATE-008]

tech-stack:
  added: [next@16.2.9, react@19.2.7, react-dom@19.2.7, typescript@6.0.2]
  patterns:
    - Exact verifier before any presentation read
    - Private frozen-fixture snapshot prevents verifier-to-projection byte races
    - Closed sanitized rejection with no partial trusted payload

key-files:
  created:
    - web/package.json
    - web/package-lock.json
    - web/src/lib/replay/types.ts
    - web/src/lib/replay/project-verified-view.ts
    - web/src/lib/replay/load-golden-capture.server.ts
    - web/test/golden-replay.test.mjs
  modified:
    - web/tsconfig.json

key-decisions:
  - "Keep tools/javascript as the sole replay-verification authority and invoke its pinned CLI through execFile with fixed arguments."
  - "Copy the immutable fixture into the exclusive temporary parent before verification so projection reads the exact private bytes the runner accepted."
  - "Expose only JSON-serializable stable IDs, decimal timestamp strings, verified digests, accepted frame data, manifest privacy facts, and honest absent/unavailable states."

patterns-established:
  - "Accept-first boundary: the accepted exact report is required before any archive member is read for presentation."
  - "Failure closure: process, report, JSON, projection, and cleanup failures all collapse to one non-sensitive rejected result."

requirements-completed: []
coverage:
  - id: D1
    description: "The existing exact Phase 2 Node runner gates the fixed local capture before a verified replay DTO can exist."
    verification:
      - kind: integration
        ref: "node --test tools/javascript/test/replay.test.mjs web/test/golden-replay.test.mjs"
        status: pass
    human_judgment: false
  - id: D2
    description: "The verified DTO preserves authoritative event/frame order, stable identities, decimal timestamps, preview bytes, privacy facts, and explicit absent scene/transaction state."
    verification:
      - kind: unit
        ref: "web/test/golden-replay.test.mjs#accepted exact replay projects one serializable authoritative view"
        status: pass
    human_judgment: false
  - id: D3
    description: "Every tested runner, report, JSON, identity, projection, and cleanup failure returns only the closed sanitized rejection."
    verification:
      - kind: unit
        ref: "web/test/golden-replay.test.mjs#runner, report, JSON, and cleanup failures return one sanitized rejection"
        status: pass
    human_judgment: false

duration: 14min
completed: 2026-07-18
status: complete
---

# Phase 07 Plan 01: Verified Replay Boundary Summary

**An exact-version Next.js package now exposes one fixed golden capture only after the existing Phase 2 runner accepts it, producing a closed serializable replay view or one sanitized rejection.**

## Performance

- **Duration:** 14 min
- **Started:** 2026-07-18T18:29:00Z
- **Completed:** 2026-07-18T18:43:23Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments

- Added the separately locked `web` package with only the audited exact Next, React, TypeScript, and type dependencies under Node 22.22.3.
- Added a server-only, argument-free loader that snapshots the fixed repository fixture, runs the exact pinned Phase 2 CLI with no shell, requires the accepted report, projects only then, and removes its exclusive temporary parent.
- Added a JSON-serializable replay view containing the fixed Mode B0 labels, accepted verification/archive identities and digests, seven authoritative events, one accepted synthetic frame, manifest privacy facts, and honest `not_present`/`unavailable` capability states.
- Added fail-closed coverage for report/fixture/archive/digest/path/content mismatches plus runner, missing-report, malformed-JSON, and cleanup failures.

## Task Commits

1. **Task 1: Create the exact-version web package** — `f02f0ee` (`chore`)
2. **Task 2 RED: Define the verified replay boundary** — `3d84e96` (`test`)
3. **Task 2 GREEN: Expose the verified golden replay DTO** — `5e805d3` (`feat`)

## Files Created/Modified

- `web/package.json` and `web/package-lock.json` — Exact private package, scripts, engines, dependency graph, and reproducible lock.
- `web/tsconfig.json`, `web/next.config.ts`, and `web/next-env.d.ts` — Strict App Router TypeScript/Next configuration.
- `web/src/lib/replay/types.ts` — Closed verified/rejected result plus serializable replay-view contracts.
- `web/src/lib/replay/project-verified-view.ts` — Pure allowlisted projection of the accepted fixed report and verified archive members.
- `web/src/lib/replay/load-golden-capture.server.ts` — Fixed-path server-only process/filesystem orchestration and sanitized failure boundary.
- `web/test/golden-replay.test.mjs` — Exact runner integration, projection identity/order, mutation, serialization, process-argument, and cleanup coverage.

## Decisions Made

- Kept `tools/javascript/src/replay.ts` byte-identical to its pinned Phase 2 revision and invoked it as the only verifier; the web package does not implement JCS, schemas, archive recovery, or canonical replay.
- Used a private fixture copy inside the exclusive temporary parent. The verifier accepts that snapshot, and all presentation reads come from the same snapshot, closing a possible verify-then-read race without changing fixture bytes or verifier behavior.
- Kept the public loader argument-free. Its test-only effects seam can fail process/read/cleanup operations but cannot introduce a request-selected production fixture or path.
- Left `FR-WEB-001`, `SEC-RETENTION-001`, and `GATE-008` pending as required by the sprint cut. This plan proves only the server verification/DTO slice.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Correctness] Prevented verifier-to-projection fixture races**

- **Found during:** Task 2 implementation
- **Issue:** Verifying repository files and then rereading the shared source paths could allow different bytes to be projected if those files changed between the two operations.
- **Fix:** Copied the fixed fixture into the exclusive temporary parent before invoking Phase 2, then projected only from that verified private copy.
- **Files modified:** `web/src/lib/replay/load-golden-capture.server.ts`, `web/test/golden-replay.test.mjs`
- **Verification:** The loader test proves the copied manifest is the fixed CLI input, the DTO is verified, and the temporary parent is absent afterward.
- **Committed in:** `5e805d3`

---

**Total deviations:** 1 auto-fixed correctness issue
**Impact on plan:** The change tightens the planned trust boundary without adding a selectable path, second verifier, persistence, service, provider, or product capability.

## Issues Encountered

- The first GREEN assertion rejected the deliberately generic word `fixture` in the sanitized user message. The assertion was narrowed to sensitive path/temp/stack/secret patterns; the production result was already correctly sanitized.

## Known Stubs

None. `not_present` and `unavailable` values are intentional truthful capability states required by the locked sprint scope, not placeholder data flows.

## Verification Evidence

- Fresh `npm ci --ignore-scripts` completed for both `tools/javascript` and `web` from their exact locks.
- `node --test tools/javascript/test/replay.test.mjs web/test/golden-replay.test.mjs` passed all 9 tests.
- `npm --prefix web run typecheck` passed under TypeScript 6.0.2 and Node v22.22.3.
- Direct dependency versions and licenses matched the audited set: Next/React/React DOM and all type packages are MIT; TypeScript is Apache-2.0.
- Fixture manifest SHA-256 remained `3b4519d2730e158df73e938f7b841664c6ce5f7d65ed2650c90ca8e89c7a7610`; replay-report schema SHA-256 remained `821784ce1a3e4f45c2fe4db70f8f16643284f2e3e9f6effe85a7aee3e17bb9a9`.
- `tools/javascript/src/replay.ts` has no diff from pinned revision `0d371bc1de9a057cbf61b70142729f6cbe620eec`.
- Changed-file secret patterns and `git diff --check -- web tools/javascript/src/replay.ts tools/javascript/test/replay.test.mjs` passed.

## User Setup Required

None. No credentials, cloud service, deployment, authentication, upload, provider, account, or device connection was added.

## Next Phase Readiness

- Plan 07-02 can consume `loadGoldenCapture()` directly from a Server Component and pass only `VerifiedReplayView` to its interactive client leaf.
- The timeline, frame, digest, privacy, and capability data needed by the local recorded-replay interface are available without granting the browser verification, filesystem, network, persistence, or mutation authority.
- Browser smoke, full retention lifecycle, general capture/video import, full `FR-WEB-001`, and `GATE-008` remain pending.

## Self-Check: PASSED

- All nine declared plan artifacts exist.
- Task commits `f02f0ee`, `3d84e96`, and `5e805d3` exist.
- Both focused verification commands, exact lock installs, fixture/source integrity checks, license checks, secret-pattern scan, and whitespace checks passed after the GREEN commit.
- Concurrent `.planning/config.json`, Xcode project/scheme, generated Swift package, workspace, and user-data changes remained outside every plan commit.

---
*Phase: 07-separate-mode-b0-web-fallback*
*Completed: 2026-07-18*
