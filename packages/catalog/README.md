# Reframe catalog

This package owns authorized product discovery, secure acquisition, deterministic
asset preparation, durable catalog state, Qdrant indexing, eligibility-first
search, client-cache synchronization, and hash-verified delivery descriptors.

## Ownership

Canonical product metadata and prepared-asset records live in the catalog store;
Qdrant is only a retrieval index. External pages, metadata, images, GLBs, and
model output are untrusted data. Injection readiness requires verified source
metadata, dimensions, origin, GLB, USDZ, collision, preview, provenance, and
hashes.

The catalog never owns scene revisions, target identity, transforms,
confirmation, commit, or restore. Raw and derived binaries, catalog databases,
Qdrant data, and OpenAI credentials remain outside Git.

## Commands

```sh
bun run --cwd packages/catalog test
bun run --cwd packages/catalog typecheck
bun run --cwd packages/catalog build
bun run --cwd packages/catalog sync -- --help
```

Environment names are documented with empty values in `.env.example`. The
pinned IKEA importer and source policy fail closed when authorization or
required processors are missing.

## Known limitations

One live product proof is recorded. The full authorized frontier, interrupted
run recovery at scale, Qdrant snapshot restore, image-assisted retrieval,
signed gateway delivery, and reproducible primary-cache synchronization remain
open.
