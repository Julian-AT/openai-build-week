---
phase: 01-contract-and-device-proof
reviewed: 2026-07-17T16:10:57Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - scripts/run-three-runtime-agreement
  - evidence/compatibility/contract-agreement.json
  - evidence/compatibility/jcs-agreement.json
  - evidence/compatibility/coordinate-agreement.json
findings:
  critical: 1
  warning: 2
  info: 0
  total: 3
status: issues_found
---

# Phase 01 Plan 15: Code Review Report

**Reviewed:** 2026-07-17T16:10:57Z
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found

## Summary

The refreshed reports do bind the intended `a5bff6896188dcac9397c48ce1a6820a7196011a` source revision, share the independently recomputed source-tree digest, record distinct deterministic `_002` evidence IDs, and reproduce byte-for-byte through the ordinary checked-in command. The comparator still fails closed on oracle/runtime disagreement, and no shell interpolation or secret exposure was found.

The review nevertheless found one binding bypass and two evidence-provenance defects. The publisher can execute an untracked Swift source file that neither its Git drift check nor its source digest sees; the reports do not bind the publisher that derives their metrics; and the JCS report cites the schema test rather than the canonical digest test that owns `FX-JCS-001`.

## Narrative Findings (AI reviewer)

### Critical Issues

#### CR-01: Untracked executable sources bypass the bound-revision guard

**File:** `scripts/run-three-runtime-agreement:117-149`

**Issue:** `_require_bound_sources` uses `git diff` to compare tracked content and `git ls-tree` to enumerate only paths that existed in the bound commit. Git intentionally omits untracked working-tree files from both operations. SwiftPM automatically discovers `.swift` files under `Sources/ReRoomContracts` and `Sources/ReRoomContractRunner`, so an extra untracked source can be compiled at lines 375-387 while remaining absent from both the drift decision and `source_tree_sha256`. The ordinary command can therefore publish `pass` evidence carrying the same exact implementation revision and digest even though it executed source bytes outside that revision. This violates the exact-source truth and the T-01-15-01 tampering mitigation.

**Fix:** Before any build or runner starts, compare the complete set of execution-eligible files under every bound source directory with the bound Git tree and fail on any extra, missing, non-regular, or mode-mismatched path. At minimum, explicitly reject untracked/ignored `.swift`, `.mjs`, and `.py` files under the executable source scopes and isolate generated Python bytecode outside those scopes; then calculate the digest from that verified exact set.

### Warnings

#### WR-01: Reports do not bind the publisher that derives their metrics

**File:** `scripts/run-three-runtime-agreement:244-335`

**Issue:** The reports bind the runner source tree and `tools/verify/compare_results.py`, but not `scripts/run-three-runtime-agreement` itself. That omission is material because `_build_report` derives `accepted`/`rejected`, sets every disagreement counter, and emits the final `verdict`. The current publisher SHA-256 is `9cd07a00ae13795779641b3bd400d3ae9f6c623269e47029a642482177b89b9c`, while the publisher stored at the reports' named implementation revision has different bytes (`870a288df679f4b4c70f9e89ee2f4edcf75952914930baff619962337c20b8ac`). A changed publisher could therefore emit reports with the same implementation revision, comparator hash, and evidence IDs without any report field identifying which metric-producing code ran. Git history can supply external context, but the MEASURED artifacts themselves leave this repudiation link incomplete.

**Fix:** Add a non-self-referential publisher provenance record to every report containing at least `scripts/run-three-runtime-agreement` and its exact SHA-256, and make the reference verifier require it. Hashing the script bytes is non-circular because the reports are outputs and are not embedded in the script.

#### WR-02: The JCS evidence cites the wrong canonical test ID

**File:** `scripts/run-three-runtime-agreement:29-35`

**Issue:** The `FX-JCS-001` manifest is emitted with `TST-CONTRACT-001`, so `jcs-agreement.json:146-148` claims schema-syntax coverage. Canonical `TEST_AND_EVALUATION_PLAN.md` assigns the three-runtime JCS vectors to `TST-DIGEST-001`; `TST-CONTRACT-001` owns schema syntax and IDs. The runtime result is valid, but its durable acceptance trace points to the wrong test family and does not directly satisfy queries for the canonical digest test.

**Fix:** Change the JCS manifest tuple to `("TST-DIGEST-001",)`, regenerate the reports through the ordinary publisher, and verify the report's test IDs against the canonical fixture-to-test mapping.

## Verification

- `scripts/run-three-runtime-agreement` — passed normally for `FX-CONTRACT-001`, `FX-JCS-001`, and `FX-COORD-001`.
- Report SHA-256 values before and after the ordinary run were identical: contract `4fd1379a…`, JCS `465fdaaf…`, coordinate `5111ce0c…`.
- Independent source-tree recomputation found 117 bound files and digest `7186a0a61c57d2073cdd475b8c8dc877647c1ce88b2e8bec5f87a73395d83ce7`, matching all three reports.
- `git log -1` over the declared source scopes resolves to `a5bff6896188dcac9397c48ce1a6820a7196011a`; tracked scoped bytes match current HEAD.
- Python syntax parsing, focused secret/debug-pattern scanning, report field assertions, and `git diff --check` passed.
- The generated Swift `.build` directory was removed after the ordinary-run check. Pre-existing scheme, `.swiftpm`, workspace, and `xcuserdata` paths remain untouched.

---

_Reviewed: 2026-07-17T16:10:57Z_
_Reviewer: Codex (generic-agent fallback following gsd-code-reviewer contract)_
_Depth: standard_
