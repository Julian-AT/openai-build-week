# ADR-005: RealityKit-First Camera-Feed Compositor

Status: Provisional  
Date: 2026-07-14

## Context

Mode A must cover a real target with spatial reveal geometry and virtual assets while the camera remains the photoreal background. RealityKit shortens the asset/anchor path, but documentation alone cannot establish alpha/depth behavior or visual quality for this use case. A full Metal compositor is feasible in principle but expensive for two developers.

## Project constraints

- The render loop never waits for network, models, or an LLM.
- The base iPhone 17 must sustain a four-minute hero session without relying on LiDAR occlusion.
- Replacement is the signature path; empty removal still must pass on the controlled fixture.

## Alternatives considered

1. RealityKit entities with occlusion, unlit reveal materials, and cached assets.
2. ARKit plus a custom Metal camera/depth/stencil compositor from the start.
3. Screen-space image punching without spatial reveal geometry.

## Decision

Start with alternative 1 behind a renderer boundary. Render the camera background, retained proxy occluders, reveal layers, assets, conservative contact shadows, and UI in deterministic order. Prepare only a bounded Metal spike as an escape hatch; do not assume a production Metal compositor is free. Reject alternative 3 as the canonical approach.

## Evidence

- RealityKit exposes `OcclusionMaterial`: https://developer.apple.com/documentation/realitykit/occlusionmaterial
- RealityKit exposes final-frame Metal postprocessing and a source depth texture: https://developer.apple.com/documentation/realitykit/arview/rendercallbacks-swift.struct/postprocess and https://developer.apple.com/documentation/realitykit/arview/postprocesscontext/sourcedepthtexture
- These APIs establish capability, not ReRoom-specific visual correctness.

## Consequences

- Asset anchoring and standard materials use the shortest supported native path.
- Renderer-specific entities remain derived from canonical artifact IDs.
- A renderer switch does not alter scene, transaction, or reveal contracts.

## Risks

- Transparent reveal edges, depth writes, foreground occlusion, and target coverage may be unstable.
- A late Metal rewrite would exceed the week.

## Fallback

First reduce reveal complexity and use the validated replacement composite. Use Metal only if the bounded spike already demonstrates the required ordering and frame budget. If neither path passes, `GATE-003` is blocking; activate B0 for resilience but do not claim Mode A complete.

## Benchmark and kill gate

All unmeasured thresholds, fixture sizes, deadlines, and timeboxes in this gate are `TARGET`, not measured results.

`GATE-003` — Fixture: canned multi-surface reveal, occluder, and normalized asset plus the hero room. Variants: RealityKit primary and minimal Metal prototype. Metrics: correct ordering at eight poses, severe-artifact count, four-minute FPS/thermal/memory, and 4/5 visual vote. Pass: no severe ordering artifact, at least 45 FPS, no crash/jetsam or sustained serious/critical thermal state, and 4/5 vote. Timebox: four hours in the first device-risk slice. Missed threshold/timebox kills that renderer variant.

## Requirements and contracts affected

`NFR-RENDER-001`, `FR-REPLACE-001`, `FR-REMOVE-001`, CON-003, and CON-004.

## Supersession

Supersedes the archived implication that Metal is an automatically available fallback. No canonical ADR is superseded.
