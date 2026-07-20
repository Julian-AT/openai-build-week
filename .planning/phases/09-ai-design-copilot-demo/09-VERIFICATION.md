---
phase: 09-ai-design-copilot-demo
verified: 2026-07-20T00:32:01Z
status: human_needed
score: 5/5 automated plan truths verified
behavior_unverified: 0
overrides_applied: 0
gaps: []
deferred:
  - truth: "Live GPT-5.6 Sol typed and one-frame vision quality"
    addressed_in: "24-hour live provider rehearsal"
    evidence: "No provider credentials were available or used; no live request is claimed."
  - truth: "Realtime five-turn quality and signed-device microphone behavior"
    addressed_in: "Phase 09 fixed five-turn manual rubric"
    evidence: "Credential/parser/queue/transcript behavior is automated; provider audio quality remains PENDING."
  - truth: "Physical consent, camera orientation, design usefulness, latency/cost, and public demo readiness"
    addressed_in: "Signed-device and human demo campaign"
    evidence: "Simulator and local mocks cannot establish these observations."
human_verification:
  - test: "Send one fixed typed prompt through a live configured gateway."
    expected: "A strict known-catalog CON-006 result appears, exact context matches, and Apply creates preview only."
    why_human: "Provider access and live model behavior were not available during automated verification."
  - test: "Consent to one current frame and send the fixed vision prompt on the base iPhone."
    expected: "Exactly one bounded JPEG is sent after explicit consent; the response cannot auto-confirm or commit."
    why_human: "Physical camera orientation, consent comprehension, and provider vision quality require real evidence."
  - test: "Run the five fixed Realtime utterances and the prompt-injection image case."
    expected: "At least 4/5 exact outcomes; every unsafe or ambiguous case rejects or clarifies; typed fallback remains complete."
    why_human: "Microphone/provider transcription quality and design judgment cannot be simulated into acceptance."
---

# Phase 09: AI Design Copilot Demo Verification Report

**Phase Goal:** Make deep model work visible in the native hero journey while keeping every spatial, revision, persistence, confirmation, commit, reconciliation, and restore decision deterministic.
**Status:** `human_needed`

## Verdict

The automated implementation slice is achieved. CON-006, the direct Responses
gateway, bounded Realtime bootstrap, strict native decoder/context rebind,
Keychain/consent boundary, visible copilot UI, local catalog, and deterministic
preview-only handoff are substantive and locally tested. Removing the gateway,
model, or network leaves the typed/tap product path intact.

This is not a live-provider, signed-device, design-quality, latency, formal
security-gate, or P0 verdict. Those observations remain pending, so the phase
cannot receive a canonical `passed` status.

## Observable Truths

| # | Truth | Status | Evidence |
|---:|---|---|---|
| 1 | Sol can return only a closed known-catalog semantic proposal and cannot emit target, transform, authority, confirmation, commit, restore execution, or URL fields. | VERIFIED locally | 34 gateway tests, strict Structured Output schema, duplicate-safe parser, ten immutable vectors, and 3 Python parity tests. |
| 2 | Realtime is optional, fixed to a 600-second credential, has no tools or response-generation authority, and only completed bounded transcript text reaches Sol. | VERIFIED locally | Gateway credential tests plus native expiry/parser/queue/cancellation/transcript tests. |
| 3 | Native rejects stale/unknown/unsafe CON-006, rebinds exact current context, maps vision to frozen CON-005 typed provenance, and creates only a revision-neutral preview. | VERIFIED locally | Clean-source 47-test `RoomEditModelTests` run plus 172 Swift contract/core tests. |
| 4 | Typed/tap operation remains complete with AI/network disabled. | VERIFIED locally | Existing reducer/authority/model regression suites remain green; AI integration calls the same preview boundary. |
| 5 | Standard credentials and room media stay out of source/logs; an image is encoded only after per-send consent. | VERIFIED locally | Gateway logging/auth/body tests, Keychain boundary tests, one-frame consent tests, release-surface scan, and tracked-source inspection. |
| 6 | Live model/voice quality, physical consent/camera/microphone behavior, and design usefulness are acceptable. | PENDING HUMAN/LIVE | No live credentials, physical run, or human evaluation was used. |

## Automated Evidence

| Surface | Result |
|---|---|
| Gateway tests | 34/34 pass |
| Gateway typecheck/build | pass |
| Gateway production audit | 0 vulnerabilities |
| CON-006 Python parity | 3/3 pass |
| Native frozen-candidate full suite | 129/129 pass at `476d88f25d0455aea7394ffa72c3188cdb6113ca`: 119 unit/integration plus 10 UI, serial iPhone 17 / iOS 26.4 simulator |
| Native builds | Debug and Release simulator builds pass; signed arm64 base-iPhone build passes, but no install/launch or physical observation is claimed |
| Full Swift package | 172/172 pass |
| Web tests/typecheck/build/audit | 10/10 pass on Next.js 16.2.10; production build and zero-vulnerability audit pass; frozen-candidate local Chromium render, slider, Previous/Next traversal, and empty console/page-error checks pass |
| CON-004/schema/catalog/provenance | 3/3 schema-valid; 36 native/web files reproducible; digest chain pass |
| Live Sol/vision/Realtime call | not run; credentials absent |

## Authority Boundary

The model may propose only `place`, `replace`, `remove`, `restore`, an
allowlisted asset, typed semantic constraints, a concise explanation, or a
clarification. Deterministic native code binds target/session/branch/revision/
world context, validates spatial readiness, owns the revision-neutral preview,
requires separate confirmation, performs CAS/persistence, and constructs any
restore compensation. There is no model tool or alternate mutation path.

## Required Human Verification

Run the exact Phase 09 validation rubric on the candidate revision. If Sol
misses its 45-minute timebox, demo the immutable CON-006 vectors and local
catalog. If Realtime misses 4/5 or any unsafe case, disable voice and use typed
input. Neither fallback changes deterministic P0 behavior.

---
_Verified: 2026-07-20 (automated/local boundary only)_
