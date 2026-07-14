# ADR-009: Multi-Surface Reveal and Supported View Envelope

Status: Provisional  
Date: 2026-07-14

## Context

Empty removal must cover camera pixels belonging to a real object using background evidence that may span floor, wall, and trim. A single plane or unconstrained inpaint is unlikely to remain credible while the user moves.

## Project constraints

- The camera feed remains untouched; ReRoom draws spatial virtual reveal content.
- Imperfect masks and unobserved background are expected.
- Removal is P0 on the controlled fixture but cannot be advertised before evidence passes.

## Alternatives considered

1. One screen-space inpainted image.
2. One plane atlas.
3. A versioned multi-surface reveal bundle with provenance, target volume, foreground proxies, and a captured supported-view envelope.

## Decision

Adopt alternative 3 provisionally. Observed texels outrank deterministic fill; synthesized evidence is labeled. Each layer references a canonical surface and provenance. P0 spatial mapping is deliberately closed: a layer declares a convex local-XY meter polygon, rigid `world_from_surface`, paired normalized top-left UV per vertex, CCW winding, and a deterministic triangle fan. This supports multiple planar floor/wall/trim layers without leaving texture placement implicit; generic mesh-atlas mapping requires a future contract version. Readiness is valid only inside the tested view envelope and only when coverage, foreground overwrite, surface ordering, seam, and exactly five human votes pass GATE-006. General diffusion or an undisclosed empty-room plate is outside P0. A commit permanently pins its reveal revision. A measured improvement may become active only through a new validate/preview/explicit-confirm transaction and new scene revision; it never mutates a prior commit or activates silently. Noncanonical cache improvements remain inactive evidence until then.

## Evidence

- A freestanding target can expose several background surfaces.
- RealityKit provides spatial materials/occlusion primitives, but final quality requires device measurement; see ADR-005.

## Consequences

- Removal can be honest and view-bounded.
- Replacement may use a validated reveal underlay without making remove ready.
- Texture provenance and foreground exclusion become contract fields.

## Risks

- The object may hide too much background for a credible bundle.
- Plane geometry can overpaint foreground content without sufficient occluders.
- Deterministic fill may produce visible repetition or seams.

## Fallback

Request another view, shrink the supported envelope, select the easier controlled target, or keep remove unavailable. Replacement remains available when its independent cover gate passes. Hero-fixture failure remains a P0 blocker under ADR-001.

## Benchmark and kill gate

All unmeasured thresholds, fixture sizes, deadlines, and timeboxes in this gate are `TARGET`, not measured results.

`GATE-006` — Fixture: controlled hero capture with at least eight trajectory poses. Variants: observed-only atlas, deterministic local fill, and the simplest license-approved fallback if already available. Metrics: p10 target coverage, median coverage, largest uncovered component, synthesized fraction, foreground overpaint, seam score, and blinded human walk-around vote. Pass: p10 at least 0.95, median at least 0.98, no uncovered component over 1%, no severe foreground overwrite, and 4/5 visual vote. Timebox: one reveal slice, completed before voice integration or release rehearsal; failure kills remove readiness for that fixture and blocks P0 completion.

## Requirements and contracts affected

`FR-REMOVE-001`, `FR-REPLACE-001`, `NFR-RENDER-001`, CON-003, and CON-004.

## Supersession

Supersedes single-plane and unbounded-removal assumptions in the archived inputs. No canonical ADR is superseded.
