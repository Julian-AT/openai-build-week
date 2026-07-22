# Reframe protocol

[Back to Reframe](../../README.md)

This package is the canonical TypeScript and JSON Schema boundary for Reframe's
wire contracts and pure scene behavior.

## Public surface

- Canonical JSON serialization and SHA-256 digests.
- Coordinate transforms and camera intrinsics conventions.
- Binary frame packets and ordered capture events.
- Placement previews and replacement-coverage evaluation.
- Immutable scene transactions, idempotency, revisions, and restore operations.
- JSON Schemas for captures, scene state, proposals, artifacts, and transactions.

The package performs no transport, persistence, rendering, inference, retrieval,
or network mutation. Swift and Python adapters must preserve these contracts
rather than define competing public shapes.

## Verify

```sh
bun run --cwd packages/protocol format
bun run --cwd packages/protocol lint
bun run --cwd packages/protocol typecheck
bun run --cwd packages/protocol test
bun run --cwd packages/protocol build
```

Any public schema change must update its TypeScript behavior, JSON Schema,
cross-runtime adapters, and contract tests together.
