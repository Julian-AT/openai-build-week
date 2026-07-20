# ReRoom 24-Hour Finish Runbook

**Objective:** deliver one reproducible, honest deep-AI hackathon demo in the
next 24 hours without weakening deterministic authority or inventing physical
evidence.
**Classification:** demo candidate, not canonical P0 release.
**Current GSD entry:** `$gsd-next`, which currently routes to `$gsd-ship`
because the finished work is committed but unpublished. Publishing is a
deliberate owner action; after that decision, resume `$gsd-verify-work 02` and
treat `.planning/STATE.md` as authoritative.
**Concurrency:** two implementation-critical lanes maximum; join only through
checked-in contracts/fixtures.

## Current checkpoint

- Phase 02.1 is 4/4 implemented. Its exact-source verifier passes all 16
  commands and marks only `CR-03`, `CR-04`, and `CR-12` as automated review
  candidates; 17 other Phase 2 findings, Phase 2 itself, and `GATE-001` remain
  open.
- Phase 09 is 1/1 implemented. Local evidence currently includes 34 gateway
  tests, a complete 129/129 serial clean-snapshot native run (119
  unit/integration plus 10 UI), 10 web tests, strict schema parity,
  deterministic regeneration of three asset bundles, and production builds.
  The frozen executable candidate also passes a signed arm64 build for the
  paired base iPhone 17. Live provider, actual signed-device execution, formal
  browser, and human gates remain pending.
- A local Chromium smoke on the frozen candidate rendered the accepted
  seven-event B0 replay and exercised keyboard-accessible slider plus
  Previous/Next transitions with no console or page errors. It is not the
  formal `GATE-008` browser matrix.
- The immediate human-visible finish is live Sol/vision (timeboxed), one clean
  signed-device rehearsal, then the sub-three-minute recording and submission
  handoff. The frozen-candidate B0 smoke is green. Optional voice is the first
  feature cut.

## Frozen executable candidate

- Revision: `476d88f25d0455aea7394ffa72c3188cdb6113ca`
- Native: 129/129 tests pass (119 unit/integration and 10 UI) on iPhone 17 / iOS
  26.4 simulator; Debug and Release simulator builds pass.
- Device build: the arm64 Debug app signs successfully for paired base iPhone
  17 `00008150-0014543E3693401C`. It was not installed or launched, so this is
  not physical camera, microphone, thermal, visual, or UX evidence.
- Browser: local Chromium traverses the seven-event accepted replay, including
  slider and both direction controls; console/page errors are empty. Local load
  observation: TTFB 258 ms, LCP/FCP 300 ms, CLS 0.
- Provider: no `OPENAI_API_KEY` or gateway token was available; no live Sol,
  vision, or Realtime result is claimed.

## Definition of done

The sprint is finished when one clean revision can demonstrate:

1. a signed native session with camera/ARKit and the three-entry local catalog;
2. place or replace → revision-neutral preview → explicit one-revision commit;
3. restore preview → explicit compensating commit while offline-capable;
4. GPT-5.6 Sol returning strict CON-006 from typed input and, if the 45-minute
   live check passes, one explicitly consented current frame;
5. model output visibly stopping at proposal/preview, never auto-committing;
6. optional push-to-talk Realtime or a clearly shown typed fallback;
7. a separate real-browser B0 golden replay/inspection path;
8. a sub-three-minute honest recording plus setup, test, pending-gate, and
   submission notes bound to the clean revision.

Canonical P0, normal removal quality, and every physical/human gate are separate
claims. A demo can finish while those remain pending.

## Lane A — deterministic integrity

| Timebox | Work | Exit |
|---:|---|---|
| 0–3 h | Execute Phase 02.1 Plans 01→04 sequentially. | Verified archive capability only; exact physically durable prefix; atomic/race-safe publication; production callers and narrow evidence all green. |
| 3–5 h | Full Swift package, contract, replay, mutation, and secret checks. | Fresh commands pass on the candidate source tree. |
| 5–7 h | Clean-revision Xcode test/build, then signed base-iPhone install. | Provenance guard passes; camera/ARKit starts; no LiDAR dependency. |
| 7–10 h | Native deterministic hero rehearsal. | Place/replace/restore preview and confirmation show exact revision behavior; removal limitation is disclosed. |

## Lane B — visible AI and demo resilience

| Timebox | Work | Exit |
|---:|---|---|
| 0–2 h | Verify gateway tests/typecheck/build/schema and native AI compilation. | CON-006 stays closed; no standard API key enters the phone. |
| 2–4 h | Run one live typed Sol proposal and one consented-frame proposal. | Exact context echo; known catalog asset; preview only; request IDs retained without prompt/image/secret logging. |
| 4–5 h | Try the five fixed Realtime utterances in [Phase 09 validation](../../phases/09-ai-design-copilot-demo/09-VALIDATION.md). | Keep voice only at ≥4/5 expected proposals with all adversarial cases rejected/clarified; otherwise disable it. |
| 5–7 h | Run B0 in a real supported browser over local HTTP. | Golden capture verifies, replays, scrubs, and exposes honest degraded state. |
| 7–10 h | Prepare demo scene, narration, fallback order, and capture sheet. | One repeatable run that does not depend on optional voice or a live model. |

## Join and final 14 hours

| Timebox | Work | Exit |
|---:|---|---|
| 10–14 h | Freeze the candidate, rerun all software checks, perform one signed build and one browser smoke. | Complete for revision `476d88f`; actual on-device launch/rehearsal remains pending. |
| 14–18 h | Capture the shortest complete demo: problem → camera-grounded edit → AI proposal boundary → explicit commit/restore → B0 replay. | Usable take under three minutes with audible explanation. |
| 18–21 h | Produce README/setup, architecture/AI explanation, Codex Session ID, license/access notes, and pending-gate disclosure. | A reviewer can run the local pieces without guessing. |
| 21–24 h | Regression, backup take, submission checklist, human publish. | No known software regression; submission remains a deliberate human action. |

## Hard kill rules

- **Sol:** if credentials/model access or a valid strict response is not working
  after 45 minutes, stop. Demo the exact mocked fixture/local catalog and say
  the live provider is unavailable; do not loosen CON-006.
- **Realtime:** if native audio/network behavior or 4/5 intent quality misses a
  45-minute slice, disable the button and use typed input. Voice is P1.
- **Removal:** do not spend the sprint inventing unseen-room synthesis. If the
  normal reveal path is not already gate-ready after a 90-minute device check,
  use the visibly disclosed demo fixture and keep GATE-006 pending.
- **Dense/semantic providers:** do not add SAM, DA3, Open3D, LingBot, a GPU host,
  or B1 during this sprint. Manual target/ARKit/no-dense fallbacks are canonical.
- **Evidence:** simulator, model output, or recollection never becomes physical
  or human evidence. A dirty-tree build never becomes revision-bound evidence.
- **Scope:** no cloud deployment, new database, new operation, schema loosening,
  large catalog, commerce, or multi-user work.

## Command sheet

```sh
# Exact shared Node runtime (when nvm is installed)
nvm use

# Deterministic Swift core
swift test --package-path ios/Packages/ReRoomContracts
xcodebuild -project ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj \
  -scheme ReRoomDeviceProof -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj \
  -scheme ReRoomDeviceProof \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4' \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 180 \
  -maximum-test-execution-time-allowance 240 \
  CODE_SIGNING_ALLOWED=NO test

# Reproducible local CON-004 demo assets (rerun after source/provenance changes)
node tools/assets/generate_hackathon_assets.mjs

# Optional AI gateway
npm --prefix gateway ci
npm --prefix gateway test
npm --prefix gateway run typecheck
npm --prefix gateway run build
npm --prefix gateway audit --omit=dev --audit-level=high

# Provider-independent web path
npm --prefix web test
npm --prefix web run typecheck
npm --prefix web run build
npm --prefix web audit --omit=dev --audit-level=high

# Static integrity
plutil -lint ios/ReRoomDeviceProof/ReRoomDeviceProof/Info.plist
plutil -lint ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/project.pbxproj
scripts/verify-reroom-release-surface
git diff --check
```

Use the serial Xcode invocation above; Xcode's parallel clone launcher can
wedge independently of the product tests. The web package pins Next.js
16.2.10 and overrides its vulnerable PostCSS 8.4.31 transitive pin with tested
PostCSS 8.5.20. Keep the override only while tests, typecheck, the production
build, and the zero-vulnerability production audit all pass.

After the production web build, start it from the repository root with
`npm --prefix web start -- -H 127.0.0.1 -p 3100` and exercise the timeline in a
real supported browser. A successful local browser smoke is still not the full
retention, ordinary-video, sharing, or fault campaign required by `GATE-008`.

For live use, export `OPENAI_API_KEY` and `REROOM_GATEWAY_TOKEN` only in the
gateway process environment. Never paste their values into GSD, logs, evidence,
source, `.rrcap`, or the iPhone app. The native app receives only the local
gateway bearer token and short-lived Realtime credential.

## Handoff truth table

| Result | Allowed statement |
|---|---|
| Local automated checks | “The deterministic software and strict AI boundary pass the listed local checks.” |
| One signed-device smoke | “The named revision ran this exact smoke on the named device.” |
| One live Sol request | “A live request succeeded once with this redacted request ID.” |
| Optional voice disabled | “Voice fell back to typed input without affecting the edit journey.” |
| DEBUG/demo removal fixture | “The demo illustrates the transaction/reveal flow; normal removal quality and GATE-006 remain pending.” |
| Missing gate evidence | Never “P0 complete,” “production ready,” or “gate passed.” |
