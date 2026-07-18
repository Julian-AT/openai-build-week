# ReRoom Demo Script and Spatial User Flow

**Document version:** 1.2  
**Date:** 2026-07-18  
**Status:** `DRAFT — FEATURE-DEPENDENT`  
**Room:** `ROOM-r01`  
**Target:** `TARGET-001` — round blue pedestal table  

## Purpose

This document defines the intended demonstration order. It is not evidence that every beat is implemented.

Before final recording, each beat must be marked:

- `VERIFIED FOR DEMO`
- `FALLBACK`
- `CUT`

Do not include an unverified operation in the final video.

---

## 1. Final-build preflight

Record:

- **Final build/commit:**  
- **Device and OS:**  
- **Room revision:**  
- **Target ID:**  
- **Approved replacement asset:**  
- **Approved placement asset:**  
- **Verified operations:**  
- **Known limitations:**  
- **Evidence links:**  

Use typed/tap input as the reliable default. Voice may be shown only if the final build supports it reliably.

---

## 2. Beat 1 — Consent and capture

**Status:** `[ ] VERIFIED FOR DEMO  [ ] FALLBACK  [ ] CUT`

### Action

1. Open ReRoom.
2. Show the consent and recording state.
3. Start a new session.
4. Begin at the approved `START-A`.
5. Move slowly through the supported target views.

### Expected visible behaviour

- capture does not begin before consent;
- recording state is understandable;
- the live camera remains responsive;
- the session can be finalized and exported.

### Presenter wording

> “We begin with an explicit, consented room capture. ReRoom records selected camera frames and their spatial metadata so the same session can later be replayed and inspected.”

Do not quote a frame rate or latency unless it has been measured on the final build.

---

## 3. Beat 2 — Place and restore

**Status:** `[ ] VERIFIED FOR DEMO  [ ] FALLBACK  [ ] CUT`

Include this beat only when the final build supports typed/tap place and restore.

### Action

1. Point at an approved area of visible floor.
2. Select the approved small placement asset.
3. Show a preview.
4. Confirm the edit.
5. Move the phone through a short supported view.
6. Restore the edit.

### Expected behaviour

- preview does not commit by itself;
- one confirmation produces one committed edit;
- the asset appears supported by the floor;
- restore returns to the prior state;
- no unsupported physical claim is made.

### Presenter wording

> “First, we place a small approved asset on the detected floor, confirm it, and restore the previous state.”

Optional voice wording may be added only after voice is verified.

---

## 4. Beat 3 — Target selection and replacement

**Status:** `[ ] VERIFIED FOR DEMO  [ ] FALLBACK  [ ] CUT`

Include this beat only when target selection and replacement have passed the final build test.

### Action

1. Select `TARGET-001`, the round blue pedestal table.
2. Confirm that the interface identifies the intended target.
3. Choose the approved replacement table.
4. Show a preview.
5. Confirm the replacement.
6. Move through the tested supported view.
7. Restore the original state.

### Expected behaviour

- ambiguity does not silently select the wrong object;
- the replacement is plausibly scaled and supported;
- the original target does not visibly leak outside the approved composite;
- the replacement remains stable within the supported view;
- restore returns to the previous state.

### Presenter wording

Typed default:

> “Replace this table with the approved alternative.”

Optional GPT-5.6 wording, only if the final product actually supports and records it:

> “Replace this table with a warmer, smaller design.”

Do not claim GPT-5.6 performed spatial validation or commit authority. Deterministic application code owns those decisions.

---

## 5. Beat 4 — Controlled removal and restore

**Status:** `[ ] VERIFIED FOR DEMO  [ ] FALLBACK  [ ] CUT`

Removal may be shown only if the relevant technical and visual checks pass.

### Action

1. Select `TARGET-001`.
2. Wait for the interface to report that removal is available.
3. Remove the target.
4. Move only within the tested supported view.
5. Restore the target.

### Expected behaviour

- removal is unavailable when evidence is insufficient;
- floor, wall, and foreground ordering remain believable within the supported view;
- no severe uncovered region or foreground overwrite is visible;
- restore returns to the previous state.

### Presenter wording

> “Removal is offered only when ReRoom has enough validated background evidence for this controlled view.”

When removal does not pass, cut this beat and state the limitation honestly.

---

## 6. Beat 5 — Exact replay and Mode B0

**Status:** `[ ] VERIFIED FOR DEMO  [ ] FALLBACK  [ ] CUT`

### Action

1. Finalize the session.
2. Open the approved replay or web interface.
3. Load the recorded session.
4. Scrub through the timeline.
5. Show available frame, event, and transaction information.

### Expected behaviour

- the session opens successfully;
- the timeline is understandable;
- recorded events appear in authoritative order;
- the interface distinguishes `.rrcap` from ordinary video;
- unavailable geometry or providers degrade honestly.

### Presenter wording

> “The recorded session is not only a video. ReRoom can replay the captured frames and events in their authoritative order for testing, recovery, and web inspection.”

Do not claim that an ordinary uploaded video contains ARKit scale, planes, or calibration.

---

## 7. Codex and GPT-5.6 explanation

Complete this section from actual project evidence before recording.

### Codex

Record:

- which implementation or testing work Codex accelerated;
- the representative `/feedback` Session ID;
- one or two concrete examples;
- the final repository evidence.

### GPT-5.6

State only the role actually present in the final build, for example:

- structured interpretation of a design preference;
- proposal of catalogue candidates;
- explanation or clarification.

Do not claim that GPT-5.6 owns target identity, transforms, confirmation, commit, revisions, persistence, or restore.

---

## 8. Fallback lines

- **Voice unavailable:** “We use the same verified operation through typed or tap input.”
- **Removal unavailable:** “This view does not yet have enough validated background evidence, so ReRoom keeps removal unavailable.”
- **Network unavailable:** “New remote processing is paused; previously committed local state remains available when supported.”
- **Web geometry unavailable:** “The replay timeline and recorded session evidence remain available without claiming calibrated browser AR.”
- **Feature cut:** “This capability remains a documented limitation of the current prototype.”

---

## 9. Final recording rule

The final video must show real product behaviour from the final build.

Do not present:

- a mock-up as implemented behaviour;
- prerecorded replay as live capture;
- a manual override as automation;
- a target or hypothesis as a measured result;
- an unsupported arbitrary-room claim.
