# Spatial protocol

This package is the single TypeScript and JSON Schema authority for Reframe's
wire contracts and pure transaction behavior.

## Ownership

It owns strict parsing, canonical JSON and SHA-256 behavior, coordinate and
matrix conventions, FramePacket layout, capture events, artifacts, proposals,
replacement coverage, transactions, replay rules, idempotency, and inverse
behavior.

It never performs transport, persistence, rendering, inference, retrieval, or
scene mutation. Swift and Python adapters must agree with these definitions
rather than create parallel public contracts.

## Commands

```sh
bun run --cwd packages/protocol format
bun run --cwd packages/protocol lint
bun run --cwd packages/protocol typecheck
bun run --cwd packages/protocol test
bun run --cwd packages/protocol build
```

## Known limitations

Session, plane, pointer, reconnect, artifact-activation, catalog-processing, and
complete `.rfcap` adapters still need one cross-runtime acceptance set. Changes
to a public schema must update TypeScript, Swift, Python, and their tests in the
same commit.
