# ReRoom

Status: **working hackathon demo candidate; deterministic software checks pass,
physical/human gates remain pending.**

ReRoom is a camera-grounded room editor for one controlled chair or small table.
The native SwiftUI/ARKit app exposes exactly place, replace, remove, and restore;
a separate web client owns deterministic Mode B0 replay. Optional GPT-5.6 Sol
and Realtime features propose design intent only. Native deterministic code
still owns target context, geometry, revisions, preview, confirmation, commit,
reconciliation, and restore.

## Continue now

Read [the canonical authority](docs/canonical/README.md), then run:

```text
$gsd-next
```

GSD must use [.planning/STATE.md](.planning/STATE.md) as the current position.
Do not restart at Phase 1, run `$gsd-new-project`, or re-ingest the repository.
The exact remaining hackathon sequence is in
[HACKATHON-24H.md](.planning/milestones/v1.0/HACKATHON-24H.md).

## Run the local AI gateway

Use Node `22.22.3` and npm `10.9.8`:

```sh
nvm use  # when nvm is installed; reads the repository .nvmrc
cd gateway
npm ci
npm test
npm run typecheck
```

Set `OPENAI_API_KEY` and a high-entropy `REROOM_GATEWAY_TOKEN` in the shell
environment; never put either value in source. For simulator-only use, bind the
gateway to `127.0.0.1`. For an iPhone, bind to the Mac's LAN interface and enter
that URL plus the gateway token in the app's **AI design copilot → Gateway
setup** panel.

```sh
npm run build
npm start
```

The gateway exposes only:

- `GET /health`
- `POST /v1/proposals` — strict CON-006 Sol proposal, optional explicitly
  consented JPEG
- `POST /v1/realtime/client-secret` — short-lived Realtime credential

See [gateway/README.md](gateway/README.md) for exact request shapes and safety
boundaries. No live OpenAI request occurs without a configured key.

## Run the native app

Open
[ReRoomDeviceProof.xcodeproj](ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj)
in the current Xcode, select the checked-in `ReRoomDeviceProof` scheme, and run
on the base iPhone. The simulator proves compilation and deterministic UI/model
tests; it cannot prove ARKit, camera, microphone, compositor, thermal, or visual
quality gates.

The native AI panel supports:

- a typed design request;
- optional one-frame vision, encoded only after explicit action and consent;
- a three-entry digest-bound local demo catalog;
- optional push-to-talk Realtime transcription;
- strict context-bound proposals that create a preview only;
- separate deterministic confirmation for commits and restore.

Turning off the gateway/model/network leaves the full local typed/tap journey
available.

## Run the deterministic checks

```sh
swift test --package-path ios/Packages/ReRoomContracts
npm --prefix gateway test
npm --prefix gateway run typecheck
npm --prefix gateway run build
node tools/assets/generate_hackathon_assets.mjs
npm --prefix gateway audit --omit=dev --audit-level=high
npm --prefix web test
npm --prefix web run typecheck
npm --prefix web run build
npm --prefix web audit --omit=dev --audit-level=high
python3 -m unittest tools.python.tests.test_semantic_proposal \
  tools.verify.tests.test_phase_05_replacement \
  tools.verify.tests.test_phase_02_1_trust_boundary
```

The Xcode project contains a provenance guard that intentionally rejects a
source-dirty evidence build. Commit an approved coherent revision before
collecting revision-bound device evidence; do not disable the guard.

## Project authority and planning

- [Canonical authority](docs/canonical/README.md)
- [Archive-to-current coverage](docs/audit/ARCHIVE_MASTER_PLAN_COVERAGE.md)
- [GSD project](.planning/PROJECT.md)
- [Requirements](.planning/REQUIREMENTS.md)
- [Roadmap](.planning/ROADMAP.md)
- [Current state](.planning/STATE.md)
- [24-hour finish runbook](.planning/milestones/v1.0/HACKATHON-24H.md)
- [GSD configuration](.planning/config.json)
- [GSD configuration rationale](.planning/milestones/v1.0/GSD-CONFIGURATION.md)

The original [Master Technical Plan v3.2](docs/archive/source/ReRoom_Master_Technical_Plan_v3.2.md)
and [PRD v1.0](docs/archive/source/ReRoom_PRD_v1.0.md) are byte-preserved
historical inputs. They are not implementation authority.

## GSD on another machine

Install GSD Core globally, never inside this repository:

```text
npx --yes @opengsd/gsd-core@1.7.0 --codex --global
```

Restart Codex, open the repository root, and run `$gsd-next`. Generated agents,
skills, hooks, MCP configuration, credentials, and machine paths remain in the
developer's user environment. Only `.planning/` is shared project state.
