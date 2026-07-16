# Phase 1: Contract and Device Proof - Pattern Map

**Mapped:** 2026-07-16  
**Proposed file surfaces classified:** 15  
**Executable analogs found:** 0 / 15  
**Repository state:** Greenfield product implementation; canonical schemas and planning artifacts are authority, not source-code analogs.

## Mapping Result

The repository has no Swift, JavaScript, TypeScript, or Python product implementation outside project skills. Consequently, no proposed Phase 1 file has a legitimate executable analog to copy. This is consistent with `docs/contracts/README.md:3`, which explicitly states that the schemas are documentation-grade field/lifecycle authority and that no product code exists yet.

The planner should use the architecture and validation patterns in `01-RESEARCH.md`, while binding behavior to the existing canonical schemas and stable IDs. It must not present a schema, ADR, planning file, or skill as an implementation pattern, and it must not scaffold later Mode B0, provider, compositor, or transaction surfaces.

## File Classification

Paths below are proposed surfaces inferred from the recommended Phase 1 structure in `01-RESEARCH.md:164-187`. Exact leaf names remain planner discretion; rows using globs classify a bounded file family rather than requiring every example leaf.

| New file surface | Role | Data flow | Closest executable analog | Match quality |
|---|---|---|---|---|
| `fixtures/contracts/1.0.0/rev-001/**` | config / test data | file-I/O, batch validation | None; `docs/contracts/*.schema.json` is field authority only | greenfield |
| `fixtures/policies/RR-COORD-1/rev-001/**` | config / test data | transform, batch validation | None; glossary and coordinate tests are semantic authority only | greenfield |
| `fixtures/policies/RR-JCS-SHA256-1/rev-001/**` | config / test data | transform, file-I/O, batch validation | None; glossary and contract digest scopes are semantic authority only | greenfield |
| `native/ReRoomDeviceProof.xcodeproj/**` | config | build configuration | None | greenfield |
| `native/ReRoomDeviceProof/*App.swift` and diagnostic checklist views | component | event-driven UI | None | greenfield |
| `native/ReRoomDeviceProof/*ARSession*.swift` | controller | streaming, event-driven | None; ADR-002/ADR-003 define ownership only | greenfield |
| `native/ReRoomDeviceProof/*CaptureAttempt*.swift` | model / controller | event-driven state transition | None; `01-RESEARCH.md:147-158` is a design constraint only | greenfield |
| `native/ReRoomDeviceProof/*EvidenceExport*.swift` | service | transform, file-I/O | None | greenfield |
| `native/ReRoomContractKernel/**/*.swift` | utility / model | transform, request-response | None; canonical schemas remain external validation inputs | greenfield |
| `native/ReRoomContractKernelTests/**/*.swift` | test | batch validation | None | greenfield |
| `tools/javascript/package.json` plus lockfile | config | dependency resolution | None | greenfield |
| `tools/javascript/**/*.{mjs,js}` | utility / test | transform, file-I/O, batch validation | None | greenfield |
| `tools/python/{requirements*,pyproject.toml}` and `tools/python/**/*.py` | config / utility / test | transform, file-I/O, batch validation | None | greenfield |
| `scripts/verify-phase-01-contracts` | utility | batch orchestration | None | greenfield |
| `evidence/templates/*.schema.json` and sanitized checklist/report templates | config / test data | file-I/O, state transition | None; gate documents define evidence semantics only | greenfield |

## Pattern Assignments

### Language-neutral fixture corpus

**Applies to:**

- `fixtures/contracts/1.0.0/rev-001/**`
- `fixtures/policies/RR-COORD-1/rev-001/**`
- `fixtures/policies/RR-JCS-SHA256-1/rev-001/**`

**Executable analog:** None.

**Use this researched pattern:** `01-RESEARCH.md:123-141` defines one immutable checked-in oracle consumed independently by Swift, JavaScript, and Python. Each revision carries declarative inputs, exact expected bytes/digests, stable case IDs, expected rejection classes, and a normalized result envelope. Generators may propose a new append-only revision but may not regenerate expectations during ordinary tests.

**Authority anchors, not copy sources:**

- `docs/contracts/README.md:15-22` requires exact 1.0 rejection behavior, RR-COORD-1/RR-FLOAT-1, the five capture states, RRFP-WIRE-1, and RR-JCS-SHA256-1.
- `docs/contracts/README.md:30-33` supplies path and Draft 2020-12 constraints.
- `docs/contracts/README.md:37-40` requires new fixture sets for contract evolution and fixed compatibility verdicts.
- `docs/contracts/frame-packet.schema.json:1-52` owns the exact CON-001 object shape and required members.
- All five schemas must be copied into no runtime-specific fork; runners load the checked-in authorities by canonical `$id`.

**Planner constraint:** Define one manifest/case-envelope shape for the corpus, but do not invent a new product contract or stable ID family. Fixture metadata that is not a product boundary must remain clearly test-only.

### Pure Swift contract and coordinate kernel

**Applies to:**

- `native/ReRoomContractKernel/**/*.swift`
- `native/ReRoomContractKernelTests/**/*.swift`

**Executable analog:** None.

**Use this researched pattern:** `01-RESEARCH.md:143-145` keeps strict JSON decoding, schema loading, JCS, SHA-256, RR-FLOAT-1, coordinate transforms/projection, path checks, and evidence sanitization free of ARKit/UIKit state. Swift Testing should parameterize the shared corpus and isolate per-case temporary output.

**Authority anchors, not copy sources:**

- `docs/contracts/frame-packet.schema.json:31-51` owns the protocol version, coordinate convention, transforms, durability, payload hash, and wire-framing members.
- `docs/contracts/frame-packet.schema.json:55-70` owns stable ID patterns, exact relative-path constraints, decimal timestamp representation, and finite binary32 range.
- `docs/contracts/README.md:16-22` owns coordinate, epoch, lifecycle, wire, journal, and digest invariants.

**Planner constraint:** Keep the Swift JCS implementation narrow and fixture-gated. Use CryptoKit for SHA-256. Treat the candidate Swift schema package as a timeboxed compatibility seam with the documented fallback; do not weaken schemas when the candidate fails.

### JavaScript and Python reference runners

**Applies to:**

- `tools/javascript/package.json` and lockfile
- `tools/javascript/**/*.{mjs,js}`
- `tools/python/{requirements*,pyproject.toml}`
- `tools/python/**/*.py`

**Executable analog:** None.

**Use this researched pattern:** Independent runners load the same checked-in schemas and fixture revisions, emit the same normalized result envelope, and fail on missing, extra, changed, or disagreeing results. JavaScript explicitly selects Ajv Draft 2020-12; Python explicitly selects `Draft202012Validator`. Neither runtime generates the oracle.

**Authority anchors, not copy sources:** `docs/contracts/README.md:3-11` identifies the five frozen schema authorities; `docs/contracts/README.md:15` requires closed exact-version behavior; `docs/contracts/README.md:33` fixes the dialect.

**Planner constraint:** Pin exact candidate versions and artifact integrity only after the research-mandated package verification checkpoints. Keep runners offline, deterministic, and bounded against untrusted fixture size/depth/count.

### Cross-language verification entry point

**Applies to:** `scripts/verify-phase-01-contracts`

**Executable analog:** None.

**Use this researched pattern:** Invoke the Swift, JavaScript, and Python runners against the same immutable corpus; normalize and compare result sets; fail closed for missing/extra case IDs, rejection-class drift, byte/digest drift, or runner failure. `01-RESEARCH.md:298-305` defines the Wave 0 ordering, and `01-RESEARCH.md:318-323` provides the target command surface.

**Planner constraint:** The script orchestrates verification only. It must not generate authoritative expected outputs, mutate a fixture revision, install unpinned dependencies, or mark a physical gate GREEN.

### Native device-proof shell

**Applies to:**

- `native/ReRoomDeviceProof.xcodeproj/**`
- app entry and diagnostic checklist views
- AR session owner
- capture-attempt state owner
- evidence exporter

**Executable analog:** None.

**Use this researched pattern:**

- Keep one imperative app shell around a pure kernel (`01-RESEARCH.md:143-145`).
- Model capture as `idle -> staged -> rejected|exported`, snapshotting one frame/orientation/viewport/epoch/capture ID at attempt start (`01-RESEARCH.md:147-158`).
- Gate capture in landscape while keeping ARKit tracking alive.
- Keep diagnostics in the same target but exclude them from release builds, with an archive/release-surface test.
- Build only portrait gating, deterministic camera/microphone authorization (without audio capture), ARKit tracking/planes, minimal hash-valid FramePacket capture, checklist state, and sanitized export. Editing, providers, compositing, audio recording, and Mode B0 remain absent.

**Authority anchors, not copy sources:**

- `docs/contracts/frame-packet.schema.json:8-28` lists the exact minimum FramePacket members.
- `docs/contracts/frame-packet.schema.json:37-51` binds sequence, timestamp, RR-COORD-1, image/intrinsics/transforms, tracking, durability, idempotency, and payload SHA.
- `docs/contracts/rrcap-manifest.schema.json:1-24` defines the record-first inventory and authoritative journal surface if the minimal diagnostic evidence uses a manifest.
- ADR-002 assigns SwiftUI flow/UI and native `ARSession` ownership; ADR-003 assigns ARKit world authority and exact coordinate semantics. Neither is an implementation template.

**Planner constraint:** Do not claim full Phase 2 atomic durability. Resolve and name the smallest GATE-013 journal/export boundary against CON-001 and gate language before implementing it.

### Sanitized evidence and gate templates

**Applies to:** `evidence/templates/*.schema.json` and corresponding checked-in sanitized reports/checklists.

**Executable analog:** None.

**Use this researched pattern:** Evidence state is exactly `UNRUN`, `RUNNING`, `GREEN`, `RED`, or `WAIVED_BY_HUMAN`. Automation may emit only `UNRUN`, `RUNNING`, or `RED`; it cannot emit `GREEN` or `WAIVED_BY_HUMAN`. `GREEN` requires passing automated evidence plus an explicit signed human checklist. `WAIVED_BY_HUMAN` requires an accountable human, the changed human-locked promise, a locked-decision change ID, and synchronized PRD plus affected-ADR digests; a timebox overrun is insufficient. Sanitize first, serialize second. Raw video, screenshots, logs, signing details, device identifiers, user paths, and room data remain outside Git behind opaque IDs and SHA-256 digests.

**Authority anchors, not copy sources:** `01-RESEARCH.md:309-326` maps requirements to automated and physical evidence and states that device/human evidence cannot be delegated or fabricated. `01-RESEARCH.md:330-338` defines path/input limits, identifier redaction, and release exclusion.

**Planner constraint:** Add schema tests proving forbidden fields cannot be serialized and automation cannot emit GREEN or WAIVED_BY_HUMAN. A failed physical gate records RED evidence and stops dependent mobile work while leaving independent contract work runnable; waiver is a human lock-change workflow, never an automated escape hatch.

## Shared Patterns

### Field and lifecycle authority

**Source:** `docs/contracts/README.md:3-33` and the five `docs/contracts/*.schema.json` files.  
**Apply to:** Every runtime model, validator, fixture, and evidence producer.

Schemas own field shape and lifecycle. Runtime convenience types may not redefine versions, variants, required fields, identifiers, paths, tolerances, coordinate meaning, or digest scopes. Unknown inputs fail before mutation.

### Immutable oracle, replaceable runners

**Source:** `01-RESEARCH.md:123-141`.  
**Apply to:** Swift, JavaScript, Python, the fixture corpus, and the verifier.

Expected bytes/digests and rejection classes are checked in. Each runtime is independently replaceable and reports comparable case results. Agreement accepts a new immutable fixture revision; generators are never the test-time oracle.

### Pure kernel, imperative shell

**Source:** `01-RESEARCH.md:143-145`.  
**Apply to:** Native kernel and device-proof app.

ARKit/UI state stays in the shell. Deterministic parsing, validation, hashing, coordinate math, path checking, and sanitization stay host-testable and free of UIKit/ARKit ownership.

### Single-owner transition state

**Source:** `01-RESEARCH.md:147-158` and `01-RESEARCH.md:338`.  
**Apply to:** Capture attempt and gate evidence state.

One owner snapshots state and authorizes transitions. Orientation or epoch changes invalidate the staged attempt without restarting the healthy AR session. Evidence cannot advance to GREEN through automation alone.

### Fail-closed untrusted input handling

**Source:** `01-RESEARCH.md:328-338` and `docs/contracts/README.md:30`.  
**Apply to:** Fixture readers, schema resolvers, relative paths, JCS parsers, package inputs, exports, and verification orchestration.

Bound size/depth/count, detect duplicate JSON keys before JCS, reject non-finite/invalid Unicode, prevent traversal/symlink escape, compare exact bytes and digests, and publish no partially validated mutation.

### No authentication/database/server pattern in Phase 1

No repository authentication, middleware, database, API handler, network transport, or server error-envelope pattern exists or is required by this phase. The planner must not introduce one merely to create a familiar architecture.

## No Analog Found

| File surface | Reason |
|---|---|
| Fixture corpus | No executable fixtures or test harness exist; canonical schemas define meaning only. |
| Native Xcode project and SwiftUI shell | No Xcode project or Swift source exists. |
| ARKit session/capture state | No session controller, streaming producer, or state-machine implementation exists. |
| Swift contract kernel/tests | No Swift module or test target exists. |
| JavaScript runner/tests | No JavaScript package, source, or tests exist. |
| Python runner/tests | No Python package, source, or tests exist. |
| Cross-language verification script | No repository automation script exists. |
| Evidence templates/export | Gate prose exists, but no executable evidence schema, sanitizer, exporter, or checklist implementation exists. |

## Planning Guardrails

1. Treat every Phase 1 implementation file as greenfield and cite `01-RESEARCH.md` plus canonical authority in each plan action; do not claim a repository code pattern that does not exist.
2. Create only Phase 1-owned directories from `01-RESEARCH.md:168-184`; avoid speculative workspace, web, gateway, provider, compositor, or edit-operation scaffolding.
3. Keep `docs/contracts/*.schema.json` unchanged unless a separately authorized contract change synchronizes every required authority and fixture surface.
4. Resolve the minimum iOS deployment target, Swift schema fallback seam, minimal GATE-013 durability boundary, and human operator/raw-artifact location as explicit plan checkpoints.
5. Preserve the pre-existing `.planning/config.json` worktree modification and all unrelated user changes.

## Metadata

**Analog search scope:** Entire repository excluding preserved archived sources, generated `.git` state, and project-skill implementation files.  
**Product source files found:** 0.  
**Canonical authorities inspected:** root `AGENTS.md`, canonical README, ADR-002, ADR-003, contracts README, CON-001/CON-002 authority surfaces, relevant glossary/test/gate/spec references, `01-CONTEXT.md`, and `01-RESEARCH.md`.  
**Pattern extraction date:** 2026-07-16.
