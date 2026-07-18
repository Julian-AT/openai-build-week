---
phase: 05-curated-replacement-vertical
status: pending_human_evidence
automated_verdict: human_needed
automated_score: 16/19
recorded: 2026-07-18
---

# Phase 5 UAT

The deterministic replacement sprint slice is implemented and independently verified with no remaining automated implementation gap. Production fails closed outside the bounded HYPOTHESIS demo policy, loads the exact repository-owned six-cube USDA once, commits exactly once, survives restart, and restores through a compensating transaction.

## Verified automated scope

- Exact `set_object_visibility` then `create_asset_instance` order and captured-exact inverse.
- Same-key retry, restart, activation faults, replay, and unrelated-state-preserving restore.
- Five deterministic simulator fixture iterations and injected asset-load failure.
- Debug/Release builds, retained exact USDA loading, no generated-box success fallback, and zero command-time network.
- Supported-view policy defaults deny and revalidates revision, world epoch, frozen target, and camera pose before confirmation.

## Pending real-world evidence

| ID | Required work | Status |
| --- | --- | --- |
| `GATE-003` / `GATE-005` | Signed-device compositor, support, mask/OBB/view-envelope measurements and human visual assessment. | `PENDING` |
| `GATE-011` | Native/web derivative parity, device/web loading, redistribution/attribution decision, and complete shipping BOM. | `PENDING` |
| `GATE-009` | Formal disconnect/reconnect, restart, and divergence campaign beyond deterministic automation. | `PENDING` |
| `OPS-GOLDEN-001` | Five complete signed-device journeys after blocking gates are green. | `PENDING` |

Accepted claim: **“The automated sprint replacement slice passed.”** Do not claim full `FR-REPLACE-001`, P0, physical quality, license/parity, or golden-run completion from this file.
