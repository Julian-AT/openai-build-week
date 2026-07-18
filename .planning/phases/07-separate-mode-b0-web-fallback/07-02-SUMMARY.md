---
phase: 07-separate-mode-b0-web-fallback
plan: "02"
subsystem: mode-b0-replay-interface
tags: [nextjs, react, accessibility, replay, timeline, local-only]

requires:
  - phase: 07-separate-mode-b0-web-fallback
    plan: "01"
    provides: Closed verified/rejected result, serializable replay DTO, and server-only exact verifier loader
provides:
  - Bounded in-memory verified-event timeline controls
  - Responsive recorded-replay inspection interface over the verified DTO only
  - Dynamic server page with sanitized verification and render failure surfaces
affects: [phase-08-hardening, FR-WEB-001, SEC-RETENTION-001, GATE-008]

tech-stack:
  added: []
  patterns:
    - Async Server Component loads once and passes one serializable DTO to a focused Client Component
    - Single selected-index state with derived event/frame inspection and functional bounded movement
    - Explicit capability status rows instead of controls for unavailable behavior

key-files:
  created:
    - web/src/lib/replay/timeline.ts
    - web/src/components/replay-explorer.tsx
    - web/test/timeline.test.mjs
    - web/src/app/layout.tsx
    - web/src/app/page.tsx
    - web/src/app/error.tsx
    - web/src/app/globals.css
  modified:
    - web/tsconfig.json

key-decisions:
  - "Keep all interaction inside one synchronous Client Component whose only mutable state is the selected event index."
  - "Render the verified DTO directly from a dynamic Server Component with no self-fetching route, API, upload, storage, provider, account, or cloud boundary."
  - "Show raw manifest retention/share/delete values and explicit not-present/unavailable capability states without implying the full retention lifecycle or GATE-008 completion."

patterns-established:
  - "Memory-only timeline: derive selected event/frame during render and clamp every transition without effects, timers, playback inference, or persistence."
  - "Closed UI boundary: rejected verification and unexpected render failures expose no replay children, identifiers, paths, stack text, or archive bytes."

requirements-completed: []
coverage:
  - id: D1
    description: "Timeline selection starts at zero, clamps every direct and previous/next transition, preserves event order, and returns a noninteractive null state for zero events."
    verification:
      - kind: unit
        ref: "node --test web/test/timeline.test.mjs"
        status: pass
    human_judgment: false
  - id: D2
    description: "The production App Router build keeps the exact verifier server-only and renders the recorded replay through one serializable client boundary."
    verification:
      - kind: integration
        ref: "NEXT_TELEMETRY_DISABLED=1 npm --prefix web run build plus client-chunk server-symbol scan"
        status: pass
    human_judgment: false
  - id: D3
    description: "A local production-server request rendered all four locked labels, a stable verified event ID, local-only retention state, and both honest absence messages without a verification-failure panel."
    verification:
      - kind: integration
        ref: "next start -p 3217 plus local HTTP rendered-markup assertions"
        status: pass
    human_judgment: false

duration: 6min
completed: 2026-07-18
status: complete
---

# Phase 07 Plan 02: Recorded Replay Interface Summary

**The verified golden capture now renders as an unmistakable local Mode B0 inspection console with a bounded event scrubber, accepted frame preview, integrity/privacy facts, and honest degradation states.**

## Performance

- **Duration:** 6 min
- **Started:** 2026-07-18T18:45:42Z
- **Completed:** 2026-07-18T18:51:12Z
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments

- Added immutable timeline selection helpers and a native range/previous/next interaction that cannot leave the verified event range or create a selectable zero-event timeline.
- Added one focused Client Component that derives selected event/frame data from the verified DTO and exposes exact stable IDs, decimal device timestamps, payloads, projection digests, frame metadata, manifest privacy facts, and capability status.
- Added the dynamic App Router Server Component that invokes `loadGoldenCapture()` directly and passes replay data across the RSC boundary only for the verified union branch.
- Added high-contrast responsive styling, keyboard-visible focus, reduced-motion handling, long-identifier wrapping, descriptive synthetic-frame text, and closed verification/render failure surfaces.
- Proved the production build and local server-rendered response while finding no loader, fixture, child-process, filesystem, runner, or `.rrcap` strings in built client chunks.

## Task Commits

1. **Task 1 RED: Define bounded replay timeline behavior** — `67236ee` (`test`)
2. **Task 1 GREEN: Add the in-memory replay explorer** — `45be230` (`feat`)
3. **Task 2: Ship the honest recorded replay page** — `df3c068` (`feat`)

## Files Created/Modified

- `web/src/lib/replay/timeline.ts` — Pure clamped selection and movement over readonly events.
- `web/src/components/replay-explorer.tsx` — Single-state interactive timeline, frame, event, integrity, privacy, absence, and capability inspector.
- `web/test/timeline.test.mjs` — RED/GREEN coverage for bounds, immutability, zero events, and non-finite input.
- `web/src/app/layout.tsx` — Local static metadata, viewport, language, and global stylesheet boundary.
- `web/src/app/page.tsx` — Dynamic Server Component with verified/rejected union branching and locked Mode B0 copy.
- `web/src/app/error.tsx` — Sanitized client error boundary with no error detail rendering.
- `web/src/app/globals.css` — Responsive dark forensic layout, focus states, contrast support, and reduced-motion handling.
- `web/tsconfig.json` — Next-required React automatic JSX runtime setting.

## Decisions Made

- Applied the Next.js skill by keeping metadata/layout/page on the server, calling the loader directly instead of self-fetching, retaining the default Node runtime, and isolating `'use client'` to the interactive leaf and error boundary.
- Applied the React performance skill by passing one serializable DTO, storing only the selected index, deriving event/frame values during render, using functional state updates, and defining helper/components outside render bodies.
- Used `next/image` for the manifest-bound data URL with explicit one-pixel dimensions, descriptive synthetic-fixture alt text, and no remote image or font configuration.
- Kept unavailable providers, sharing, typed proposals, ordinary video, and live phone as non-actionable status rows. Scene and transactions explicitly say `not present in this capture`.
- Kept `FR-WEB-001`, `SEC-RETENTION-001`, and `GATE-008` pending. The successful build and HTTP render smoke are not a real-browser claim or the required two-run/fault/ordinary-video/retention evidence.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Build Compatibility] Accepted Next.js mandatory JSX runtime configuration**

- **Found during:** Task 2 production build
- **Issue:** Next.js 16.2.9 required `jsx: react-jsx` and rewrote the older `preserve` setting during its type phase.
- **Fix:** Committed the mandatory React automatic JSX runtime setting while restoring suggested/generated `.next/dev` and `next-env.d.ts` edits so clean typecheck does not depend on build output.
- **Files modified:** `web/tsconfig.json`
- **Verification:** Clean strict typecheck and two post-change production builds passed.
- **Committed in:** `df3c068`

---

**Total deviations:** 1 auto-fixed build-compatibility issue
**Impact on plan:** The change is the framework-required compiler setting and adds no runtime capability, dependency, service, or product scope.

## Issues Encountered

- Next's build process also generated a `.next/types` import in `next-env.d.ts` and suggested a `.next/dev/types` include. Those generated edits were restored after build so the committed clean typecheck remains independent of `.next` output.

## Known Stubs

None. Zero-event/zero-frame branches are required explicit empty states, and `not_present`/`unavailable` rows are truthful locked degradation states rather than placeholder implementations.

## Verification Evidence

- `node --test web/test/golden-replay.test.mjs web/test/timeline.test.mjs` passed all 9 tests.
- `npm --prefix web run typecheck` passed before and after the production build under exact TypeScript 6.0.2.
- `NEXT_TELEMETRY_DISABLED=1 npm --prefix web run build` passed on Next.js 16.2.9; `/` is a dynamic server-rendered route.
- Built client chunks contain none of `child_process`, `load-golden-capture`, `tools/javascript/src/replay`, `fixtures/capture`, `.rrcap`, `node:fs`, or `process.execPath`.
- A local `next start` request returned rendered markup containing all four locked labels, the first stable event ID, `local_only_until_share`, and two `not present in this capture` messages; `Archive verification failed` was absent.
- Changed-file secret-pattern scanning and `git diff --check -- web` passed.

## User Setup Required

None. No deployment, credential, account, auth, upload, network API, database, provider, share link, or cloud resource exists in this slice.

## Next Phase Readiness

- The minimal provider-independent local B0 recorded replay path is ready for browser-level interaction/visual smoke if the approved evidence workflow provides a real browser.
- Full general `.rrcap`/ordinary-video import, scene/transaction fixtures, typed proposals, sharing, server retention/deletion lifecycle, browser/fault matrix, and two-run `GATE-008` evidence remain deferred and pending.

## Self-Check: PASSED

- All seven declared Plan 07-02 artifacts exist, and the required Next compiler adjustment is tracked.
- Commits `67236ee`, `45be230`, and `df3c068` exist.
- Focused tests, strict typecheck, production build, server-rendered response assertions, client-chunk boundary scan, secret-pattern scan, and whitespace check passed.
- Concurrent config, Phase 5 verifier, Phase 8 planning, Xcode, Swift build, workspace, and user-data changes remained outside every Plan 07-02 commit.

---
*Phase: 07-separate-mode-b0-web-fallback*
*Completed: 2026-07-18*
