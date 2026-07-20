# ADR-011: Agent Intent and Deterministic System Boundary

Status: Accepted  
Date: 2026-07-14

## Context

Typed/tap semantic proposals are part of the deterministic P0 path. Voice and GPT may make the product more legible and design-aware without becoming authorities for geometry, scene state, credentials, or mutations. The current Realtime model supports function calling but not Structured Outputs.

## Project constraints

- Standard API credentials remain server-side.
- Typed/tap proposal ingress for all four operations must pass without a model or network; voice is nonblocking stretch work.
- Untrusted utterances, labels, asset metadata, and external content cannot redefine tool authority.

## Alternatives considered

1. Let Realtime invoke mutating scene tools directly.
2. Send audio through a permanent gateway WebSocket only.
3. Direct client WebRTC with an ephemeral credential, one narrow intent function, strict server planning, and deterministic validation/commit.

## Decision

Adopt alternative 3 for optional voice. The P0 typed/tap path first enters a schema-validated, nonmutating `submit_user_intent` boundary and completes all four operations with no model call. If enabled, Realtime may call only that same function. The gateway attaches the captured pointer/scene context, deduplicates, and may invoke GPT-5.6 Sol through the Responses API with strict tool schemas. GPT interprets semantic/design constraints and selects candidates; deterministic application code owns target resolution, transforms, support, collision, clearance, readiness, revisions, preview, commit, and restore. Tool outputs and asset IDs are allowlisted; model-produced URLs or transforms are never trusted.

## Evidence

- Realtime WebRTC ephemeral credentials: https://developers.openai.com/api/docs/guides/realtime-webrtc
- GPT-Realtime-2.1 supports function calling but not Structured Outputs: https://developers.openai.com/api/docs/models/gpt-realtime-2.1
- GPT-5.6 Sol supports function calling and Structured Outputs: https://developers.openai.com/api/docs/models/gpt-5.6-sol

## Consequences

- Conversational behavior is optional; candidate selection always has a deterministic curated/typed route.
- Typed and voice paths share identical downstream behavior.
- Prompt/tool-injection tests are required.

## 2026-07-19 native hackathon transport amendment

The optional native push-to-talk demo may connect to Realtime over WebSocket using only a gateway-minted ephemeral client secret. OpenAI documents that browser WebSocket can use an ephemeral token but recommends WebRTC for browser/mobile robustness. This amendment therefore does not replace WebRTC as the production-preferred client path: it authorizes only a bounded hackathon implementation with 24 kHz mono PCM, a 64-chunk oldest-preserving buffer that fails the attempt on overflow, an explicit `input_audio_buffer.commit` turn boundary, completed-transcript-only intake, and fail-closed cancellation. It does not issue `response.create` because Sol/CON-006 performs the separate semantic proposal step. The standard API key remains gateway-only.

For Phase 09, this amendment narrows the earlier optional function design:
Realtime exposes no function, and Sol uses strict Structured Outputs followed by
independent gateway/native validation rather than a callable model tool.

The transcript is not a tool execution or canonical proposal. It is sent through the same GPT-5.6 Sol strict CON-006 route, then rebound and revalidated against current native context before it may create a revision-neutral preview. No voice result confirms or commits. Failure immediately returns to the complete typed/tap path and leaves P0 unchanged.

Evidence: https://developers.openai.com/api/docs/guides/realtime-websocket and https://developers.openai.com/api/reference/resources/realtime/subresources/client_secrets/methods/create .

## Risks

- Ephemeral-token or Realtime availability may fail.
- Transcript and proposal bytes may be malformed, stale, duplicated, or adversarial.

## Fallback

Use typed/tap intent through the same local schema and deterministic validation boundary; a gateway is optional for replication, B0, and voice, not required for the Mode A typed path. Reject invalid/stale requests; ask one concise clarification when semantic ambiguity remains. Never bypass deterministic validation.

## Benchmark and kill gate

All unmeasured thresholds, fixture sizes, deadlines, and timeboxes in this gate are `TARGET`, not measured results.

`GATE-010`: first require typed/tap completion of every golden edit and 100% rejection of malformed/adversarial typed intent fixtures. The optional voice variant then uses five fixed hero utterances; at least four must produce the correct nonmutating proposal and every malformed/adversarial case must be rejected or clarified. Timebox: one voice slice after typed transactions pass. Voice failure selects typed demo control, ends voice work, and does not fail P0; typed/injection failure blocks commits.

## Requirements and contracts affected

`FR-AGENT-001`, `STR-VOICE-001`, `FR-REPLACE-001`, `SEC-AGENT-001`, `SEC-CREDENTIAL-001`, CON-005, and CON-006.

## Supersession

Supersedes any archived implication that an audio model or GPT owns canonical state. No canonical ADR is superseded.
