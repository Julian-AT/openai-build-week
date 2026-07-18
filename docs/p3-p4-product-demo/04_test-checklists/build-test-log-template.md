# ReRoom Build Test Log and Defect Template

**Document version:** 1.2  
**Date:** 2026-07-18  
**Workspace:** P3/P4 Product & Demo  

## 1. Build handoff

- **Build/commit SHA:**  
- **Branch:**  
- **Install method:**  
- **Developer contact:**  
- **Feature expected to work:**  
- **Known limitations:**  
- **Export/debug instructions:**  
- **Handoff time:**  

A build is not ready for structured testing until its commit and expected feature are known.

---

## 2. Test-run metadata

- **Run ID:**  
- **Date/time:**  
- **Tester operating device:**  
- **Tester observing/logging:**  
- **Device model:**  
- **OS version:**  
- **Room ID/revision:** `ROOM-r01`
- **Target ID:** `TARGET-001`
- **Session ID:**  
- **Fixture/capture ID:**  
- **Network state:**  
- **Evidence folder:**  

---

## 3. Step log

Use one row per actual step. Mark unavailable features `NOT IN BUILD`; do not call them failures.

| Step ID | Action | Expected result | Actual result | Status | Evidence/timestamp | Bug ID |
|---|---|---|---|---|---|---|
| `T-01` | Launch app | App opens without unexpected failure | | `PASS / FAIL / BLOCKED` | | |
| `T-02` | Consent decision | Capture follows the explicit consent state | | | | |
| `T-03` | Start capture | Recording state becomes understandable | | | | |
| `T-04` | Finalize/export | Session finalizes and can be identified | | | | |
| `T-05` | Replay | Approved capture opens and its timeline is inspectable | | | | |
| `T-06` | Typed/tap place | Run only when included in build | | `NOT IN BUILD` | | |
| `T-07` | Restore | Run only when included in build | | `NOT IN BUILD` | | |
| `T-08` | Target selection | Run only when included in build | | `NOT IN BUILD` | | |
| `T-09` | Replacement | Run only when included in build | | `NOT IN BUILD` | | |
| `T-10` | Removal | Run only when included in build and ready | | `NOT IN BUILD` | | |
| `T-11` | Web/Mode B0 | Run only when included in build | | `NOT IN BUILD` | | |

Allowed status values:

- `PASS`
- `FAIL`
- `BLOCKED`
- `NOT RUN`
- `NOT IN BUILD`

---

## 4. Run summary

- **Overall result:**  
- **Passed steps:**  
- **Failed steps:**  
- **Blocked steps:**  
- **Steps not in build:**  
- **Top issue:**  
- **Evidence index:**  
- **Retest required:** Yes / No
- **Retest build:**  

---

## 5. Defect report

Create one report per reproducible issue.

### Identification

- **Bug ID:**  
- **Title:**  
- **Severity:** `P0 / P1 / P2 / P3`
- **Status:** `OPEN / FIXED / RETEST / CLOSED / DEFERRED`

### Environment

- **Build/commit SHA:**  
- **Device/OS:**  
- **Room revision:**  
- **Target ID:**  
- **Session ID:**  
- **Fixture/capture ID:**  

### Reproduction

1.  
2.  
3.  

- **Expected result:**  
- **Actual result:**  
- **Frequency:** ___ / 5
- **First observed at:**  

### Evidence

- **Screen recording:**  
- **Timestamp:**  
- **Screenshot:**  
- **Debug bundle:**  
- **Other logs/reference:**  

### Retest

- **Retest build:**  
- **Retest date:**  
- **Same reproduction steps used:** Yes / No
- **Retest result:** `PASS / FAIL / BLOCKED`
- **Notes:**  

---

## 6. Severity guide

- **P0 — blocker:** prevents the approved core path, causes a crash or data loss, or invalidates required evidence.
- **P1 — demo critical:** clearly visible instability or failure likely to damage the final demonstration.
- **P2 — polish:** understandable and usable, but visibly rough or inconsistent.
- **P3 — later improvement:** useful enhancement that does not block the approved demo.
