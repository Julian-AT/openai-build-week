# ADR-007: Versioned Segmentation and Depth Providers

Status: Provisional  
Date: 2026-07-14

## Context

The archived plan freezes SAM 3.1 and initially favors DA3Metric-Large. Both are current models, but model recency does not establish one-week suitability. SAM 3.1 is large, access-gated, and under a custom license; LingBot has a heavier, rapidly changing runtime.

## Project constraints

- One selected hero object, not whole-room discovery.
- Model access, license acceptance, runtime compatibility, VRAM, startup, and replay quality all matter.
- Experimental models cannot alter contracts or block record/replay.

## Alternatives considered

- Segmentation: SAM 2.1 Hiera Small, SAM 3.1, or manually frozen masks.
- Native-capture depth: DA3Metric-Large, pose-conditioned DA3 Small/Base, or no learned dense depth.
- Ordinary video: LingBot-Map or replay-only/degraded processing.

## Decision

Use provider interfaces. The initial semantic default is SAM 2.1 Hiera Small; SAM 3.1 is an optional measured upgrade. Native depth is selected between DA3Metric-Large, pose-conditioned Apache-licensed DA3 Small/Base, and no-dense. LingBot is an optional offline ordinary-video provider and is not part of the B0 guarantee. Pin code, checkpoint, license, and runtime before use.

## Evidence

- SAM 3.1 release/runtime/access: https://raw.githubusercontent.com/facebookresearch/sam3/main/RELEASE_SAM3p1.md and https://raw.githubusercontent.com/facebookresearch/sam3/main/README.md
- SAM 3 custom license: https://raw.githubusercontent.com/facebookresearch/sam3/main/LICENSE
- SAM 2.1 public Small checkpoint and Apache-2.0 license: https://raw.githubusercontent.com/facebookresearch/sam2/main/README.md and https://raw.githubusercontent.com/facebookresearch/sam2/main/LICENSE
- DA3 model capabilities/licenses: https://raw.githubusercontent.com/ByteDance-Seed/Depth-Anything-3/main/README.md
- LingBot runtime and recent fixes: https://raw.githubusercontent.com/Robbyant/lingbot-map/main/README.md

## Consequences

- The smallest adequate semantic model is favored over novelty.
- Dense and ordinary-video quality degrade explicitly rather than infecting P0 identity.
- Runtime images load only selected providers.

## Risks

- SAM 2.1 may underperform SAM 3.1 on the fixture.
- DA3 temporal inconsistency or Open3D packaging may make dense fusion unusable.
- Checkpoint access/license review may miss the implementation deadline.

## Fallback

Semantic fallback: freeze the best validated masks and allow explicit reseeding. Dense fallback: no-dense fast path and plane/point B0. Ordinary-video fallback: deterministic media replay and processing status without learned geometry.

## Benchmark and kill gate

All unmeasured thresholds, fixture sizes, deadlines, and timeboxes in this gate are `TARGET`, not measured results.

`GATE-004` — Fixture: 20 annotated hero frames plus one 60-second replay. Variants: SAM 2.1 Hiera Small and an accessible, license-approved SAM 3.1 checkpoint. Metrics: mask IoU/boundary leakage, identity switches, seed-to-first-mask p95, sustained queue growth, VRAM, cold/warm startup, access, and license. Pass: median IoU at least 0.80, p10 IoU at least 0.65, zero hero-target identity switches, seed-to-first-mask p95 at most 1.5 seconds, zero sustained queue growth, fit within the selected tier, and recorded access/license. Tie or missed four-hour timebox selects SAM 2.1 Small. Deadline: before semantic integration. `GATE-007` — Fixture: one shared `.rrcap` with a taped floor and three taped distances. Variants: DA3Metric-Large, pose-conditioned Apache-licensed DA3 Small/Base, and no-dense. Metrics: floor RMSE, three distance errors, temporal flicker, accepted-update p95, rejection rate, queue growth, and VRAM. A provider qualifies for live enhancement only with floor RMSE at most 0.025 m, every taped error within ±4%, accepted-update p95 at most 450 ms, no two-minute queue growth, and no OOM. Timebox: four hours before any dense integration; failure selects no-dense live and may retain the provider for offline research only. LingBot receives no P0 time unless `GATE-008` is already green.

## Requirements and contracts affected

`FR-TARGET-001`, `FR-B0-001`, `NFR-COORD-001`, `OPS-LICENSE-001`, CON-001, CON-003, and CON-004.

## Supersession

Supersedes archived model-default and “universal LingBot fallback” claims. No canonical ADR is superseded.
