# Reframe implementation status

Updated 2026-07-21 after the current verification run.

## Verified in this checkout

- Repository identity and CI paths use Reframe naming; case-insensitive source
  search finds no legacy ReRoom product references.
- Durable room capture/session state, authenticated frame and artifact intake,
  event journaling, scene previews, compare-and-swap confirmation, idempotency,
  restore, and restart recovery are covered by API tests.
- Catalog validation, resumable acquisition, normalization contracts, prepared
  assets, eligibility, retrieval, cache synchronization, delivery verification,
  and the pinned downloader importer are covered by catalog tests.
- OpenAI tool schemas are strict, mutation-free, bounded, and traced only with
  redacted lifecycle facts. Exact model capability probing degrades when a
  required model is absent.
- SAM target prompts, identity-bound mask encoding, provider readiness, and
  conservative CPU geometry readiness are implemented with failure-path tests.
- iOS room credential validation, typed gateway transport, local edit controls,
  Swift package tests, and the Reframe simulator target build successfully.
- The web replay route validates ordered room events and can load a verified GLB
  into a Three.js scene twin.

## Open acceptance gates

- The configured Runpod image cannot currently satisfy the official SAM 3.1
  runtime requirement (its driver/Torch CUDA stack is older), and no server-side
  Hugging Face checkpoint credential is available in that runtime. SAM therefore
  reports unavailable instead of silently substituting a model.
- No live IKEA smoke run, normalized asset delivery, OpenAI embedding, Qdrant
  point, or signed GLB/USDZ delivery was performed in this checkout. Those
  require external service credentials, persistent volumes, and a permitted
  source run.
- The physical iPhone path, ARKit capture transport, RealityKit visual load,
  WebRTC Realtime session, 60 Hz/thermal measurements, and human visual review
  remain unverified.
- DA3 CUDA execution, TSDF reconstruction, plane atlases, and the gated LaMa
  reveal/removal path remain provider/runtime work; conservative geometry stays
  the safe degraded capability.
- Live agent-turn wiring still requires an explicitly configured catalog/Qdrant
  runtime and authoritative room context. Missing configuration returns a
  bounded unavailable response; it cannot create synthetic scene state.

## Highest-value follow-up work

1. Prepare a CUDA-compatible SAM 3.1 worker image, verify the checkpoint hash,
   and run one real target-track acceptance.
2. Run the authorized IKEA smoke profile through the persistent catalog,
   processor, OpenAI embedding, Qdrant, and delivery volumes.
3. Connect the live agent service to that room-scoped catalog and persist a
   placement preview as a durable, revision-neutral transaction resource.
4. Exercise the physical iPhone, WebRTC, offline cache/restore, and web replay
   acceptance matrix, then record redacted timing and visual results.

No credentials, model weights, captures, catalog binaries, Qdrant data, or
machine-specific paths are stored in Git.
