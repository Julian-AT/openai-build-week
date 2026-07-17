---
phase: 01-contract-and-device-proof
reviewed: 2026-07-17T17:00:43Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - scripts/run-three-runtime-agreement
  - evidence/compatibility/contract-agreement.json
  - evidence/compatibility/jcs-agreement.json
  - evidence/compatibility/coordinate-agreement.json
findings:
  critical: 2
  warning: 1
  info: 0
  total: 3
status: issues_found
---

# Phase 01 Plan 15: Code Review Report

**Reviewed:** 2026-07-17T17:00:43Z
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found

## Summary

The CR-04 end-of-run recheck works for the mutation timing covered by the focused regression: changes to a recorded source or to the publisher during comparator execution fail before `_atomic_write_reports`, and the previous report remains unchanged. Independent checks also confirmed the current 117 recorded files, source digest `7186a0a61c57d2073cdd475b8c8dc877647c1ce88b2e8bec5f87a73395d83ce7`, exact publisher digest `1d923e55769c0f70f9c69428deabcaf6f8892cf59d99f21ae38f8edb341760a8`, canonical `TST-DIGEST-001` trace, distinct `_005` IDs, sorted JSON encoding, and zero-disagreement report fields.

The bounded review is not clean. SwiftPM can execute an untracked version-specific manifest outside the enumerated source set. The checked-in reports were also generated with Node 26 even though the bound package declares exact Node 22.22.3; an ordinary run in the repository's pinned Node environment rewrites all three reports, so checked-in byte reproducibility fails. Finally, the writer makes three independent replacements and can leave a mixed report generation after a later replacement failure.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-05: A version-specific SwiftPM manifest bypasses the bound source set

**File:** `scripts/run-three-runtime-agreement:58-73,158-162,498-505`

**Issue:** The source gate treats `Package.swift` and `Package.resolved` as individual file scopes and only walks scopes that are directories in the bound Git tree. It never enumerates the package root. SwiftPM supports and preferentially selects version-specific manifests matching `Package@swift-(major)[.(minor)[.(patch)]].swift`. In an isolated clone, adding an untracked `ios/Packages/ReRoomContracts/Package@swift-6.swift` left `_require_bound_sources()` passing with exactly 117 records and `extra_recorded=False`, while installed SwiftPM's verbose `dump-package` invocation showed `Package@swift-6.swift` as the manifest it compiled. The same selection applies to the `swift build` calls at lines 498-505. Such a manifest can redefine products, targets, settings, dependencies, and source paths, so the reports can claim the bound `Package.swift` revision and source digest while executing an unrecorded package definition.

**Fix:** Include every SwiftPM execution-eligible manifest in the closed package-root enumeration. Reject any untracked, ignored, symlinked, non-regular, mode-drifted, or historically absent file matching SwiftPM's version-specific manifest pattern before build, and record the selected manifest path/hash. Add focused regressions for `Package@swift-6.swift`, a more-specific minor/patch variant, an ignored variant, a symlink, and a variant that redirects the runner target outside the bound source directories.

### CR-06: The ordinary command does not enforce the pinned Node runtime and cannot reproduce the checked-in bytes

**File:** `scripts/run-three-runtime-agreement:118-126,316-327,490-496`; `evidence/compatibility/contract-agreement.json:24-31`; `evidence/compatibility/jcs-agreement.json:24-31`; `evidence/compatibility/coordinate-agreement.json:24-31`

**Issue:** The harness resolves whichever `node` is first on `PATH` and records its version, but it never enforces the exact runtime declared by the bound `tools/javascript/package.json` (`22.22.3`). The three checked-in reports currently say `v26.0.0`. Running the ordinary command from this repository's active pinned Node 22.22.3 environment passed both times but changed all three checked-in reports from `v26.0.0` to `v22.22.3`; the first before/after SHA comparison therefore failed. Only the second run was stable. The reports were restored to their original HEAD bytes after this read-only test. This violates the plan's locked-environment and byte-for-byte reproduction requirement and allows measured evidence from an unapproved runtime version to be published as passing.

**Fix:** Resolve the declared exact Node engine from the bound package metadata, require `node --version` to equal `v22.22.3` before any runtime work, and fail closed otherwise (or invoke an explicitly locked executable whose artifact is independently verified). Regenerate all three reports under that enforced runtime, then prove two ordinary runs from the normal repository entry environment leave the checked-in hashes unchanged. Add a regression that places a different Node version first on `PATH` and requires failure without report replacement.

## Warnings

### WR-03: Three report replacements are not atomic as a set

**File:** `scripts/run-three-runtime-agreement:461-484`

**Issue:** `_atomic_write_reports()` fsyncs all temporary files, but then calls `os.replace` sequentially. If the second or third replacement fails, or the process terminates between replacements, an earlier report is already new while the remaining reports are old; the `finally` block deletes the still-staged files and performs no rollback. The focused mutation test proves only that pre-write binding mismatches do not call this function. It does not prove set-level publication atomicity. A mixed generation can also pass the narrow `--verify-reports` checks when the publisher and canonical test IDs did not change but environment or raw-result fields did.

**Fix:** Publish a generation directory plus an atomically replaced current-generation pointer/manifest, or implement a durable transaction/rollback protocol that makes readers select either the complete old set or complete new set. Require the shared generation manifest to bind all three report hashes. Add fault-injection tests at every replacement boundary and a restart/recovery test proving consumers never observe or accept a mixed set.

## Closed Findings Rechecked

- **CR-01 closed for the currently enumerated directory scopes:** untracked/ignored `.swift`, `.mjs`, and `.py` files inside those directories, symlinks, non-regular paths, and executable-mode drift are rejected. CR-05 identifies a separate execution-eligible path outside those directory scopes.
- **WR-01 closed:** every report carries the independently recomputed publisher SHA-256, and missing/wrong publisher mutations fail the checked-in verifier. The publisher remains non-self-referential to the report outputs.
- **WR-02 closed:** `FX-JCS-001` maps to canonical `TST-DIGEST-001` in both publisher and report.
- **CR-04 partially closed:** recorded-source and publisher mutations during the tested comparator window fail before report replacement. The new findings above are distinct source-enumeration, runtime-lock, and set-publication defects.

## Verification

- `python3 -m unittest tools.verify.tests.test_three_runtime_agreement -v` — 7/7 passed.
- `scripts/run-three-runtime-agreement --verify-reports` — passed for all three reports.
- Independent current-report coherence — 117 recorded sources; shared source digest and exact publisher digest matched; three distinct `_005` IDs; canonical test IDs, sorted bytes, pass verdicts, and all six disagreement counters verified.
- Isolated SwiftPM bypass reproduction — source gate passed with the untracked variant omitted from records; installed SwiftPM selected `Package@swift-6.swift`.
- Two ordinary publisher runs under active Node 22.22.3 — both executions passed; the first changed all three HEAD reports because they record Node 26.0.0, and the second was stable. The review restored the three report files byte-for-byte to HEAD and removed the generated `.build` directory.
- `git diff --check` passed. No reviewed source/evidence file remains modified by this review; only the pre-existing planning and user/Xcode state remains.

---

_Reviewed: 2026-07-17T17:00:43Z_
_Reviewer: Codex (generic-agent workaround following gsd-code-reviewer contract)_
_Depth: standard_
