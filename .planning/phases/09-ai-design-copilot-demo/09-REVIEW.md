---
phase: 09-ai-design-copilot-demo
reviewed: 2026-07-20T00:00:23Z
depth: deep-final
files_reviewed: 32
findings:
  blockers: 0
  warnings: 0
  total: 0
status: passed
---

# Phase 09 Deep Final Review

## Verdict

**The automated implementation slice passes deep review with no remaining
correctness blocker.** All original and follow-up code findings are resolved.
The model and Realtime paths still terminate at strict semantic proposals;
deterministic native code still owns current-context binding, target and spatial
readiness, the revision-neutral preview, explicit confirmation, CAS commit,
persistence, reconciliation, and captured-exact Restore.

The final interaction state is linearized across voice startup/cancellation,
typed Ask, Apply, native preview creation, operation selection, Cancel, Confirm,
and Retry. The delivered web catalog now closes the native/web manifest,
payload, validation-evidence, license, and provenance byte chain.

The former non-blocking PostCSS dependency warning is closed. The web package
now pins Next.js 16.2.10 and overrides its vulnerable PostCSS 8.4.31
transitive pin with PostCSS 8.5.20; the complete web suite, typecheck,
production build, dependency tree, and zero-vulnerability production audit
all pass.

This is a local automated code-review verdict, not canonical Phase 09
acceptance. Live provider behavior, signed-device camera/microphone behavior,
human design usefulness, latency/cost, physical asset review, and formal gates
remain pending exactly as recorded in `09-VERIFICATION.md`.

## Final finding disposition

| Finding | Status | Final evidence |
|---|---|---|
| `BL-01` Realtime bounds, deadlines, and cancellation | **RESOLVED** | Gateway and native input are duplicate-safe and bounded; audio queue, send/transcript/session deadlines, socket cancellation, and visible Cancel remain covered. The pre-session generation hole is closed by `BL-R1`. |
| `BL-02` partial audio rollback | **RESOLVED** | Audio resources are independently acquired and unwound in reverse order; fault-injection, idempotent-stop, and retry coverage remains green. |
| `BL-03` canonical asset integrity | **RESOLVED for the automated delivery boundary** | Native loading validates the canonical CON-004 record and all referenced bytes. Web delivery now includes identical provenance, license, evidence, manifest, and derivative bytes. Three of three current manifests validate against CON-004. `GATE-011` remains `PENDING`. |
| `BL-04` multiple preview slots | **RESOLVED** | One typed transition owner now covers semantic creation, manual operation selection, Cancel, Confirm, Retry, and restore automation; competing UI controls disable while it is owned. Controlled suspensions prove one winning transition, one preview, and at most one commit. |
| `WR-01` duplicate-unsafe Realtime JSON | **RESOLVED** | Both gateway bootstrap and native Realtime events reject duplicate keys, invalid UTF-8, and oversized input before projection. |
| `WR-02` typed Ask/voice overlap | **RESOLVED** | Attempt IDs bind voice callbacks; typed and voice work cannot release or overwrite each other's operation state. |
| `WR-03` no production Ask-to-preview join | **RESOLVED** | The production-injected Ask to Apply test reaches the real native preview boundary and proves revision neutrality with no history or receipt. |
| `BL-R1` cancellation during permission/secret startup | **RESOLVED** | `startVoice()` reserves its generation before the first suspension and rechecks it plus task cancellation after permission, secret minting, and session start (`DesignCopilot.swift:1642-1704`). `cancelVoice()` invalidates owned voice state without touching an unrelated typed Ask (`DesignCopilot.swift:1732-1749`). Delayed-permission and delayed-secret tests prove zero session-factory creations after cancellation, and the typed-Ask cleanup test proves independent ownership (`RoomEditModelTests.swift:769-858`). |
| `BL-R2` Cancel/Confirm/manual preview races | **RESOLVED** | `RoomEditPreviewTransitionOwner` and its synchronous claim/release boundary cover every user preview transition (`RoomEditModel.swift:726-733,1161,1205-1225,1489-1760`). Operation, Cancel, Confirm, and Retry controls disable immediately (`RoomEditView.swift:791-817,958-1026`). Suspension tests cover Confirm versus Cancel/manual select/double Confirm and manual select versus stale Confirm/Cancel (`RoomEditModelTests.swift:1113-1183`). |
| `BL-R3` false Apply success | **RESOLVED** | Native previewing returns `Bool` and reports success only when an exact preview slot exists (`RoomEditModel.swift:1252-1311`). Apply reserves and defer-releases `isWorking`, retains the envelope on a local no-preview outcome, and clears it only after success or explicit stale-context rejection (`DesignCopilot.swift:1597-1610,1772-1872`). Tests cover place without support, replace without target, restore without source, rapid double Apply, and Ask during suspended Apply (`RoomEditModelTests.swift:902-1074`). |
| `WR-R1` incomplete web evidence/provenance chain | **RESOLVED** | Generation copies provenance into the web bundle (`generate_hackathon_assets.mjs:293-302`). The web test requires native/web byte identity, RR-JCS manifest/catalog identity, evidence to license/provenance digests, provider to generator digest, and every derivative length/digest/format (`asset-delivery.test.mjs:77-171`). |

## Dependency remediation

### WR-F1: Next.js transitive PostCSS advisory — RESOLVED

**Files:** `web/package.json`; `web/package-lock.json`

The prior production audit reported `next@16.2.9` and its transitive
`postcss@8.4.31` under `GHSA-qx2v-qp2m-jg93`. The candidate now uses exact
`next@16.2.10` plus an npm override to `postcss@8.5.20`. `npm ls` resolves that
exact tree; 10/10 web tests, `next typegen` plus strict TypeScript, the
production build, and `npm audit --omit=dev --audit-level=high` all pass with
zero reported vulnerabilities. The override remains an explicit compatibility
decision and must not be removed without rerunning the same checks.

## Verification state at final cutoff

- Complete clean temporary-snapshot, serial simulator Xcode run: **129/129
  passed** (**119 unit/integration plus 10 UI**); `xcodebuild TEST SUCCEEDED`.
- Gateway: **34/34 tests passed**; typecheck and build passed; production audit
  reported zero vulnerabilities.
- Web under the repository-pinned Node `v22.22.3`: **10/10 tests passed** on
  Next.js 16.2.10 and overridden PostCSS 8.5.20. Typecheck, production build,
  dependency resolution, and a zero-vulnerability production audit pass.
- Swift package: **172/172 tests passed**. Targeted Python checks: **27/27
  passed**. Current CON-004 manifests: **3/3 schema-valid**. Regenerated asset
  bytes remained deterministic.
- The Phase 02.1 verifier passed independently; that is upstream capture/replay
  evidence and is not promoted into a Phase 09 physical or live-model claim.
- A local Chromium Mode B0 replay rendered and its slider/button interactions
  traversed verified events. This is local browser wiring evidence only.
- No live Sol, live Realtime provider, signed-device microphone/camera/iPhone,
  human design review, latency/cost, physical asset parity/collision/cover, or
  formal gate pass is claimed. `GATE-011` and all live/human gates remain
  `PENDING`.
- Archive sources were not edited. The only final-review write is this file.
