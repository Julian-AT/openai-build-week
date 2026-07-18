# GATE-001 physical capture/replay procedure

This procedure is the human/device boundary for `GATE-001`. Automated, simulator, synthetic, and replay-fixture results are useful preflight evidence, but none may be relabeled as physical `MEASURED` evidence or authorize `GREEN`.

## 1. Freeze the candidate and external evidence location

1. Select the exact signed Release candidate on the base iPhone 17 path. Record its `git:<40 lowercase hex>` implementation revision, a safe build revision, sanitized iOS/Xcode labels, and one opaque evaluator ID. Do not record a device UUID, team/account identifier, signing material, user name, or machine path.
2. Confirm the build does not require rear LiDAR and exposes instrumented termination controls for the exact lifecycle states below.
3. Retain the `.rrcap`, crash/termination logs, replay outputs, screen recordings, and evaluator ballot outside Git. Give each retained artifact an opaque ID and lowercase SHA-256; never copy raw room bytes or private traces into this repository.
4. Hash the sanitized environment object exactly as canonical sorted compact UTF-8 JSON. Every state/run record must repeat the same build revision, evaluator ID, and environment digest.
5. In the Xcode Run scheme for this signed Release candidate, add the exact argument `--gate-001-termination-controls` under **Arguments Passed On Launch**. Do not add an environment value, device identifier, account identifier, or filesystem path. Without this argument the Release app must remain on the normal Candidate screen.
6. Run the signed Release candidate on the phone and confirm the root says **GATE-001 termination diagnostics**. Confirm the five-state picker and **Arm abrupt termination** control are visible, while the upload label truthfully says no live upload is configured.

## 2. Prove the consent boundary

1. Start from no camera/capture consent. Attempt capture and verify that denial creates no local `.rrcap` and zero upload references.
2. Retain the denial observation externally, then record only its opaque artifact ID/digest and the sanitized zero/false facts.
3. Grant explicit capture consent. Before each physical run, make the current local state, upload state, and consent state visible to the operator.

## 3. Run the physical duration/state matrix

For each lifecycle state, run both `FX-RRCAP-010S` for TARGET 10 seconds and `FX-RRCAP-060S` for TARGET 60 seconds on the same declared physical candidate. Start capture explicitly, apply queue pressure, blackhole the network, verify upload is paused first, and then physically terminate the instrumented process immediately after the named state:

1. `selected`
2. `image_and_metadata_durable`
3. `journaled`
4. `network_eligible`
5. `server_acknowledged`

This is ten physical termination runs: two durations after each of the five exact canonical states. Do not infer a state from elapsed time, reuse one termination for two states, substitute backgrounding for termination, or substitute simulator/synthetic output. Where the app supports background/foreground observation, record it separately without changing the named termination point. Stop capture explicitly when a control run calls for a normal stop.

For each of those ten runs, perform this exact phone sequence:

1. Launch the signed Release app with `--gate-001-termination-controls`, tap **Start room capture**, review the local-only disclosure, and tap **Accept and Start**. Confirm **Recording locally** and **Upload not configured** are visible.
2. Keep the session active for the fixture duration—10 seconds for `FX-RRCAP-010S` or 60 seconds for `FX-RRCAP-060S`—while applying the separately recorded pressure exercise. The deterministic acknowledgement is an internal fixture event only; it is not a live upload. The network remains blackholed because no live transport is configured.
3. Choose exactly one required state in the **Exact lifecycle state** picker. Tap **Arm abrupt termination**, review the destructive confirmation, then confirm the button labeled with that exact state.
4. Confirm the UI says it is armed for that state. Tap **Save explicit capture frame** exactly once. Do not press Stop, background the app, swipe it away, or reuse this run for another state.
5. The app must disappear immediately because the one-shot control delivers `SIGKILL` only after the selected durable boundary. If it remains open, terminates before the explicit tap, or terminates for a cadence/keyframe observation, retain the failure externally and mark the attempted run invalid/RED.
6. Use Xcode to relaunch the same signed candidate with the same launch argument. Let launch recovery finish, then record whether the UI exposes a hash-verified recovered replay or an archive-verification failure. Never treat the failure card as an accepted replay.
7. Inspect the recovered prefix and externally retain the `.rrcap`, termination log, replay outputs, and screen recording. Enter only the opaque IDs, digests, expected/actual sequences, and other schema-allowed sanitized facts. Start a fresh capture for the next run; do not delete or overwrite the prior raw evidence.

For every duration/state run, record the following sanitized facts and retain the raw source outside Git:

- packet/image digest binding is valid;
- consent is granted and the recovered local state is a hash-valid prefix;
- upload is paused or blackholed;
- zero upload references to non-journaled frames;
- zero earlier-record corruption;
- the expected and actual global sequences prove the exact recovered prefix;
- bounded queue capacity, maximum depth, stale-drop count, pressure applied, network blackhole, and upload-paused-first facts;
- opaque raw-artifact ID/digest plus the same build, evaluator, and environment bindings.

If a separate Phase 2 three-minute NFR timing observation is requested, keep its real duration/queue evidence external and pending until it is actually run. It is not a substitute for either canonical 10-second/60-second capture and does not alter the GATE-001 threshold.

## 4. Replay and evaluate independently

For every duration/state run, execute two independent replays with learned providers disabled. Use distinct opaque replay IDs and the declared evaluator. Recompute the hash-valid contiguous global journal, accepted frame/event projection, accepted order, and RR-JCS digests. The two independent replays must match the expected result and each other exactly.

Inspect explicit consent/local/upload state before accepting each record. Any packet/image mismatch, unexpected upload eligibility, non-journaled upload reference, earlier-record corruption, queue depth above capacity, non-exact prefix, incomplete raw-artifact binding, or replay disagreement is a miss.

## 5. Build the sanitized observation document

1. Construct a new document from the allowlisted fields in `gate-001-physical-observations.schema.json`; do not forward arbitrary tool or operator output.
2. Include exactly five ordered termination observations—one for each canonical state—with exactly the 10-second and 60-second physical runs inside each observation.
3. Validate the closed schema and independent semantic verifier. Unknown/private fields, missing/duplicate/reordered states, wrong fixtures, stale bindings, simulator/synthetic origins, and absent duration facts must fail.
4. Compute the SHA-256 of the exact sanitized observation document bytes. Add that digest as a supporting evidence artifact in the final GateReportV2. Bind the same report decision through the OperatorChecklistV2 unsigned-checklist digest and the externally retained operator-attestation ballot.
5. Set `REROOM_GATE_001_OBSERVATIONS_PATH` only in the invocation environment to the external sanitized document. Do not persist the external path.

## 6. Human decision and kill rule

The accountable human records `GREEN` only when the automated full preflight is fresh, all ten physical terminations are present, both independent replays match for every run, all threshold/consent/privacy checks pass, and the report/checklist/attestation digest chain validates.

If the physical procedure has not been run or is incomplete, leave the gate `UNRUN`/`RUNNING` and pending. If an attempted evaluation misses any required state, duration, binding, invariant, or recovery budget, record `RED` with the exact miss. Valid RED evidence is retained, the gate command exits non-success, upload remains paused first, the valid local prefix is preserved, provider work uses replay fixtures only, and GATE-001 blocks live integration. No network-first variant may proceed.

Run:

```text
REROOM_GATE_001_OBSERVATIONS_PATH=<external-sanitized-document> scripts/verify-phase-02-capture-replay gate
```

Only a zero exit for the bound human `GREEN` pair permits the checkpoint resume signal `approved`.
