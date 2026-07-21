# Reframe agent

This package owns the bounded OpenAI adapter layer for GPT-5.6 planning and
Realtime turn ingress.

## Ownership

It owns strict read-only or preview-only tool schemas, tool-step and candidate
budgets, cancellation, continuation items, model capability checks, and redacted
request tracing. Realtime may submit one user turn; GPT-5.6 may inspect trusted
context and prepare at most one proposal.

The agent never resolves spatial truth, chooses authoritative transforms,
changes visibility, confirms, commits, restores, persists canonical state, or
mutates Qdrant. The gateway binds session, pointer, identity, and revision
context instead of trusting model or client arguments.

## Commands

```sh
bun run --cwd packages/agent test
bun run --cwd packages/agent typecheck
bun run --cwd packages/agent build
```

Standard OpenAI credentials remain server-side. Clients receive only scoped,
short-lived Realtime credentials.

## Known limitations

The exact live iPhone WebRTC, interruption, clarification, timeout, and full
replacement acceptance scenario remains unverified. Deadline-only gateway
bypasses must be removed so typed and voice turns always share the same bounded
planning boundary.
