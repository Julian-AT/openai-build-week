# ReRoom 24-Hour Finish Runbook

Status: **software-complete demo candidate; provider/device/browser/human finish
lane remains**

Objective: produce one reproducible, honest deep-AI hackathon demo without
weakening deterministic authority or converting simulator/model output into
physical evidence. This is a demo finish lane, not a declaration that canonical
P0 is complete.

## Current checkpoint

- The repository is a Bun `1.3.11`/Turborepo workspace with package-owned
  runtime dependencies and one `bun.lock`.
- Hono is the only public application API. OpenAI calls use Vercel AI SDK;
  Python/FastAPI/PyTorch remains one private, single-lane worker behind an
  independently validating Hono adapter.
- The worker has honest `disabled` and `fixture_only` profiles. No SAM/DA3
  profile or checkpoint is selected, and no model quality/hardware gate is
  claimed.
- Native typed, optional vision, and push-to-talk transcript input share the
  same CON-006-to-deterministic-preview path. Realtime exposes no tools and can
  never confirm or commit.
- Local workspace formatting, lint, strict types, 80 Bun/Python tests,
  production builds, lockfile policy, tracked-secret scan, and GSD health pass.
- The native app compiles after the copilot activity-state cleanup. The most
  recent broad local Xcode test attempt was blocked before assertions by the
  host simulator test runners; this is pending evidence, not a test pass or a
  known assertion failure.
- An older frozen candidate has signed-build and browser-smoke evidence bound to
  its recorded revision. It remains historical and cannot prove the current
  revision.

## Definition of the hackathon finish

One clean revision must demonstrate:

1. native camera/ARKit launch on the base iPhone without rear LiDAR;
2. place or replace → revision-neutral preview → explicit one-revision commit;
3. restore preview → explicit compensating commit, including offline behavior;
4. one credentialed GPT-5.6 Sol typed proposal and, if consented, one current-
   frame vision proposal crossing only CON-006;
5. visible proof that model output stops before confirmation/commit;
6. push-to-talk only if the fixed five-utterance gate passes, otherwise the
   explicit typed fallback;
7. the separate Mode B0 golden replay in a real supported browser;
8. a sub-three-minute recording and submission checklist bound to that clean
   revision, with every pending gate disclosed.

Normal removal quality, canonical 5/5 P0, and physical/human evidence remain
separate claims.

## Critical path for the remaining hours

| Timebox | Action | Stop condition / output |
|---:|---|---|
| 0–1 h | Start from a clean clone/install and run the software gate below. | All frozen installs, static checks, tests, builds, secrets, locks, and Swift package tests pass. Any regression is fixed before rehearsal. |
| 1–2 h | Run one redacted live typed Sol request, then one explicitly consented current-frame request. | Exact trusted context echoes, asset is in the three-item catalog, output creates preview only, and logs contain no prompt/image/secret. Cut live AI after 45 minutes if access or strict output fails. |
| 2–3 h | Run the five Phase 09 push-to-talk utterances plus adversarial cases on device. | Keep voice only at ≥4/5 correct nonmutating proposals and zero authority/security failures. Otherwise disable voice and use typed input. |
| 3–5 h | Execute one signed base-iPhone camera/ARKit and deterministic edit rehearsal. | Place/replace/restore survive interruption/retry with exact revision behavior; record factual environment and sanitized results. Removal stays disclosed until GATE-006. |
| 5–6 h | Run Mode B0 from the current clean revision over local HTTP in a supported browser. | Golden capture verifies, timeline scrubs, inspector stays exact, keyboard controls work, and console/page errors are empty. |
| 6–7 h | Freeze the candidate and repeat the complete software/build gate. | One immutable candidate revision with no dirty behavior-bearing files. |
| 7–9 h | Record the shortest complete demo and one backup take. | Under three minutes, audible, deterministic commit boundary visible, typed fallback available. |
| 9–11 h | Finalize README, architecture/model explanation, license/access notes, representative Codex Session ID, and pending-gate table. | Reviewer can install and understand the system without guessing. |
| 11–12 h | Human rules checklist, publish decision, and submission. | Publishing remains an explicit owner action; no automated process signs or submits for a human. |

## Optional local-model decision

Storage availability does not by itself authorize a checkpoint. Do not spend the
finish lane pulling several model families. A real SAM 2.1 Hiera Small profile
may proceed only if all of the following are ready before its four-hour
GATE-004 timebox starts:

- the 20 annotated hero frames and 60-second replay fixture;
- exact official code revision, checkpoint URL and SHA-256, separate code and
  weight license decision, and attribution;
- pinned runtime dependency closure compatible with the selected machine;
- adapter tests for normalization, seed handling, mask identity, output shape,
  cancellation, queue saturation, and invalid bytes;
- the metric calculator and raw-evidence destination for median/p10 IoU,
  leakage, identity switches, p95 latency, queue growth, VRAM, and startup.

If any prerequisite is absent, keep the worker `disabled` for the demo and use
manual target/reseed or the explicitly labeled fixture path. Do not turn a
download or visually plausible mask into `MEASURED` evidence. DA3 and LingBot
remain out of this final lane unless their separate canonical gates are already
prepared and higher-priority demo evidence is green.

## Exact software gate

From the repository root:

```sh
bun install --frozen-lockfile
uv sync --project apps/inference --frozen
bun run check
bun run test:swift
node "$HOME/.codex/gsd-core/bin/gsd-tools.cjs" query validate.health
git diff --check
```

Native build and test:

```sh
xcodebuild test \
  -project apps/ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj \
  -scheme ReRoomDeviceProof \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -derivedDataPath /tmp/reroom-derived-data \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO
```

If the simulator runner fails before test assertions, retain the complete log,
run a clean compile/build-for-testing, and mark simulator execution pending. Do
not report zero selected cases or runner startup failure as a pass. Physical
camera/microphone/ARKit work still requires the signed base device.

## Service rehearsal

No-provider topology:

```sh
bun run dev
```

Gateway with semantic/voice providers:

```sh
export REROOM_GATEWAY_HOST=127.0.0.1
export REROOM_GATEWAY_TOKEN=<high-entropy-local-token>
export OPENAI_API_KEY=<server-only-project-key>
bun run --cwd apps/api dev
```

Explicit private fixture worker in a separate terminal:

```sh
export REROOM_INFERENCE_HOST=127.0.0.1
export REROOM_INFERENCE_PROFILE=fixture
export REROOM_INFERENCE_TOKEN=<private-worker-token>
bun run --cwd apps/inference dev
```

Then give Hono `REROOM_INFERENCE_URL=http://127.0.0.1:8790` and the same
private token. The public gateway token must be different. Keep port `8790`
loopback-only and never give the worker token to the iPhone or web client.

Mode B0:

```sh
bun run --cwd apps/web build
bun run --cwd apps/web start -- --hostname 127.0.0.1 --port 3100
```

## Demo sequence

1. Show the live camera and explicit controlled target.
2. Type or say “Replace this with the cobalt chair.”
3. Point out the model provenance and unchanged base revision in preview.
4. Confirm manually and show exactly one revision increment.
5. Restore and show a new compensating transaction rather than history rewind.
6. Briefly show the provider-independent Mode B0 replay/inspector.
7. State the fallback: typed input, manual target, no-dense, local journal, and
   B0 remain usable with OpenAI/Python/network disabled.

Use the disclosed removal fixture only if it is clearly labeled as a transaction
and reveal demonstration. Do not imply that normal removal quality or GATE-006
has passed.

## Hard kill rules

- **Sol:** 45 minutes. If credential/model access or strict CON-006 fails, use
  the local typed path and fixture response; never loosen the schema.
- **Realtime:** 45 minutes. If network/audio behavior, 4/5 intent accuracy, or
  any injection case fails, disable the voice button. Voice is optional.
- **Simulator:** do not burn the device rehearsal window fighting a host runner
  crash after the app compiles. Preserve logs, use CI/another host, and proceed
  to the signed-device gate.
- **Segmentation/depth:** no checkpoint without the prepared gate packet above;
  no multi-model bake-off inside the final demo window.
- **Removal:** no unseen-room synthesis. Ask for another view, shrink the
  envelope, or keep remove unavailable. Controlled-fixture failure still blocks
  canonical P0.
- **Scope:** no cloud platform, Kubernetes, Redis/Postgres migration, large
  catalog, commerce, multi-user, B1, or new operation.
- **Evidence:** simulator, model output, local fixture, or recollection never
  becomes physical/human evidence. A dirty-tree build never becomes a
  revision-bound claim.

## Handoff truth table

| Result | Allowed statement |
|---|---|
| Clean local/CI software gate | “The deterministic software and strict AI boundary pass the listed checks.” |
| One signed-device observation | “This exact revision ran this exact observation on the named device.” |
| One live Sol request | “A live request succeeded once with this redacted request ID.” |
| Fixture worker result | “The Hono/Python protocol works end-to-end with a non-evidentiary fixture provider.” |
| Optional voice disabled | “Voice fell back to typed input without affecting the edit journey.” |
| Disclosed removal fixture | “The fixture illustrates transaction/reveal flow; normal quality and GATE-006 remain pending.” |
| Missing gate evidence | Never “P0 complete,” “production ready,” “real-time,” or “gate passed.” |

## GSD handoff

Do not reinitialize GSD or create another speculative phase. This direct
owner-authorized overlay is the active implementation handoff. After the
software/docs slice is committed, update `.planning/STATE.md` with the exact
stopping point and let `$gsd-next` route back to the unresolved Phase 2
verification/evidence work. Publication, branch protection, physical evidence,
and submission remain deliberate owner actions.
