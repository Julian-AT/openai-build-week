# Documentation Synthesis

Mode: `new`

All 28 manifest-classified documents were consumed using their per-document precedence overrides. Lower integers are stronger: canonical human-lock index `-10`, Accepted ADRs `0`, Provisional ADRs `10`, specifications/contracts `20`, PRD `30`, and supporting canonical documents `40`. No default type tiebreak was needed.

## Document counts

- Total: 28
- ADR: 14
- PRD: 1
- SPEC: 7
- DOC: 6
- UNKNOWN/low-confidence: 0

## Cross-reference graph

- Cycle detection: complete
- Resolved internal edges: 101
- Maximum traversal depth: 7 (cap: 50)
- Cycles: 0

## Decisions

- Total decisions: 14
- Locked: 11
- Proposed/provisional: 3
- Locked sources:
  - docs/adr/ADR-001-product-modes-and-p0-scope.md
  - docs/adr/ADR-002-native-iphone-and-web-split.md
  - docs/adr/ADR-003-arkit-authority-and-coordinates.md
  - docs/adr/ADR-004-atomic-capture-and-record-first-replay.md
  - docs/adr/ADR-006-fast-and-dense-geometry-tracks.md
  - docs/adr/ADR-008-scene-identity-and-readiness.md
  - docs/adr/ADR-010-asset-contract.md
  - docs/adr/ADR-011-agent-and-deterministic-boundary.md
  - docs/adr/ADR-012-transaction-and-offline-restore.md
  - docs/adr/ADR-013-mode-b0-guarantee.md
  - docs/adr/ADR-014-service-topology-and-hardware-tiers.md
- Detail: [decisions.md](decisions.md)

## Requirements

- Total requirements: 26
- P0: 24
- Stretch: 2
- IDs: `FR-CAPTURE-001`, `FR-TARGET-001`, `FR-PLACE-001`, `FR-REPLACE-001`, `FR-REMOVE-001`, `FR-RESTORE-001`, `FR-TRANSACTION-001`, `FR-AGENT-001`, `FR-B0-001`, `FR-WEB-001`, `NFR-COORD-001`, `NFR-REPLAY-001`, `NFR-RENDER-001`, `NFR-LATENCY-001`, `NFR-RESILIENCE-001`, `NFR-CONTRACT-001`, `SEC-CONSENT-001`, `SEC-CREDENTIAL-001`, `SEC-RETENTION-001`, `SEC-AGENT-001`, `OPS-DEVICE-001`, `OPS-LICENSE-001`, `OPS-GOLDEN-001`, `OPS-SUBMISSION-001`, `STR-VOICE-001`, `STR-B1-001`
- Detail: [requirements.md](requirements.md)

## Constraints

- Total synthesized constraints: 13
- Type breakdown: 3 nfr, 5 protocol, 3 schema, 2 api-contract
- Sources: Master Technical Spec, contracts README, and CON-001 through CON-005 schemas
- Detail: [constraints.md](constraints.md)

## Context

- Topics: 6
- Topics: canonical authority; implementation sequencing; terminology/lifecycle; risk gates; test evidence; research limitations
- Detail: [context.md](context.md)

## Conflict passes

- LOCKED-vs-LOCKED ADR contradiction: 0
- ADR-vs-existing locked context: not applicable in `new` mode
- Competing PRD acceptance variants: 0 (one PRD source)
- SPEC-vs-higher-precedence ADR contradiction: 0
- Other lower-vs-higher contradiction: 0
- UNKNOWN/low-confidence blockers: 0
- Cycle blockers: 0
- Totals: 0 blockers, 0 competing variants, 0 auto-resolved conflicts
- Report: [../INGEST-CONFLICTS.md](../INGEST-CONFLICTS.md)

STATUS: READY — safe to route
