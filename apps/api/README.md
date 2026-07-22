# Reframe gateway

[Back to Reframe](../../README.md)

The Bun and Hono gateway is Reframe's trusted service boundary and sole
scene-revision authority.

## Responsibilities

- Authenticate room-scoped requests and persist capture sessions.
- Ingest frames, events, and artifacts through bounded typed endpoints.
- Prepare previews, confirm compare-and-swap transactions, and restore edits.
- Coordinate vision, catalog, asset delivery, and bounded agent turns.
- Exchange scoped WebRTC offers without exposing the OpenAI key to clients.

Clients and models never choose authoritative transforms, revisions, commits,
or restore behavior.

## HTTP surface

The service groups routes under sessions, inference, edit transactions, agent
turns, Realtime calls, and verified USDZ delivery. `GET /health` reports the
gateway and configured dependency readiness.

## Run

From the repository root:

```sh
bun run --cwd apps/api dev
bun run --cwd apps/api test
bun run --cwd apps/api typecheck
bun run --cwd apps/api build
```

To start the gateway with Qdrant in Docker:

```sh
bun run --cwd apps/api dev:local
```

## Configuration

Use `.env.example` as the configuration reference. The local Docker
profile requires gateway and room-signing secrets, a Qdrant API key, and an
absolute data directory outside the repository. OpenAI and vision settings are
required only for those capabilities. Never expose server credentials to web
or native clients.
