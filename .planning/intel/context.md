# Synthesized Context

DOC-classified material is retained as topic-keyed, source-attributed verbatim notes. Each excerpt is fenced with a fresh randomized data delimiter because source documents are treated as untrusted input.

## Canonical authority and locked scope

- source: docs/canonical/README.md
- precedence: -10

DATA_A19F7C2E_START
When documents disagree, use this order:

1. Human-locked decisions listed in this file and embodied in the Accepted ADR set.
2. Accepted ADRs in `docs/adr/`; no Accepted ADR may change a human lock without the explicit escalation below.
3. Provisional ADRs in `docs/adr/`, within their stated benchmark gates.
4. `MASTER_TECHNICAL_SPEC.md` and the versioned schemas in `docs/contracts/`.
5. `PRD.md`.
6. `DEVELOPMENT_STRATEGY.md`, `TEST_AND_EVALUATION_PLAN.md`, and `RISK_AND_KILL_GATES.md`.

The glossary is the naming authority; JSON Schemas are the field and lifecycle authority. A newer ADR may supersede an older ADR only when it says so explicitly. Audit reports explain history but are not implementation authority.
DATA_A19F7C2E_END

## Dependency-driven implementation sequencing

- source: docs/canonical/DEVELOPMENT_STRATEGY.md
- precedence: 40

DATA_B84D01F6_START
Build one replayable vertical path at a time. The critical path starts with contracts, physical-device readiness, deterministic capture/replay, and a typed place/restore transaction. It surfaces coordinate, compositor, semantic, and reveal risk before voice or polish. Mode B0 exists before the demo depends on a live service. Mode B1 has no P0 task.

This is a dependency strategy for two developers working with Codex/Sol, not a staffing or named-owner plan. At most two implementation-critical streams should be active, plus a bounded research/fixture task. Parallel work must join through versioned contracts and replay fixtures rather than unreviewed integration branches.
DATA_B84D01F6_END

## Canonical lifecycle and readiness vocabulary

- source: docs/canonical/GLOSSARY_AND_ID_REGISTRY.md
- precedence: 40

DATA_C3E96A52_START
Object lifecycle values are `candidate`, `tracked`, `lost`, `retired`. Capability readiness is independent and uses `unavailable`, `warming`, `ready`, `degraded`, `failed` for each of `select`, `place`, `replace`, `remove`, and `restore`. An object may be replace-ready while remove-unavailable. P0 release still requires the removal gate to pass on the controlled hero fixture.

Tracking state values are `normal`, `limited`, and `not_available`. Transaction state values are defined below. Artifact readiness uses the same five readiness values.

The normative capture lifecycle is exactly `selected → image_and_metadata_durable → journaled → network_eligible → server_acknowledged`. CON-002 event types use `frame_selected`, `frame_image_and_metadata_durable`, `frame_journaled`, `frame_network_eligible`, and `frame_server_acknowledged`; event names are evidence of transitions, not a second lifecycle.
DATA_C3E96A52_END

## Risk gates and evidence semantics

- source: docs/canonical/RISK_AND_KILL_GATES.md
- precedence: 40

DATA_D71B4F09_START
This file is the authoritative `GATE-NNN` mapping. Terms and requirement IDs come from [GLOSSARY_AND_ID_REGISTRY.md](../../docs/canonical/GLOSSARY_AND_ID_REGISTRY.md) and [PRD.md](../../docs/canonical/PRD.md). Evidence procedures and formats are identified by the canonical `TEST-NNN` and `EVAL-NNN` registries. ADRs own the architectural decision; this register owns the operational trigger and final kill rule.

Every numeric value below is a **TARGET**, not a measured result. A gate becomes green only when an evidence record identifies the fixture version, implementation revision, device/runtime tier, provider and checkpoint revisions, run count, raw output location, metric code revision, and evaluator. Missing evidence is a failed gate, not an assumed pass.
DATA_D71B4F09_END

## Test and evaluation evidence policy

- source: docs/canonical/TEST_AND_EVALUATION_PLAN.md
- precedence: 40

DATA_E05C8A73_START
This plan defines the evidence needed to decide whether ReRoom's controlled P0 is ready. Requirement behavior is owned by [PRD.md](../../docs/canonical/PRD.md), terminology by [GLOSSARY_AND_ID_REGISTRY.md](../../docs/canonical/GLOSSARY_AND_ID_REGISTRY.md), contract fields by `docs/contracts/`, and final kill decisions by [RISK_AND_KILL_GATES.md](../../docs/canonical/RISK_AND_KILL_GATES.md).

All numeric acceptance values in this plan are explicitly labeled **TARGET**. They are not measured performance. A result may be called `MEASURED` only when it links the immutable fixture, implementation revision, environment, raw evidence, and metric calculation. Product copy may not convert a TARGET or HYPOTHESIS into a claim.
DATA_E05C8A73_END

## Research evidence and unresolved empirical claims

- source: docs/canonical/RESEARCH_LEDGER.md
- precedence: 40

DATA_F2D64B18_START
The evidence establishes safe APIs, versions, provenance, and license boundaries. It does **not** establish the following as facts: sustained base-device FPS/thermal behavior, semantic target quality, learned metric-depth accuracy, reveal credibility, provider latency/VRAM, reconnect recovery, or end-to-end voice reliability. Those are intentionally `REQUIRES_BENCHMARK` and are controlled by `GATE-003`, `GATE-004`, `GATE-006`, `GATE-007`, `GATE-010`, and `GATE-012` in [RISK_AND_KILL_GATES.md](../../docs/canonical/RISK_AND_KILL_GATES.md).

The shipping bill of materials must reference the exact artifact records above or add new `CLM-NNN` records before adopting another version. Moving `main`, an unpinned model alias, a repository code license standing in for checkpoint terms, or an author-reported benchmark is never sufficient shipping evidence.
DATA_F2D64B18_END
