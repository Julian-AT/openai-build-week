---
phase: 07-separate-mode-b0-web-fallback
status: pending_human_evidence
automated_verdict: human_needed
automated_score: 10/14
recorded: 2026-07-18
---

# Phase 7 UAT

The fixed-golden local B0 sprint slice is implemented and independently verified. It invokes the exact Phase 2 replay runner server-side, exposes only a verified serializable DTO, keeps the client scrubber in memory, and states honestly that the current capture has no scene/transaction events.

## Verified automated scope

- Hash-bound replay runner and golden capture, fail-closed loader, DTO validation, and provider-disabled execution.
- Local scrub/inspection UI, stable event details, absence/degradation copy, strict server/client boundary, and no upload/share/auth/cloud/provider path.
- Tests, typecheck, production build, client-bundle scan, repeatable local HTTP render, mutation suite, and byte-identical source-bound evidence.

## Pending canonical scope

| ID | Required work | Status |
| --- | --- | --- |
| `GATE-008` | Real supported-browser runs, fault/degradation matrix, ordinary-video behavior, and retained browser artifacts. | `PENDING` |
| `FR-WEB-001` | General capture import plus scene/transaction/artifact inspection, sessions, sharing, and typed fork behavior. | `PENDING` |
| `SEC-RETENTION-001` | Server TTL/share/delete lifecycle and audit evidence if server retention is introduced. | `PENDING` |

Accepted claim: **“The automated fixed-golden local B0 sprint slice passed.”** Local HTTP rendering is not real-browser evidence and does not complete Phase 7 or P0.
