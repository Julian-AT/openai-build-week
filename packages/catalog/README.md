# Reframe catalog

[Back to Reframe](../../README.md)

This package turns authorized product sources into searchable, injection-ready
3D assets.

## Responsibilities

- Discover and acquire products with bounded, resumable operations.
- Canonicalize metadata and validate source GLB content.
- Produce normalized GLB, USDZ, collision, and preview derivatives.
- Record provenance, dimensions, hashes, eligibility, and cache profiles.
- Index eligible assets in Qdrant and resolve hash-verified delivery.

The catalog store owns canonical asset records; Qdrant is a retrieval index.
External pages, metadata, downloads, and model output are always untrusted data.

## Verify and operate

```sh
bun run --cwd packages/catalog test
bun run --cwd packages/catalog typecheck
bun run --cwd packages/catalog build
bun run --cwd packages/catalog sync -- smoke
```

The sync CLI accepts exactly one configured profile: `smoke`, `full`, or
`incremental`.

## Configuration

Use `.env.example` for the external data directory, explicitly authorized IKEA
frontier, source-measured dimensions, pinned processor tools, OpenAI embeddings,
and Qdrant access. Catalog databases, downloaded binaries, prepared derivatives,
vector indexes, and credentials stay outside Git.
