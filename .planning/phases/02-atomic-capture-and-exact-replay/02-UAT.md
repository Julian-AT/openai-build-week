---
status: testing
phase: 02-atomic-capture-and-exact-replay
source: [02-VERIFICATION.md]
started: 2026-07-18T12:58:00Z
updated: 2026-07-18T12:58:00Z
---

## Current Test

number: 1
name: Signed-device GATE-001 evidence
expected: |
  The sprint smoke is recorded honestly. GATE-001 becomes GREEN only after the
  complete closed physical matrix and human-bound report pass; until then it
  remains PENDING and live providers remain blocked.
awaiting: user response

## Tests

### 1. Signed-device GATE-001 evidence

expected: Run the signed-device pressure/recovery smoke for the sprint and the complete new-revision GATE-001 matrix before any release claim.
result: pending

### 2. Local durability authority

expected: Confirm server acknowledgement, queue completion, and network availability never become local durability or replay authority.
result: pending

### 3. Provider-independent replay oracle

expected: Confirm provider or network output never enters the deterministic replay oracle.
result: pending

### 4. Journal-before-exposure boundary

expected: Confirm no frame is exposed, enqueued, or acknowledged before durable image, metadata, and journal binding.
result: pending

### 5. Consent boundary

expected: Confirm there are no pre-consent capture bytes and consent is never reused across session IDs.
result: pending

### 6. Verified-prefix boundary

expected: Confirm replay exposes no record beyond the last hash-valid contiguous prefix.
result: pending

### 7. Journal ordering authority

expected: Confirm journal gaps or ordering are never repaired from timestamps, arrays, directory order, or provider output.
result: pending

### 8. Live-queue independence

expected: Confirm live drop, cancellation, pause, or completion order cannot delete durable packets or redefine replay order.
result: pending

### 9. Independent runtime agreement

expected: Confirm cross-runtime agreement is not produced by copied output, mismatch normalization, or another runtime's authority.
result: pending

### 10. Truthful durability and upload wording

expected: Confirm local durability is never presented as upload/share completion and paused, offline, and recovered states remain visible.
result: pending

### 11. Inspector verification boundary

expected: Confirm the inspector cannot decode or expose records that ReplayCore did not verify.
result: pending

### 12. Physical evidence classification

expected: Confirm synthetic, simulator, fixture, or inferred output is never labeled physical MEASURED GATE-001 evidence.
result: pending

### 13. Evidence privacy boundary

expected: Confirm no raw room imagery, private traces, device identifiers, signing material, or account data is committed as gate evidence.
result: pending

## Summary

total: 13
passed: 0
issues: 0
pending: 13
skipped: 0
blocked: 0

## Gaps

- Full GATE-001 physical evidence is deferred to Phase 8 by the approved 36-hour sprint cut and remains PENDING.
- The twelve judgment-tier prohibitions remain queued for human review; the verifier found no contrary implementation evidence.
