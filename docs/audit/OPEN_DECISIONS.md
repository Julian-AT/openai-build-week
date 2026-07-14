# Open Decisions

Status: no human blockers  
Date: 2026-07-14

No decision currently meets the governing threshold for human input. All remaining architecture uncertainty is safely bounded by a fixture, threshold, timebox, fallback, and kill gate in ADR-005, ADR-007, ADR-009, `ASSUMPTION_REGISTER.md`, and the canonical risk plan.

In particular, RealityKit versus the bounded Metal escape hatch, SAM/provider selection, optional dense geometry, reveal readiness, hardware tier, asset inclusion, and voice availability are empirical gate outcomes rather than human product choices. The working product name is also nonblocking and does not alter the roadmap.

If a controlled-fixture removal failure would require changing the exact four-operation P0 promise, stop and add a dedicated human escalation here; do not demote remove automatically.
