# Hackathon CON-004 derivative provenance

The three source USDA files in this directory are repository-authored literal
primitive geometry under the repository MIT license. No third-party model,
texture, or provider output is present.

- The warm chair has six cubes, the cobalt chair has eight, and the halo table
  has three; the literal sources remain the authority for their geometry.
- These repository-authored sources and generated derivatives are approved for
  hackathon use and redistribution under the root MIT license. This approval
  does not extend to any future third-party asset or dependency.
- Exact source identities, digests, bounds, catalog labels, and derivative
  bindings live in `asset-catalog.json` and the three canonical manifests.

`tools/assets/generate_hackathon_assets.mjs` reproducibly packages each source
as a local USDZ and generates a GLB plus a conservative box collision GLB from
the literal primitive geometry. Each `*.asset-manifest.json` is a schema-valid
CON-004 record whose RR-JCS content digest covers identity, dimensions,
source/license evidence, delivery metadata, validation evidence, and every
payload digest. Native and web tests independently verify the bundled bytes and
formats. `ASSET-LICENSE.txt` is a byte-identical bundled copy of the repository
MIT license.

All three records deliberately remain `degraded` demo proxies with `GATE-011`
`PENDING`. Automated checks establish record and payload integrity, repository
ownership, permissive license bytes, and local native/web delivery. They do not
claim rendered USDZ/GLB dimension or visual parity, base-iPhone physical
loading, collision/cover quality, human review, or a completed asset gate.
Those pending checks stay explicit in `asset-validation-evidence.json`.
