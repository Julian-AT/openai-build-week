---
status: resolved
trigger: "Fresh cross-phase mutation run found five Phase 5 replacement verifier failures after Phase 6 changed shared RoomEditModel/RoomEditView source."
created: 2026-07-18T20:27:00Z
updated: 2026-07-18T20:40:00Z
---

# Debug Session: Phase 5 Source Drift

## Symptoms

- **Expected:** `python3 -m unittest tools.verify.tests.test_phase_05_replacement -v` passes against the current Phase 8 tree while retaining fail-closed replacement invariants.
- **Actual:** Five tests fail with `replacement_source:model_fail_closed` or `evidence:source_drift`; Phase 6 and Phase 8 tests pass.
- **Errors:** `test_atomic_publish_writes_only_valid_full_report`, `test_report_rejects_green_gates_overclaims_raw_content_and_drift`, `test_report_self_digest_is_canonical_and_tamper_evident`, `test_source_contract_binds_one_time_retained_exact_asset_and_fail_closed_seam`, and `test_source_contract_requires_inverse_idempotency_and_failure_tests` error.
- **Timeline:** The retained Phase 5 evidence passed before later Phase 6 shared-source edits. The regression was found by a fresh final cross-phase run after Phase 8.
- **Reproduction:** `python3 -m unittest tools.verify.tests.test_phase_05_replacement -v`

## Current Focus

- hypothesis: The historical evidence and current successor tree need separate, explicit validation scopes.
- test: Phase 5 tests load the bound implementation revision; Phase 8 validates implementation bindings, verification-parent bindings, unchanged current core files, and Phase 6 superseding shared-app bindings independently.
- expecting: All adjacent suites and evidence validators pass without rewriting the retained Phase 5 report or weakening current-tree coverage.
- next_action: Archive this resolved session and retain the corrected cross-phase mutation suite in final verification.
- reasoning_checkpoint:
    hypothesis: Phase 6's additive remove arguments and support-provider closure cause Phase 5's adjacency-sensitive source token and current-tree report fixture to fail, while replacement semantics remain present.
    confirming_evidence:
      - The only absent required model token is the compound `supportProvider: { _ in .fixture }` plus adjacent fixture-policy string; the fixture and live policy tokens each still occur exactly once.
      - The two current shared-source digests differ from `BOUND_PRODUCT_DIGESTS`, while `git show f53ba72:<path> | shasum -a 256` exactly equals both bound constants and the retained evidence report.
      - The f53ba72-to-HEAD diff shows removal additions and trailing initializer arguments; replacement policy revalidation calls and replacement authority paths were not removed.
    falsification_test: If the minimal verifier/test-fixture patch does not make the exact five failures green, or if existing policy/digest mutations stop failing, then this diagnosis is incomplete.
    fix_rationale: Testing the immutable Phase 5 verifier against its bound source and separating implementation, verification-parent, unchanged-current-core, and superseding-Phase-6 bindings preserves each authority instead of conflating revisions.
    blind_spots: No heavy Xcode/device run will be performed in this focused repair; Phase 5/6 Python mutation suites and retained evidence validation cover the verifier seam, while existing phase evidence remains the runtime record.
- tdd_checkpoint: Existing failing Phase 5 contract tests are the RED reproduction.

## Evidence

- timestamp: 2026-07-18T20:27:00Z
  observation: Fresh combined run passed Phase 6, Phase 7, and Phase 8 suites but failed five of ten Phase 5 tests.
- timestamp: 2026-07-18T20:29:00Z
  checked: Exact reproduction command from Symptoms.
  found: Ten tests ran deterministically; five passed and five errored. Two source-contract tests stop at `replacement_source:model_fail_closed`; three report/publication tests stop at `evidence:source_drift` before their intended assertions.
  implication: The failures split cleanly into one source-pattern predicate and one fixture-digest construction seam; no runtime Swift behavior has yet been shown to regress.
- timestamp: 2026-07-18T20:32:00Z
  checked: Every `required_model` token against current RoomEditModel plus the f53ba72-to-HEAD shared-source diff.
  found: The default deny-all token and both explicit fixture/live replacement policies remain. Only the compound fixture token is absent because Phase 6 expanded `supportProvider` and appended remove arguments. Replacement revalidation call sites remain unchanged.
  implication: `replacement_source:model_fail_closed` is an adjacency-sensitive verifier false positive, not evidence that replacement authorization was removed.
- timestamp: 2026-07-18T20:33:00Z
  checked: Current and f53ba72 SHA-256 values for RoomEditModel/View, `BOUND_PRODUCT_DIGESTS`, and retained Phase 5 evidence bindings.
  found: f53ba72 hashes exactly match the constants and retained report; current hashes differ after 566 net Phase 6 additions. Unit `valid_report()` incorrectly supplies current product hashes to a validator that requires the retained Phase 5 implementation revision.
  implication: The three `evidence:source_drift` errors are invalid test-fixture construction, while the production validator correctly rejects source drift for a Phase 5 report.
- timestamp: 2026-07-18T20:36:00Z
  checked: Exact original Phase 5 reproduction after the minimal patch.
  found: All 10 tests pass in 0.038 seconds, including policy omission mutations, every bound-product digest mutation, atomic publication, canonical self-digest, inverse/idempotency tokens, asset load, and fail-closed seams.
  implication: The counterfactual matched exactly: correcting only the adjacency and retained-report fixture removed all five failures without weakening mutation coverage.
- timestamp: 2026-07-18T20:38:00Z
  checked: Phase 6 Python mutation suite, Phase 8 Python suites, and direct Phase 5 retained-report validation.
  found: Phase 6 passed 10/10, Phase 8 passed 18/18, and the committed Phase 5 report passed strict self-digest validation. The combined command then stopped because Phase 6's CLI accepts only `quick|full`, not `--verify-evidence`.
  implication: Adjacent mutation coverage is green; the remaining verification step needs the Phase 6 module's direct report validator rather than a nonexistent CLI option.

## Eliminated

- hypothesis: A Phase 6 change removed the replacement supported-view guard or changed it to allow by default.
  evidence: Current source retains `.denyAll`, explicit fixture/live policies, and policy revalidation in both proposal and confirmation paths; the diff does not remove those calls.
  timestamp: 2026-07-18T20:32:00Z

- hypothesis: The evidence validator should accept current Phase 8 shared-source digests in a report identified as the f53ba72 Phase 5 implementation.
  evidence: The committed retained report and both `BOUND_PRODUCT_DIGESTS` exactly bind f53ba72; accepting current digests would erase the report's immutable implementation binding.
  timestamp: 2026-07-18T20:33:00Z

## Resolution

- root_cause: Phase 5 verifier tests fed current successor source and digests into checks that intentionally describe the immutable Phase 5 implementation; Phase 8 also treated historical verifier/test bindings as if they had to equal the current files.
- fix: Load Phase 5 source-contract fixtures from the bound implementation revision, use immutable product digests for retained-report fixtures, and make Phase 8 validate product bindings at the implementation revision, verifier/test bindings at the verification-parent revision, unchanged current core files directly, and shared-app successors through Phase 6 evidence.
- verification: Phase 5 and Phase 6 mutation suites passed 20/20 together; Phase 7 retained evidence and both Phase 8 standalone evidence validators passed; repository whitespace validation passed.
- files_changed: [tools/verify/tests/test_phase_05_replacement.py, tools/verify/verify_phase_08_hardening.py]
