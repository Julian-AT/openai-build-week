---
phase: 01
slug: contract-and-device-proof
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-16
---

# Phase 01 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Commands are planning targets until their referenced files exist.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing/XCTest via `xcodebuild`, Node.js built-in test runner, Python `unittest` |
| **Config file** | None — Wave 0 creates the minimal project and runner manifests |
| **Quick run command** | `scripts/verify-phase-01-contracts --quick` |
| **Full suite command** | `scripts/verify-phase-01-contracts` |
| **Estimated runtime** | TARGET: quick <30 seconds; full automated suite <120 seconds, excluding physical-device and human gates |

---

## Sampling Rate

- **After every task commit:** Run the task's narrow automated command and `scripts/verify-phase-01-contracts --quick` once the wrapper exists.
- **After every plan wave:** Run `scripts/verify-phase-01-contracts`.
- **Before `$gsd-verify-work`:** Full automated suite must be green; GATE-002 and GATE-013 remain pending until real physical-device evidence and explicit human sign-off exist.
- **Max feedback latency:** TARGET 30 seconds for the quick suite; TARGET 120 seconds for the full automated suite.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 01-W0-01 | TBD | 0 | NFR-CONTRACT-001 | T-01-01 | Fixture inputs and expected bytes/digests are immutable, closed, and reject unknown versions/fields before mutation | contract | `scripts/verify-phase-01-contracts --contracts` | ❌ W0 | ⬜ pending |
| 01-W0-02 | TBD | 0 | NFR-COORD-001 | T-01-02 | RR-COORD-1, RR-FLOAT-1, orientation, transformed intrinsics, and world-epoch cases agree in Swift, JavaScript, and Python | contract | `scripts/verify-phase-01-contracts --coordinates` | ❌ W0 | ⬜ pending |
| 01-W0-03 | TBD | 0 | OPS-DEVICE-001 | T-01-03 | Sanitized diagnostics cannot serialize signing, account, user, stable device-ID, or private-path data; release UI excludes diagnostic controls | security/build | `scripts/verify-phase-01-contracts --evidence` | ❌ W0 | ⬜ pending |
| 01-GATE-002 | TBD | final | NFR-COORD-001 | — | Portrait physical geometry passes; landscape capture is rejected with coaching; no simulated evidence is credited | physical + human | `scripts/verify-phase-01-contracts --gate GATE-002` | ❌ W0 | ⬜ pending |
| 01-GATE-013 | TBD | final | OPS-DEVICE-001 | — | Signed base-iPhone build installs and launches without rear LiDAR; camera permission, ARKit tracking, planes, and minimal hash-valid FramePacket capture pass | physical + human | `scripts/verify-phase-01-contracts --gate GATE-013` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `fixtures/contracts/` — language-neutral valid/invalid inputs, expected canonical bytes/digests, stable case IDs, expected rejection classes, and immutable revision manifest for CON-001 through CON-005.
- [ ] `fixtures/coordinates/` — RR-COORD-1, RR-FLOAT-1, orientation/crop, transformed-intrinsics, projection, and world-epoch correction vectors.
- [ ] `tools/javascript/` and `tools/python/` — independent reference runners that consume the checked-in corpus without regenerating expected values.
- [ ] Swift validator benchmark — timeboxed compatibility matrix against every mandatory schema feature, with the named fallback activated on failure.
- [ ] `scripts/verify-phase-01-contracts` — one bounded, non-watch cross-language command that fails on missing, extra, changed, or disagreeing results.
- [ ] Evidence schemas and negative fixtures — sanitized machine-readable diagnostic export, compact human checklist, raw-evidence opaque IDs/digests, and forbidden-field rejection.
- [ ] Debug/release surface checks — diagnostics are debug/internal-only in the same target and absent from shipping UI.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Portrait positive and landscape negative/correction behavior on the declared physical base iPhone | NFR-COORD-001 / GATE-002 | Simulator and synthetic fixtures cannot prove the device camera crop/orientation path | Run the versioned checkerboard procedure on the named sanitized build/device environment; attach opaque raw-evidence IDs and digests; record automated result plus explicit human checklist sign-off. Any unknown alignment is RED/quarantined. |
| Signed install/launch, permission, ARKit tracking, plane callbacks, and minimal hash-valid FramePacket capture without rear LiDAR | OPS-DEVICE-001 / GATE-013 | Signing, camera, ARKit, and hardware capability evidence requires a real device and accountable operator | Build the production-seed target, install on the declared base iPhone, execute the compact diagnostic checklist, export the sanitized machine record, and obtain explicit human approval. Record failures as RED; never substitute simulator or fabricated evidence. |
| External raw-evidence retention/location is reachable through opaque references | OPS-DEVICE-001 | Repository policy forbids committing private video, screenshots, and logs | Operator confirms each opaque evidence ID resolves in the approved external store and matches its recorded digest; Git contains only sanitized manifests, checksums, reports, and tool/device versions. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verification or explicit Wave 0 dependencies.
- [ ] Sampling continuity: no 3 consecutive tasks without automated verification.
- [ ] Wave 0 covers all missing test and runner references.
- [ ] No watch-mode flags or unbounded commands.
- [ ] Quick feedback latency is MEASURED and below its accepted threshold, or the threshold is revised through an explicit planning decision.
- [ ] Full automated suite is green.
- [ ] GATE-002 and GATE-013 have real automated evidence plus explicit human sign-off.
- [ ] `nyquist_compliant: true` is set only after the validation map is reconciled to final plan task IDs and all required evidence paths exist.

**Approval:** pending
