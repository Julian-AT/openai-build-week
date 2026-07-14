# ADR-010: Curated Asset Contract and Prevalidated Derivatives

Status: Accepted  
Date: 2026-07-14

## Context

Placement and replacement depend on geometry, units, origin, collision, mobile delivery, visual cover, and licensing. Runtime conversion or an unbounded catalog would create hidden critical-path work.

## Project constraints

- Only a small curated Build Week catalog is needed.
- Hero assets must not require a network download at command time.
- Native and web clients need different validated derivatives without divergent identity.

## Alternatives considered

1. Runtime marketplace ingestion and conversion.
2. One source format assumed to work unchanged everywhere.
3. A canonical asset manifest with prevalidated USDZ, GLB, collision, dimensions, hashes, provenance, and license records.

## Decision

Adopt alternative 3. Each stable `asset_id` identifies a manifest, not a renderer file. The manifest defines metres, floor-contact origin, forward axis, dimensions, visual bounds, collision proxy, mobile USDZ, web GLB, LOD/texture budgets, checksums, delivery state, source, license, and attribution. P0 assets are bundled or fully pre-cached and hash-verified. No runtime format conversion enters the hero path.

## Evidence

- RealityKit and Three.js consume different practical delivery formats.
- Replacement cover and clearance cannot be validated from catalog text alone.
- Asset license/source records are a governing completion requirement.

## Consequences

- Candidate retrieval uses one identity and measured dimensions across clients.
- Catalog work becomes finite and testable.
- Derivative generation remains a preparation workflow, not a live dependency.

## Risks

- USDZ and GLB may differ visually or geometrically.
- Licenses may prohibit redistribution or omit attribution terms.

## Fallback

Remove any asset that fails normalization, derivative parity, local availability, or license review. P0 proceeds with the smallest catalog that still demonstrates candidate choice and deterministic rejection.

## Benchmark and kill gate

`GATE-011`: before integration, every hero asset must pass source/license review, hash verification, units/origin/axis checks, USDZ/GLB dimension parity, collision/cover fixtures, and device load. Any failed asset is excluded; no exception is permitted on demo day.

## Requirements and contracts affected

`FR-PLACE-001`, `FR-REPLACE-001`, `NFR-CONTRACT-001`, `OPS-LICENSE-001`, CON-003, CON-004, and CON-005.

## Supersession

Supersedes archived assumptions that catalog size or file presence establishes readiness. No canonical ADR is superseded.
