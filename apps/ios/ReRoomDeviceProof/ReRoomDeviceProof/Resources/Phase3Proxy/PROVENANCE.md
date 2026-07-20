# Phase 3 proxy provenance

`proxy-chair.usda` is repository-owned text geometry generated for the Phase 3 deterministic local place/restore demonstration. It contains six USD cubes: one seat, one back, and four legs. No third-party model, texture, binary, or provider output is included.

- Proxy label: `asset_proxy-chair-phase3`
- Generation recipe: create the six named cubes and apply the literal scale/translation values stored in the USDA source.
- Qualification: `phase3_local_demo_proxy_only`
- License: repository project license; no external asset license is asserted.
- Scope: deterministic transaction and presentation proof only.
- Geometry assumptions: `HYPOTHESIS` only — metres, Y-up, floor contact at `y=0`, and nominal bounds `[0.6, 1.0, 0.6]` metres.
- Renderer qualification: the exact digest-bound six-cube USDA must load; a generated box is not an accepted substitute.
- Gate status: `GATE-003`, `GATE-005`, `GATE-009`, `GATE-011`, and `OPS-GOLDEN-001` remain `PENDING`.

This artifact does not claim production compositor quality, licensed catalog parity, measured device quality, physical-device loading, or completion of any pending gate.
