# Reframe

Reframe is a spatial room editor for iPhone and the web. It combines native
ARKit tracking, deterministic scene transactions, GPU-assisted geometry, a
searchable furniture catalog, and a conversational OpenAI design agent.

The camera feed stays real. Reframe renders only replacement assets, reveal
surfaces, occlusion, shadows, and interface elements. AI can understand and
propose an edit; only deterministic code and explicit user confirmation can
change the scene.

## Applications

- `apps/ios` — native SwiftUI, ARKit, and RealityKit editor.
- `apps/api` — trusted session, scene, transaction, catalog, and agent gateway.
- `apps/vision` — SAM, metric depth, reconstruction, and reveal workers.
- `apps/web` — capture upload, replay, scene inspection, and typed editing.

Shared behavior lives in `packages/protocol`, `packages/catalog`, and
`packages/agent`. The complete architecture is defined in
[`MASTER_TECHNICAL_PROMPT.md`](MASTER_TECHNICAL_PROMPT.md).

## Requirements

- Bun 1.3.11
- Xcode 26 and an iOS 26 simulator or device
- Python 3.12 and uv
- Docker with Compose
- An OpenAI API key
- A CUDA 12.8 host for real vision models; macOS supports application and
  contract development without loading those models

## Setup

```sh
bun install --frozen-lockfile
cp .env.example .env
bun run catalog:up
bun run catalog:sync -- --profile hero
```

Model and catalog downloads are explicit preparation operations. Starting an
application never downloads model weights or furniture assets.

## Development

```sh
bun run dev
bun run check:quick
bun run test
```

Open the native project at `apps/ios/Reframe/Reframe.xcodeproj`. Run the real
vision profiles from `apps/vision` on a CUDA Docker host or the configured warm
RunPod deployment.

## Repository policy

Downloaded assets, captures, model weights, Qdrant data, and generated reports
are local data and are not committed. Read `AGENTS.md` before changing product
contracts or architecture.
