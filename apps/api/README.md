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
```

Configuration names are listed in the root `.env.example`. Keep OpenAI,
Qdrant, vision-worker, and gateway credentials server-side. Routes whose real
dependencies are not configured fail closed.
