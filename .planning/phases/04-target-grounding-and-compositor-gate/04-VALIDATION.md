---
phase: 04
slug: target-grounding-and-compositor-gate
status: retroactive-executed
nyquist_compliant: true
automated_coverage: complete
manual_gates: pending
created: 2026-07-19
---

# Phase 04 — Validation Strategy

This file records the executed automated fallback slice. The phase verdict
remains `human_needed`; compositor, provider, runtime, and device gates are not
green from simulator tests.

## Test infrastructure

| Scope | Command |
|---|---|
| Target reducer/model | Xcode `RoomEditModelTests` |
| AR adapter/session | Xcode `ARSessionPolicyTests` |
| UI/compositor wiring | Xcode `RoomEditJourneyTests` plus Debug/Release build |
| Phase verifier | `scripts/verify-phase-04-targeting` |

## Requirement coverage

| Requirement | Automated behavior |
|---|---|
| `FR-TARGET-001` | Manual selection/reseed is revision-neutral; stable identity survives reseed; invalid/tracking evidence fails closed. |
| `NFR-RENDER-001` | One ARView/session graph, fixed compositor order, immutable render snapshots, and no model/network dependency in the render loop. |

## Continuous strategy

Run focused model/session tests after each behavior change, then the phase
verifier and both build configurations before handoff.

## Manual-only gates

GATE-003, GATE-004, GATE-005, GATE-007, and GATE-012 retain the exact physical,
provider, visual, performance, and runtime campaigns in the canonical test
plan. Manual/no-dense/local fallbacks remain active until real evidence exists.
