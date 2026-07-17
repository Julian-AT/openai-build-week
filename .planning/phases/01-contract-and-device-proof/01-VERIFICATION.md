---
phase: 01-contract-and-device-proof
verified: 2026-07-17T14:46:27Z
status: gaps_found
score: 48/49 must-haves verified
behavior_unverified: 0
---

# Phase 1: Contract and Device Proof Verification Report

**Phase Goal:** The project has one verified contract/coordinate vocabulary and a signed physical base-iPhone path that works without rear LiDAR.
**Verified:** 2026-07-17T14:46:27Z
**Status:** gaps_found

The phase behavior and both physical gates are verified. Closeout is blocked by one reproducibility/provenance gap: the checked-in three-runtime acceptance command and reports still bind `e6a92c9864f814b5b9a8feeec7456eaf9f889db0`, while the later concurrency fix `69764a4d8181d2af30d1ea5277c547f520e5fa3e` changed two files inside that command's bound source scope. A non-publishing run of the same evaluator against current HEAD passed, so this is a stale recorded-evidence gap rather than an observed contract disagreement.

## Goal Achievement

### Roadmap Success Criteria

| # | Truth | Status | Evidence |
|---|---|---|---|
| R1 | A signed build installs and launches on the declared base iPhone, exercises permission/ARKit/plane capability without rear LiDAR, and has repeatable build evidence. | ✓ VERIFIED | Human-supplied GateReportV2/checklist pair for GATE-013 is GREEN and semantically binds candidate `git:97d8d9d9b05477bddef8ae0aa3a635ed650dce13`, the automated preflight, opaque supporting evidence, and signed decision/checklist digests. `scripts/verify-phase-01-contracts gate` passed. |
| R2 | Swift, JavaScript, and Python agree on RR-COORD-1, orientation/intrinsics, RR-FLOAT-1, and world-epoch cases. | ✓ VERIFIED | Fresh current-HEAD, non-publishing execution of the production three-runtime harness passed `FX-COORD-001`; Swift package tests (33), JavaScript tests (5), and Python tests (7) passed with exact oracle/value assertions. |
| R3 | CON-001 through CON-005, RR-JCS-SHA256-1, digests, wire bytes, and malformed input behavior agree and fail closed across all three runtimes. | ✓ VERIFIED | Fresh current-HEAD three-runtime evaluation passed `FX-CONTRACT-001` and `FX-JCS-001`; fixture integrity, mutation gates, schema-selection spoofing, byte/depth limits, wire mutations, and archive-path rejection all passed. |
| R4 | Physical crop/orientation evidence has no row/column swap and unknown alignment is quarantined. | ✓ VERIFIED | Human-supplied GateReportV2/checklist pair for GATE-002 is GREEN and binds the same candidate/preflight plus opaque retained evidence. The verifier validated the V2 schema, digest scopes, single attestation ballot, and cross-file binding without substituting simulator or synthetic observations for the human check. |

### Plan Must-Have Truths

| ID | Truth | Status | Evidence |
|---|---|---|---|
| P01.1 | Exact schema versions and inclusive/exclusive boundaries reject unknown or invalid values without coercion/defaults. | ✓ VERIFIED | Frozen schema corpus, all three runners, and `ContractValidationTests` value assertions passed. |
| P01.2 | Null and empty inputs follow exact schema rules without invented defaults. | ✓ VERIFIED | Swift coordinate/contract negative tests and JS/Python immutable-oracle tests passed. |
| P01.3 | Array order is normative, object normalization is JCS-only, and case rows are lexicographic. | ✓ VERIFIED | Manifest/result schemas, comparator order checks, and runner-order tests passed. |
| P01.4 | Checked-in inputs, bytes, digests, rejection classes, and schema hashes are immutable oracle data. | ✓ VERIFIED | Three-manifest fixture integrity and mutation controls passed; no oracle file changed during evaluation. |
| P02.1 | Gate state is exactly UNRUN, RUNNING, GREEN, RED, or WAIVED_BY_HUMAN. | ✓ VERIFIED | GateReportV2 schema and valid/invalid state tests passed. |
| P02.2 | Automation cannot emit GREEN or WAIVED_BY_HUMAN. | ✓ VERIFIED | Evidence schema/tests and Swift exporter rejection tests enforce actor/state constraints. |
| P02.3 | A waiver requires a human lock change plus PRD and ADR bindings. | ✓ VERIFIED | Waiver schema branches and negative tests passed. |
| P02.4 | Checked-in evidence is sanitized and references raw evidence only by opaque ID/digest. | ✓ VERIFIED | Privacy-negative fixtures, V2 verifier, exporter sanitizer tests, and tracked secret scan passed. |
| P03.1 | One fail-closed comparator verifies oracle integrity and exact per-case agreement. | ✓ VERIFIED | `compare_results.py` integrity, comparison, omission, copied-oracle, and mutation tests passed. |
| P03.2 | Full verification can finish automated preflight before physical evidence and emits only after all required checks pass. | ✓ VERIFIED | Script control flow, existing candidate-bound preflight, final clean review evidence, and preflight/gate separation were inspected; no preflight was regenerated during this verification. |
| P03.3 | Gate mode alone requires signed physical pairs and fails unless both gates are GREEN while retaining RED evidence. | ✓ VERIFIED | Gate script semantics inspected; current signed pairs produced `GATE-013=GREEN,GATE-002=GREEN`. |
| P04.1 | Every dependency has exact version, license/artifact evidence, official-doc provenance, and fallback. | ✓ VERIFIED | Offline dependency verifier passed all six decisions and ten reachable transitives. |
| P04.2 | Candidate set is exactly six named packages and SUS is never a dependency. | ✓ VERIFIED | Audit/manifest/lock set equality passed. |
| P04.3 | Locks exist only after human decisions and match approved exact artifacts. | ✓ VERIFIED | Human-provenance fields and all npm/Python/Swift lock hashes, versions, sources, and parent chains passed. |
| P05.1 | JavaScript independently validates schema, JCS/digest, wire, path, and coordinate cases. | ✓ VERIFIED | Node runner and mutation suites passed 5/5. |
| P05.2 | JavaScript consumes immutable manifests and emits a closed normalized result. | ✓ VERIFIED | Runner envelope and comparator checks passed. |
| P06.1 | Python independently validates all frozen schema/policy cases. | ✓ VERIFIED | Python runner and mutation suites passed 7/7 with no JS-result dependency. |
| P06.2 | Python emits the same closed envelope while retaining independent parser behavior. | ✓ VERIFIED | Fresh comparator agreement and parser-differential cases passed. |
| P07.1 | JavaScript and Python execute independently against identical immutable inputs and agree exactly. | ✓ VERIFIED | Reference-parity tests and fresh three-runtime run passed. |
| P07.2 | Mutation gates detect contract, digest, coordinate, omission, and oracle-integrity faults. | ✓ VERIFIED | JS/Python mutation suites and comparator mutation tests passed. |
| P08.1 | Swift validates all five schemas with the same closed Draft 2020-12 behavior. | ✓ VERIFIED | `ContractValidationTests` passed the complete frozen corpus and cross-runtime current-HEAD comparison. |
| P08.2 | The intentionally bounded Swift validator is benchmarked and fails closed outside its supported keyword surface. | ✓ VERIFIED | Keyword-surface, remote/dynamic/unknown keyword, timebox, schema-tamper, and size/depth tests passed. |
| P09.1 | Swift JCS, SHA-256, RRFP-WIRE-1, and archive paths match exact oracle bytes/classes. | ✓ VERIFIED | Canonical JSON, wire, archive, and runner tests passed. |
| P09.2 | RR-COORD-1 adjacency and projection use exact threshold and transform order. | ✓ VERIFIED | Coordinate math tests passed exact inclusive neighbors and all transform vectors. |
| P09.3 | Null, empty, wrong-length, non-finite, singular, and non-rigid coordinates reject. | ✓ VERIFIED | Parameterized negative coordinate tests passed. |
| P09.4 | Matrices remain row-major serialized with column-vector math and stable case order. | ✓ VERIFIED | Coordinate oracle and math tests passed exact artifacts/order. |
| P10.1 | Swift, JavaScript, and Python independently agree on identical current immutable revisions. | ✓ VERIFIED | Current-HEAD non-publishing run of the production harness passed all three fixture families. |
| P10.2 | Checked-in agreement reports bind the implemented runner revision, source tree, schema/oracle hashes, evaluator, environment, raw-result digests, and measured metrics. | ✗ FAILED | Reports correctly bind `e6a92c...`, but current bound sources differ after `69764a4...`; the checked-in command exits `bound implementation sources differ from their recorded revision`. Current results passed only in a non-publishing verification run, so durable provenance is stale. |
| P11.1 | Device proof is scoped to the declared iOS 26.0 proof baseline, not a broader minimum. | ✓ VERIFIED | Project/build settings and signed GATE-013 report retain the declared proof scope. |
| P11.2 | One portrait-only SwiftUI seed links the contract package and excludes edit/provider/compositor scope. | ✓ VERIFIED | Project/source inspection and Debug/Release builds/tests passed. |
| P11.3 | Camera and microphone permissions are independent; microphone denial never blocks visual/typed paths and no audio recording exists. | ✓ VERIFIED | `ARSessionPolicyTests`, source search, app unit tests, and signed GATE-013 binding cover the boundary. |
| P11.4 | AR tracking and plane callbacks are independent capabilities with no rear-LiDAR requirement. | ✓ VERIFIED | AR policy source/tests and signed GATE-013 GREEN evidence passed. |
| P12.1 | Rotation rejects an in-flight capture while preserving ARSession and coaching retry. | ✓ VERIFIED | `CaptureAttemptTests` and Debug UI orientation test passed. |
| P12.2 | Reset/relocalization advances `world_frame_version`. | ✓ VERIFIED | `WorldEpochTests`, `ARSessionPolicyTests`, and signed GATE-002 binding passed. |
| P12.3 | Only a valid directed correction releases quarantine; other correction states keep capture unavailable. | ✓ VERIFIED | World-epoch correction/quarantine behavior tests passed. |
| P12.4 | Atomic rename establishes only internal durability; visibility/network eligibility follows authoritative journal sync. | ✓ VERIFIED | Capture/journal crash, torn-tail recovery, concrete filesystem, and journal-order tests passed. |
| P13.1 | Internal checklist reports each required capability independently. | ✓ VERIFIED | `DiagnosticChecklistView.swift`, checklist state tests, and Debug XCUITest passed. |
| P13.2 | Export sanitizes and validates before any write, excluding private/raw/signing data. | ✓ VERIFIED | `EvidenceExporter.validatedData` precedes destination creation; exporter/evidence privacy and atomic-publication tests passed. |
| P13.3 | Release UI contains the narrow seed and no diagnostic/export surface. | ✓ VERIFIED | Debug and Release XCUITests passed 1/1 each; same-product release binary/resource scanner passed. |
| P14.1 | Physical evidence is from the declared signed base-iPhone candidate, never automation/simulator substitution. | ✓ VERIFIED | Human-supplied V2 attestations bind candidate `git:97d8...`; automated verification checked only the record/binding semantics. |
| P14.2 | GATE-013 covers the required signed-device capability proof without audio or LiDAR dependence. | ✓ VERIFIED | V2 report/checklist pair is GREEN, single-human-attested, preflight-bound, and passes the semantic verifier. |
| P14.3 | GATE-002 covers required physical geometry/orientation/reset evidence. | ✓ VERIFIED | V2 report/checklist pair is GREEN, single-human-attested, preflight-bound, and passes the semantic verifier. |
| P14.4 | GREEN requires automated pass, resolvable opaque evidence, and accountable signed checklist. | ✓ VERIFIED | Both pairs pass report-decision, unsigned-checklist, exact-checklist-byte, attestation-ballot, automated-preflight, and opaque-artifact binding checks. |
| P14.5 | RED remains exact failure evidence and phase completion requires both gates GREEN. | ✓ VERIFIED | V2 schemas/tests and gate script enforce the lifecycle; current gate command passed only because both are GREEN. |
| P14.6 | D-05 promotion occurs only on GATE-013 GREEN. | ✓ VERIFIED | Gate state is GREEN and the candidate remains the one narrow Mode A seed; non-GREEN/waiver branches remain fail-closed in schema/script tests. |

**Score:** 48/49 truths verified. All four roadmap criteria are verified; one plan-level recorded-provenance truth is stale.

### Must-Have Prohibitions

| Prohibition | Status | Evidence |
|---|---|---|
| Frozen expected bytes/digests/classes/thresholds/revisions must not be altered to manufacture a pass. | ✓ VERIFIED | Fixture integrity, mutation-copy isolation, source review, and unchanged oracle hashes. |
| Rear-LiDAR capability must not be inferred; epochs must not be silently relabeled; partially durable packets must not publish. | ✓ VERIFIED | AR policy, epoch, packet/journal crash-recovery tests, and source inspection. |
| Physical gates must not be GREEN from automation, simulator, missing raw evidence, unsigned checklists, or fabrication. | ✓ VERIFIED | Exact GateReportV2 actor/state rules, one-attestation requirement, signed pair binding, and genuine user attestation. No private raw evidence was read by the verifier. |

### Required Artifacts

| Plan | Artifact | Status | Details |
|---|---|---|---|
| 01-01 | `fixtures/manifest.schema.json` | ✓ EXISTS + SUBSTANTIVE | Closed manifest schema; fixture integrity passed. |
| 01-01 | `fixtures/runner-result.schema.json` | ✓ EXISTS + SUBSTANTIVE | Closed normalized envelope; runtime output validation passed. |
| 01-01 | `fixtures/contracts/1.0.0/rev-001/` | ✓ EXISTS + SUBSTANTIVE | Immutable CON-001–CON-005 corpus with valid/invalid oracle cases. |
| 01-02 | `evidence/templates/gate-report.schema.json` | ✓ EXISTS + SUBSTANTIVE | GateReportV2 actor/state/privacy/binding schema. |
| 01-02 | `evidence/templates/operator-checklist.schema.json` | ✓ EXISTS + SUBSTANTIVE | Non-circular signed checklist binding. |
| 01-03 | `tools/verify/compare_results.py` | ✓ EXISTS + SUBSTANTIVE | Bounded integrity/comparison evaluator; mutation tests passed. |
| 01-03 | `scripts/verify-phase-01-contracts` | ✓ EXISTS + SUBSTANTIVE | Separate deterministic modes; gate mode passed. |
| 01-04 | `evidence/dependencies/phase-01-package-audit.json` | ✓ EXISTS + SUBSTANTIVE | Six final human decisions plus exact reachable lock evidence. |
| 01-05 | `tools/javascript/src/runner.mjs` | ✓ EXISTS + SUBSTANTIVE | Independent JS runner; all tests passed. |
| 01-06 | `tools/python/reroom_verify/runner.py` | ✓ EXISTS + SUBSTANTIVE | Independent Python runner; all tests passed. |
| 01-07 | `scripts/run-reference-parity` | ✓ EXISTS + SUBSTANTIVE | Independent reference/mutation pipeline. |
| 01-08 | `ios/Packages/ReRoomContracts/Sources/ReRoomContracts/ContractValidation.swift` | ✓ EXISTS + SUBSTANTIVE | Typed fail-closed registry and serialized validator boundary. |
| 01-08 | `evidence/compatibility/swift-schema-validation.json` | ✓ EXISTS + SUBSTANTIVE | Measured Swift validator decision and limits. |
| 01-09 | `ios/Packages/ReRoomContracts/Sources/ReRoomContracts/CoordinateMath.swift` | ✓ EXISTS + SUBSTANTIVE | Pure RR-COORD-1/RR-FLOAT-1 implementation. |
| 01-10 | `scripts/run-three-runtime-agreement` | ⚠ SUBSTANTIVE, STALE BINDING | Production evaluator works when rebound, but committed `BOUND_REVISION` rejects current bound sources. |
| 01-10 | `evidence/compatibility/contract-agreement.json` | ⚠ SUBSTANTIVE, STALE PROVENANCE | Valid measured report for `e6a92c...`; not durable evidence for the later validator source change. |
| 01-11 | `ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/project.pbxproj` | ✓ EXISTS + SUBSTANTIVE | One iPhone app target plus unit/UI tests and local package link. |
| 01-11 | `ios/ReRoomDeviceProof/ReRoomDeviceProof/ARSessionController.swift` | ✓ EXISTS + SUBSTANTIVE | ARKit/plane/recovery policy with no LiDAR dependency. |
| 01-12 | `ios/ReRoomDeviceProof/ReRoomDeviceProof/WorldEpochController.swift` | ✓ EXISTS + SUBSTANTIVE | Version/correction/quarantine authority. |
| 01-12 | `ios/ReRoomDeviceProof/ReRoomDeviceProof/DiagnosticJournal.swift` | ✓ EXISTS + SUBSTANTIVE | Atomic durability, authoritative journal, bounded recovery. |
| 01-13 | `ios/ReRoomDeviceProof/ReRoomDeviceProof/EvidenceExporter.swift` | ✓ EXISTS + SUBSTANTIVE | V2 sanitizer, schema validation, atomic publication. |
| 01-13 | `scripts/verify-reroom-release-surface` | ✓ EXISTS + SUBSTANTIVE | Same-product Release scanner passed. |
| 01-14 | `evidence/device/phase-01/gate-013-report.json` | ✓ EXISTS + VERIFIED | Human GREEN V2 report bound to candidate/preflight/checklist. |
| 01-14 | `evidence/device/phase-01/gate-002-report.json` | ✓ EXISTS + VERIFIED | Human GREEN V2 report bound to candidate/preflight/checklist. |

**Artifacts:** 22/24 fully current; 2/24 are substantive but share the same stale agreement revision gap.

### Key Link Verification

| Plan | From → To | Status | Details |
|---|---|---|---|
| 01-01 | Contract fixture manifest → canonical schemas | ✓ WIRED | All five schema tuples and SHA-256 values pass fixture integrity; the static GSD regex probe itself errored on `schema_sha256`, so this was verified directly. |
| 01-02 | Operator checklist → gate report | ✓ WIRED | Report/checklist/attestation digest scopes pass semantic verification. |
| 01-03 | Phase verifier → comparator | ✓ WIRED | Explicit modes invoke integrity/comparison gates. |
| 01-04 | Package audit → locks | ✓ WIRED | Exact versions, artifact hashes, licenses, and reachable parent chains pass. |
| 01-05 | JS runner → result schema | ✓ WIRED | Closed envelope validation and comparator acceptance pass. |
| 01-06 | Python runner → result schema | ✓ WIRED | Closed envelope validation and comparator acceptance pass. |
| 01-07 | Reference parity → comparator | ✓ WIRED | Independent outputs and mutations route through comparator. |
| 01-08 | Swift validation tests → contract fixtures | ✓ WIRED | Complete frozen corpus executes. |
| 01-09 | Swift coordinate tests → coordinate fixtures | ✓ WIRED | All accepted/rejected oracle cases execute. |
| 01-10 | Three-runtime harness → comparator | ✓ WIRED | Three fresh normalized outputs compare; publishing is blocked only by stale revision pin. |
| 01-11 | Xcode app → local contracts package | ✓ WIRED | Build graph resolves and tests link `ReRoomContracts`. |
| 01-12 | World epoch → coordinate validation | ✓ WIRED | Directed correction calls rigid-transform validation. |
| 01-13 | Evidence exporter → V2 gate schema | ✓ WIRED | `GateReportV2Validator` runs before any destination creation. Plan frontmatter's literal `GateReportV1` probe is stale after the deliberate V2 migration. |
| 01-14 | Signed checklist → human gate report | ✓ WIRED | Both exact report-decision and checklist/attestation bindings pass. |

**Wiring:** 14/14 connections verified.

## Automated Verification Results

| Check | Result |
|---|---|
| Phase dependency audit | PASS — 6 decisions, 5 direct dependencies, 10 reachable transitives |
| Fixture integrity | PASS — 3 manifests |
| Evidence schema/binding and release-bundle regression | PASS — 23 tests |
| Signed evidence semantic verification | PASS — GATE-013 and GATE-002 V2 report/checklist pairs |
| Phase gate command | PASS — both states GREEN |
| Current-HEAD three-runtime agreement, non-publishing | PASS — `FX-CONTRACT-001`, `FX-JCS-001`, `FX-COORD-001` |
| Checked-in three-runtime publishing command | FAIL — expected drift guard: bound source revision is stale |
| Swift contracts package | PASS — 33 tests in 5 suites; includes 1,024 concurrent shared-validator requests |
| JavaScript runner/mutations | PASS — 5 tests |
| Python runner/mutations/reference parity | PASS — 7 tests |
| Debug app unit target on iPhone 17 simulator | PASS — 50 tests, 88 executions, 0 failures/skips |
| Debug diagnostic UI surface | PASS — 1/1 |
| Release candidate UI surface | PASS — 1/1 |
| Release binary/resource surface scanner | PASS |
| `git diff --check` and tracked-secret pattern scan | PASS |
| GSD roadmap validation | PASS |
| GSD consistency | PASS with expected future-phase-directory warnings |
| GSD health | DEGRADED (non-phase warning): `.planning/config.json` uses model profile `adaptive`, while this installed GSD reports only `quality`, `balanced`, `budget`, or `inherit` as valid |

### Test Quality Audit

| Test surface | Linked requirements | Provenance | Strongest assertion | Verdict |
|---|---|---|---|---|
| Immutable contract/JCS/coordinate corpora | NFR-CONTRACT-001, NFR-COORD-001 | Independent checked-in oracle plus canonical schema hashes | Exact value/bytes/digest/rejection class | PASS |
| Three runtime runners/comparator | NFR-CONTRACT-001, NFR-COORD-001 | Independent Swift/JS/Python execution | Exact cross-runtime behavioral agreement | PASS, recorded revision stale |
| Swift package tests | NFR-CONTRACT-001, NFR-COORD-001 | Frozen corpus plus held-out mutations/concurrency stress | Value and behavioral | PASS |
| Capture/epoch/journal tests | OPS-DEVICE-001, NFR-COORD-001, NFR-CONTRACT-001 | Deterministic state/crash fixtures | Multi-step behavioral/ordering | PASS |
| Evidence tests | OPS-DEVICE-001, NFR-CONTRACT-001 | V2 schemas plus positive/negative mutation fixtures | Exact cross-file binding and pre-write behavior | PASS |
| Debug/Release UI and binary tests | OPS-DEVICE-001 | Actual built products | End-to-end surface behavior and negative string/resource scan | PASS |
| Physical gates | OPS-DEVICE-001, NFR-COORD-001 | External human observation retained by opaque digest | Human attestation plus exact record binding | PASS |

No disabled requirement test, circular expected-value source, skipped acceptance test, or assertion-strength blocker was found.

## Requirements Coverage

| Requirement | Status | Evidence / Remaining Issue |
|---|---|---|
| NFR-COORD-001 | ✓ SATISFIED | Current three-runtime exact coordinate agreement, Swift value tests, epoch/quarantine behavior, and signed GATE-002. |
| NFR-CONTRACT-001 | ✓ SATISFIED | Current three-runtime execution and all fail-closed contract/JCS/wire/schema tests pass. Durable agreement provenance needs refresh, but no current contract disagreement was observed. |
| OPS-DEVICE-001 | ✓ SATISFIED | Signed GATE-013 and GATE-002 GREEN evidence is bound to the approved installed candidate; simulator/build/release checks independently pass. |

**Coverage:** 3/3 phase requirements behaviorally satisfied. The remaining gap is acceptance-evidence freshness.

## Anti-Patterns and Disconfirmation

| File | Line | Finding | Severity | Impact |
|---|---|---|---|---|
| `scripts/run-three-runtime-agreement` | 17 | `BOUND_REVISION` predates the serialized-validator fix inside the bound source scope. | 🛑 Blocker | The ordinary acceptance command cannot publish current measured reports. |
| `01-13-PLAN.md` | 33 | Static key-link pattern still says `GateReportV1` after intentional V2 migration. | ℹ️ Info | No product gap; direct source/tests prove the stronger V2 link. |
| `.planning/config.json` | 4 | Installed GSD reports `adaptive` as an invalid model profile. | ℹ️ Info | Health warning outside Phase 1 product/contract goal; consistency and roadmap validation still pass. |

Searches over tracked Phase 1 implementation/tests found no TODO/FIXME/HACK/placeholder implementation. The partial-looking contract behavior was challenged with current-HEAD execution rather than inferred from old reports; the result passed. The potentially misleading schema-acceptance path was challenged with semantic cross-file binding and mutation tests, not schema presence alone. The externally retained physical bytes remain intentionally human-only; the user's completed signed checklist covers that error path, and this verifier did not access or fabricate it.

## Human Verification Required

None pending. The only phase truths that intrinsically required physical human observation have already been supplied as accountable GateReportV2/checklist attestations. This verification independently checked their sanitized binding and consistency; it did not repeat, infer, or replace those observations.

## Gaps Summary

### Critical Gaps (Block Phase Closeout)

1. **Refresh three-runtime recorded provenance after the validator concurrency fix**
   - Missing: a checked-in `scripts/run-three-runtime-agreement` binding and compatibility report set for the current contract source scope.
   - Evidence: ordinary execution fails because `ContractValidation.swift` and `FrozenSchemaValidator.swift` changed after `e6a92c...`; the same evaluator bound in memory to current HEAD passes all three corpora.
   - Impact: current behavior is green, but Plan 01-10's durable measured-evidence requirement and reproducible acceptance command are not current.
   - Fix: bind the command to the exact post-fix contract revision, regenerate the three compatibility reports, rerun the ordinary command byte-stably, and rerun the focused mutation/package checks. Do not modify the signed physical candidate, preflight, gate reports, checklists, or opaque physical evidence.

## Recommended Fix Plan

### 01-15-PLAN.md: Refresh Post-Review Three-Runtime Provenance

**Objective:** Make the ordinary Phase 1 three-runtime acceptance command and recorded reports reproducible for the finalized contract validator sources without disturbing the signed device candidate.

**Tasks:**

1. Update the harness's exact bound revision to the finalized contract source revision containing `69764a4...`, then regenerate `contract-agreement.json`, `jcs-agreement.json`, and `coordinate-agreement.json` through the production command.
2. Verify each report records the new revision/source-tree digest and zero oracle/runtime disagreements; rerun the production command to prove byte-stable reproduction.
3. Run focused Swift concurrency/contract tests, JS/Python mutation gates, fixture integrity, `git diff --check`, and the tracked-secret scan. Leave all GATE-002/GATE-013 signed evidence and candidate `git:97d8...` unchanged.

**Estimated scope:** Small.

## Verification Metadata

**Verification approach:** Goal-backward; summaries treated as claims, current source/tests/evidence treated as proof.
**Must-haves source:** Four ROADMAP success criteria plus 45 PLAN frontmatter truths; no semantic deduplication because plan truths add narrower acceptance details.
**Sources inspected:** All 14 plans and summaries, phase context/research/clean review, ROADMAP, REQUIREMENTS, canonical authority/ADRs/contracts/spec/PRD/test/risk/glossary/research ledger, current code/tests, compatibility evidence, and sanitized signed gate records.
**Automated checks:** 16 passed, 1 expected stale-provenance failure, 1 non-phase GSD health warning.
**Human checks required:** 0 pending; 2 supplied and cryptographically/semantically bound.
**Protected worktree state:** Candidate `git:97d8...` and pre-existing scheme/`.swiftpm`/workspace/`xcuserdata` changes were not modified.

---
*Verified: 2026-07-17T14:46:27Z*
*Verifier: GSD goal verifier (independent subagent)*
