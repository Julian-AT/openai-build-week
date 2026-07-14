# ReRoom Product Requirements Document v1.0

**Status:** P0 product freeze for OpenAI Build Week  
**Date:** 13 July 2026  
**Working title:** ReRoom  
**Technical authority:** `ReRoom_Master_Technical_Plan_v3.2.md`  
**Release target:** Build Week submission by 21 July 2026

---

## 1. Product summary

ReRoom lets a user look at a real room through an iPhone, point at furniture, say what they want changed, and see the edit remain anchored as they walk around.

The live camera feed remains the visual background. ReRoom adds only the virtual content needed for the edit: reconstructed floor/wall reveals, replacement furniture, occlusion, shadows, and status UI. The cloud builds spatial understanding in parallel, while the phone keeps rendering locally.

The product has three modes:

- **Mode A — Live AR:** the native iPhone hero experience.
- **Mode B0 — Scan, process, and continue:** a guaranteed web/replay path for recorded iPhone captures and ordinary videos.
- **Mode B1 — Photoreal twin:** an optional post-scan polish path, built only after P0 is complete.

---

## 2. Problem

Furniture-shopping and room-design tools usually make the user choose between convenience and credibility. A flat product preview does not understand the room. A high-quality room reconstruction requires a separate scanning/build step. General image editing may look convincing from one angle but breaks as soon as the camera moves.

The user’s actual questions are simple:

- Will this item fit?
- Will it leave enough space to walk?
- What would it look like from different positions?
- Can I compare a replacement with what is physically there now?

ReRoom answers those questions in the live view rather than asking the user to leave the room and inspect a disconnected model.

---

## 3. Target user and launch scenario

### 3.1 Primary user

A renter, homeowner, or furniture shopper who wants to preview a small room change before buying or moving an item.

### 3.2 Build Week scenario

- One controlled room.
- One freestanding armchair or small side table.
- Clear floor and a simple wall behind the object.
- One base iPhone 17 running the native application.
- Five to ten curated replacement assets, bundled or pre-cached on iPhone before the hero session.
- A short 10–30 second look-around before the edit.

This is a focused proof of a general interaction model, not a claim that every room and object can already be edited.

---

## 4. Product promise

> Point your phone at an object in your room, tell ReRoom what you want instead, and watch a physically validated change appear live—anchored as you move.

### Honest fine print

- The enhanced live experience requires the native iPhone application in v1.
- A short look-around is required so the system can understand the target and surrounding floor/wall.
- Replacement becomes ready before empty removal in many scenes.
- Empty removal is available only when ReRoom has a sufficiently good background reveal.
- Other devices can upload, process, replay, and edit a scan in the web application; they do not receive the full live iPhone compositor in v1.

---

## 5. Goals

### 5.1 P0 goals

1. Make a live room edit feel immediate and spatially stable on an ordinary non-LiDAR iPhone.
2. Demonstrate exactly four operations: place, replace, remove, and undo/restore.
3. Make GPT-5.6 Sol visibly load-bearing in a physically validated replacement decision.
4. Preserve every capture for deterministic replay and a universal web fallback.
5. Complete the golden path five consecutive times before final recording.

### 5.2 Non-goals

- General removal of arbitrary objects and backgrounds.
- Whole-room autonomous redesign.
- Full product marketplace or purchase flow.
- On-device AI reconstruction.
- Multi-room mapping or long-term AR relocalization.
- Android or headset clients during Build Week.
- Mandatory photoreal post-processing.

---

## 6. Golden-path user story

### Beat 1 — Start and look around

**User action:** opens ReRoom and points the phone naturally around the hero object for 10–30 seconds.

**What the user sees:**

- live camera at 60 FPS;
- a small tracking/coverage indicator;
- concise coaching such as “show me a little more floor” or “move to the left side of the chair”;
- no point cloud or reconstruction covering the camera view.

**Expected behavior:** a floor becomes place-ready; the targeted object becomes tracked; “Replace ready” appears before “Remove ready” when necessary.

### Beat 2 — Target the object

**User action:** holds the center reticle on the chair or taps it.

**What the user sees:** a subtle focus indicator and “Understanding chair…” status.

**Expected timing:** tracked within roughly 0.8 seconds median; replace-ready within 2.0 seconds median and 3.5 seconds p95 after sufficient useful views.

### Beat 3 — Prove placement and local undo

**User says:** “Put that small side table there.”

**What the user sees:** a local ghost appears at the reticle immediately, the validated asset commits, and “Undo that” removes it without waiting for the network. This beat is intentionally brief.

### Beat 4 — Remove and restore, only when ready

**User says:** “Remove this chair.”

**Precondition:** the original real object displays “Remove ready.”

**What the user sees:** the chair disappears and ReRoom shows reconstructed floor/wall content. The user then says “Undo that,” and the original real chair returns immediately from the locally cached transaction state. If the reveal has not passed the quality gate, the app does not offer empty removal and this beat is omitted rather than faked.

### Beat 5 — Ask for the signature replacement

**User says:**

> “Replace this chair with something warmer and red, but keep the walkway clear.”

**What the user hears/sees:**

- ReRoom confirms the target;
- GPT-5.6 Sol evaluates matching catalog choices;
- if a candidate is too large, the UI may briefly show that it was rejected;
- a valid replacement appears as a preview and is committed.

**Expected timing:** simple spoken command to visible result ≤2.5 seconds p50 and ≤4.0 seconds p95.

### Beat 6 — Walk around

**User action:** walks a half-circle around the replacement.

**What the user sees:**

- replacement remains anchored;
- real room geometry occludes it where the retained-scene proxy is available;
- floor/wall reveal remains spatially stable;
- contact shadow and ambient tint help it belong in the scene.

### Beat 7 — Continue on the web

**User action:** opens the session link in the Next.js application.

**What the user sees:** recorded timeline, scene status, web twin/replay, object and transaction history, and typed/voice controls. This demonstrates that the session is a persistent spatial document rather than a one-off camera effect.

---

## 7. Modes

### 7.1 Mode A — Live AR

**Required client:** native iPhone app.  
**Required features:** capture, coaching, reticle/tap targeting, readiness chips, voice, place/replace/remove/undo, anchored walk-around, local committed-state persistence.

### 7.2 Mode B0 — Scan, process, and continue

**Required clients:** Next.js web application and backend services.  
**Inputs:** `.rrcap` or ordinary video.  
**Required features:** upload, processing status, deterministic replay, mesh/point twin, scene graph inspection, typed transaction path, catalog assets, and session persistence.

B0 is the fallback when live network, native compositing, or voice is unavailable. It is also the main development and regression environment.

### 7.3 Mode B1 — Photoreal twin

Optional after release readiness. B1 may create a polished splat scene for the web but must not delay or destabilize A or B0.

---

## 8. Functional requirements

### FR-1 — Session and consent

- User must explicitly grant camera/microphone access and consent to cloud upload.
- UI must display recording and network state.
- Every accepted frame must be recorded locally before or while it is uploaded.
- User can end and delete a session.

**Acceptance:** disconnecting the network does not lose the recorded scan.

### FR-2 — Warm-up and coaching

- App shows short, contextual coverage/tracking prompts.
- Prompts react to real tracking and target-view evidence.
- App never describes the warm-up as a completed full-room scan when it is not.

**Acceptance:** a new user can obtain a tracked target without team intervention in the staged room.

### FR-3 — Place

- User chooses a location by reticle or tap.
- A local ghost appears immediately on a floor plane.
- Server validates support, bounds, collision, orientation, and clearance.
- Final asset remains anchored during a half-circle walk.

**Acceptance:** one normalized USDZ asset is placed five consecutive times without drift or intersection that harms the demo.

### FR-4 — Replace

- User identifies the real target by voice + reticle or tap.
- GPT-5.6 Sol interprets style/category/color constraints and selects among valid catalog candidates.
- Deterministic validation rejects non-fitting candidates and reports minimum 2D floor gap; it does not claim full path planning unless a walkway corridor is explicitly defined.
- Replacement is previewed, committed as one transaction, and reversible.
- Replacement must meet the opaque asset-cover threshold or use a quality-approved reveal underlay; fragments of the real object may not remain visible around the replacement.

**Acceptance:** the hero sentence produces a validated replacement and visible agent rationale in four of five voice attempts, with typed fallback always available.

### FR-5 — Remove

- Remove is enabled only for objects in `remove_ready` state.
- ReRoom may draw multiple spatial reveal layers such as floor and wall.
- Reveal uses observed image evidence first and synthesized texture only for unresolved holes.
- The app must not display an incomplete removal as successful.

**Acceptance:** projected reveal coverage passes the technical gate and team visual review passes 4/5 during a half-circle walk.

### FR-6 — Undo / restore

- Undo restores the previous committed scene revision.
- It hides/shows reveal layers, real-object state, and virtual assets as needed.
- Active-session undo works without the network.

**Acceptance:** undo visibly restores the prior state within 250 ms once triggered locally.

### FR-7 — Targeting and readiness

- Voice + center reticle is the hero interaction.
- Tap-to-select is required as a reliability path.
- UI distinguishes `tracked`, `replace_ready`, and `remove_ready`; a readiness chip appears only after required assets/artifacts are downloaded, hash-verified, and activated on the phone.
- Ambiguous targets cause one concise clarification rather than an arbitrary choice.

### FR-8 — Voice and agent

- P0 uses push-to-talk.
- OpenAI credentials remain server-side; the phone receives a short-lived Realtime credential.
- Realtime uses one narrow, gateway-validated `submit_user_intent` function; it does not mutate scene state.
- Direct WebRTC is primary; a gateway-mediated push-to-talk Realtime WebSocket is the sanctioned audio fallback.
- GPT-5.6 Sol planning tools use strict schemas through the Responses API.
- GPT may choose and explain an edit but may not compute geometry or override validation.
- Typed commands use the same transaction service.

### FR-9 — Mode B0 web application

- Create/list sessions.
- Upload `.rrcap` and ordinary video.
- Display processing and failure status.
- Replay images, poses, events, and edits.
- Display a Three.js mesh/point twin.
- Use the same sparse high-resolution keyframes and canonical scene IDs as Mode A.
- Send typed commands through the same tools.
- Inspect scene/artifact revisions in debug mode.

### FR-10 — Resilience

- The live backend runs on a warm, session-sticky worker; cold queue-style serverless execution is not allowed for Mode A.
- Committed edit artifacts and inverse operations are cached locally for the active AR session.
- Network loss pauses new understanding but preserves the current edited view and local undo; the gateway reconciles the undo when connectivity returns.
- Tracking loss pauses new edits and coaches the user.
- Unrecoverable AR world reset preserves the recording and offers restart/B0.

---

## 9. UX requirements

### 9.1 Scan screen

- Full-screen camera.
- Center reticle.
- Push-to-talk control.
- Small tracking/network/recording indicators.
- One coaching message at a time.
- Capability chip near the selected object.
- No dense developer overlays in the recorded product take.

### 9.2 Preview and commit

- New asset appears first as a preview.
- User hears a short explanation only when useful.
- Commit state is visible and undo is always discoverable.
- Corrections from server validation animate smoothly.

### 9.3 Failure language

Use concrete language:

- “Show me a little more floor behind the chair.”
- “I can replace this now; removal needs another angle.”
- “Tracking paused—return to where you started.”
- “That chair is too wide; I found a smaller one that keeps 76 cm clear.”

Do not use generic “AI is thinking” language when a specific capability is missing.

---

## 10. Non-functional requirements

| Requirement | P0 target |
|---|---:|
| Camera/compositor | 60 FPS target; 45 FPS hard minimum |
| Local placement response | under one rendered frame |
| Accepted cloud frames | 6–12 per second |
| Queue behavior | no growing lag over 2 minutes |
| Target → replace-ready | ≤2.0 s p50; ≤3.5 s p95 |
| Warm-up → remove-ready | 10–30 s when supported |
| Voice command → visible result | ≤2.5 s p50; ≤4.0 s p95 |
| Placement validation excluding LLM | ≤300 ms |
| Commit activation after cache | ≤250 ms |
| Active session | stable for four minutes |
| Golden path | 5/5 consecutive |

Additional requirements:

- Metric world in metres, right-handed, +Y up.
- Live camera frames are uploaded once through a bounded gateway ingest path; stale frames are dropped rather than queued.
- Sparse high-resolution keyframes preserve exact frame IDs, poses, transformed intrinsics, and source metadata for reveal quality and B0/B1 continuity.
- Deterministic replay of the golden capture.
- Contract compatibility across Swift, TypeScript, and Python.
- All P0 catalog assets are available locally before the golden path begins.
- All scene mutations idempotent and revision-checked.
- No renderer-specific IDs in canonical state.
- Raw frames deleted by default within 24 hours after processing unless retained by the user.

---

## 11. Success metrics

### Product KPIs

- Golden-path success rate.
- First-attempt target resolution rate.
- Replace-ready and remove-ready latency.
- Spoken-command success rate.
- Walk-around anchoring quality.
- Empty-removal visual pass rate.
- User-visible frame rate and thermal stability.
- Percentage of sessions recoverable through B0.

### Build Week release criteria

Release candidate is accepted when:

1. the golden path passes five times consecutively on the physical iPhone and hero room;
2. replacement is Sol-mediated and deterministic fit validation is visible;
3. anchoring survives a half-circle walk;
4. undo works locally;
5. Mode B0 opens and replays the same session;
6. typed fallback is proven;
7. voice succeeds at least four of five attempts or is demoted according to the gate;
8. empty removal is included only if its quality gate passes;
9. all model/asset licenses and hashes are recorded;
10. primary and over-the-shoulder demo footage are captured before final submission day.

---

## 12. Risks in product language

The main risk is not raw model speed; it is visual credibility at the boundary between the real camera and the reconstructed background. ReRoom protects the demo by staging a simple target, separating replacement from removal readiness, using several background surfaces rather than one flat patch, and refusing empty removal when quality is insufficient. Native iOS scope is controlled through a half-day compositor gate and a guaranteed web/replay product. Voice, dense reconstruction, and photoreal polish each have explicit fallbacks and cannot invalidate the four core moments.

---

## 13. Privacy and trust

- Explicit consent before recording/upload.
- Visible recording/network status.
- Room-scoped, short-lived authentication.
- OpenAI standard API key never stored on the device.
- Raw frames deleted by default within 24 hours after processing unless the user chooses retention.
- No training reuse without separate consent.
- Consent distinguishes self-hosted room processing from OpenAI processing of microphone audio and selected object crops/structured scene facts; full raw room video is not sent to OpenAI.
- User can delete a session and its derived geometry/reveal artifacts.
- Product copy clearly distinguishes live output, recorded replay, and optional polished output.

---

## 14. Future work

After Build Week:

- Mode B1 photoreal splat twin.
- More general, non-planar background completion.
- Whole-room semantic discovery and multi-object redesign.
- Recoloring and material changes.
- Re-supporting real dependent objects after removal.
- Persistent AR relocalization between launches.
- Android native client using ARCore.
- visionOS/OpenXR client using the same FramePacket, scene graph, pointer-ray, and EditKit contracts.
- On-device depth/segmentation where thermal and model budgets permit.
- Retail catalog and purchase integration.

The glasses path changes the client inputs—head pose, stereo/depth, gaze and hand rays—but does not require a new backend architecture.

---

## 15. Changelog

### v1.0 — 13 July 2026

- Adopted native SwiftUI Mode A and separate Next.js web application.
- Made Mode B0 guaranteed and Mode B1 optional.
- Limited P0 to place, replace, remove, and undo.
- Made readiness capability-specific.
- Added tap as P0 reliability path.
- Made replacement the signature operation and empty removal quality-gated.
- Added persistent record-first capture and universal web replay.
- Added measured performance, privacy, and release criteria.
- Split Realtime intent capture from strict GPT-5.6 Sol planning and canonical transactions.
- Clarified the golden-path operation order and warm stateful deployment requirement.
- Added high-resolution keyframe continuity, strict replacement-cover behavior, local inverse operations, and an audio-transport fallback.
- Added client-acknowledged readiness, pre-cached hero assets, and an honest minimum-gap interpretation of walkway constraints.
- Clarified external-AI data boundaries and the four-operation recording sequence.

---

## 16. Authoritative references

- Technical plan: `ReRoom_Master_Technical_Plan_v3.2.md`
- OpenAI Build Week: `https://openai.com/build-week/`
- OpenAI GPT-5.6 Sol: `https://developers.openai.com/api/docs/models/gpt-5.6-sol`
- OpenAI GPT-Realtime-2.1: `https://developers.openai.com/api/docs/models/gpt-realtime-2.1`
- OpenAI Realtime WebRTC: `https://developers.openai.com/api/docs/guides/realtime-webrtc`
- Apple ARKit: `https://developer.apple.com/documentation/arkit/`
- Depth Anything 3: `https://github.com/ByteDance-Seed/Depth-Anything-3`
- LingBot-Map: `https://github.com/robbyant/lingbot-map`
- SAM 3: `https://github.com/facebookresearch/sam3`
