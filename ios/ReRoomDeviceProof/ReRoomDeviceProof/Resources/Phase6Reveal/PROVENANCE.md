# Phase 6 degraded demo reveal fixture

This directory is an audit-only mirror of bytes compiled into `RoomEditModel.swift`.
It is intentionally not loaded through `Bundle`, not added to Xcode resources, and not
canonical room or reveal evidence.

- Classification: `degraded_demo_fixture`
- Assumption status: `HYPOTHESIS`
- Formal status: `GATE-006 PENDING`
- Geometry: two deterministic local proxy surfaces (`floor_proxy`, `wall_proxy`)
- Pose bound: 0.2 m translation and direction dot >= 0.966

The proxy surfaces are not observed/tracked room surfaces, provider output, foreground
occluders, coverage evidence, seam evidence, or a visual-vote result. Normal and Release
launches keep removal unavailable with `reveal_quality_failed`.
