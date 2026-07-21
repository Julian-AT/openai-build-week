# Catalog verification record

This package-local record describes the bounded live proof. Downloaded assets,
Qdrant records, credentials, and processor workspaces remain outside Git.

## Live proof completed

- The authorized US IKEA page for product `40541421` was fetched and its live
  GLB variant was acquired with resumable, content-addressed storage. The
  selected source bytes were 887,544 bytes with digest
  `d74d34f0a8615eb04e973f17c0e8b8d5e994cd77718f3531683b4b27b2fe202e`.
- Blender 5.2.0 normalized the source into validated GLB, USDZ, collision,
  and preview derivatives. The prepared asset is
  `ikea-us-40541421-d74d34f0a861`; its delivery GLB is 608,696 bytes with
  digest `8b7b7a80a5fd7c34f1f741ba44e01deb82726fa62bb5071527de1912c03a5a5f`.
- OpenAI embeddings and the local authenticated Qdrant service returned the
  same eligible product under category, floor support, dimensions, cache
  profile, authorization, and derivative-readiness filters.
- GPT-5.6 Sol then returned one `pending_confirmation` placement preview bound
  to that stable asset ID and base scene revision zero. No commit authority was
  exposed to the model.

## Errors found and handled

- The first processor attempt used guessed product dimensions and correctly
  failed closed with `asset_dimension_mismatch`. Blender measured
  `0.8050000668 × 0.5230337381 × 0.3071348667` metres; rerunning with those
  measured values passed the five-percent validation gate.
- A downloader JPEG with tolerated trailing bytes was rejected by the strict
  vision wire contract. The GPU proof uses a canonical re-encoded image and
  keeps the rejection behavior for untrusted input.

## Potential upgrades

- Persist a signed, redacted proof manifest linking source, derivation,
  embedding, Qdrant point, delivery, and preview IDs without retaining raw
  room imagery or credentials.
- Add a durable catalog-to-gateway artifact handoff so a prepared asset can be
  delivered through the same scoped artifact transport used by capture replay.
- Expand the bounded smoke run to a configured variant frontier only after
  processor capacity, request budgets, and reconciliation reporting are
  measured on the persistent volume.
