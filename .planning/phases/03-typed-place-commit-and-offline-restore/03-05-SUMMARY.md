---
phase: 03-typed-place-commit-and-offline-restore
plan: "05"
subsystem: native-room-edit
tags: [swiftui, observation, actors, accessibility, durable-transactions, offline-restore]

requires:
  - phase: 03-typed-place-commit-and-offline-restore
    plan: "04"
    provides: sole crash-safe native branch authority, exact CAS, durable receipts, restart recovery, and offline compensation
provides:
  - compact native four-operation surface with place and restore available offline and typed replace/remove blockers
  - MainActor presentation adapter over immutable native-authority snapshots with Button-only confirmation ingress
  - repository-owned digest-bound Phase 3 chair proxy with explicit local-demo provenance
  - simulator coverage for preview, cancel, confirm, restart recovery, restore, blocker visibility, and confirmation safety
affects: [03-06, 03-07, native-mode-a, demo-sprint]

tech-stack:
  added: []
  patterns:
    - MainActor Observation presentation model with private canonical dependencies
    - explicit SwiftUI Button commands crossing into one actor-owned transaction authority
    - scoped Documents durability root with immutable restart-derived presentation snapshots

key-files:
  created:
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/RoomEditModel.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/RoomEditView.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/Resources/Phase3Proxy/asset-manifest.json
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/Resources/Phase3Proxy/proxy-chair.usda
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/Resources/Phase3Proxy/PROVENANCE.md
    - ios/ReRoomDeviceProof/ReRoomDeviceProofTests/RoomEditModelTests.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProofUITests/RoomEditJourneyTests.swift
  modified:
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/App.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/project.pbxproj

key-decisions:
  - "Expose exactly place, replace, remove, and restore while retaining replace/remove as visible typed nonmutating blockers until their later capability slices exist."
  - "Convert live ARKit pose and support evidence to immutable transaction-core values before proposing place; no ARKit object enters the pure authority boundary."
  - "Create explicit native-ui confirmation only inside dedicated Button command methods, leaving preview, cancellation, SwiftUI state, and relaunch presentation revision-neutral."
  - "Label the generated chair as a digest-bound Phase 3 local demo proxy and make no production compositor, catalog parity, measured quality, or deferred-gate claim."

requirements-completed: [FR-PLACE-001, FR-RESTORE-001, FR-TRANSACTION-001, FR-AGENT-001]

coverage:
  - id: D1
    description: "The presentation model binds the closed proxy manifest, requires support, keeps preview/cancel at r, confirms once to r+1, recovers after restart, and restores offline to r+2."
    requirement: FR-PLACE-001
    verification:
      - kind: integration
        ref: "ios/ReRoomDeviceProof/ReRoomDeviceProofTests/RoomEditModelTests.swift"
        status: pass
      - kind: integration
        ref: "xcodebuild test -only-testing:ReRoomDeviceProofTests/RoomEditModelTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "The accessible native journey exposes exactly four operation selectors, visible typed blockers, one explicit confirmation, durable relaunch state, and compensating restore."
    requirement: FR-RESTORE-001
    verification:
      - kind: end_to_end
        ref: "ios/ReRoomDeviceProof/ReRoomDeviceProofUITests/RoomEditJourneyTests.swift"
        status: pass
      - kind: end_to_end
        ref: "xcodebuild test -only-testing:ReRoomDeviceProofUITests/RoomEditJourneyTests"
        status: pass
    human_judgment: false
  - id: D3
    description: "Debug and Release products compile, the protected Release surface remains closed, and no deferred gate is promoted by the proxy or UI."
    requirement: FR-AGENT-001
    verification:
      - kind: build
        ref: "Debug and Release xcodebuild on iPhone 17 simulator"
        status: pass
      - kind: other
        ref: "scripts/verify-reroom-release-surface"
        status: pass
    human_judgment: false

duration: 25min
completed: 2026-07-18
status: complete
---

# Phase 3 Plan 5: Native Four-Operation Place/Restore Surface Summary

**The Release app now presents a compact native four-operation journey where a supported chair proxy previews without revision change, confirms durably once, survives restart, and restores offline through a fresh compensating transaction.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-07-18T14:49:00Z
- **Completed:** 2026-07-18T15:14:24Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments

- Added an `@MainActor @Observable` presentation model that converts live AR support into core values, delegates every canonical decision to `NativeBranchAuthority`, and publishes immutable revision/readiness/durability snapshots.
- Added a Dynamic Type-safe SwiftUI surface with exactly four operation Buttons, visible replace/remove blockers, provisional confirm/cancel controls, restart-derived committed status, and offline restore.
- Added a repository-owned generated USDA chair proxy whose closed manifest pins stable identity, generation recipe, local-demo qualification, and source SHA-256 `afdd38d8713f7e02fb91b15709094c9a0f990d91cedddf8812ea7e4ae5e32379`.
- Preserved the Debug diagnostic default, explicit UI-test route, launch-gated GATE-001 route, protected Release identifiers, and all pre-existing user Xcode signing/resource-format/scheme edits.

## Task Commits

Each behavior-bearing task began with failing tests before implementation:

1. **Task 1 RED: room-edit model contract** - `8d92532` (test)
2. **Task 1 GREEN: durable room-edit presentation model and proxy** - `f948da3` (feat)
3. **Task 1 regression: restart test authority correction** - `acfc15d` (test)
4. **Task 2 RED: complete native UI journey** - `ea3c31b` (test)
5. **Task 2 GREEN: accessible four-operation surface** - `e4419f2` (feat)
6. **Task 2 regression: stable accessibility nodes** - `f7037d6` (fix)

## Files Created/Modified

- `RoomEditModel.swift` - MainActor presentation adapter, live support conversion, scoped local authority/store, typed blockers, preview, confirm, restart, and restore commands.
- `RoomEditView.swift` - Four-operation native owner/view, immutable status panels, provisional controls, and stable accessibility surface.
- `Resources/Phase3Proxy/*` - Closed manifest, text USDA chair geometry, and honest provenance record.
- `RoomEditModelTests.swift` - Proxy binding, support rejection, exact revisions, restart/offline restore, and nonmutating blocker coverage.
- `RoomEditJourneyTests.swift` - End-to-end selector, blocker, preview/cancel/confirm, relaunch, and restore journey.
- `App.swift` - Normal Release room-edit route while preserving Debug diagnostics and explicit diagnostic/test arguments.
- `project.pbxproj` - Scoped new source, test, resource, and `ReRoomTransactionCore` product linkage.

## Decisions Made

- Keep canonical scene arrays, revisions, persistence, receipt activation, and restore authority entirely outside SwiftUI; the view receives only presentation snapshots and invokes commands.
- Keep the human-facing proxy label separate from its canonical stable asset identifier so copy can remain honest without weakening transaction identity.
- Require live visual capture plus horizontal support for production preview, while allowing only the explicit simulator UI-test launch route to inject deterministic support.
- Use a dedicated accessibility marker for the protected Release root and a single textual revision node, avoiding identifier inheritance and duplicated image/text matches.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected restart verification to query the recovered authority**
- **Found during:** Task 1 GREEN test run
- **Issue:** The test committed restore through a restarted authority but then queried the intentionally stale pre-restart instance.
- **Fix:** Read the post-restore snapshot from the recovered authority that performed the mutation.
- **Verification:** Focused model tests and the full app unit suite pass.
- **Committed in:** `acfc15d`

**2. [Rule 1 - Bug] Stabilized root and revision accessibility nodes**
- **Found during:** Task 2 GREEN UI run
- **Issue:** Parent identifier inheritance replaced the room root identifier, and a labeled system image exposed two matches for the revision identifier.
- **Fix:** Added a separate clear root marker and split the decorative image from one identified revision text node.
- **Verification:** The complete UI journey passed twice without source changes between runs.
- **Committed in:** `f7037d6`

---

**Total deviations:** 2 auto-fixed test/presentation bugs
**Impact on plan:** Both fixes improve evidence correctness and automation stability without changing product scope, canonical authority, or gate status.

## TDD Gate Compliance

- Task 1 RED failed because `RoomEditModel` and its closed proxy contract did not exist; GREEN proves exact preview, confirmation, restart, restore, and blocker behavior.
- Task 2 RED failed on the preserved Debug diagnostic screen; GREEN routes only the explicit UI-test argument and normal Release surface to the new journey.
- The focused UI journey passed, then passed again unchanged; complete package and app-unit regressions also pass.

## Verification

- Focused `RoomEditModelTests` — 5 tests passed.
- Focused `RoomEditJourneyTests` — 1 complete UI journey passed twice; latest run 22.781 seconds.
- Complete app unit target — passed (`Test-ReRoomDeviceProof-2026.07.18_17-12-40-+0200.xcresult`).
- `swift test --package-path ios/Packages/ReRoomContracts` — 129 tests in 21 suites passed.
- Debug iPhone 17 simulator build — passed.
- Release iPhone 17 simulator build — passed.
- `scripts/verify-reroom-release-surface` — passed against the Release app.
- `plutil -lint`, scoped secret/source scans, empty-index check, and `git diff --check` — passed.

## User Setup Required

None. The proof uses a bundled repository-owned proxy and local Documents persistence; no account, service, model, provider, or network configuration is required.

## Next Phase Readiness

- Ready for `03-06-PLAN.md` to emit isolated Swift, TypeScript, and Python transaction traces over the now-visible proposal/blocker/confirm/restore journey.
- Physical-device, reconnect, compositor, catalog/license, visual-quality, and human gate evidence remain explicitly `PENDING` under `.planning/SPRINT-CUT-36H.md`; this plan promotes none of them.

---
*Phase: 03-typed-place-commit-and-offline-restore*
*Completed: 2026-07-18*

## Self-Check: PASSED

- All nine planned files exist and the RED/GREEN commit chain is present.
- Focused model/UI, full app-unit, full package, Debug/Release, and protected Release-surface verification pass.
- The source exposes exactly four operations, has no undo selector, and retains only two dedicated Button-originated explicit confirmation constructors.
- Pre-existing `.planning/config.json`, Xcode signing/resource-format/scheme edits, workspace, user data, and local Swift build artifacts remain unstaged.
