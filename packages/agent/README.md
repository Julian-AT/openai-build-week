# Reframe agent

[Back to Reframe](../../README.md)

This package contains the bounded OpenAI adapter layer for design planning and
live voice ingress.

## Public surface

- Responses API planning with a small, strict tool set.
- Tool-call, candidate, deadline, and cancellation budgets.
- Redacted lifecycle tracing and exact model-capability checks.
- Realtime WebRTC session exchange and strict `submit_user_turn` parsing.
- Browser and mobile transport interfaces for audio and data-channel events.

Realtime can submit a normalized turn. The planner can inspect trusted context
and prepare one proposal. Neither can resolve spatial truth, confirm an edit,
commit canonical state, restore history, or mutate the catalog.

## Verify

```sh
bun run --cwd packages/agent test
bun run --cwd packages/agent typecheck
bun run --cwd packages/agent build
```

## Integration

The gateway supplies authoritative session, pointer, identity, and revision
context to this package. Standard OpenAI credentials remain server-side;
clients receive only room-scoped Realtime access through the gateway.
