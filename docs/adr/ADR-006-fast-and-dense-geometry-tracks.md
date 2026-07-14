# ADR-006: Separate Fast Interaction and Dense Geometry Tracks

Status: Accepted  
Date: 2026-07-14

## Context

Making the first edit wait for learned depth, metric alignment, fusion, semantic lifting, and mesh extraction creates the longest and least debuggable failure chain. ARKit planes plus calibrated target masks can produce conservative interaction proxies earlier, although those proxies are not accurate surfaces.

## Project constraints

- No rear-LiDAR dependency.
- Replacement and removal must expose honest, capability-specific readiness.
- Dense geometry and model choice remain experimental during the week.

## Alternatives considered

1. One dense TSDF path blocks all edits.
2. Pure 2D masks with no world-space proxy.
3. Fast mask-volume/plane/OBB path plus asynchronous dense enhancement.

## Decision

Adopt alternative 3. The fast track owns calibrated target masks, conservative multi-view mask volume, OBB, support relation, and reveal/view-envelope evidence. The dense track may add depth-aligned surfaces, collision evidence, occluders, and B0 visualization but cannot change stable object IDs or invalidate a committed transaction. A mask volume is never represented as collision-quality geometry.

## Evidence

- ARKit provides world tracking, plane detection, and raycasting without requiring scene reconstruction.
- The archived architecture correctly separated fast interaction from dense fusion; this ADR removes its remaining dense-path assumptions from readiness.

## Consequences

- Targeted replacement can progress while dense inference is absent or rejected.
- Each capability cites the evidence it actually uses.
- Provider outputs remain disposable evidence attached to canonical identities.

## Risks

- Visual hull depth and OBB dimensions may be poor under small baselines.
- Conservative dilation can hide real fragments but overpaint nearby content.

## Fallback

Request additional calibrated views, shrink the supported view envelope, or keep the affected capability unavailable. Dense failure falls back to ARKit planes, mask volume, and degraded B0 visualization; it never kills capture/replay.

## Benchmark and kill gate

All unmeasured thresholds, fixture sizes, deadlines, and timeboxes in this gate are `TARGET`, not measured results.

`GATE-005` validates the fast volume on three-to-five hero views: stable identity/support, target-projection coverage within the supported envelope, and bounded OBB variation. `GATE-007` separately selects or disables dense geometry. Failure of `GATE-005` blocks replace/remove readiness; failure of `GATE-007` activates the no-dense fallback.

## Requirements and contracts affected

`FR-TARGET-001`, `FR-REPLACE-001`, `FR-REMOVE-001`, `NFR-COORD-001`, CON-003, and CON-004.

## Supersession

Supersedes archived statements that dense TSDF is needed before a valid edit. No canonical ADR is superseded.
