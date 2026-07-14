# ReRoom Canonical Authority

Status: **PRE-GSD documentation authority**  
Effective date: 2026-07-13

## Authority and precedence

When documents disagree, use this order:

1. Human-locked decisions listed in this file and embodied in the Accepted ADR set.
2. Accepted ADRs in `docs/adr/`; no Accepted ADR may change a human lock without the explicit escalation below.
3. Provisional ADRs in `docs/adr/`, within their stated benchmark gates.
4. `MASTER_TECHNICAL_SPEC.md` and the versioned schemas in `docs/contracts/`.
5. `PRD.md`.
6. `DEVELOPMENT_STRATEGY.md`, `TEST_AND_EVALUATION_PLAN.md`, and `RISK_AND_KILL_GATES.md`.

The glossary is the naming authority; JSON Schemas are the field and lifecycle authority. A newer ADR may supersede an older ADR only when it says so explicitly. Audit reports explain history but are not implementation authority.

## Human-locked decisions

1. The native SwiftUI iPhone app is the Mode A hero.
2. A separate Next.js web client owns Mode B0 replay, debugging, fallback, session management, sharing, and typed control.
3. ARKit is the healthy native session's world/pose authority.
4. The live camera feed remains the photoreal background; ReRoom renders only edit-related virtual/reveal/occlusion/shadow/UI overlays.
5. Recorded/replay Mode B0 is guaranteed P0.
6. Photoreal refinement Mode B1 is stretch-only and cannot block or rewrite P0.
7. P0 exposes exactly **place, replace, remove, and restore**; “undo” invokes restore and is not a fifth operation.
8. The controlled hero target is a freestanding chair or small table with visible floor.
9. The base iPhone 17 path cannot require rear LiDAR; the Mac, current Xcode, signing path, and physical device are available and must be verified.
10. XR glasses are future work, not P0.
11. Delivery assumes two developers using Codex and Sol.
12. Work is dependency-driven and must not be assigned through a person-based plan.
13. Compute is specified as measured capability/hardware tiers, never a hidden mandatory GPU SKU.
14. No GSD command or `.planning/` creation occurs during preparation; onboarding is a later explicit manual action.
15. The two original project Markdown documents are byte-preserved historical evidence, not current authority.
16. Canonical project documentation is English.

Changing any locked decision requires an explicit human escalation in `docs/audit/OPEN_DECISIONS.md`.

## Provisional decisions

A `Provisional` ADR is usable only behind its provider/contract boundary. It must name a fixture, variants, metric, threshold, timebox, deadline, fallback, and kill gate. Failure activates the fallback; it never silently expands P0. Benchmark results must update the ADR, research ledger, risk gate, and any affected requirement/schema together.

## Change discipline

- Requirement behavior changes update `PRD.md`, referenced specification sections, tests, and schemas.
- A load-bearing architectural change requires an ADR. A contract change additionally requires a schema version and compatibility decision.
- Material differences from the archived inputs are recorded in `docs/audit/DECISION_CHANGELOG.md`.
- Performance values remain labeled `TARGET`, `HYPOTHESIS`, or `MEASURED`; only reproducible evidence may change a value to `MEASURED`.
- Stable terms and ID families are defined in `GLOSSARY_AND_ID_REGISTRY.md` and must not be redefined elsewhere.

## Historical sources

`docs/archive/source/ReRoom_Master_Technical_Plan_v3.2.md` and `docs/archive/source/ReRoom_PRD_v1.0.md` are byte-preserved evidence, not current authority. They are excluded from GSD ingestion.

## Intended GSD ingest set

The exact ordered 28-entry set is `docs/gsd/ingest-manifest.yml`. This index is ingested as the sole highest-authority `DOC` at precedence `-10`, so all 16 human locks outrank accepted ADRs at `0`; provisional ADRs use `10`, specifications/contracts `20`, PRD `30`, and supporting canonical documents `40`. The compact set includes development, test, risk, research, glossary, and contract documents and excludes archives, audits, prompts, Codex/GSD setup material, and raw research.

GSD has not been installed project-locally or run for this repository, and
`.planning/` must not exist until the human follows
`docs/gsd/ONBOARDING_AND_CONTINUATION.md`. An older user-global GSD `1.5.0`
surface is workstation context, not project authority, and must be reconciled
through that guide before onboarding.
