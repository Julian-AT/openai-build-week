---
phase: 01-contract-and-device-proof
review: 01-REVIEW.md
fixed: 2026-07-17T03:05:00Z
iteration: 1
findings_fixed:
  critical: 2
  warning: 6
  total: 8
status: fixes_complete_pending_physical_gates
---

# Phase 01 Code Review Fix Report

## Outcome

All two Critical and six Warning findings in `01-REVIEW.md` have regression-first fixes. Each finding, or its tightly coupled boundary, has a failing RED commit followed by a GREEN implementation commit. No physical-device result, signing result, gate promotion, or human decision was fabricated.

## Finding Resolution

| Finding | Resolution | RED | GREEN |
|---|---|---|---|
| CR-01 stable-ID overwrite | Preflight checks the validated durable prefix and filesystem for frame, event, and idempotency collisions before any write; concrete and memory filesystems use create-only publication. | `7d4cdb5` | `7dc1c9b` |
| CR-02 missing capture consent | Capture requires a digest-valid session-bound consent record; denial is an explicit non-capture path; manifest privacy and retention facts derive from the validated choice. | `7c0716e` | `fb5677a` |
| WR-01 torn journal tail | Recovery atomically replaces the journal with its validated canonical prefix and permits a later distinct capture. | `ca9e4a4` | `e128209` |
| WR-02 synthetic/disconnected Debug diagnostics | One Debug-only app owner supplies live epoch, AR/session, packet, journal, build, orientation, and export facts. The primary capture copy remains `Capture Test Frame`; capture consent has explicit allow/deny choices. A validated sanitized evidence request exports successfully. Release exclusion remains compile-time structural. | `1619323` | `c9f142a` |
| WR-03 arbitrary bytes labeled upright | One `CapturedFrameSnapshot` owns pixel bytes, dimensions, crop, transform, intrinsics, pose, tracking, and health. The AR adapter physically orients/encodes pixels; validation rejects unrelated image or transform facts. Checkerboard geometry tests remain automated contract evidence, not physical proof. | `66a3bbd` | `bd9ad44` |
| WR-04 stale AR capture authority | Interruption/failure revokes running state; restart is explicit; attempt completion requires the same healthy atomic frame snapshot selected at attempt start. | `06d7a22` | `6faa9d5` |
| WR-05 three-runtime RR-COORD drift | Swift, JavaScript, and Python consume one frozen boundary vector. Python now applies binary32 quantization, exact RR-FLOAT tolerance boundaries, full rigid/Frobenius and determinant checks, and proper OpenCV rotation; JavaScript validates the same proper rotation boundary. | `790251f` | `c8ddc5d` |
| WR-06 permissive Python migration | Migration applies only to the exact named schema/version predicate, reads a bounded source, validates the source as CON-001 before translation, and rejects reader/source/oversize mutations. | `f7ccc31` | `82049fe` |

Fresh agreement artifacts are bound to implementation revision `c9f142aa31d6b27c4c42901703c68b1da0c6a40f` by `fe4af7f`. The bound source scope now includes the shared runtime-boundary fixture.

## Verification Evidence

Passed:

- `scripts/verify-phase-01-contracts quick`
- `scripts/verify-phase-01-contracts references`
- JavaScript parity mutation suite: 2 tests
- Python parity mutation and reference parity suites: 5 tests
- complete `ReRoomContracts` Swift package suite: 32 tests across 5 suites
- complete Debug `ReRoomDeviceProof` scheme test action, including unit and UI tests
- targeted Debug and Release `DiagnosticSurfaceTests`
- targeted `EvidenceExporterTests`, `CaptureAttemptTests`, and `ARSessionPolicyTests`
- `scripts/verify-reroom-release-surface`
- evidence fixture validation and dependency audit through the quick verifier
- GSD planning consistency validation; no consistency errors
- tracked-secret pattern scan and `git diff --check`

Observed verification limitation:

- The aggregate `xcodebuild test ... -configuration Release` command exits 65 on Xcode 26.4 because the Release unit-test target intentionally excludes all four Debug/internal test sources and Xcode emits an empty `.xctest` bundle with no executable. The targeted Release UI test and Release product/symbol/resource verifier both pass. This pre-existing project/verification-wrapper mismatch was not "fixed" by compiling Debug diagnostics into Release.
- GSD health reports the pre-existing non-repairable warning that `.planning/config.json` uses model profile `adaptive`, while GSD Core 1.7 accepts `quality`, `balanced`, `budget`, or `inherit`. It also reports Plan 01-14 has no summary because that signing/physical plan remains in progress.

## Preserved Blockers and Evidence Boundaries

- `scripts/verify-phase-01-contracts full` remains blocked by its intentional requirements for a real candidate artifact and `REROOM_SIGNING_RESULT=pass`. No signing result was invented to bypass that guard.
- GATE-002 and GATE-013 remain pending real signed-device/operator evidence. Automated simulator, checkerboard, and runtime agreement results do not promote either gate to GREEN.
- Plan 01-14 remains incomplete. No physical capture, ARKit tracking, thermal, camera/microphone authorization, operator signature, or human approval evidence was fabricated.

