# Reframe gateway

The Bun gateway is Reframe's trusted public service boundary and sole
scene-revision authority.

## Ownership

The gateway owns room-scoped authentication, durable sessions, bounded ingress,
pointer and target context, preview records, CAS transactions, compensating
restore, artifact access, worker coordination, catalog access, GPT-5.6 planning,
and Realtime credential exchange.

Models and clients never own spatial truth, target identity, revisions,
transforms, confirmation, commit, or restore. Product routes must not fabricate
room facts or use showcase assets when a dependency is unavailable.

## Commands

```sh
bun run --cwd apps/api test
bun run --cwd apps/api typecheck
bun run --cwd apps/api build
bun run --cwd apps/api start
```

`bun run --cwd apps/api dev:local` starts the current API/Qdrant development
profile. Persistent state belongs under an operator-selected data directory
outside Git. Configuration names and empty examples live in `.env.example`;
credentials stay server-side.

## Known limitations

The current compose profile is not the complete GPU service topology. Signed
short-lived GLB/USDZ delivery, binary frame WebSocket ingest, artifact event
fan-out, reconnect activation state, and full deletion/retention acceptance are
open. Deadline-only showcase paths must be removed according to the web
submission cleanup plan.
