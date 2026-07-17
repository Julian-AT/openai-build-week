---
phase: 01-contract-and-device-proof
plan: "14"
subsystem: device-proof
tags: [ios, arkit, signing, physical-evidence, gate-002, gate-013]
requires:
  - phase: 01-13
    provides: Debug diagnostic surface, Release exclusion proof, and sanitized evidence boundary
provides:
  - Candidate-bound automated preflight for the signed base-iPhone build
  - Human-attested GREEN GATE-013 base-device evidence bound to the final report decision
  - Human-attested GREEN GATE-002 physical coordinate and world-reset evidence bound to the final report decision
affects: [02-atomic-capture-and-exact-replay, mode-a-production-seed]
tech-stack:
  added: []
  patterns: [external-raw-evidence, opaque-digest-binding, explicit-world-reset-quarantine]
key-files:
  created:
    - evidence/device/phase-01/gate-013-report.json
    - evidence/device/phase-01/gate-013-operator-checklist.json
    - evidence/device/phase-01/gate-002-report.json
    - evidence/device/phase-01/gate-002-operator-checklist.json
  modified:
    - evidence/device/phase-01/automated-preflight.json
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/ARSessionPolicy.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/DeviceProofModel.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/DiagnosticChecklistView.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/EvidenceExporter.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProofTests/ARSessionPolicyTests.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProofTests/EvidenceExporterTests.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomContracts/ContractValidation.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomContracts/FrozenSchemaValidator.swift
key-decisions:
  - "Use the structurally Debug-only diagnostic checklist for physical proof while separately retaining the verified clean Release surface."
  - "An explicit ARKit reset advances world_frame_version and quarantines spatial capture because no directed correction is inferred."
  - "Physical GREEN decisions bind human attestation and externally retained raw artifacts by digest; raw room pixels, device identifiers, and signing details remain outside Git."
patterns-established:
  - "Physical metrics bind immutable capture bytes, evaluator provenance, fixture revision, and human observations through opaque external digests."
  - "A failed or incomplete evidence pull triggers another physical measurement; no screen observation substitutes for required durable bytes."
requirements-completed: [OPS-DEVICE-001, NFR-COORD-001, NFR-CONTRACT-001]
duration: 4h
completed: 2026-07-17
---

# Phase 01 Plan 14: Physical Device Gates Summary

**The exact signed diagnostic candidate passed automated preflight and digest-bound human physical GATE-013/GATE-002 on the declared base iPhone, including a measured 0.505941-pixel checkerboard maximum and explicit reset-to-quarantine.**

## Performance

- **Started:** 2026-07-17T08:36:39Z
- **Completed:** 2026-07-17T13:41:03Z
- **Duration:** 4h
- **Tasks:** 3
- **Files modified:** 9 product/evidence files, the V2 evidence boundary and regression coverage, plus this summary

## Accomplishments

- Archived, strictly code-sign verified, clean-installed, and launched the exact Debug diagnostic candidate on the base iPhone 17 path. The candidate archive digest is `ffef3623404f2e902d7aea12ff2aeecd1e86e31490f2a81ade9ff154544e0fb9`; the candidate embeds implementation revision `97d8d9d9b05477bddef8ae0aa3a635ed650dce13`.
- Re-ran the full candidate-bound Phase 1 automated suite: dependency audit, immutable fixtures, three-runtime agreement, mutation gates, Swift/package tests, Debug and Release simulator tests, Release binary-surface inspection, signing validation, evidence fixtures, secret scan, and diff checks all passed.
- Completed separate camera denial/grant and microphone denial/grant cases without recording audio. Camera denial stopped visual capture; microphone denial left ARKit, tap controls, and a minimal visual FramePacket capture available.
- Observed normal ARKit tracking plus horizontal and vertical planes with no rear-LiDAR requirement. The mic-denied physical capture recovered a contiguous five-record authoritative journal with one hash-valid network-eligible FramePacket and no torn tail.
- Measured the versioned physical checkerboard capture at maximum `0.505941` encoded pixel reprojection error, RMS `0.222444`, mean `0.194127`, and zero orientation/crop swaps against the one-pixel/zero-swap targets.
- Verified the landscape negative case kept tracking active while rejecting capture and coaching portrait. An explicit physical ARKit reset advanced `world_frame_version` from 1 to 2 and retained explicit quarantine with no guessed correction.
- Migrated the evidence boundary to `GateReportV2` / `OperatorChecklistV2` after mandatory review found that V1 did not bind the human decision to final report fields. Each V2 checklist now binds the automated preflight, canonical final-report decision, and exact unsigned checklist payload; each report binds the final checklist bytes and the externally retained digest-scoped ballot.
- Bound both GREEN reports to the same successful automated preflight digest and a fresh human ballot approving the four frozen V2 payload digests. The human attestations and all raw device/capture/measurement artifacts remain externally retained and appear in Git only as opaque IDs and SHA-256 digests.
- Migrated the diagnostic app's evidence producer to the same V2 boundary after re-review detected producer/schema drift. Actual Swift-emitted UNRUN/RUNNING/RED bytes now validate against the checked-in schema; automation cannot emit an operator-attestation role.

## Task Commits

1. **Task 1: Candidate-bound automated preflight** - `7101150` (test)
2. **Task 2/3: Initial human-bound physical gate evidence** - `5ffbc61` (test)
3. **Review fix: Bind signed gate decisions with V2 schemas/verifier** - `e87d81c` (fix)
4. **Review fix: Serialize shared schema validation** - `69764a4` (fix)
5. **Review fix: Clear stale capture selection** - `2ada97c` (fix)
6. **Final digest-scoped physical gate attestations** - `26cb685` (test)
7. **Review RED: Expose stale V1 device export** - `2a02253` (test)
8. **Review GREEN: Migrate device exporter to canonical V2** - `a5bff68` (fix)

Supporting preflight/device-proof commits:

- `0e61bbf` - Bind automated preflight to the first signed candidate.
- `63599e0` - Bind preflight to the signed diagnostic candidate required by the physical checklist.
- `a32c4ea` / `6cde11f` - Add the explicit world-reset proof control by RED/GREEN TDD.
- `97d8d9d` - Cover reset-driven spatial invalidation and quarantine.

**Plan metadata:** recorded by the closeout commit containing this summary.

## Files Created/Modified

- `evidence/device/phase-01/automated-preflight.json` - Successful full automation report bound to the final signed candidate digest and embedded implementation revision.
- `evidence/device/phase-01/gate-013-report.json` - Sanitized GREEN signed-device report with opaque external install, permission, capture, and human evidence digests.
- `evidence/device/phase-01/gate-013-operator-checklist.json` - Human checklist bound to the automated preflight, final report-decision digest, unsigned checklist digest, and external attestation digest.
- `evidence/device/phase-01/gate-002-report.json` - Sanitized GREEN physical coordinate report with versioned checkerboard, capture, reset/quarantine, evaluator, and human evidence digests.
- `evidence/device/phase-01/gate-002-operator-checklist.json` - Human coordinate/reset checklist bound to the same preflight plus its own final report-decision and unsigned-checklist digests.
- `ios/ReRoomDeviceProof/ReRoomDeviceProof/ARSessionPolicy.swift` - Explicit ARKit world-reset command/event path.
- `ios/ReRoomDeviceProof/ReRoomDeviceProof/DeviceProofModel.swift` - Reset policy execution and stale spatial-observation invalidation.
- `ios/ReRoomDeviceProof/ReRoomDeviceProof/DiagnosticChecklistView.swift` - Debug-only reset confirmation and explicit quarantine presentation.
- `ios/ReRoomDeviceProof/ReRoomDeviceProofTests/ARSessionPolicyTests.swift` - Reset command and invalidation regression coverage.
- `ios/ReRoomDeviceProof/ReRoomDeviceProof/EvidenceExporter.swift` - Automation-owned GateReportV2 producer with supporting-evidence-only artifact roles.
- `ios/ReRoomDeviceProof/ReRoomDeviceProofTests/EvidenceExporterTests.swift` - Canonical-schema cross-validation of actual Swift output plus role/version drift regressions.
- `ios/Packages/ReRoomContracts/Sources/ReRoomContracts/ContractValidation.swift` - Narrow independent JSON Schema document-validation façade used by canonical boundary tests.
- `ios/Packages/ReRoomContracts/Sources/ReRoomContracts/FrozenSchemaValidator.swift` - Parameterized document version and standard Draft 2020-12 `maxContains` support.

## Decisions Made

- Used the Debug diagnostic product for physical proof because D-07/D-08 require the compact internal checklist, while the independently tested Release product intentionally excludes every diagnostic/exporter control and identifier.
- Promoted the candidate device-proof seed under D-05 only after GATE-013 became human-signed GREEN. A valid RED or incomplete physical report would have remained retained evidence and blocked Phase 2.
- Used quarantine, not a directed correction, for the reset case. The app advances the world epoch but never infers a transform from absent physical correction evidence.
- Kept the temporary physical checkerboard, raw frames, device/launch results, evaluator scripts, and human attestation outside the repository. Checked-in reports carry only schema-approved sanitized facts and opaque external digests.
- Required a new human ballot after the review-driven V2 migration. The earlier attestation remains supporting evidence only; exactly one V2 `operator_attestation` ballot signs the digest-scoped checklist payload for each GREEN decision.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added the missing explicit physical world-reset action**

- **Found during:** Task 3 preflight of the operator procedure
- **Issue:** The checklist reported epoch state but exposed no operator action capable of performing the canonical explicit reset required by GATE-002.
- **Fix:** Added a Debug-only confirmed reset command that calls ARKit with reset tracking/remove anchors, advances the sole epoch owner, clears stale planes, and quarantines capture without inventing correction evidence.
- **Verification:** Focused reset policy tests, Debug UI tests, Release UI exclusion tests, Release surface inspection, and the final full preflight passed.
- **Committed in:** `6cde11f`, `97d8d9d`

**2. [Rule 3 - Blocking] Repeated evidence collection until durable capture bytes were independently measurable**

- **Found during:** Task 2/3 physical evidence retrieval
- **Issue:** The first post-run container pull exposed only the sanitized report, and the first isolated frames showed the room rather than the checkerboard. A later app activation also reused a consumed one-capture process.
- **Fix:** Preserved every raw attempt externally, refused a GREEN inference, hard-terminated the exact app PID, launched a fresh process, repeated the physical capture, and pulled the held container immediately.
- **Verification:** The final immutable capture contains all 54 checkerboard corners, four correctly oriented color markers, a schema-valid packet, exact payload digest, contiguous five-record journal, four self-hashed lifecycle events, and one network-eligible frame.
- **Committed in:** no product change; external measurement evidence is digest-bound by `5ffbc61`

**3. [Rule 1 - Bug] Corrected temporary evaluator corner-array ordering**

- **Found during:** Task 3 numerical evaluation
- **Issue:** OpenCV detected all corners and a 0.505941-pixel maximum but returned the array from the image bottom-right; the first temporary marker sampler assumed top-left and reported a false 180-degree swap.
- **Fix:** Normalized detected grid rows/columns by image coordinates before marker sampling and reran the unchanged capture bytes. Evaluator source/version/package metadata are externally digest-bound.
- **Verification:** Maximum reprojection remained 0.505941 pixel and every payload/dimension/orientation/marker check passed with zero swaps.
- **Committed in:** no product change; corrected external evaluator provenance is bound by `5ffbc61`

**4. [Post-execution review - Critical] Bound the human ballot to final report decisions**

- **Found during:** Mandatory standard-depth Phase 1 code review
- **Issue:** V1 bound the final report to checklist bytes but did not bind the human-approved checklist back to load-bearing final report fields.
- **Fix:** Introduced the non-circular V2 report-decision and unsigned-checklist digest scopes, exact checklist-byte binding, exactly one externally retained operator-attestation ballot, semantic mutation tests, and fresh digest-scoped human approval.
- **Verification:** Twenty-two evidence tests pass, post-signature report/checklist mutations fail closed, both report/checklist pairs independently verify, and gate mode reports both gates GREEN.
- **Committed in:** `e87d81c`, `26cb685`

**5. [Post-execution review - Warning] Serialized shared compiled-schema validation**

- **Found during:** Mandatory standard-depth Phase 1 code review
- **Issue:** Concurrent simulator tests could make overlapping top-level evaluations observe shared validator conditional state.
- **Fix:** Wrapped each compiled schema validator in a lock-backed serialized boundary and added a concurrent determinism stress test.
- **Verification:** The Swift package passes 33 tests, including the concurrent shared-validator test, and the focused simulator capture suite passes.
- **Committed in:** `69764a4`

**6. [Post-execution review - Warning] Cleared a stale selection on rejected reselection**

- **Found during:** Mandatory standard-depth Phase 1 code review
- **Issue:** A valid selected attempt could survive a subsequent rejected orientation selection.
- **Fix:** Clear selection at the start of every selection operation and require `.noSelection` after a rejected reselection.
- **Verification:** The regression failed before the fix and passes in the focused simulator capture suite afterward.
- **Committed in:** `2ada97c`

**7. [Post-execution re-review - Critical] Migrated the device evidence producer to GateReportV2**

- **Found during:** Fresh standard-depth re-review after the first fix iteration
- **Issue:** The canonical schema and checked-in reports required V2, but `EvidenceExporter` still emitted and self-validated V1, so its machine-readable output was rejected by the current boundary.
- **Fix:** Migrated automation-owned output and the local validator to V2/supporting-evidence roles, rejected operator attestations, added standard `maxContains` support, and cross-validated actual emitted bytes with the checked-in schema.
- **Verification:** Fourteen focused exporter tests, the complete Debug iPhone 17 simulator unit target, 33 Swift package tests, 22 canonical evidence tests, signed gate mode, secret scan, and diff check pass.
- **Committed in:** `2a02253`, `a5bff68`

---

**Total deviations:** 7 auto-fixed (2 blocking, 1 evaluator bug, 2 critical review findings, 2 review warnings)
**Impact on plan:** All fixes strengthened the required evidence path without changing canonical product scope, weakening thresholds, adding shipping dependencies, or claiming synthetic proof as physical evidence.

## Issues Encountered

- iOS required the human operator to trust the Apple Development profile after each clean reinstall; automation correctly paused at that device-owned trust boundary.
- Apple device tools emitted a benign provisioning-parameter-provider warning while still acquiring the tunnel, mounting developer services, installing, launching, listing, and copying successfully.
- The temporary OpenCV evaluator was isolated outside the repository at exact version `4.13.0.92`; it did not alter product dependencies or the signed candidate.

## Verification Evidence

- `python3 tools/verify/verify_evidence.py` passes independently for both report/checklist pairs.
- `scripts/verify-phase-01-contracts gate` reports `GATE-013=GREEN,GATE-002=GREEN`.
- The V2 evidence suite passes 22 tests, including mutations to implementation revision, fixtures, environment, supporting artifacts, checklist payload, and attestation digest.
- `swift test --package-path ios/Packages/ReRoomContracts` passes 33 tests across five suites, including the concurrent shared-validator stress test.
- The focused iPhone 17 simulator `CaptureAttemptTests` run succeeds, including the rejected-reselection regression and durable journal/capture matrix.
- The complete Debug iPhone 17 simulator unit target succeeds after the V2 exporter migration; all 14 exporter tests pass against the checked-in canonical schema.
- External device-capture validation reports 5/5 contiguous recovered records, four valid lifecycle events, one hash-valid network-eligible frame, normal tracking, RR-COORD-1, and zero torn tail.
- External physical measurement reports maximum reprojection `0.505941 px <= 1.0 px`, RMS `0.222444 px`, mean `0.194127 px`, and orientation/crop swap count `0`.
- The signed install/launch, base-device facts, developer-service readiness, permission observations, capture trees, measurement provenance, and human attestation resolve externally by the exact digests stored in the GREEN reports.
- Tracked evidence privacy scanning, `git diff --check`, and the gate verifier pass; no raw image, device identifier, account/team value, signing material, or machine path is checked in.

## User Setup Required

None. The profile trust and physical observations required for this gate were completed and signed during execution.

## Next Phase Readiness

- D-05 promotion is authorized: the verified device-proof seed may serve as the Mode A production seed.
- Phase 2 may begin contract-first atomic capture/exact replay work against the proven base-device, RR-COORD-1, RR-JCS-SHA256-1, FramePacket, and journal boundaries.
- Later compositor, provider, thermal, visual-vote, removal, web, security, license, golden-run, and submission gates remain pending; this plan makes no claim for them.

## Self-Check: PASSED

- All five Plan 01-14 evidence files exist and validate.
- Both physical reports are human-attested GREEN and bind the exact successful automated preflight, final report-decision payload, unsigned checklist, external ballot, and their own checklist bytes.
- The versioned physical checkerboard passes the numerical target, landscape rejection is attested, and reset advances to explicit quarantine.
- External raw evidence is retained by opaque digest only; repository privacy/secret rules remain satisfied.
- Phase 1 gate mode and `git diff --check` pass.

---
*Phase: 01-contract-and-device-proof*
*Completed: 2026-07-17*
