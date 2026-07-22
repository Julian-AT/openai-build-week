# Reframe

> A live spatial design system for understanding and reshaping real rooms.

![OpenAI Build Week](https://img.shields.io/badge/OpenAI-Build_Week-000000?style=flat-square&logo=openai&logoColor=white)
![iOS 18+](https://img.shields.io/badge/iOS-18%2B-111111?style=flat-square&logo=apple&logoColor=white)
[![MIT License](https://img.shields.io/badge/license-MIT-d7ff64?style=flat-square)](LICENSE)

![Apartment captured as a spatial point cloud in Reframe](assets/readme/reframe-room-point-cloud.png)

Reframe turns a live room capture into reversible spatial edits. The native
iPhone experience combines ARKit tracking, spatial understanding, prepared 3D
assets, and an OpenAI design assistant without giving cloud services control of
the render loop or canonical scene state.

Instead of treating AR as a model viewer, Reframe understands what already
occupies the room, finds an asset that physically fits, and previews the change
against the live camera. The four operations are **place**, **replace**,
**remove**, and **restore**.

## How it works

```mermaid
flowchart LR
    CAPTURE[Capture<br/>ARKit poses + room frames] --> UNDERSTAND[Understand<br/>tracking + geometry]
    UNDERSTAND --> RETRIEVE[Retrieve<br/>eligible 3D assets]
    RETRIEVE --> PROPOSE[Propose<br/>voice + bounded AI tools]
    PROPOSE --> PREVIEW[Preview<br/>local RealityKit render]
    PREVIEW -->|user confirms| COMMIT[Commit<br/>revisioned transaction]
    COMMIT --> PREVIEW
```

The iPhone owns the camera, tracking, and 60 Hz render loop. The gateway owns
room identity, revisions, transactions, and confirmation. Vision, catalog, and
OpenAI integrations sit behind typed boundaries; the web app consumes the same
room and transaction contracts. Models can understand, retrieve, clarify, and
propose, but only deterministic code can commit a scene change.

## Workspace

| Area | Responsibility |
| --- | --- |
| [iOS](apps/ios/README.md) | Native capture, interaction, and AR rendering |
| [API](apps/api/README.md) | Trusted gateway, sessions, transactions, and service coordination |
| [Vision](apps/vision/README.md) | Private segmentation, depth, geometry, and reveal inference |
| [Web](apps/web/README.md) | Room model, capture handoff, and replay experience |
| [Agent](packages/agent/README.md) | Bounded Responses and Realtime adapters |
| [Catalog](packages/catalog/README.md) | Acquisition, preparation, retrieval, and delivery of 3D assets |
| [Protocol](packages/protocol/README.md) | Canonical schemas, coordinates, and transaction behavior |

## Quickstart

The standalone web room viewer is the fastest way to explore the project. It
requires [Bun 1.3.11](https://bun.sh/) and no service credentials.

```sh
bun install --frozen-lockfile
bun run --cwd apps/web dev
```

Open [localhost:3000](http://localhost:3000) and switch between the source point
cloud and reconstructed 3D model. Full-stack setup is documented by the owning
application or package.

Run the repository checks with:

```sh
bun run check
bun run test:swift
```

## Stack

| Layer | Technology |
| --- | --- |
| Native | Swift 6.1, SwiftUI, ARKit, RealityKit |
| Web | Next.js 16, React 19, Three.js |
| Gateway | Bun, TypeScript, Hono, SQLite |
| Vision | Python 3.12, FastAPI, provider-isolated GPU models |
| AI | OpenAI Responses API and Realtime API |
| Assets | GLB, USDZ, Qdrant semantic retrieval |

## Design principles

- The live renderer never waits for the network or an inference worker.
- ARKit remains the pose authority for healthy native sessions.
- AI tools are bounded, typed, and unable to commit canonical state.
- Prepared assets are activated only after dimensions, provenance, and hashes verify.
- Committed edits remain available locally when cloud services disconnect.

## License

Reframe is available under the [MIT License](LICENSE). Built for OpenAI Build
Week 2026.
