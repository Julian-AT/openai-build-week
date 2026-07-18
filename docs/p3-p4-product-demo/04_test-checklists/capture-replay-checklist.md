# Phase 2 Capture and Exact Replay QA Checklist

**Document version:** 1.2  
**Date:** 2026-07-18  
**Status:** Working operator checklist  
**Room:** `ROOM-r01`  
**Target:** `TARGET-001`  

## Purpose

This checklist is for the two-person P3/P4 team to run observable capture and replay tests.

It does not replace developer-level contract, coordinate, intrinsics, digest, or crash-safety verification.

A feature that is not included in the supplied build is `NOT IN BUILD`, not a failure.

---

## 1. Test-run metadata

- **Run ID:**  
- **Date/time:**  
- **Build/commit SHA:**  
- **Install method:**  
- **Device model:**  
- **OS version:**  
- **Room revision:** `ROOM-r01`
- **Target ID:** `TARGET-001`
- **Session ID:**  
- **Expected feature:**  
- **Known limitations:**  
- **Evidence folder:**  

---

## 2. Preflight

- [ ] Correct build and commit recorded
- [ ] Developer stated what should work in this build
- [ ] Room and target match `room-setup.md`
- [ ] Candidate movement area is clear and physically safe
- [ ] No people or private information are visible
- [ ] Device is charged
- [ ] Screen recording is ready when required
- [ ] Export/replay instructions are available

---

## 3. Consent-denial test

1. Open the app.
2. Decline or withhold capture consent.
3. Attempt to continue.

### Expected

- [ ] No room recording begins
- [ ] No capture is presented as active
- [ ] The user sees an understandable explanation
- [ ] No room evidence is intentionally exported by the operator

**Result:** `PASS / FAIL / BLOCKED / NOT IN BUILD`  
**Evidence:**  
**Notes:**  

---

## 4. Ten-second capture test

1. Grant the required consent.
2. Start a new session.
3. Hold at the candidate `START-A`.
4. Record approximately 10 seconds using slow movement.
5. Stop or finalize the session.
6. Export or locate the resulting session as instructed.

### Expected

- [ ] Recording state is visible
- [ ] App remains responsive
- [ ] Session finalizes without visible corruption
- [ ] Session ID is available
- [ ] Exported or stored capture is identifiable
- [ ] No unexplained data-loss warning appears

**Result:** `PASS / FAIL / BLOCKED / NOT IN BUILD`  
**Session ID:**  
**Capture reference:**  
**Evidence:**  
**Notes:**  

---

## 5. Longer capture test

Run only when the developer says the build is ready for it.

1. Record the approved longer room path.
2. Keep the target visible for most of the movement.
3. Finalize the session.
4. Record any drops, warnings, freezing, or incorrect state.

### Expected

- [ ] App remains responsive
- [ ] Recording state remains understandable
- [ ] Session finalizes
- [ ] Visible warnings match what happened
- [ ] The result can be identified by session, build, and room revision

**Result:** `PASS / FAIL / BLOCKED / NOT RUN / NOT IN BUILD`  
**Evidence:**  
**Notes:**  

---

## 6. Replay-twice test

1. Open the finalized or approved recovered-prefix capture.
2. Replay or inspect it once.
3. Close or reset the replay view as instructed.
4. Replay or inspect the same capture a second time.

### Operator-observable checks

- [ ] Same session or capture identity is shown both times
- [ ] Same visible timeline order is shown both times
- [ ] Same visible finalization or recovery state is shown both times
- [ ] No unexplained missing or duplicated event is visible
- [ ] Replay does not require a live learned provider when the build claims exact replay

**Result:** `PASS / FAIL / BLOCKED / NOT IN BUILD`  
**Evidence:**  
**Notes:**  

---

## 7. Developer-evidence fields

Record the developer-provided result. Do not independently claim these passed without observing the evidence.

| Technical item | Developer evidence/result | Link/reference |
|---|---|---|
| Frame/image digest validation | `PASS / FAIL / PENDING` | |
| Authoritative journal order | `PASS / FAIL / PENDING` | |
| Cross-runtime replay agreement | `PASS / FAIL / PENDING` | |
| Encoded orientation/intrinsics checks | `PASS / FAIL / PENDING` | |
| Corrupt-suffix/recovered-prefix behaviour | `PASS / FAIL / PENDING` | |
| Bounded queue/stale-drop behaviour | `PASS / FAIL / PENDING` | |

---

## 8. Optional developer-directed tests

Do not force-crash, terminate, corrupt, or modify a capture unless a developer supplies a special test build and exact instructions.

### Network interruption

**Authorized for this build:** Yes / No  
**Result:** `PASS / FAIL / BLOCKED / NOT RUN / NOT IN BUILD`  
**Notes:**  

### Crash/recovery injection

**Authorized for this build:** Yes / No  
**Lifecycle edge tested:**  
**Result:** `PASS / FAIL / BLOCKED / NOT RUN / NOT IN BUILD`  
**Notes:**  

---

## 9. Final result

- **Overall result:** `PASS / FAIL / BLOCKED`
- **Blocking bug IDs:**  
- **Nonblocking bug IDs:**  
- **Evidence links:**  
- **Recommended next action:**  
- **Tester 1:**  
- **Tester 2:**  
