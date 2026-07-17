---
phase: 01-contract-and-device-proof
review: 01-REVIEW.md
fixed_at: 2026-07-17T03:53:37Z
iteration: 2
status: fixes_complete_pending_physical_gates
findings_in_scope:
  - WR-01
  - WR-02
  - WR-03
fixed:
  - id: WR-01
    title: journal boundary repair
    red_commit: e1e1e12
    green_commit: 9cd95ea
    resolution: >-
      Recovery now atomically publishes the validated canonical prefix for every
      invalid nonempty tail, including a torn first append and a complete final
      record that lacks its newline delimiter.
    evidence:
      - Targeted CaptureAttemptTests passed for memory and Foundation journals.
      - RED failed all four new boundary cases while existing cases passed.
  - id: WR-02
    title: build-provenanced runtime facts
    red_commit: 19cbf79
    green_commit: e6a92c9
    resolution: >-
      Debug builds now generate and bundle truthful implementation and contract
      fixture provenance from tracked product inputs. Normal launches require no
      injected environment values, dirty scoped inputs fail closed, Release does
      not contain the generated resource, and generic device-model text is not
      emitted as hardware evidence.
    evidence:
      - Hosted EvidenceExporterTests passed with an empty environment.
      - Normal Debug DiagnosticSurfaceTests launched and exported evidence without provenance injection.
      - Targeted Release DiagnosticSurfaceTests and the Release product inspector passed.
      - ReRoomBuildProvenance.plist was absent from both the Release product and unsigned archive structure.
  - id: WR-03
    title: coordinate precondition convergence
    red_commit: 42a0c16
    green_commit: 0966d1c
    resolution: >-
      Swift, JavaScript, and Python now enforce the shared RR-COORD boundary
      preconditions before multiplication or projection, including positive
      focal values and affine-row validation.
    evidence:
      - Shared rr-coord-runtime-boundaries.json fixture covers accepted and rejected boundary cases.
      - JavaScript parity mutations passed.
      - Python boundary and reference parity tests passed.
      - Swift runtime-boundary tests passed.
skipped: []
agreement:
  commit: 510af5f
  bound_revision: e6a92c9864f814b5b9a8feeec7456eaf9f889db0
  result: pass
  fixtures:
    - FX-CONTRACT-001
    - FX-JCS-001
    - FX-COORD-001
verification:
  targeted_regressions: pass
  phase_quick_verifier: pass
  reference_parity: pass
  javascript_parity_mutations: pass
  python_parity_and_reference_tests: pass
  swift_package:
    result: pass
    tests: 32
    suites: 5
  ios_debug_scheme:
    result: pass
    test_nodes: 44
    parameterized_runs: 82
  ios_release_ui: pass
  ios_release_build: pass
  ios_release_surface_inspector: pass
  unsigned_release_archive_structure: pass
  evidence_and_privacy:
    result: pass
    tests: 15
  tracked_secret_scan: pass
  diff_check: pass
  project_and_plist_lint: pass
  gsd_consistency:
    result: pass
    warnings: future roadmap phase directories are not created yet
  gsd_health:
    result: degraded
    existing_warnings:
      - config.json uses model_profile adaptive, which GSD Core 1.7 does not recognize
      - Plan 01-14 has no SUMMARY.md because physical and signing work remains in progress
cumulative_commits:
  iteration_1:
    red:
      - 7d4cdb5
      - 7c0716e
      - ca9e4a4
      - 1619323
      - 66a3bbd
      - 06d7a22
      - 790251f
      - f7ccc31
    green:
      - 7dc1c9b
      - fb5677a
      - e128209
      - c9f142a
      - bd9ad44
      - 6faa9d5
      - c8ddc5d
      - 82049fe
    agreement: fe4af7f
  iteration_2:
    red:
      - e1e1e12
      - 42a0c16
      - 19cbf79
    green:
      - 9cd95ea
      - 0966d1c
      - e6a92c9
    agreement: 510af5f
limitations:
  - >-
    The unfiltered Release scheme test action still exits 65 after its UI tests
    pass because the intentionally source-empty Release unit-test bundle has no
    executable. The required targeted Release UI, Release build, resource/symbol
    inspector, and archive-structure checks pass. This unrelated scheme mismatch
    was not changed outside the three findings in scope.
  - >-
    Full signing verification remains intentionally blocked without a real
    candidate artifact and REROOM_SIGNING_RESULT=pass.
  - >-
    GATE-002, GATE-013, Plan 01-14, and all physical-device, ARKit, thermal,
    camera or microphone authorization, operator signature, and human approval
    evidence remain pending. No such evidence was fabricated.
  - >-
    The first quick-verifier invocation used a system Python without jsonschema;
    the unchanged verifier passed in the repository's locked Python environment.
  - >-
    One CoreSimulator Busy result was recovered with bounded shutdown, boot,
    boot-status, and unchanged retry; the retry passed.
---
