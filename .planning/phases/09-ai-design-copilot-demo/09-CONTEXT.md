---
phase: 09-ai-design-copilot-demo
status: implementation-authorized
created: 2026-07-19
source: direct-human-sprint-instruction
---

# Phase 09 Context — AI Design Copilot Demo

## Outcome

Make the model work visible in the native hero journey without giving a model,
gateway, network, or web client any spatial or mutation authority. A user can
type a design request, optionally consent to one current frame, or use bounded
push-to-talk. GPT-5.6 Sol may return one closed semantic proposal; native code
must validate it against the exact current context and create only the existing
revision-neutral preview. Confirmation and commit remain separate explicit
native actions.

## Locked decisions

- Use the direct OpenAI Responses API through the exact official JavaScript
  SDK in the local Node gateway. Do not add an agent framework for one linear,
  schema-constrained model call.
- Use `gpt-5.6-sol` for typed/vision proposal normalization with strict
  Structured Outputs, `store: false`, a server-owned three-item catalog, and
  at most one explicitly consented JPEG.
- Use `gpt-realtime-2.1` only as optional push-to-talk transcription ingress
  through a 600-second server-minted ephemeral credential. The transcript is
  sent to Sol through the same CON-006 proposal path. Typed/tap remains the
  complete fallback.
- CON-006 is a new, closed, nonmutating sideband contract. Frozen CON-005 is
  unchanged; `vision` maps to CON-005 `typed` plus model provenance.
- Model output may contain only operation, allowlisted asset ID, typed design
  constraints, explanation, or clarification. It may never contain target,
  transform, branch/session/world authority, confirmation, idempotency,
  revision, artifact activation, commit, restore execution, or URLs.
- Native code rejects stale context, unknown assets, unsafe copy, unknown
  fields, noncanonical constraints, and invalid provenance before preview.
- Store the gateway bearer token in iPhone Keychain. Never place the standard
  OpenAI API key in the app, repository, logs, capture, or browser bundle.
- Permit cleartext gateway credentials only to loopback, `.local`, RFC1918,
  link-local, or unique-local roots; public gateways require HTTPS.
- The live render loop never waits for AI. Frame encoding and network work
  begin only after the user taps Ask; one-frame consent is consumed per send.

## Evidence boundary

Automated contract, gateway, native, and simulator evidence may establish
shape, fail-closed behavior, revision neutrality, and buildability. It does not
establish live provider quality, physical-device camera/microphone behavior,
design quality, latency, or a public demo. Those claims remain `PENDING` until
their real evidence is recorded.

## Kill rules

- If live Sol setup cannot be made reliable quickly, demo the deterministic
  typed path and the checked-in CON-006 vectors; do not weaken validation.
- If Realtime fails, remove voice from the rehearsed path; do not change P0.
- If one-frame consent, context binding, or explicit confirmation is unclear in
  the UI, do not send imagery or present the model path as ready.
- No new orchestration, vector database, hosted tracing, or cloud state enters
  the 24-hour slice.
