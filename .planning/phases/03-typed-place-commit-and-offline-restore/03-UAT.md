---
status: testing
phase: 03-typed-place-commit-and-offline-restore
source: [03-VERIFICATION.md]
started: 2026-07-18T16:20:00Z
updated: 2026-07-18T16:20:00Z
---

## Current Test

number: 1
name: Signed-device place, restart, and restore
expected: |
  On the signed Release build with healthy ARKit floor tracking, preview leaves
  the revision unchanged, Cancel mutates nothing, Confirm produces exactly one
  new durable revision, relaunch recovers it, and Restore creates a fresh
  compensating revision while preserving immutable history.
awaiting: user response

## Tests

### 1. Signed-device place, restart, and restore

expected: Run the complete live place, cancel, confirm, relaunch, and offline restore journey on the bound revision with a visible tracked floor.
result: pending

### 2. GATE-009 reconnect and replication campaign

expected: Complete the canonical reconnect, replication, worker-restart, retry, and same-branch divergence matrix with exactly-once results and no automatic merge.
result: pending

### 3. GATE-010 adversarial input campaign

expected: Complete the closed formal attack corpus and confirm malformed, stale, oversized, injected, or authority-bearing input cannot confirm, commit, or mutate.
result: pending

### 4. GATE-011 production asset qualification

expected: Qualify the production asset manifest, license, geometry/collision behavior, and measured device load; the checked-in Phase 3 proxy remains demo-only until this passes.
result: pending

### 5. Judgment-tier prohibition review

expected: Review all fourteen unresolved Phase 3 prohibitions and either accept each preserved boundary or record a concrete gap without promoting local automation to gate evidence.
result: pending

## Summary

total: 5
passed: 0
issues: 0
pending: 5
skipped: 0
blocked: 0

## Gaps

- The automated sprint slice passes 37/37 must-haves with zero software behavior gaps.
- Signed-device behavior, GATE-009, GATE-010, GATE-011, and the fourteen judgment-tier prohibitions remain human-authoritative and PENDING under the approved 36-hour sprint cut.
