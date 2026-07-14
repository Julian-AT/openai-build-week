# ADR-008: Canonical Scene Identity and Capability Readiness

Status: Accepted  
Date: 2026-07-14

## Context

Renderer indices, provider buffer positions, one global `editable` flag, and server-only artifact readiness would create identity drift and premature user promises.

## Project constraints

- Mode A and B0 must share stable identity and transaction history.
- Providers and renderers are replaceable.
- A server-generated artifact is unusable until the client verifies and activates it.

## Alternatives considered

1. Provider/renderer indices as scene identity.
2. Stable IDs with one global readiness flag.
3. Stable canonical IDs plus lifecycle and independent capability readiness.

## Decision

Adopt alternative 3. Scene state uses stable prefixed UUID strings for world frames, surfaces, objects, assets, artifacts, and transactions. Object lifecycle is separate from readiness. Readiness for select/place/replace/remove/restore uses `unavailable`, `warming`, `ready`, `degraded`, or `failed` and includes client hash verification/resource activation. Derived meshes, Open3D blocks, RealityKit entities, Three.js objects, and neural tracks never become canonical identity.

## Evidence

- Provider independence and deterministic replay require identity outside transient buffers.
- Replacement and removal have different evidence and therefore different readiness.

## Consequences

- Dense results and renderer swaps upgrade evidence without rewriting history.
- UI states can explain the missing capability precisely.
- Schemas and fixtures must enforce stable references and revisions.

## Risks

- Stale artifacts may appear ready if activation acknowledgement is omitted.
- Duplicated readiness definitions can drift across documents.

## Fallback

Unknown, stale, hash-failed, or unactivated artifacts keep the relevant capability unavailable/degraded; the previous activated revision remains in use.

## Benchmark and kill gate

Contract fixtures must reject renderer indices, missing references, and illegal readiness transitions. Artifact activation/revision tests are part of `GATE-009`; failures block commit acknowledgement.

## Requirements and contracts affected

`FR-TARGET-001`, `FR-REPLACE-001`, `FR-REMOVE-001`, `NFR-CONTRACT-001`, CON-003, CON-004, and CON-005.

## Supersession

Supersedes any archived lifecycle example that treats readiness as a linear object state. No canonical ADR is superseded.
