---
phase: 08
slug: p0-hardening-and-evidence
status: retroactive-executed
nyquist_compliant: true
automated_coverage: complete
manual_gates: pending
created: 2026-07-19
---

# Phase 08 — Validation Strategy

This map records the executed fail-closed hardening/evidence automation. The
phase remains `human_needed`; a verified pending report is not a green gate.

## Test infrastructure

| Scope | Command |
|---|---|
| Hardening/mutation suite | `scripts/verify-phase-08-hardening` |
| Evidence index/status/BOM | `scripts/verify-phase-08-evidence` |
| Full component regressions | Phase 2–7 quick/full verifiers referenced by the Phase 8 plans |

## Requirement coverage

| Requirement | Automated behavior |
|---|---|
| `NFR-RESILIENCE-001` | Fault fixtures preserve acknowledged deterministic state or explicit pending evidence. |
| `SEC-CREDENTIAL-001` / `SEC-AGENT-001` | Credential, injection, authority-expansion, build-surface, and private-path scans fail closed. |
| `OPS-LICENSE-001` | Exact BOM blocks unknown/unapproved items. |
| `OPS-GOLDEN-001` / `OPS-SUBMISSION-001` | Schemas and runbooks require real device/human artifacts and never fabricate completion. |

## Continuous strategy

Run the smallest owning phase check after a change, both Phase 8 scripts before
candidate freeze, and validate evidence against the exact clean source revision.

## Manual-only gates

Physical device, visual/browser, reconnect/runtime, license decision, 5/5
golden journeys, rules confirmation, video, Session ID, and publication remain
human-owned. Their current state is `PENDING` or `BLOCKED` exactly as recorded
in the Phase 8 evidence index and verification report.
