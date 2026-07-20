---
phase: 03-typed-place-commit-and-offline-restore
plan: "06"
subsystem: transaction-trace-producers
tags: [swift, typescript, python, deterministic-traces, provenance, offline-restore]

requires:
  - phase: 03-typed-place-commit-and-offline-restore
    plan: "04"
    provides: durable native branch authority, exact CAS, idempotency, restore, and divergence quarantine
  - phase: 03-typed-place-commit-and-offline-restore
    plan: "05"
    provides: native four-operation proposal/blocker/confirm/restore journey
provides:
  - independent exact-Node TypeScript and dependency-free Python transaction trace producers
  - shipping-core Swift transaction trace exporter over NativeBranchAuthority, PlaceReducer, and RestoreReducer
  - byte-stable provenance-bound normalized results with complete proposal, blocker, order, injection, retry, restore, and divergence evidence
affects: [03-07, transaction-evidence, demo-sprint]

tech-stack:
  added: []
  patterns:
    - immutable-oracle comparison only after independent runtime computation
    - exact runtime, fixture, repository revision, and closed source-tree provenance binding
    - atomic exclusive-output publication for every runtime

key-files:
  created:
    - tools/javascript/src/transaction.ts
    - tools/javascript/test/transaction.test.mjs
    - tools/python/reroom_verify/transaction.py
    - tools/python/tests/test_transaction.py
    - ios/Packages/ReRoomContracts/Sources/ReRoomTransactionTraceExporter/NormalizedTraceResult.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomTransactionTraceExporter/main.swift
    - ios/Packages/ReRoomContracts/Tests/ReRoomTransactionTraceExporterTests/TransactionTraceExporterTests.swift
  modified:
    - ios/Packages/ReRoomContracts/Package.swift

key-decisions:
  - "Keep every producer independent and compare normalized semantic output only after each runtime has validated the immutable fixture and computed its own result."
  - "Use the frozen-contract-valid arkit_plane support method in all producers so shipping Swift and independent reference implementations share exact fingerprints and projections."
  - "Include all transaction-core Swift sources in the Swift exporter source digest while keeping runtime-specific provenance outside semantic parity comparison."

requirements-completed: [FR-PLACE-001, FR-RESTORE-001, FR-TRANSACTION-001, FR-AGENT-001]

duration: 20min
completed: 2026-07-18
status: complete
---

# Phase 3 Plan 6: Independent Transaction Trace Producers Summary

**Swift, exact-Node TypeScript, and dependency-free Python now independently consume the immutable Phase 3 fixture and emit byte-deterministic, provenance-bound transaction traces with identical semantic results.**

## Performance

- **Duration:** 20 min
- **Started:** 2026-07-18T17:17:00+02:00
- **Completed:** 2026-07-18T17:37:22+02:00
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments

- Added an executable Node v22.22.3 TypeScript producer and a stdlib-only Python producer that independently validate the pinned fixture, calculate projections and RR-JCS fingerprints, reject fixture/runtime/revision drift, and publish atomically.
- Added a shipping Swift executable that constructs the fixture scene through `ReRoomTransactionCore`, proves preview no-op, exact commit and retry, changed-fingerprint conflict, offline compensating restore, immutable source history, and divergence mutation freeze.
- Emitted the accepted place and restore proposals without pre-authorized confirmation or commit, visible typed nonmutating replace/remove blockers, exact four-operation order, and rejected transform injection in every runtime.
- Proved byte equality across two isolated publications per runtime and exact cross-runtime semantic equality after removing only runtime-specific provenance.

## Task Commits

Each behavior-bearing task began with failing tests before implementation:

1. **Task 1 RED: independent Node/Python trace contracts** - `4e8b7af` (test)
2. **Task 1 GREEN: executable Node/Python producers** - `ecc25be` (feat)
3. **Task 2 RED: shipping Swift exporter contract** - `f461526` (test)
4. **Task 2 GREEN: core-backed Swift exporter and contract-valid parity** - `10de1b6` (feat)

## Decisions Made

- Keep the immutable expected trace file read-only and consult it only after actual trace computation; it never supplies projections, fingerprints, cases, or producer output.
- Keep runtime/source provenance exact and intentionally runtime-specific, while requiring every semantic field—including fingerprints, projections, cases, receipts, revisions, and traces—to match.
- Use the repository's existing native TypeScript execution pattern and exact Node version instead of adding a transpiler, loader, package, or generated JavaScript copy.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Replaced a synthetic support method rejected by the frozen contract**
- **Found during:** Task 2 GREEN shipping-core activation
- **Issue:** The initial independent producers used `fixture_support`; CON-003/CON-005 permit the closed support methods including `arkit_plane`, not the synthetic label.
- **Fix:** Switched all three independent computations to `arkit_plane` and recomputed the affected projection and request fingerprints.
- **Verification:** Swift durable activation succeeds and all three runtimes emit identical fingerprints and projections.
- **Committed in:** `10de1b6`

---

**Total deviations:** 1 auto-fixed contract-validity bug
**Impact on plan:** The correction strengthens frozen-contract compliance without changing the immutable fixture, expected traces, product scope, or gate status.

## TDD Gate Compliance

- Task 1 RED failed only because the Node and Python producer modules did not exist; GREEN passes four tests in each runtime, including isolated byte equality and fail-closed provenance/oracle mutations.
- Task 2 RED failed only because the Swift executable product and source boundary did not exist; GREEN passes four focused tests, including two isolated executable publications.
- No oracle, schema, dependency, physical evidence, or deferred gate was regenerated or promoted.

## Verification

- `node --test tools/javascript/test/transaction.test.mjs` — 4/4 passed under exact Node v22.22.3.
- `PYTHONPATH=tools/python python3 -m unittest tools.python.tests.test_transaction` — 4/4 passed without external packages.
- `swift test --package-path ios/Packages/ReRoomContracts --filter TransactionTraceExporterTests` — 4/4 passed.
- `swift test --package-path ios/Packages/ReRoomContracts` — 133 tests in 22 suites passed.
- Fresh Swift/Node/Python publications matched exactly after deleting only `.runtime` and `.implementation`; all semantic fields remained compared.
- Dependency-drift, cross-runtime import, scoped secret, `git diff --check`, and exclusive-output checks passed.
- Pre-existing Xcode project changes remain recoverable by `/tmp/reroom-pbx-user-post-03-05.patch` with SHA-256 `f56e95241d7a4ac8f0eb1d61d2210834cf52e6ca93475f85855ee4ad052cdeca`.

## User Setup Required

None. All producers run locally from checked-in fixture, contract, and source bytes.

## Next Phase Readiness

- Ready for `03-07-PLAN.md` to orchestrate two isolated runs per runtime, enforce quick/full verification, and publish the sprint evidence transaction.
- Physical-device, human, reconnect, compositor, catalog/license, visual-quality, and deferred risk-gate evidence remain explicitly `PENDING` under `.planning/milestones/v1.0/SPRINT-CUT-36H.md`.

---
*Phase: 03-typed-place-commit-and-offline-restore*
*Completed: 2026-07-18*

## Self-Check: PASSED

- All eight planned files exist and the two RED/GREEN commit pairs are present.
- Focused and full runtime verification passes, and normalized semantic parity is exact.
- No producer imports another runtime's output or authorizes confirmation/commit through proposal bytes.
- Pre-existing `.planning/config.json`, Xcode signing/resource-format/scheme edits, workspace, user data, and local build artifacts remain unstaged.
