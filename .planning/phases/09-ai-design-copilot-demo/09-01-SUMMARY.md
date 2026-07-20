---
phase: 09-ai-design-copilot-demo
plan: "01"
subsystem: ai-design-copilot
tags: [openai, responses, realtime, structured-outputs, swiftui, con-006]

requires:
  - phase: 03-typed-place-commit-and-offline-restore
    provides: Frozen CON-005 intent boundary, deterministic reducers, revision-neutral preview, and explicit confirmation
  - phase: 04-target-grounding-and-compositor-gate
    provides: Trusted native target/world context and renderer-independent readiness
  - phase: 05-curated-replacement-vertical
    provides: Stable local asset identities and deterministic preview/commit path
provides:
  - Closed CON-006 semantic proposal contract with ten immutable accept/reject vectors
  - Credential-isolating local gateway for strict Sol proposals and bounded Realtime client secrets
  - Visible native typed, one-frame-consent, and optional push-to-talk copilot that can create only a deterministic preview
  - Three-entry digest-bound repository-owned demo catalog with deterministic CON-004 USDZ/GLB/collision delivery and explicit GATE-011 qualification pending
affects: [demo, FR-AGENT-001, SEC-AGENT-001, SEC-CREDENTIAL-001, STR-VOICE-001]

tech-stack:
  added: [openai@6.39.0, node@22.22.3, typescript@6.0.2]
  patterns:
    - Model output is untrusted structured data and is independently validated at gateway and native boundaries
    - Trusted context is bound after model inference and rechecked before a revision-neutral preview
    - Realtime yields only a bounded transcript that re-enters the same Sol/CON-006 path

key-files:
  created:
    - docs/contracts/semantic-proposal.schema.json
    - fixtures/semantic-proposals/1.0.0/rev-001/cases.json
    - gateway/src/proposal-service.ts
    - gateway/src/realtime-client-secret.ts
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/DesignCopilot.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/DesignCopilotView.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/Resources/Phase3Proxy/asset-catalog.json
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/Resources/Phase3Proxy/CON004-PROVENANCE.md
    - tools/assets/generate_hackathon_assets.mjs
    - web/test/asset-delivery.test.mjs
  modified:
    - ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore/IntentBoundary.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/RoomEditModel.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProof/RoomEditView.swift
    - ios/ReRoomDeviceProof/ReRoomDeviceProofTests/RoomEditModelTests.swift

key-decisions:
  - "Use direct Responses and Realtime APIs, not an agent framework, because the model performs one closed semantic extraction and owns no tool or mutation loop."
  - "Keep CON-006 as a nonmutating sideband; vision maps to frozen CON-005 typed ingress plus explicit model provenance."
  - "Allow exactly one visible preview owner; an AI proposal rejects while a manual preview exists, and Cancel always targets the visible preview."
  - "Generate repository-owned native/web/collision derivatives deterministically and bind each delivery through a canonical degraded CON-004 record without promoting GATE-011."
  - "Use balanced GSD routing plus explicit Sol debugger/security overrides because GSD 1.7's health validator rejects the catalog-supported adaptive profile."

patterns-established:
  - "AI removal test: disabling gateway, model, and network leaves typed/tap place, replace, remove, restore, preview, confirmation, commit, and restore intact."
  - "Consent is per send: no camera frame is encoded or transmitted until the user explicitly asks with one-frame vision enabled."
  - "No authority echo: session, branch, revision, world epoch, and selection are trusted request context, never model-selected state."

requirements-completed: []
trace-requirements: [FR-AGENT-001, SEC-AGENT-001, SEC-CREDENTIAL-001, STR-VOICE-001]
formal-acceptance: human_needed
coverage:
  - id: D1
    description: "Sol output is constrained by a strict server-owned schema, independently parsed, bound to trusted current context, and limited to the three-entry catalog."
    requirement: SEC-AGENT-001
    verification:
      - kind: integration
        ref: "gateway npm test (34/34), typecheck, and production build"
        status: pass
      - kind: unit
        ref: "python3 -m unittest tools.python.tests.test_semantic_proposal (3/3)"
        status: pass
    human_judgment: false
  - id: D2
    description: "The native copilot strictly decodes and rebinds CON-006, stores only the gateway bearer in Keychain, and creates at most the existing revision-neutral preview before separate confirmation."
    requirement: FR-AGENT-001
    verification:
      - kind: integration
        ref: "clean-source serial Xcode suite (129/129 total; 119 unit/integration plus 10 UI)"
        status: pass
      - kind: unit
        ref: "full ReRoomContracts Swift package suite"
        status: pass
    human_judgment: false
  - id: D3
    description: "Realtime credentials are fixed-model and short-lived; bounded push-to-talk yields only a completed transcript that returns through Sol/CON-006."
    requirement: STR-VOICE-001
    verification:
      - kind: unit
        ref: "gateway and RoomEditModelTests credential, duplicate/UTF-8/size parsing, send/receive deadlines, queue, audio rollback, cancellation, and transcript cases"
        status: pass
    human_judgment: false
  - id: D4
    description: "All three catalog assets have deterministic digest-bound USDZ, GLB, and collision delivery with strict native and web verification."
    requirement: FR-REPLACE-001
    verification:
      - kind: integration
        ref: "129/129 clean native tests plus 10/10 web tests and 3/3 CON-004 schema validation"
        status: pass
      - kind: reproducibility
        ref: "two fresh generator runs preserve all 36 native/web source and delivered-file hashes"
        status: pass
    human_judgment: false
  - id: D5
    description: "Live Sol/vision usefulness, five-turn Realtime quality, signed-device camera/microphone behavior, latency, and public-demo readiness."
    verification: []
    human_judgment: true
    rationale: "No provider credentials, physical device, human design review, or public demo evidence was used during automated implementation."

duration: not-recorded
completed: 2026-07-19
status: complete
---

# Phase 09 Plan 01: AI Design Copilot Demo Summary

**A visible Sol/Realtime design copilot now produces only strict, context-bound semantic proposals over a local catalog and can never bypass the deterministic preview/confirmation path.**

## Accomplishments

- Added closed CON-006 plus ten immutable vectors, strict duplicate-safe parsing, and independent JavaScript/Python contract checks.
- Added a stateless authenticated gateway using `gpt-5.6-sol`, strict Structured Outputs, `store: false`, no tools, no CORS, bounded bodies/deadlines, sanitized logs, and an optional 600-second `gpt-realtime-2.1` credential.
- Added the native AI panel, Keychain bearer boundary, one-frame consent, strict context rebind, bounded audio/transcript path with deadlines and rollback, single-preview arbitration, three local catalog assets, and preview-only proposal application.
- Added deterministic USDA → USDZ/GLB/collision generation, canonical degraded CON-004 manifests, native RealityKit loading checks, and independent web delivery verification while keeping `GATE-011` pending.
- Preserved the complete offline deterministic path. A model proposes semantic/design intent only; native code still owns target authorization, geometry, revision, persistence, confirmation, commit, reconciliation, and restore.

## Verification

- Gateway: **34/34 tests passed**; TypeScript typecheck/build passed; production dependency audit reported **0 vulnerabilities**.
- CON-006 Python parity: **3/3 tests passed**; schema, fixtures, plist, project file, catalog, and asset SHA-256 values parse/match.
- Native: a clean temporary Git snapshot passed the complete serial Xcode suite, **129/129 tests** total (**119 unit/integration plus 10 UI**), including production Ask → Apply → native preview, delayed voice cancellation, transition-race coverage, all three RealityKit USDZ loads, relaunch durability, the four-operation inventory, and deterministic replace/retry/restore journeys.
- Web/assets: exact Next.js `16.2.10` with a tested PostCSS `8.5.20` override passed **10/10 web tests**, typecheck, production build, and a zero-vulnerability production audit; all three CON-004 records validate, the web bundle closes the license/evidence/provenance chain byte-for-byte with native, and two fresh generator runs preserved all 36 native/web source and delivered-file hashes.
- Full deterministic core: **172/172 Swift package tests** passed. A local Chromium smoke rendered and traversed the accepted seven-event B0 replay; formal browser/device/human gates remain pending.
- No `OPENAI_API_KEY` or `REROOM_GATEWAY_TOKEN` was present, and no live provider request was made.

## Deviations from Plan

The intended GSD profile was `adaptive`. GSD Core 1.7 resolves that catalog value but its health validator emits `W004`; the checked-in health-clean equivalent is `balanced` with explicit Sol overrides for debugging and security. Model role depth is preserved and the discrepancy is recorded in the GSD configuration rationale. Independent deep review also expanded the original implementation with duplicate-safe bounded Realtime ingress, explicit send/receive deadlines, independent audio rollback, preview ownership, attempt-race control, canonical asset integrity, and a production boundary integration test.

## Human / Live Work Still Required

- Run one live typed Sol request and one explicitly consented frame without retaining prompt/image/secret data.
- Run the fixed five-turn Realtime rubric on a signed device and keep voice only at 4/5 or better with every unsafe case rejected or clarified.
- Review design usefulness, camera/microphone consent, latency/cost, accessibility, and the public demo on the actual device.
- Keep `FR-AGENT-001`, `SEC-AGENT-001`, `SEC-CREDENTIAL-001`, `STR-VOICE-001`, every formal gate, and milestone v1.0 open until their canonical evidence exists.

---
*Phase: 09-ai-design-copilot-demo*
*Completed: 2026-07-19 (automated implementation only)*
