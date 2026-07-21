# Replacement status

## Verified

- Target resolution is room-scoped and deterministic. Ambiguous, unknown, hidden,
  stale, or low-confidence target identities fail closed.
- Replacement candidates come only from the same bounded catalog search and are
  rejected when their validated dimensions exceed the trusted target envelope.
- A replacement preview is revision-neutral. The room service stages its target,
  reveal bundle, replacement instance, and transform through the durable edit
  authority before confirmation.
- Confirmation and restore continue to use the existing CAS, idempotency, and
  compensating-transaction journal.
- Native iOS Realtime voice uses the pinned WebRTC package and forwards only the
  non-mutating `submit_user_turn` function to the deterministic gateway path.

## Remaining gates

- A capture/SAM pipeline must publish trusted target records through the server-only
  `REFRAME_KNOWN_TARGETS_JSON` configuration (or a durable target store). Without
  records, replacement is intentionally unavailable rather than guessing an ID.
- SAM track observations are validated in `SceneObjectRegistry`, but persistence
  from live inference into the replacement registry is still required.
- Real multi-view replacement coverage, plane atlases, and the isolated LaMa
  reveal worker are not yet connected to the preview path. The current path must
  therefore not be presented as arbitrary real-object removal.
- Physical iPhone microphone, WebRTC negotiation, live target tracking, and human
  visual placement/replacement acceptance remain pending device checks.

## Follow-up upgrades

1. Persist target records and SAM track revisions in the room database, including
   mask provenance and capability transitions.
2. Add a deterministic coverage service that selects asset-only replacement or a
   validated reveal bundle before staging any replacement.
3. Hydrate the native scene replica from committed deltas so the captured object
   visibility and replacement/reveal state remain correct after reconnect.
4. Add a physical-device acceptance capture covering voice, typed fallback,
   replacement preview, CAS confirmation, offline render, and restore.

Verification at the latest implementation checkpoint: API tests 79/79, shared
protocol/agent/catalog tests 90/90, API typecheck/build, Biome lint, gitleaks,
and the unsigned iOS simulator build all pass.
