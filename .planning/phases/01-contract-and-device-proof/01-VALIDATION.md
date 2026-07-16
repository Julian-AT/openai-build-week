---
phase: 01
slug: contract-and-device-proof
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-16
---

# Phase 01 — Validation Strategy

> Final-plan validation contract. Commands remain planning targets until their owning task creates them.

## Test Infrastructure

| Property | Value |
|---|---|
| **Framework** | Swift Testing/XCTest via `swift test`/`xcodebuild`, Node built-in test runner, Python `unittest` |
| **Config** | Minimal manifests/projects are created by Plans 01-01, 01-04, 01-08, and 01-11 |
| **Quick command** | `scripts/verify-phase-01-contracts quick` |
| **Full command** | `scripts/verify-phase-01-contracts full` |
| **Latency targets** | TARGET quick <30s; full automated <120s excluding physical/human gates |

## Sampling Rate

- After each task: run its narrow command; after Plan 01-03 exists, also run `scripts/verify-phase-01-contracts quick` where applicable.
- After each wave: run all completed-plan commands; after Plan 01-10, run `scripts/verify-phase-01-contracts references`.
- Before verification: `full` must pass, then real GATE-013 and GATE-002 evidence plus human signatures must pass `gate`; `gate` exits zero only when both report states are GREEN, while RED remains retained failure evidence.
- Physical-device and human checks never become green from synthetic tests or automation alone.

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---|---|---:|---|---|---|---|---|---|---|
| 01-01-01 | 01-01 | 1 | NFR-CONTRACT-001 | T-01-01/02 | Closed bounded fixture/result envelopes parse | schema | `python3 -m json.tool fixtures/manifest.schema.json >/dev/null && python3 -m json.tool fixtures/runner-result.schema.json >/dev/null` | ❌ W0 | ⬜ pending |
| 01-01-02 | 01-01 | 1 | NFR-CONTRACT-001 / NFR-COORD-001 | T-01-01 | Three immutable manifests exist and parse | fixture | `python3 -c "import json,pathlib; p=list(pathlib.Path('fixtures').glob('**/rev-001/manifest.json')); assert len(p)==3; [json.load(open(x)) for x in p]"` | ❌ W0 | ⬜ pending |
| 01-02-01 | 01-02 | 1 | NFR-CONTRACT-001 / OPS-DEVICE-001 | T-01-03/04 | Automation cannot approve or waive gates | schema/security | `python3 -m unittest tools.verify.tests.test_evidence_templates -v` | ❌ W0 | ⬜ pending |
| 01-02-02 | 01-02 | 1 | OPS-DEVICE-001 | T-01-04 | Private fields and unbound approvals reject | security | `python3 -m unittest tools.verify.tests.test_evidence_templates -v` | ❌ W0 | ⬜ pending |
| 01-04-01 | 01-04 | 1 | NFR-CONTRACT-001 | T-01-07 | Exact six candidates are pending and no ignored install/lock path exists | supply chain | `python3 -c "import json; d=json.load(open('evidence/dependencies/phase-01-package-audit.json')); assert set(d['candidates'])=={'ajv','ajv-formats','canonicalize','jsonschema','rfc8785','swift-json-schema'}" && test ! -f tools/javascript/package-lock.json && test ! -f tools/python/requirements.lock && test ! -f ios/Packages/ReRoomContracts/Package.resolved && test ! -d node_modules && test ! -d .venv && test ! -d tools/javascript/node_modules && test ! -d tools/python/.venv && test ! -d ios/Packages/ReRoomContracts/.build` | ❌ W0 | ⬜ pending |
| 01-04-02 | 01-04 | 1 | NFR-CONTRACT-001 | T-01-07 | Direct manifest sets exactly equal approved subsets; locks/pins match and all transitives are reachable from approved roots | checkpoint | `python3 tools/verify/verify_phase_01_dependencies.py --audit evidence/dependencies/phase-01-package-audit.json --package-json tools/javascript/package.json --package-lock tools/javascript/package-lock.json --requirements-in tools/python/requirements.in --requirements-lock tools/python/requirements.lock --swift-package ios/Packages/ReRoomContracts/Package.swift --swift-resolved ios/Packages/ReRoomContracts/Package.resolved` | ❌ W0 | ⬜ pending |
| 01-03-01 | 01-03 | 2 | NFR-CONTRACT-001 / NFR-COORD-001 | T-01-05/06 | Oracle/result mutations fail closed | unit/mutation | `python3 -m unittest tools.verify.tests.test_compare_results -v` | ❌ W0 | ⬜ pending |
| 01-03-02 | 01-03 | 2 | all | T-01-05 | Full runs complete automation and emits preflight without reading physical evidence; only gate requires signed reports | integration | `python3 -m unittest tools.verify.tests.test_compare_results -v && scripts/verify-phase-01-contracts fixture-integrity` | ❌ W0 | ⬜ pending |
| 01-05-01 | 01-05 | 3 | NFR-CONTRACT-001 | T-01-08 | JS enforces exact 24-byte RRFP header, duplicate values, payload SHA, and no trailing bytes | unit/fixture | `node --test tools/javascript/test/runner.test.mjs` | ❌ W0 | ⬜ pending |
| 01-05-02 | 01-05 | 3 | NFR-COORD-001 | T-01-08 | JS coordinate results are complete and ordered | unit/fixture | `node --test tools/javascript/test/runner.test.mjs` | ❌ W0 | ⬜ pending |
| 01-06-01 | 01-06 | 3 | NFR-CONTRACT-001 | T-01-09 | Python independently enforces exact trailer-less CON-001 framing | unit/fixture | `.venv/bin/python -m unittest tools.python.tests.test_runner -v` | ❌ W0 | ⬜ pending |
| 01-06-02 | 01-06 | 3 | NFR-COORD-001 | T-01-09 | Python coordinate results are complete and ordered | unit/fixture | `.venv/bin/python -m unittest tools.python.tests.test_runner -v` | ❌ W0 | ⬜ pending |
| 01-07-01 | 01-07 | 4 | NFR-CONTRACT-001 / NFR-COORD-001 | T-01-10 | Fresh independent JS/Python results agree | integration | `python3 -m unittest tools.verify.tests.test_reference_parity -v` | ❌ W0 | ⬜ pending |
| 01-07-02 | 01-07 | 4 | NFR-CONTRACT-001 / NFR-COORD-001 | T-01-10 | Cross-runtime and comparator mutations are killed | mutation | `node --test tools/javascript/test/parity-mutations.test.mjs && .venv/bin/python -m unittest tools.python.tests.test_parity_mutations tools.verify.tests.test_reference_parity -v` | ❌ W0 | ⬜ pending |
| 01-08-01 | 01-08 | 5 | NFR-CONTRACT-001 | T-01-11 | Swift validator supports used keywords and agrees | compatibility | `swift test --package-path ios/Packages/ReRoomContracts --filter ContractValidationTests` | ❌ W0 | ⬜ pending |
| 01-08-02 | 01-08 | 5 | NFR-CONTRACT-001 | T-01-11 | Swift validation is allowlisted and bounded | unit | `swift test --package-path ios/Packages/ReRoomContracts --filter ContractValidationTests` | ❌ W0 | ⬜ pending |
| 01-09-01 | 01-09 | 6 | NFR-CONTRACT-001 | T-01-12 | Swift JCS and exact trailer-less 24-byte RRFP wire/path behavior match | unit/fixture | `swift test --package-path ios/Packages/ReRoomContracts --filter 'CanonicalJSONTests|WireFrameTests'` | ❌ W0 | ⬜ pending |
| 01-09-02 | 01-09 | 6 | NFR-COORD-001 | T-01-12 | Swift exact coordinate edge cases match | unit/fixture | `swift test --package-path ios/Packages/ReRoomContracts --filter CoordinateMathTests` | ❌ W0 | ⬜ pending |
| 01-10-01 | 01-10 | 7 | NFR-CONTRACT-001 / NFR-COORD-001 | T-01-13 | Package registers a buildable ReRoomContractRunner executable dependent on ReRoomContracts | build/unit | `swift build --package-path ios/Packages/ReRoomContracts --product ReRoomContractRunner && swift test --package-path ios/Packages/ReRoomContracts --filter RunnerTests` | ❌ W0 | ⬜ pending |
| 01-10-02 | 01-10 | 7 | NFR-CONTRACT-001 / NFR-COORD-001 | T-01-13 | Three runtimes agree with bound evidence | integration | `scripts/run-three-runtime-agreement && scripts/verify-phase-01-contracts references` | ❌ W0 | ⬜ pending |
| 01-11-01 | 01-11 | 8 | OPS-DEVICE-001 | T-01-14 | Candidate targets only the ASSUMED proof baseline with camera/microphone metadata and no LiDAR/audio requirement | build | `xcodebuild -project ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj -scheme ReRoomDeviceProof -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO` | ❌ W0 | ⬜ pending |
| 01-11-02 | 01-11 | 8 | OPS-DEVICE-001 / NFR-COORD-001 | T-01-14 | Camera denial blocks visual capture; microphone denial disables only optional microphone readiness and never visual/AR/typed-tap P0 | unit | `xcodebuild test -project ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj -scheme ReRoomDeviceProof -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ReRoomDeviceProofTests/ARSessionPolicyTests CODE_SIGNING_ALLOWED=NO` | ❌ W0 | ⬜ pending |
| 01-12-01 | 01-12 | 9 | NFR-COORD-001 | T-01-15 | Epoch reset is corrected or quarantined | unit | `xcodebuild test -project ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj -scheme ReRoomDeviceProof -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ReRoomDeviceProofTests/CaptureAttemptTests -only-testing:ReRoomDeviceProofTests/WorldEpochTests CODE_SIGNING_ALLOWED=NO` | ❌ W0 | ⬜ pending |
| 01-12-02 | 01-12 | 9 | NFR-CONTRACT-001 / OPS-DEVICE-001 | T-01-16 | Exact CON-002 journal/events/projections/digests/recovered-prefix gate CON-001 network eligibility | unit/crash | `xcodebuild test -project ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj -scheme ReRoomDeviceProof -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ReRoomDeviceProofTests/CaptureAttemptTests CODE_SIGNING_ALLOWED=NO` | ❌ W0 | ⬜ pending |
| 01-13-01 | 01-13 | 10 | OPS-DEVICE-001 / NFR-CONTRACT-001 | T-01-17/18 | Export is sanitized and cannot self-approve | security/unit | `xcodebuild test -project ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj -scheme ReRoomDeviceProof -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ReRoomDeviceProofTests/EvidenceExporterTests CODE_SIGNING_ALLOWED=NO && python3 tools/verify/verify_evidence.py --fixtures evidence/fixtures` | ❌ W0 | ⬜ pending |
| 01-13-02 | 01-13 | 10 | OPS-DEVICE-001 | T-01-17 | Configured UI-test target launches real Debug diagnostic and Release shipping roots; Release excludes diagnostics | UI/build | `xcodebuild test -project ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj -scheme ReRoomDeviceProof -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ReRoomDeviceProofUITests/DiagnosticSurfaceTests CODE_SIGNING_ALLOWED=NO && xcodebuild test -project ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj -scheme ReRoomDeviceProof -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:ReRoomDeviceProofUITests/DiagnosticSurfaceTests CODE_SIGNING_ALLOWED=NO && scripts/verify-reroom-release-surface` | ❌ W0 | ⬜ pending |
| 01-14-01 | 01-14 | 11 | all | T-01-19 | Candidate build has full automated preflight | integration | `scripts/verify-phase-01-contracts full && python3 tools/verify/verify_evidence.py --file evidence/device/phase-01/automated-preflight.json` | ❌ W0 | ⬜ pending |
| 01-14-02 | 01-14 | 11 | OPS-DEVICE-001 | T-01-19 | GATE-013 binds signed-device camera/microphone grant-deny proof and conditionally promotes only on GREEN | physical/checkpoint | `python3 tools/verify/verify_evidence.py --file evidence/device/phase-01/gate-013-report.json --checklist evidence/device/phase-01/gate-013-operator-checklist.json` | ❌ W0 | ⬜ pending |
| 01-14-03 | 01-14 | 11 | NFR-COORD-001 | T-01-19 | RED remains valid failure evidence, but completion succeeds only when both signed physical gates are GREEN | physical/checkpoint | `python3 tools/verify/verify_evidence.py --file evidence/device/phase-01/gate-002-report.json --checklist evidence/device/phase-01/gate-002-operator-checklist.json && scripts/verify-phase-01-contracts gate` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

## Wave 0 Requirements

- [ ] Plans 01-01/02: closed immutable oracle and canonical evidence schemas/negative fixtures.
- [ ] Plan 01-03: comparator tests and stable multi-mode verifier.
- [ ] Plan 01-04: approved exact dependency locks or audited fallbacks.
- [ ] Plans 01-05/06/07: real JavaScript/Python runners, direct test commands, parity and mutation gates.
- [ ] Plans 01-08/09/10: Swift validator/policies/runner and three-runtime reports.
- [ ] Plans 01-11/12/13: minimal app, explicit epoch/correction/quarantine, atomic capture, sanitized diagnostics, release-surface test.
- [ ] Plan 01-14: real device/operator evidence; never considered present until produced physically.

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|---|---|---|---|
| Signed install/launch, separate camera/microphone grant-deny authorization without audio recording, tracking, planes, recovery of a minimal journaled hash-valid packet, no rear LiDAR, and D-05 promotion decision | OPS-DEVICE-001 / GATE-013 | Requires actual signing, permissions, camera, ARKit, hardware, operator | Run Plan 01-14 Task 2 on bound base iPhone; resolve opaque raw evidence and sign bound checklist. RED validates as failure evidence but does not complete the gate. Promote only on GREEN; RED/pending remains unpromoted and blocks dependent mobile work. |
| Portrait geometry, landscape rejection/coaching, and explicit physical world reset with epoch advance plus correction or quarantine | NFR-COORD-001 / GATE-002 | Simulator/fixtures cannot prove physical camera/reset path | Run versioned Plan 01-14 Task 3 procedure on same device/build; bind reset evidence, sign checklist; RED/quarantine on unknown or invalid alignment. |
| External raw-evidence retention | OPS-DEVICE-001 | Private raw artifacts cannot enter Git | Operator resolves every opaque ID, verifies digest/retention, and signs; Git retains sanitized records only. |

## Validation Sign-Off

- [ ] Every final plan task appears exactly once in the verification map.
- [ ] No three consecutive tasks lack automated verification; checkpoint tasks also validate evidence mechanically.
- [ ] Commands are bounded, non-watch, and invoke the named tests directly.
- [ ] Full automated suite is green and quick/full latency is MEASURED or explicitly revised.
- [ ] GATE-013 and GATE-002 have real raw evidence plus accountable human signatures and both states are GREEN; RED evidence is retained but completion remains failed.
- [ ] `nyquist_compliant` and `wave_0_complete` change only after the mapped artifacts exist and pass.

**Approval:** pending
