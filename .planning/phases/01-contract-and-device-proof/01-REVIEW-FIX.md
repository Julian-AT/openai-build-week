---
phase: 01-contract-and-device-proof
fixed_at: 2026-07-17T19:28:15Z
review_path: .planning/phases/01-contract-and-device-proof/01-REVIEW.md
iteration: 1
findings_in_scope: 3
fixed: 3
skipped: 0
status: all_fixed
---

# Phase 01: Code Review Fix Report

**Fixed at:** 2026-07-17T19:28:15Z
**Source review:** `.planning/phases/01-contract-and-device-proof/01-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 3
- Fixed: 3
- Skipped: 0

## Fixed Issues

### CR-05: A version-specific SwiftPM manifest bypasses the bound source set

**Status:** fixed
**Files modified:** `scripts/run-three-runtime-agreement`, `tools/verify/tests/test_three_runtime_agreement.py`, `evidence/compatibility/contract-agreement.json`, `evidence/compatibility/jcs-agreement.json`, `evidence/compatibility/coordinate-agreement.json`
**Commit:** `37e1f10`
**Applied fix:** Closed the Swift package-root manifest namespace before and after execution, rejected every execution-eligible `Package@swift-*` sibling including ignored and non-regular variants, bound the selected primary manifest path and SHA-256 into every report, and added regressions for major/minor/patch names, leading-zero names, ignored files, symlinks, target redirection, and an execution-time manifest mutation.

### CR-06: The ordinary command does not enforce the pinned Node runtime

**Status:** fixed
**Files modified:** `scripts/run-three-runtime-agreement`, `tools/verify/tests/test_three_runtime_agreement.py`, `evidence/compatibility/contract-agreement.json`, `evidence/compatibility/jcs-agreement.json`, `evidence/compatibility/coordinate-agreement.json`
**Commit:** `5507b55`
**Applied fix:** Parsed the exact Node engine from the bound JavaScript package metadata, required the PATH-selected executable to report exactly `v22.22.3` before runtime work, required reports to carry that exact runtime provenance, regenerated all reports under Node 22.22.3, and added a wrong-PATH-runtime regression that proves no report replacement occurs.

### WR-03: Three report replacements are not atomic as a set

**Status:** fixed: requires human verification
**Files modified:** `scripts/run-three-runtime-agreement`, `tools/verify/tests/test_three_runtime_agreement.py`, `evidence/compatibility/contract-agreement.json`, `evidence/compatibility/jcs-agreement.json`, `evidence/compatibility/coordinate-agreement.json`, `evidence/compatibility/three-runtime-agreement-generation.json`
**Commit:** `da8d1c2`
**Applied fix:** Replaced independent report writes with a directory-locked, durable generation transaction. The transaction stages and fsyncs all reports plus a shared hash manifest, retains digest-bound backups, publishes the manifest last, rolls back ordinary replacement faults, and recovers an interrupted prepared or committed transaction before verification. Fault injection covers every report/manifest replacement boundary, and restart recovery proves the verifier restores and accepts only a complete generation.

## Verification

- `python3 -m unittest tools.verify.tests.test_three_runtime_agreement -v` under Node 22.22.3: 16/16 passed.
- Two consecutive ordinary pinned publisher runs reproduced all three reports and the shared generation manifest byte-for-byte.
- `scripts/run-three-runtime-agreement --verify-reports` under Node 22.22.3: passed for all three fixture IDs.
- An ordinary run under PATH-selected Node 26.0.0 failed before runtime work and left all four generation files unchanged.
- `scripts/verify-phase-01-contracts references`: passed.
- Roadmap validation: zero warnings. Planning health: zero errors and only the pre-existing allowlisted `W004` warning.
- Tracked-secret scan and `git diff --check`: passed.

---

_Fixed: 2026-07-17T19:28:15Z_
_Fixer: Codex (generic-agent workaround following gsd-code-fixer contract)_
_Iteration: 1_
