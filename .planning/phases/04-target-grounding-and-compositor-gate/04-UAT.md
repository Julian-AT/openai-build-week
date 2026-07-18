---
phase: 04-target-grounding-and-compositor-gate
status: pending_human_evidence
automated_verdict: human_needed
automated_score: 15/18
recorded: 2026-07-18
---

# Phase 4 UAT

The approved manual-target/no-dense/local sprint fallback is implemented and its automated preflight passes. Independent verification found no remaining code or evidence gap. This is not a physical-device or full P0 gate result.

## Pending real-world evidence

| ID | Required human/physical work | Current status |
| --- | --- | --- |
| `GATE-003` | Run the signed base-iPhone eight-pose compositor review, four-minute FPS/frame-time/memory/thermal capture, and five blinded ballots. | `PENDING` |
| `GATE-004` | Run the semantic-provider benchmark if promoting a provider; otherwise retain and document the manual tap/reseed fallback on device. | `PENDING` |
| `GATE-005` | Measure the controlled mask volume, OBB, support, and view envelope on the prescribed fixture. | `PENDING` |
| `GATE-007` | Run the learned-depth/dense bake-off only if promoting that enhancement; otherwise retain the no-dense ARKit plane/proxy fallback. | `PENDING` |
| `GATE-012` | Select and measure a declared runtime tier, or retain the explicitly local-only demo fallback without provider/cloud claims. | `PENDING` |

## Signed-device operator path

1. Launch the signed app on the declared base device and confirm the live camera is the background.
2. Tap the visible floor beside one controlled chair/small table and confirm one stable target ID and current epoch appear.
3. Exercise a miss, tracking loss/interruption, recovery, and explicit reseed. Confirm unsafe operations disable immediately and reseed retains the same stable target identity or fails visibly.
4. Observe camera, proxy, readiness, recovery, and UI ordering at the prescribed poses; retain device video and synchronized diagnostics without raw private-room data.
5. Complete the canonical gate worksheets and attach real measurements/ballots. Do not change a gate from `PENDING` until its exact schema and thresholds pass.

## Accepted sprint claim

“The automated Phase 4 manual-target/no-dense/local fallback slice passed.”

Do not claim measured compositor quality, qualified semantic/dense providers, a declared runtime tier, full P0 completion, or any green gate from this UAT file.
