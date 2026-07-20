# ReRoom architecture decisions

Accepted ADRs are binding below human-locked decisions. Provisional ADRs are
binding only inside their named fixture, benchmark, fallback, deadline, and kill
gate. See [canonical authority](../canonical/README.md) for the complete
precedence and change discipline.

## Accepted

- [ADR-001 — Product modes and P0 scope](ADR-001-product-modes-and-p0-scope.md)
- [ADR-002 — Native iPhone and web split](ADR-002-native-iphone-and-web-split.md)
- [ADR-003 — ARKit authority and coordinates](ADR-003-arkit-authority-and-coordinates.md)
- [ADR-004 — Atomic capture and record-first replay](ADR-004-atomic-capture-and-record-first-replay.md)
- [ADR-006 — Fast and dense geometry tracks](ADR-006-fast-and-dense-geometry-tracks.md)
- [ADR-008 — Scene identity and readiness](ADR-008-scene-identity-and-readiness.md)
- [ADR-010 — Asset contract](ADR-010-asset-contract.md)
- [ADR-011 — Agent intent and deterministic boundary](ADR-011-agent-and-deterministic-boundary.md)
- [ADR-012 — Transaction and offline restore](ADR-012-transaction-and-offline-restore.md)
- [ADR-013 — Mode B0 guarantee](ADR-013-mode-b0-guarantee.md)
- [ADR-014 — Service topology and hardware tiers](ADR-014-service-topology-and-hardware-tiers.md)

## Provisional

- [ADR-005 — RealityKit-first compositor](ADR-005-realitykit-first-compositor.md)
  — `GATE-003`
- [ADR-007 — Segmentation and depth providers](ADR-007-segmentation-and-depth-providers.md)
  — `GATE-004`, `GATE-007`, `GATE-012`
- [ADR-009 — Multi-surface reveal](ADR-009-multi-surface-reveal.md)
  — `GATE-006`

Changing a load-bearing decision requires a new superseding ADR and synchronized
canonical contracts, requirements, glossary, fixtures, tests, and evidence. Do
not edit an accepted decision in place to make an implementation appear
compliant.
