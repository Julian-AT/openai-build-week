---
phase: 02-atomic-capture-and-exact-replay
plan: "07"
subsystem: capture-verification
tags: [swiftui, crash-recovery, replay, gate-evidence, physical-device]

requires:
  - phase: 02-atomic-capture-and-exact-replay
    plan: "05"
    provides: Three-runtime replay agreement and atomic evidence publication
  - phase: 02-atomic-capture-and-exact-replay
    plan: "06"
    provides: Native consent, capture, recovery, and verified replay presentation
provides:
  - Fail-closed eight-check Phase 2 preflight and human-authoritative GATE-001 evidence boundary
  - Release-only exact lifecycle termination controls with replayable open-manifest recovery
  - Contract-supported JPEG interrupted-capture recovery
  - Durable gate-only queue-pressure observation before explicit termination
affects: [phase-03-transactions, phase-07-b0, phase-08-gate-001]

tech-stack:
  added: []
  patterns:
    - Synthetic and simulator evidence can never authorize a physical gate
    - Release diagnostics require an explicit launch argument
    - Gate pressure stalls one ordinary write while preserving the reserved user-event lane

key-files:
  created:
    - evidence/templates/gate-001-physical-observations.schema.json
    - evidence/templates/gate-001-operator-procedure.md
    - evidence/capture/phase-02/automated-preflight.json
  modified:
    - scripts/verify-phase-02-capture-replay
    - scripts/run-phase-02-replay-agreement
    - tools/verify/verify_phase_02_gate.py
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/App.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/CaptureSessionAdapter.swift
    - ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureRecovery.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProofTests/CaptureSessionAdapterTests.swift

key-decisions:
  - "Keep GATE-001 human-authoritative: automation may publish RUNNING/RED evidence but never GREEN."
  - "Persist an open manifest early enough that exact journal-prefix recovery remains possible after every tested lifecycle boundary."
  - "Accept every frame codec allowed by the capture contract during recovery, including the live JPEG profile."
  - "Require a durable bounded-pressure observation before the Release diagnostic surface enables abrupt termination."
  - "Under the human-approved 36-hour sprint cut, defer the repeated new-revision physical matrix without enabling live-provider integration or claiming GATE-001 GREEN."

patterns-established:
  - "Physical evidence boundary: raw room/device artifacts remain external; Git stores only closed sanitized facts and opaque digests."
  - "Termination instrumentation: the next explicit user-event frame terminates at one exact armed durable boundary."
  - "Pressure instrumentation: ordinary work reaches capacity and pauses upload before the explicit user-event lane is used."

requirements-completed: [FR-CAPTURE-001, FR-B0-001, NFR-REPLAY-001, SEC-CONSENT-001]

coverage:
  - id: D1
    description: "The full deterministic Phase 2 preflight covers contracts, lifecycle crashes, exact recovery/replay, queue pressure, consent denial, native simulator flow, Release surface, and three-runtime agreement."
    requirement: NFR-REPLAY-001
    verification:
      - kind: integration
        ref: "scripts/verify-phase-02-capture-replay full"
        status: pass
    human_judgment: false
  - id: D2
    description: "Interrupted live JPEG archives and open manifests recover only the exact hash-valid contiguous journal prefix."
    requirement: FR-CAPTURE-001
    verification:
      - kind: unit
        ref: "CaptureCrashMatrixTests#journaled recovery accepts the live JPEG capture profile"
        status: pass
      - kind: integration
        ref: "scripts/verify-phase-02-capture-replay full"
        status: pass
    human_judgment: false
  - id: D3
    description: "The signed Release diagnostic build proves bounded queue pressure and durably records capacity, maximum depth, drops, blackhole state, and upload-pause ordering before termination unlocks."
    requirement: FR-CAPTURE-001
    verification:
      - kind: unit
        ref: "CaptureSessionAdapterTests#GATE-001 pressure measurement, harness, and evidence"
        status: pass
      - kind: integration
        ref: "xcodebuild Release simulator build and Release diagnostic surface test"
        status: pass
    human_judgment: false
  - id: D4
    description: "The complete new-revision physical 10s/60s five-boundary matrix, external videos/logs, and human attestation satisfy GATE-001."
    requirement: SEC-CONSENT-001
    verification: []
    human_judgment: true
    rationale: "The human-approved 36-hour demo sprint defers this real-device campaign to Phase 8; GATE-001 remains PENDING and live-provider integration remains blocked."

duration: 12h
completed: 2026-07-18
status: complete
---

# Phase 2 Plan 07: Fail-Closed Verification and Physical Gate Summary

**Eight deterministic checks pass, Release termination pressure is durably instrumented, and the full physical GATE-001 matrix remains explicitly pending under the approved demo sprint cut.**

## Performance

- **Duration:** 12h
- **Completed:** 2026-07-18
- **Tasks:** 2 automated tasks complete; 1 human physical campaign deferred
- **Files modified:** 15+

## Accomplishments

- Published a closed, privacy-safe automated preflight with all eight declared checks passing.
- Added exact Release lifecycle termination, open-manifest recovery, live JPEG recovery, and two-process replay agreement.
- Added TDD-covered gate-only queue pressure that reaches capacity, observes a capacity rejection, pauses upload first, and persists the sanitized measurement before SIGKILL.
- Retained every physical artifact outside Git and kept the human GATE-001 report/checklist in `RUNNING`/pending state.

## Task Commits

Representative atomic commit groups:

1. **Fail-closed verifier and sanitized preflight** — `725254a`, `a1b162f`, `ea3dfb6`
2. **Exact Release termination and operator workflow** — `7a91df5` through `5fc502c`
3. **Open-manifest and JPEG recovery fixes** — `68e2d9e`, `d15738f`, `1c0a398`, `5046c2b`
4. **Durable pressure evidence** — `923c008`, `17b9af6`, `25fc361`
5. **Final replay/preflight binding** — `47f4816`, `f5f070b`

## Files Created/Modified

- `tools/verify/verify_phase_02_gate.py` — Independent deterministic and human-authority verifier.
- `evidence/templates/gate-001-physical-observations.schema.json` — Closed physical observation contract.
- `evidence/templates/gate-001-operator-procedure.md` — Exact consent, pressure, termination, recovery, and replay procedure.
- `ios/ReRoomDeviceProof/ReRoomDeviceProof/App.swift` — Launch-gated termination and pressure diagnostic surface plus durable pressure evidence.
- `ios/ReRoomDeviceProof/ReRoomDeviceProof/CaptureSessionAdapter.swift` — Lifecycle observation and ordinary-write pressure harness integration.
- `ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureRecovery.swift` — Exact recovery for all contract-supported image codecs.
- `evidence/capture/phase-02/automated-preflight.json` — Latest passing eight-check preflight.

## Decisions Made

- The 36-hour sprint is a demo candidate, not a full P0 claim. The repeated new-revision physical matrix is recorded in `.planning/SPRINT-CUT-36H.md` and remains `PENDING`.
- Local deterministic Phase 3 work may proceed because it introduces no live provider or upload integration; `GATE-001` still blocks those integrations.
- A physical smoke run can be performed when the operator returns, but no device or human evidence is inferred in their absence.

## Deviations from Plan

### Auto-fixed Issues

1. **Missing open-manifest durability** — physical selected-boundary termination exposed an unrecoverable archive; persisted a replayable open manifest.
2. **Recovery codec mismatch** — physical journaled recovery exposed PNG-only recovery against the live JPEG profile; recovery now enforces the declared inventory codec across all supported image codecs.
3. **Missing physical pressure observation** — the first physical matrix did not actually exercise bounded pressure; added a deterministic Release-only pressure harness and durable observation instead of mislabeling that matrix GREEN.
4. **Sprint sequencing** — the human owner explicitly deferred repeating the ten physical pairs; the complete campaign remains recorded and pending rather than silently omitted.

**Impact on plan:** Correctness and evidence honesty improved. No deferred gate is marked green, and live integration remains blocked.

## Issues Encountered

- One full-preflight Release UI launch failed transiently; both constituent Release checks passed immediately, and the complete authoritative full command then passed on rerun.

## User Setup Required

None for continued local implementation. The deferred signed-device procedure requires the physical phone and human operator later.

## Next Phase Readiness

- Phase 3 may build deterministic local place/commit/restore behavior against the verified contract and replay core.
- No learned provider, live upload, or cloud integration is authorized while `GATE-001` remains pending.
- Resume the full physical campaign with `$gsd-verify-work 2` after the demo-critical implementation window.

## Self-Check: PASSED

- `scripts/verify-phase-02-capture-replay full` passed all 8 declared checks.
- Focused pressure measurement, harness, and durable-evidence tests passed.
- Release simulator build and release-surface verification passed.
- Physical/human evidence is explicitly deferred and not claimed.

---
*Phase: 02-atomic-capture-and-exact-replay*
*Completed: 2026-07-18*
