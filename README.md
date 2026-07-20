# ReRoom

Status: **working hackathon demo candidate; deterministic software checks pass,
physical, provider, and human gates remain pending.**

ReRoom is a camera-grounded room editor for one controlled chair or small table.
The native SwiftUI/ARKit app exposes exactly `place`, `replace`, `remove`, and
`restore`; a separate Next.js client owns deterministic Mode B0 replay. Optional
AI can propose typed design intent, but deterministic application code retains
target, geometry, revision, persistence, confirmation, commit, reconciliation,
and restore authority.

## Repository map

```text
apps/
  api/        private/public API boundary (migrating to Hono on Bun)
  ios/        native SwiftUI/ARKit client and shared Swift packages
  web/        separate Next.js Mode B0 client
packages/
  contracts/  JavaScript/TypeScript contract and replay reference runtime
docs/         canonical authority, contracts, ADRs, evidence, and history
tools/        Python reference code and repository verification tooling
```

The JavaScript workspace uses Bun `1.3.11`, an isolated workspace install, and
Turborepo. Each workspace owns the dependencies it imports; the root owns only
cross-workspace orchestration. `bun.lock` is the sole JavaScript lockfile.

## Start here

Read [the canonical authority](docs/canonical/README.md) before changing product
meaning. The active implementation handoff is
[AUTONOMOUS-FINISH-PLAN-2026-07-20.md](.planning/milestones/v1.0/AUTONOMOUS-FINISH-PLAN-2026-07-20.md),
and GSD resumes from [.planning/STATE.md](.planning/STATE.md):

```text
$gsd-next
```

Do not reinitialize GSD or edit the byte-preserved files in
`docs/archive/source/`.

## Install and verify

Install the exact Bun release, then from the repository root run:

```sh
bun install --frozen-lockfile
bun test
bun run typecheck
bun run build
swift test --package-path apps/ios/Packages/ReRoomContracts
```

Open
[ReRoomDeviceProof.xcodeproj](apps/ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj)
for the native app. Simulator checks prove compilation and deterministic
behavior only; they do not prove ARKit, camera, microphone, thermal, compositor,
or visual-quality gates.

The API workspace can be checked independently:

```sh
bun --cwd apps/api test
bun --cwd apps/api run typecheck
bun --cwd apps/api run build
```

Live provider use requires `OPENAI_API_KEY` and a high-entropy
`REROOM_GATEWAY_TOKEN` in the API process environment. Never place their values
in source, `.env.example`, evidence, or logs. With no provider, model, worker,
or network, the typed/tap deterministic journey remains available.

## Product authority and evidence

- [Canonical authority](docs/canonical/README.md)
- [Master Technical Specification](docs/canonical/MASTER_TECHNICAL_SPEC.md)
- [Contracts](docs/contracts/README.md)
- [Architecture decisions](docs/adr/README.md)
- [Risk and kill gates](docs/canonical/RISK_AND_KILL_GATES.md)
- [Archive-to-current coverage](docs/audit/ARCHIVE_MASTER_PLAN_COVERAGE.md)
- [GSD project](.planning/PROJECT.md)
- [Roadmap](.planning/ROADMAP.md)
- [Current state](.planning/STATE.md)
- [24-hour finish runbook](.planning/milestones/v1.0/HACKATHON-24H.md)

The archived Master Technical Plan and PRD are historical inputs, not current
implementation authority. Claims labeled `MEASURED` require reproducible raw
evidence; physical-device and human gates remain pending until actually run.

## GSD on another machine

GSD Core is machine-global rather than repository-local:

```text
npx --yes @opengsd/gsd-core@1.7.0 --codex --global
```

Restart Codex after installation. The repository shares `.planning/` only;
generated skills, hooks, runtime files, credentials, and machine paths stay in
the developer environment.
