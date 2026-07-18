# Phase 8 Demo Runbook

> ReRoom demo candidate: automated integration checks passed; representative device/browser smoke recorded where linked; deferred P0 gates remain pending.

This is an operator rehearsal for the existing local demo candidate. It does not change product source, dependencies, signing, the Xcode project, deployment, or external services.

## Evidence classification rules

- `automated_check`: command, unit-test, simulator, retained build, or local HTTP evidence.
- `device_smoke`: only a real signed-device run with a separately retained opaque artifact ID and digest.
- `browser_smoke`: only a real browser run with a separately retained opaque artifact ID and digest.
- `human_observation`: only a separately retained operator ballot or observation artifact.
- `external_submission`: only a human-authorized public/submission artifact.

Local HTTP output is `automated_check`, not `browser_smoke`. An Xcode or simulator result is not `device_smoke`. One representative run is rehearsal evidence only. OPS-GOLDEN-001 remains PENDING until 5/5 after blocking gates are green.

Current state: Device smoke PENDING. Browser smoke PENDING. License shipping BLOCKED. Submission PENDING.

## 1. Preflight

From the repository root:

```bash
df -Pk .
git status --short
python3 --version
node --version
npm --version
swift --version
scripts/verify-phase-08-hardening --verify-evidence
scripts/verify-phase-08-evidence full
scripts/verify-phase-08-evidence --verify-evidence
```

Expected automated result: both Phase 8 commands return `PASS`; shipping remains `BLOCKED`, and physical/browser/human/submission rows remain `PENDING`. Stop on any failure. Do not clean repository or user data to create space.

## 2. Signed native rehearsal

This procedure requires the existing Xcode signing configuration and connected iPhone. Do not edit PBX, signing, capabilities, bundle identity, or schemes.

1. Open `ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj` in Xcode.
2. Select the existing `ReRoomDeviceProof` scheme and the connected signed device.
3. Build and run without changing project settings.
4. Confirm the app opens as ReRoom Device Check and reaches the existing room-edit surface.
5. Use the controlled hero target: one freestanding chair or small table with visible floor.
6. Exercise exactly `place`, `replace`, `remove`, and compensating `restore` in that order.
7. Confirm typed/tap fallback remains usable with network and learned providers absent.
8. Record only an opaque external artifact ID, lowercase SHA-256, implementation revision, environment class, and operator procedure. Keep video, room imagery, signing details, device identifiers, and logs outside Git.

Until that artifact is separately retained and validated, the result remains `device_smoke: PENDING`.

## 3. Local Mode B0 rehearsal

Use the existing B0 verifier and page; do not add uploads, accounts, sharing, deployment, or provider calls.

```bash
scripts/verify-phase-07-b0 --verify-evidence
```

If a local page is launched through the existing Phase 7 procedure, inspect the verified capture, scrub the timeline, and confirm its fixed archive/report identity. Local HTTP inspection remains `automated_check`. A `browser_smoke` claim requires a separately retained real-browser artifact and remains PENDING here.

## 4. Recovery

- Native launch/build failure: stop, preserve the exact sanitized Xcode diagnostic class outside Git, and return to the last source-bound automated evidence. Do not change PBX/signing to force a pass.
- Tracking loss: use the existing manual tap/re-seed fallback. Do not infer semantic target authority.
- Removal unavailable: retain the bounded reveal-quality failure; do not bypass it.
- B0 verifier or digest failure: stop and regenerate only through the authoritative Phase 7/8 verifier. Do not edit evidence JSON manually.
- Disk preflight failure: stop. Reclaim only a specifically identified rebuildable cache with human awareness; never broad-clean.
- Missing physical/browser artifact: leave the row PENDING and follow the exact procedure later.

## 5. Rehearsal result

After the run, update no checked-in evidence unless the relevant classifier accepts the sanitized record. One representative journey never completes the canonical 5/5 campaign, latency distributions, resilience campaigns, license closure, or submission.

## Deferred Resume Order

1. Finish the missing Phase 5–7 implementation/evidence plans and rerun their authoritative verifiers.
2. Resume `$gsd-verify-work 2` for the full `GATE-001` signed-device termination matrix.
3. Run formal `GATE-003`, `GATE-006`, `GATE-008`, `GATE-009`, and `GATE-011` campaigns against the frozen implementation.
4. Benchmark `GATE-004`, `GATE-007`, and `GATE-012` only if replacing the activated manual/no-dense/local fallbacks.
5. Complete the canonical latency/resilience distributions and security/license closure, then run `OPS-GOLDEN-001` 5/5.
6. Audit the milestone and assemble signed release/submission evidence before making a full P0 claim.
