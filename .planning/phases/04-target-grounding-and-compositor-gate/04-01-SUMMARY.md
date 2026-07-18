---
phase: 04-target-grounding-and-compositor-gate
plan: "01"
subsystem: native-target-grounding
tags: [swift, swift-testing, arkit, deterministic-reducer, capability-readiness]

requires:
  - phase: 03-typed-place-commit-and-offline-restore
    provides: immutable room-edit snapshots, typed proposal binding, sole branch authority, and durable restore eligibility
provides:
  - deterministic manual chair/table target lifecycle bound to exact world epoch and scene revision
  - stable target identity with versioned frozen-proxy evidence and explicit reseed semantics
  - independent canonical readiness for select, place, replace, remove, and restore
affects: [04-02, 04-03, 04-04, target-recovery, native-mode-a]

tech-stack:
  added: []
  patterns:
    - pure Equatable and Sendable reducer for AR-derived target state
    - immutable exact-epoch spatial evidence separated from stable semantic identity
    - fail-closed capability readiness with stable coded reasons

key-files:
  created: []
  modified:
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/RoomEditModel.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProofTests/RoomEditModelTests.swift

key-decisions:
  - "Keep manual target selection and reseeding revision-neutral; neither path may call NativeBranchAuthority or mutate committed scene state."
  - "Preserve one stable object identity across reseeds while replacing only exact-epoch frozen spatial evidence."
  - "Fail closed on misses, ambiguity, unhealthy tracking, stale revisions, unsupported categories, and wrong world epochs while leaving the prior target unchanged."
  - "Expose each operation's readiness independently and retain canonical fallbacks while formal compositor/provider gates remain pending."

patterns-established:
  - "Target evidence binding: every accepted spatial candidate carries the exact world frame ID/version and captured scene revision."
  - "Recovery: tracking loss or reset revokes unsafe readiness; explicit reseed is the only route back to a current target."

requirements-completed: [FR-TARGET-001]

coverage:
  - id: D1
    description: "One valid manual chair/table candidate creates a revision-neutral, stable, exact-epoch target context; invalid candidate sets are typed and nonmutating."
    requirement: FR-TARGET-001
    verification:
      - kind: integration
        ref: "ios/ReRoomDeviceProof/ReRoomDeviceProofTests/RoomEditModelTests.swift#manual target lifecycle tests"
        status: pass
      - kind: integration
        ref: "xcodebuild test -only-testing:ReRoomDeviceProofTests/RoomEditModelTests"
        status: pass
    human_judgment: false
  - id: D2
    description: "Tracking loss/reset and explicit reseed deterministically update independent select/place/replace/remove/restore readiness without inventing gate evidence."
    requirement: FR-TARGET-001
    verification:
      - kind: integration
        ref: "ios/ReRoomDeviceProof/ReRoomDeviceProofTests/RoomEditModelTests.swift#readiness and reseed tests"
        status: pass
      - kind: integration
        ref: "xcodebuild test -only-testing:ReRoomDeviceProofTests/RoomEditModelTests"
        status: pass
    human_judgment: false

duration: 8min
completed: 2026-07-18
status: complete
---

# Phase 4 Plan 1: Manual Target Lifecycle and Readiness Summary

**The native room-edit model now grounds one stable manual chair/table target through a pure fail-closed reducer, binds its spatial evidence to the exact world epoch and revision, and explains each operation's readiness independently.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-07-18T16:42:09Z
- **Completed:** 2026-07-18T16:50:16Z
- **Tasks:** 1 TDD feature
- **Files modified:** 2

## Accomplishments

- Added immutable candidate, lifecycle, frozen-proxy, failure, environment, event, readiness, and snapshot values plus a pure deterministic target reducer.
- Bound accepted target context to one stable prefixed object identity, the exact AR world ID/version, and the captured scene revision without incrementing the branch revision.
- Made miss, ambiguity, unhealthy tracking, stale revision, wrong epoch, unsupported category, interruption, failure, and reset paths fail closed with stable actionable reason codes.
- Preserved semantic target identity across explicit reseed while replacing only current-epoch proxy evidence and incrementing its evidence version.
- Published independent readiness for select, place, replace, remove, and restore while keeping reveal, dense-provider, mask, OBB, and formal gate claims unavailable or degraded as canonically required.

## Task Commits

The behavior-bearing task followed RED then GREEN:

1. **RED: define manual target lifecycle contract** - `3341d2b` (test)
2. **GREEN: add deterministic manual target reducer** - `ce1bfa8` (feat)

## Files Created/Modified

- `ios/ReRoomDeviceProof/ReRoomDeviceProof/RoomEditModel.swift` - Pure target reducer, exact evidence validation, stable identity, target context binding, recovery commands, meaningful snapshot publication, and independent readiness.
- `ios/ReRoomDeviceProof/ReRoomDeviceProofTests/RoomEditModelTests.swift` - Target seed, fail-closed nonmutation, readiness separation, tracking loss/reset, and stable-identity reseed coverage.

## Decisions Made

- Treat AR input as untrusted evidence: accept it only after finite-value, exact epoch, exact revision, category, uniqueness, and tracking-health checks.
- Keep stable semantic identity separate from replaceable spatial evidence so world reset cannot silently rewrite or migrate a target.
- Require explicit reseed after a lost/reset target; a later normal tracking update cannot implicitly recover stale evidence.
- Keep restore transaction-derived and independent of target tracking, while target-dependent select/place/replace readiness is revoked immediately on loss.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Committed GREEN before its verification run**

- **Found during:** GREEN verification
- **Issue:** The repository's debug provenance phase intentionally rejects a dirty app source tree, so the planned implementation could not compile while uncommitted.
- **Fix:** Inspected the exact staged scope, committed only the planned model implementation, then ran the focused verification against that immutable commit.
- **Verification:** Direct `xcodebuild test` completed with exit code 0 and `** TEST SUCCEEDED **`.
- **Committed in:** `ce1bfa8`

---

**Total deviations:** 1 blocking workflow accommodation
**Impact on plan:** No product or requirement scope changed; RED still preceded GREEN and the final GREEN commit is verified unchanged.

## Issues Encountered

- The fresh Xcode build exhausted local disk space. Only the exact generated ReRoom DerivedData directory was deleted; it is rebuildable and the subsequent clean focused run passed. No repository or user source was removed.
- Plan 04-02 was executing concurrently in the same checkout. Its commits were left intact and are not attributed to this plan.

## TDD Gate Compliance

- RED failed on the intentionally absent `ManualTargetCandidate` and `TargetGroundingEnvironment` contract types.
- GREEN introduced the minimum lifecycle/readiness implementation required by those tests.
- The clean focused `RoomEditModelTests` run passed unchanged from commit `ce1bfa8`.

## Verification

- `xcodebuild test -project ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj -scheme ReRoomDeviceProof -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ReRoomDeviceProofTests/RoomEditModelTests` — passed, direct exit code 0, `** TEST SUCCEEDED **`.
- Scoped placeholder scan of the two plan files — passed; no TODO, FIXME, placeholder, or unimplemented failure trap introduced.
- `git diff --check` — passed.

## User Setup Required

None. This slice adds deterministic model behavior and simulator tests only; it requires no account, provider, network, model, or cloud configuration.

## Next Phase Readiness

- Ready for the shared-session AR event/raycast adapter and local compositor/recovery UI to consume immutable target events and readiness snapshots.
- Formal `GATE-003`, `GATE-004`, `GATE-005`, `GATE-007`, and `GATE-012` device, thermal, provider, and human evidence remains explicitly `PENDING`; this plan promotes none of it.

---
*Phase: 04-target-grounding-and-compositor-gate*
*Completed: 2026-07-18*

## Self-Check: PASSED

- Both planned files exist and commits `3341d2b` and `ce1bfa8` are present.
- The clean focused model test command passes with direct exit code 0.
- No 04-01 code remained uncommitted; the concurrent 04-02 summary plus pre-existing configuration, Xcode project/scheme, workspace/user data, and package build artifacts remained unstaged.
