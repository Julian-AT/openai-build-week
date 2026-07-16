---
phase: 01-contract-and-device-proof
plan: "09"
subsystem: swift-policy-runtime
tags: [swift, jcs, sha256, rrfp, archive-paths, coordinates, tdd]

requires:
  - phase: 01-contract-and-device-proof
    provides: Immutable contract, JCS, wire, and coordinate fixtures from Plans 01-01 through 01-07
  - phase: 01-contract-and-device-proof
    provides: Swift package and bounded contract-validation boundary from Plan 01-08
provides:
  - Pure Swift RFC 8785 canonicalization and SHA-256 matching every frozen expected byte and digest
  - Exact trailer-less RRFP-WIRE-1 encode/decode with bounded fail-closed validation
  - Symlink-aware safe archive-relative path validation
  - Pure Swift RR-COORD-1 projection, intrinsics, rigid-transform, correction, and conversion math
affects: [01-10, mode-a-capture, frame-packet-durability, three-runtime-agreement]

tech-stack:
  added: []
  patterns: [strict duplicate-aware JSON parsing, stable rejection enums, exact binary framing, binary32-first coordinate math, parameterized oracle tests]

key-files:
  created:
    - ios/Packages/ReRoomContracts/Sources/ReRoomContracts/CanonicalJSON.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomContracts/WireFrame.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomContracts/ArchivePath.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomContracts/CoordinateMath.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomContractsTests/CanonicalJSONTests.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomContractsTests/WireFrameTests.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomContractsTests/CoordinateMathTests.swift
  modified: []

key-decisions:
  - "Frozen checked-in bytes and stable rejection classes are the Swift policy authority; parsing and evaluation never repair malformed input."
  - "RRFP framing is exactly its 24-byte big-endian prefix, canonical header bytes, and payload bytes, with no checksum or trailer appended."
  - "RR-COORD-1 quantizes inputs through binary32 before comparison and math, preserves row-major serialization with column-vector composition, and accepts only physical-up encoded orientation."
  - "Archive paths are normalized ASCII relative segments and are resolved component-by-component to reject symlink escape from the archive root."

requirements-completed: [NFR-CONTRACT-001, NFR-COORD-001]

coverage:
  - id: D1
    description: "Swift JCS, SHA-256, RRFP-WIRE-1, and archive paths match every frozen positive and negative policy case with exact bytes or stable rejection."
    requirement: NFR-CONTRACT-001
    verification:
      - kind: integration
        ref: "swift test --package-path ios/Packages/ReRoomContracts --filter 'CanonicalJSONTests|WireFrameTests'"
        status: pass
      - kind: integration
        ref: "scripts/run-reference-parity#FX-CONTRACT-001,FX-JCS-001,FX-COORD-001"
        status: pass
    human_judgment: false
  - id: D2
    description: "Swift RR-COORD-1 matches all frozen artifacts, inclusive threshold neighbors, projection/crop order, rigid transforms, correction direction, and fail-closed malformed-input behavior."
    requirement: NFR-COORD-001
    verification:
      - kind: integration
        ref: "swift test --package-path ios/Packages/ReRoomContracts --filter CoordinateMathTests"
        status: pass
      - kind: regression
        ref: "swift test --package-path ios/Packages/ReRoomContracts#29 tests in 4 suites"
        status: pass
    human_judgment: false

duration: 15min
completed: 2026-07-16
status: complete
---

# Phase 01 Plan 09: Swift Serialization, Wire, Path, and Coordinate Policies Summary

**Swift now reproduces every immutable JCS, RRFP wire, archive-path, and RR-COORD-1 policy case with exact outputs, bounded pure code, and stable fail-closed rejections.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-07-16T22:55:20Z
- **Completed:** 2026-07-16T23:09:50Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- Implemented strict UTF-8 JSON parsing with duplicate-name and malformed-Unicode rejection, RFC 8785 canonical serialization, lowercase SHA-256, and exact agreement with all ten frozen JCS cases.
- Implemented the exact 24-byte big-endian RRFP prefix plus canonical header and payload, with bounded lengths, duplicated sequence/length agreement, payload digest verification, and rejection of all eleven frozen mutations including truncation and any trailer byte.
- Implemented normalized ASCII archive-relative paths with absolute, drive, UNC, traversal, backslash, confusable, overlength, and symlink-escape rejection.
- Implemented binary32-first RR-COORD-1 scalar and translation adjacency, projection, intrinsics transform, rigid transform validation, world correction, and ARKit-to-OpenCV conversion; all accepted fixture artifacts and rejection classes match exactly.
- Added Swift Testing suites covering inclusive threshold neighbors, orientation/crop/scale variants, stable fixture order, null/empty/wrong-length values, non-finite/overflow scalars, singular/reflection matrices, transform direction, and visibility.

## Task Commits

Each task was committed as a failing specification followed by its passing implementation:

1. **Task 1 RED: Swift serialization, wire, and path policy specification** - `c483a7d` (test)
2. **Task 1 GREEN: Exact JCS, RRFP, and archive-path policies** - `74e2234` (feat)
3. **Task 2 RED: RR-COORD-1 policy specification** - `2a42167` (test)
4. **Task 2 GREEN: Pure Swift coordinate policies** - `f8594b7` (feat)

**Plan metadata:** recorded by the closeout commit containing this summary.

## Files Created/Modified

- `ios/Packages/ReRoomContracts/Sources/ReRoomContracts/CanonicalJSON.swift` - Strict duplicate-aware JSON parser, RFC 8785 serializer, canonical value model, and SHA-256 helper.
- `ios/Packages/ReRoomContracts/Sources/ReRoomContracts/WireFrame.swift` - Exact bounded RRFP-WIRE-1 encoder/decoder with stable rejection classes.
- `ios/Packages/ReRoomContracts/Sources/ReRoomContracts/ArchivePath.swift` - ASCII archive-relative path policy and symlink-aware root containment.
- `ios/Packages/ReRoomContracts/Sources/ReRoomContracts/CoordinateMath.swift` - RR-FLOAT-1 and RR-COORD-1 value types, math, validation, and fixture evaluator.
- `ios/Packages/ReRoomContracts/Tests/ReRoomContractsTests/CanonicalJSONTests.swift` - Exact JCS bytes/digests, parser rejection, number, path, and manifest-order coverage.
- `ios/Packages/ReRoomContracts/Tests/ReRoomContractsTests/WireFrameTests.swift` - Exact wire image, decode, mutation, no-trailer, and path-fixture coverage.
- `ios/Packages/ReRoomContracts/Tests/ReRoomContractsTests/CoordinateMathTests.swift` - Frozen artifacts/rejections plus threshold, malformed-input, orientation, direction, and visibility coverage.

## Decisions Made

- Kept canonical JSON parsing local and strict so duplicate members and unpaired surrogate escapes remain distinguishable stable rejections before Foundation can normalize them away.
- Made RRFP decoding require total byte equality with the declared header and payload lengths; even one trailing byte is rejected rather than treated as a future extension.
- Quantized all contract coordinate inputs through `Float` before calculations and comparisons, then used the specified inclusive absolute/relative tolerance combination without hidden defaults.
- Required rigid rotation orthogonality, determinant positive one, and the homogeneous last row independently; version corrections must move strictly from an older to a newer world-frame version.

## Deviations from Plan

None - the plan was executed as written.

## Issues Encountered

- GSD health remains degraded only by the pre-existing non-repairable `adaptive` model-profile warning. Consistency passes with expected notices for future phase directories.

## Verification Evidence

- The exact serialization/wire filter passes 12 tests across 2 suites, including 10 JCS cases, 11 wire mutations, and parameterized unsafe-path cases.
- The exact coordinate filter passes 8 tests in 1 suite, including 6 accepted frozen artifacts, 3 frozen rejection classes, 4 intrinsics scenarios, 4 non-finite/overflow cases, and 8 malformed-input cases.
- The complete Swift package passes 29 tests in 4 suites, including the prior bounded contract-validation suite.
- Fresh JavaScript/Python reference parity passes `FX-CONTRACT-001`, `FX-JCS-001`, and `FX-COORD-001` from newly generated outputs.
- Placeholder/stub and changed-file secret scans are clean; `git diff --check` and GSD consistency pass.
- No physical-device, signing, ARKit, camera, thermal, human, cloud, deployment, or publication evidence is claimed.

## User Setup Required

None - the policies use Foundation/CryptoKit and checked-in immutable fixtures; no dependency or environment change was added.

## Next Phase Readiness

- Ready for Plan 01-10 to run the final three-runtime agreement and evidence closeout over the Swift policy implementation.
- Physical-device and human gates remain pending until their named plans collect real evidence.

## Self-Check: PASSED

- All seven declared source/test files exist, and the four RED/GREEN task commits are present in history.
- Both exact task commands, the complete Swift package, fresh reference parity, changed-file scans, GSD consistency, and `git diff --check` pass.
- SwiftPM build artifacts were removed with `swift package reset`; the worktree was clean before this summary was written.

---
*Phase: 01-contract-and-device-proof*
*Completed: 2026-07-16*
