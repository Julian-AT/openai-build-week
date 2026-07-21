# Reframe submission status and cleanup plan

Updated 2026-07-21 for the submission handoff.

## Submission surface

The submitted browser experience is intentionally one thing: a fixed,
full-viewport Gaussian-splat room model.

- The model is deterministic and stored as source-owned splat data.
- Three.js renders 8,796 bounded Gaussian point sprites.
- The page has no visible marketing, capture, voice, replay, catalog, or debug
  interface.
- Rendering happens once at startup and after resize, not in a continuous loop.
- WebGL failure falls back to the room-colored CSS background.
- The scene is presentation-only. It is not canonical room state, a Mode B0
  replay, or a Mode B1 reconstruction.
- No generated model binary, capture, catalog asset, credential, database, or
  machine path is committed.

This narrow surface is honest and stable for the deadline. The broader Reframe
architecture remains in the repository as work to continue after submission.

## Honest implementation state

### Verified foundations

- Reframe naming, current CI targets, and the main package boundaries exist.
- The shared protocol has deterministic frame, capture, transaction, coordinate,
  and replacement-coverage tests.
- The catalog has one recorded live IKEA acquisition and prepared GLB, USDZ,
  collision, preview, OpenAI embedding, Qdrant, and GPT-5.6 placement proof.
- The gateway has durable SQLite session and transaction foundations with
  revision-neutral preview, CAS confirmation, and compensating restore tests.
- DA3 and official SAM 3.1 have separate recorded A100 smoke evidence.
- The iOS app has ARKit/RealityKit, placement, capture, gateway, cache, restore,
  and Realtime foundations.
- The fixed web splat model, web test suite, strict typecheck, and production
  build pass locally.

### Not complete and must not be claimed

- The current phone proof is placement, not real captured-object replacement.
- Live iPhone frames and target seeds are not one complete durable path into
  stateful SAM tracking and authoritative target state.
- Conservative multi-view volume, exact live replacement coverage, and
  capability activation are not proven end to end.
- Plane atlases, the real isolated LaMa checkpoint/service, reveal rendering,
  and honest empty removal are missing.
- Robust ARKit/depth alignment, Open3D TSDF, retained occluders, and dense
  artifact upgrades are missing.
- Signed short-lived GLB/USDZ delivery and complete artifact activation/reconnect
  are missing.
- Realtime code exists, but physical WebRTC, interruption, and the full agentic
  replacement scenario are not accepted.
- The full authorized IKEA frontier and production-scale Qdrant recovery are not
  complete.
- Physical FPS, thermal, drift, occlusion, reveal quality, offline, reconnect,
  and human visual gates remain open.

## Architecture conflicts to fix first

These are correctness issues, not optional cleanup.

1. Browser ordinary-video capture currently fabricates identity intrinsics and
   an identity ARKit world transform. Ordinary video must carry no invented
   ARKit facts and must route to the video mapping provider.
2. Typed turns currently accept client-supplied world positions for placement.
   The gateway must bind pointer, frame, scene revision, and spatial authority
   from durable server-side context.
3. Showcase asset configuration can bypass GPT-5.6 and catalog retrieval with a
   deterministic early return. Remove that path from product runtime and keep
   any future smoke operator isolated from user-facing routes.
4. SAM observations are not yet persisted into the authoritative replacement
   registry. Do not map an untrusted or transient model index directly to a
   public object identity.

## Cleanup plan

Complete these sections in order after the submission branch is safe.

### 1. Remove deadline-only behavior

- Delete every `showcase`, demo bypass, forced asset, synthetic room fact, and
  provider shortcut from production request paths.
- Keep smoke operations explicit, server-only, bounded, and incapable of
  mutating user sessions.
- Remove unused environment keys and tests that preserve deadline-only behavior.
- Verify that catalog or OpenAI unavailability returns a typed unavailable
  result rather than a fabricated placement.

### 2. Restore authority boundaries

- Make ordinary video omit ARKit pose/intrinsics and route it to LingBot-Map.
- Persist target seeds, pointer snapshots, planes, and accepted frames before
  they can influence a proposal.
- Resolve positions and targets only from authoritative stored context.
- Persist SAM track revisions and map them deterministically to stable object
  IDs before replacement becomes eligible.
- Preserve preview as revision-neutral and commit/restore as single CAS-backed
  transactions.

### 3. Consolidate documentation

- Keep one README in each application and package.
- Each README states purpose, owned authority, forbidden authority, local
  commands, runtime dependencies, and current limitations.
- Move still-valid verification facts into the owning README or a single
  package-local verification record.
- Delete stale status counts, overlapping handoff documents, duplicate plans,
  and claims that cannot be reproduced.
- Keep the Master Technical Prompt as the only product authority and the root
  implementation plan as the only ordered completion plan.

### 4. Clean repository state

- Inspect and remove ignored stale package caches, legacy contract directories,
  `.DS_Store` files, root virtual environments, test caches, and generated build
  output when they contain no unique work.
- Keep generated captures, model weights, IKEA binaries, Qdrant data, databases,
  and reports outside Git.
- Remove unused imports, routes, configuration keys, packages, symbols, and
  lockfile entries after the deadline-only code is gone.
- Run case-insensitive legacy-name search, secret scan, dependency/license
  review, and whitespace validation.
- Do not rewrite history, push, publish, or deploy during cleanup without direct
  authorization.

### 5. Normalize the development runtime

- Provide one documented operation for persistent stores, Qdrant, gateway, web,
  semantics, geometry, mapping, and reveal readiness.
- Make readiness distinguish process, storage, model hash, GPU, provider,
  Qdrant, catalog, and OpenAI capabilities.
- Remove machine-specific remote addresses and manual model setup from product
  configuration.
- Pin and record exact model source, checkpoint, license, byte length, and
  SHA-256 before a service can report ready.
- Keep queues bounded and cancellation/backpressure explicit.

### 6. Finish the real proof spine

1. Authenticated hash-verified delivery to Three.js and RealityKit.
2. Real iPhone frames and target seed into stateful SAM tracking.
3. Conservative multi-view volume, OBB, floor support, and independent
   capability readiness.
4. Eligible catalog retrieval and exact delivered-geometry replacement fit.
5. Preview, explicit confirmation, one CAS commit, offline render, and exact
   compensating restore.
6. Robust depth alignment, bounded TSDF, retained occlusion, plane atlases, and
   gated LaMa reveal.
7. Live Realtime speech through the one non-mutating ingress function and
   bounded GPT-5.6 proposal tools.
8. Real `.rfcap` upload/replay and ordinary-video processing in the web client.

## README standard

The package READMEs created for this handoff use this structure:

1. What the component is.
2. What it owns.
3. What it must never own.
4. How to run its smallest reliable checks.
5. Runtime/model dependencies and where data lives.
6. Known limitations stated without stale test counts or completion claims.

Future documentation should remain brief and update the owning README in the
same commit as a changed public boundary.

## Cleanup acceptance gate

Cleanup is complete only when:

- the browser root shows only the fixed Gaussian room model;
- no production route contains showcase/demo bypass behavior;
- ordinary video and typed pointers obey the authority rules above;
- every application and package has one accurate README;
- stale overlapping status documents and local residue are gone;
- all package format, lint, typecheck, tests, and builds pass;
- Swift package tests and the Reframe simulator build pass;
- secret scan and whitespace validation pass; and
- the final status distinguishes verified software from external, GPU,
  physical-device, and human visual gates.
