# ReRoom Asset Licence and Format Evidence

**Version:** 1.1  
**Date:** 2026-07-18  
**Status:** `RESEARCH DRAFT — NOT APPROVED FOR INTEGRATION`  
**Related CSV:** `assets.csv`  
**Room/target:** `ROOM-r01` / `TARGET-001` (round pedestal table, approximately 0.60 m × 0.60 m × 0.75 m)

## Decision summary

Two table candidates are retained for research only:

- `table_white_round_01` — preferred visual match;
- `table_modern_art_01` — backup.

Neither is approved for the ReRoom app, the web client, or a final demo. No binary file is stored in this repository.

## Source evidence

Publisher page: https://ar-code.com/blog/furniture-ar-codes-and-their-3d-models-in-glb-usdz-formats

The publisher page, dated 2026-01-06, states that its furniture models are available in GLB, USDZ, and STL formats and are licensed under CC0 for unlimited commercial use. It lists:

| Asset ID | Publisher-reported generic model size | Published GLB link | Published USDZ link |
|---|---:|---|---|
| `table_white_round_01` | 1.562552 MB | Yes | Yes |
| `table_modern_art_01` | 2.954624 MB | Yes | Yes |

These are **not** verified per-file download sizes. The exact GLB and USDZ bytes, checksums, dimensions, origin, axis, and licence evidence remain pending.

## Temporary working budget

Use a temporary working budget of **less than 15,000,000 bytes for each downloaded USDZ and GLB file**. This is a planning constraint, not a measured thermal guarantee or a substitute for device load testing.

The CSV deliberately leaves `mobile_download_bytes` and `web_download_bytes` blank until the exact files are downloaded and measured.

## Required approval checklist

A developer may mark an asset `APPROVED` only after all items are complete:

- [ ] Exact USDZ and GLB files downloaded from the recorded URLs.
- [ ] Exact filenames, byte counts, and SHA-256 hashes recorded.
- [ ] Both files are below the temporary 15,000,000-byte budget, or an approved exception is documented.
- [ ] Width, depth, and height measured in metres.
- [ ] USDZ and GLB dimensions, floor-contact origin, and forward/up orientation agree within the project parity gate.
- [ ] Collision/cover behaviour is tested against the controlled table target.
- [ ] USDZ loads locally on the target iPhone.
- [ ] GLB loads in the web client.
- [ ] Exact licence/terms evidence and any attribution requirement are saved in restricted evidence storage.
- [ ] Asset is bundled or fully pre-cached; no command-time network download is required.

## What P3/P4 own now

P3/P4 may maintain candidate names, source links, visual fit notes, and research status. Developers own downloading, normalization, hashing, derivative parity, device/web loading, and the final canonical asset manifest.

## Rejection rule

Reject an asset if either derivative is missing, its final licence cannot be evidenced, dimensions/origin differ across formats, it fails device or web loading, it exceeds the agreed delivery budget without approval, or it does not plausibly replace the controlled target.

## Evidence storage

Keep raw model binaries, downloaded licence pages, hashes, and device-load traces in restricted project storage until the engineering team confirms the approved binary-storage and manifest locations. Do not add unreviewed model binaries to this branch.
