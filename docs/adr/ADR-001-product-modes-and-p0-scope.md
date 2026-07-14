# ADR-001: Product Modes, Exact P0 Scope, and B1 Isolation

Status: Accepted  
Date: 2026-07-14

## Context

The archived inputs mix an exact four-operation promise with a kill rule that could silently demote empty removal. They also describe enough Mode B1 detail that a planning agent could put photoreal refinement on the one-week critical path.

## Project constraints

- Two developers, one week, controlled hero scene, and a base iPhone 17 without a LiDAR dependency.
- Human-locked P0 operations are exactly place, replace, remove, and restore/undo.
- Mode B0 is guaranteed P0; Mode B1 and XR glasses are outside the P0 critical path.

## Alternatives considered

1. Keep the archived scope and allow failed removal to become experimental.
2. Reduce P0 to replacement and restore.
3. Preserve four operations, constrain removal by readiness and a controlled-fixture release gate, and isolate B1.

## Decision

Adopt alternative 3. The product operation enum is `place`, `replace`, `remove`, and `restore`. “Undo” invokes `restore` for the latest eligible committed edit and is not a fifth operation. Internal visibility and asset-delta primitives are not user operations. Removal may be unavailable in an unsupported session, but P0 is not complete until it passes on the controlled hero fixture. B1 may consume only an immutable snapshot after all P0 release gates are green and a human explicitly starts it.

## Evidence

- Human-locked decisions in the governing prompt.
- The archived plan correctly identifies replacement as the signature path and removal as scene-dependent, but its demotion rule conflicts with the locked P0 inventory.

## Consequences

- Readiness can be honest without weakening the release promise.
- PRD, schemas, tests, and demo language share one operation set.
- Detailed B1 technology choices cannot create P0 dependencies.

## Risks

- The hero fixture may fail the removal gate.
- Downstream agents may count “restore” and “undo” separately.

## Fallback

For an unsupported session, keep remove unavailable and guide the user toward replacement. If the hero fixture fails `GATE-006`, P0 remains not ready unless a human explicitly changes the locked promise; do not relabel or fake removal.

## Benchmark and kill gate

Accepted scope does not require a technology bake-off. `GATE-006` validates removal on the hero fixture. `GATE-014` forbids B1 work while any P0 gate is red.

## Requirements and contracts affected

`FR-PLACE-001`, `FR-REPLACE-001`, `FR-REMOVE-001`, `FR-RESTORE-001`, `FR-B0-001`, `STR-B1-001`, CON-003, CON-004, and CON-005.

## Supersession

Supersedes the archived removal-demotion and dated B1-start rules. No canonical ADR is superseded.
