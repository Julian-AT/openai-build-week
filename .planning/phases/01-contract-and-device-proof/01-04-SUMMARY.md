---
phase: 01-contract-and-device-proof
plan: "04"
subsystem: tooling
tags: [supply-chain, npm, python, swiftpm, lockfiles, offline-verification]

requires:
  - phase: 01-contract-and-device-proof
    provides: Human-approved six-candidate dependency audit from Task 1
provides:
  - Six exact human-approved dependency decisions with bounded provenance
  - Reproducible npm, Python, and Swift package locks
  - Offline dependency-set, artifact, provenance, and pin drift verifier
affects: [01-03, 01-05, 01-06, 01-08, javascript-runtime, python-runtime, swift-runtime]

tech-stack:
  added: [ajv-8.20.0, ajv-formats-3.0.1, canonicalize-3.0.0, jsonschema-4.26.0, rfc8785-0.1.4, swift-json-schema-0.13.1]
  patterns: [human-gated exact dependencies, audited reachable transitive closure, offline fail-closed lock verification]

key-files:
  created:
    - tools/javascript/package-lock.json
    - tools/python/requirements.lock
    - ios/Packages/ReRoomContracts/Package.swift
    - ios/Packages/ReRoomContracts/Package.resolved
    - tools/verify/verify_phase_01_dependencies.py
  modified:
    - evidence/dependencies/phase-01-package-audit.json
    - tools/python/requirements.in

key-decisions:
  - "The human approved all six candidates only at their audited exact versions/revision, artifact integrity/hash, licenses, and sources; this is not blanket package approval."
  - "Resolved transitives are permitted only as the exact compatible-license, integrity/hash/pin-bound closure proven reachable from an approved root."
  - "Swift Package.swift requires swift-json-schema exactly at 0.13.1, while Package.resolved additionally binds its audited f299eb1 revision."

patterns-established:
  - "Direct manifest sets are derived from final human decisions and must equal the approved ecosystem subset."
  - "The local-only verifier treats lock provenance and integrity drift as a release-blocking failure."

requirements-completed: [NFR-CONTRACT-001]

coverage:
  - id: D1
    description: "All six dependency candidates have exact, human-provenanced approved decisions and compatible license/artifact evidence."
    requirement: NFR-CONTRACT-001
    verification:
      - kind: other
        ref: "approval/license audit over evidence/dependencies/phase-01-package-audit.json"
        status: pass
    human_judgment: false
  - id: D2
    description: "Exact npm, Python, and Swift locks contain only approved roots and audited reachable transitives, with offline drift rejection."
    requirement: NFR-CONTRACT-001
    verification:
      - kind: integration
        ref: "python3 tools/verify/verify_phase_01_dependencies.py --audit evidence/dependencies/phase-01-package-audit.json --package-json tools/javascript/package.json --package-lock tools/javascript/package-lock.json --requirements-in tools/python/requirements.in --requirements-lock tools/python/requirements.lock --swift-package ios/Packages/ReRoomContracts/Package.swift --swift-resolved ios/Packages/ReRoomContracts/Package.resolved"
        status: pass
    human_judgment: false

duration: 22min
completed: 2026-07-16
status: complete
---

# Phase 01 Plan 04: Approved Dependency Closure Summary

**Six exact human-approved roots now resolve through reproducible npm, Python, and Swift locks whose compatible-license transitive closure is integrity-bound and verified fully offline.**

## Performance

- **Duration:** 22 min
- **Started:** 2026-07-16T11:26:00Z
- **Completed:** 2026-07-16T11:48:42Z
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments

- Recorded an individual human `approved` decision and exact-scope provenance for `ajv`, `ajv-formats`, `canonicalize`, `jsonschema`, `rfc8785`, and `swift-json-schema` without changing their audited versions, revision, or artifact digests.
- Generated npm, hash-pinned Python, and SwiftPM locks containing three, two, and one approved direct roots respectively, plus ten exact audited transitives reachable from those roots.
- Added a bounded standard-library verifier that reads only the audit and specified manifests/locks, runs without network access, and rejects decision, direct-set, source, version, integrity/hash, license, provenance, closure, and Swift pin drift.

## Task Commits

Each task was committed atomically:

1. **Task 1: Prepare exact dependency audit and fallback manifests** - `b2c7ee5` (chore)
2. **Task 2: Approve package audit before install** - `ff99430` (chore)

**Plan metadata:** recorded by the closeout commit containing this summary.

## Files Created/Modified

- `evidence/dependencies/phase-01-package-audit.json` - Exact human decisions, approval scope, and audited transitive closure evidence.
- `tools/javascript/package-lock.json` - npm lockfile v3 with three approved roots and four reachable integrity-bound transitives.
- `tools/python/requirements.in` - Exact approved Python direct requirements.
- `tools/python/requirements.lock` - Hash-pinned six-package Python closure with resolver provenance annotations.
- `ios/Packages/ReRoomContracts/Package.swift` - Exact Swift package requirement and contract-library package boundary.
- `ios/Packages/ReRoomContracts/Package.resolved` - Audited Swift root revision plus two reachable transitive revisions.
- `tools/verify/verify_phase_01_dependencies.py` - Bounded offline verifier for all approval, manifest, lock, closure, and pin invariants.

## Decisions Made

- Applied the user's explicit option 1 approval to all six candidates, limited to the exact evidence already recorded by Task 1.
- Treated transitive resolution as derived closure rather than new direct approval; every transitive now has a recorded exact version, compatible license, source/integrity or revision, and parent chain.
- Used the Swift exact semantic version in `Package.swift` and required the immutable audited tag revision in `Package.resolved`.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- The plan resumed after its blocking human checkpoint. The completed Task 1 commit was verified byte-for-byte and preserved without amendment before Task 2 began.
- GSD health retains the pre-existing non-repairable `adaptive` model-profile warning; GSD consistency passes with only expected notices for future phase directories not yet created.

## Verification Evidence

- Downloaded every approved direct artifact and rechecked all recorded npm SHA-512/SHA-1, PyPI SHA-256, and Swift archive SHA-256 values before mutation.
- Offline verifier passes: 6 final decisions, direct npm/Python/Swift roots `3/2/1`, and 10 audited reachable transitives.
- Negative probes confirmed rejection of a pending decision, an extra npm direct, npm integrity drift, an unreachable npm node, Python hash drift, and Swift revision drift.
- License audit passes for six approved roots and ten compatible-license transitives.
- Secret-pattern scan, install/build-directory scan, GSD consistency, verifier syntax, and `git diff --check` pass.

## User Setup Required

None - later package consumption must use the committed verified locks.

## Next Phase Readiness

- JavaScript, Python, and Swift contract runners may now consume only the committed exact locks.
- No unapproved direct package, unaudited transitive, resolver directory, or physical/human evidence claim remains in this plan.

## Self-Check: PASSED

- All eight declared manifest, lock, audit, and verifier files exist.
- Task commits `b2c7ee5` and `ff99430` exist in history.
- Stub scan and GSD summary verification pass.

---
*Phase: 01-contract-and-device-proof*
*Completed: 2026-07-16*
