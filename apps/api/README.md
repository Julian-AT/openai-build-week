# Reframe gateway

The Bun/Hono gateway is the only public service boundary. It owns scoped
authentication, bounded ingress, authoritative scene revisions, edit
transactions, GPT-5.6 agent turns, Realtime SDP exchange, and access to private
vision workers.

The model can read scene facts, resolve a target, retrieve injection-ready
catalog candidates, validate them, and prepare a revision-neutral preview. It
cannot commit, restore, change visibility, choose transforms, or override the
server's session, pointer, or revision context.

## Local commands

```sh
bun run --cwd apps/api test
bun run --cwd apps/api typecheck
bun run --cwd apps/api build
bun run --cwd apps/api start
bun run --cwd apps/api agent:smoke
```

`agent:smoke` is a server-side proof operator. It requires the explicit
`REFRAME_AGENT_SMOKE_*` values from `.env.example`, plus OpenAI and Qdrant
credentials; it can only prepare one local placement preview and has no commit
path.

Configuration names are listed in the root `.env.example`. Keep OpenAI,
Qdrant, vision-worker, and gateway credentials server-side. Routes whose real
dependencies are not configured fail closed.
## Local durable runtime

Install workspace dependencies, set `REFRAME_DATA_DIR` to an absolute location
outside this repository, and set non-empty `REFRAME_GATEWAY_TOKEN` and
`QDRANT_API_KEY` values. Then start the API, SQLite catalog store, writable
asset storage, and persistent Qdrant service together:

```sh
bun run dev:local
```

The API is available only on loopback at `http://127.0.0.1:8787`; its public
`/health` response reports catalog storage, asset storage, and Qdrant
readiness without exposing paths or credentials. All persistent runtime data
lives under `REFRAME_DATA_DIR`, never in the repository.
