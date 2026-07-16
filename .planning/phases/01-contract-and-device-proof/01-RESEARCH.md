# Phase 1: Contract and Device Proof — Research

**Researched:** 2026-07-16  
**Status:** Ready for planning  
**Confidence:** MEDIUM — canonical requirements are verified locally; current dependency/API findings are source-backed, but the Swift JSON Schema candidate and all physical-device results still require Phase 1 measurement.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

### Supported orientations
- **D-01:** P0 Mode A officially supports portrait orientation only.
- **D-02:** When the phone is held sideways, ARKit tracking remains alive, but capture and commit are gated and the UI coaches the user back to portrait.
- **D-03:** If the phone rotates away from portrait during a capture attempt, reject that attempt explicitly, preserve the AR session, and coach a retry.
- **D-04:** GATE-002 physical evidence covers portrait pass cases and a landscape negative/coaching case; all rotation/crop transforms remain covered by synthetic fixtures.

### Device-proof app lifecycle
- **D-05:** The signed minimal device-proof app becomes the Mode A production seed after GATE-013 passes.
- **D-06:** Phase 1 keeps that seed deliberately narrow: portrait gating, permissions, ARKit tracking and planes, and minimal hash-valid FramePacket capture only. Edit UI and provider integration remain out of scope.
- **D-07:** The proof surface is a compact diagnostic checklist with machine-readable evidence export.
- **D-08:** Diagnostic controls remain debug/internal-only in the same app target and are excluded from shipping UI.

### Golden fixture ownership
- **D-09:** Canonical vectors live in one top-level, language-neutral fixture corpus organized by contract/version and RR policy.
- **D-10:** Checked-in declarative inputs plus expected bytes and digests are authoritative. Generators are reproducible tools, not the oracle.
- **D-11:** Valid and invalid fixtures use stable case IDs; invalid cases declare the expected rejection class rather than only pass/fail.
- **D-12:** A fixture revision is accepted only when Swift, JavaScript, and Python agree and the result digests are recorded. Changes create a new immutable fixture revision.

### Evidence and gate approval
- **D-13:** Git contains sanitized manifests, checksums, reports, and tool/device versions. Raw video, screenshots, and logs remain outside Git behind opaque evidence IDs and digests.
- **D-14:** GATE-002 and GATE-013 become green only after automated checks pass and a human explicitly signs the operator checklist.
- **D-15:** Evidence records include device model, OS, Xcode/build revision, capability flags, and signing result while redacting device UUIDs, team IDs, accounts, and user data.
- **D-16:** A failed physical gate is recorded RED with exact evidence. Dependent mobile work stops; only independent contract or B0 work may continue.

### the agent's Discretion
The planner may choose internal module names, test runners, and implementation libraries within these decisions, provided exact compatible versions, license evidence, canonical contracts, and required fallbacks are preserved.

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within Phase 1 scope.
</user_constraints>

## Summary

Phase 1 should be planned as two independently useful tracks joined by one immutable fixture corpus: a pure contract/coordinate kernel that runs in Swift, JavaScript, and Python, and a deliberately small native iPhone proof app. The contract track can progress even if the physical gate is RED; dependent mobile work cannot. [VERIFIED: `.planning/ROADMAP.md`, D-09–D-16]

The highest-risk planning item is not ARKit session startup. It is proving that three runtimes emit and reject exactly the same schema, coordinate, wire, and RFC 8785 digest cases. JavaScript and Python have mature current packages; no authoritative, production-proven native Swift RFC 8785 implementation was found. Plan a small Swift JCS kernel, restricted to the exact canonical profile, and accept it only against checked-in RFC/cross-language vectors. This is the one justified hand-written standards component; SHA-256 itself must use CryptoKit. [CITED: https://www.rfc-editor.org/rfc/rfc8785] [CITED: https://developer.apple.com/documentation/cryptokit/sha256]

The device proof must preserve a live AR session when orientation becomes unsupported. Capture is an attempt state machine: snapshot one `ARFrame`, interface orientation, viewport, epoch, and capture ID; any portrait-to-landscape transition invalidates that attempt before evidence publication. Do not derive orientation from image pixels or a later UI callback. [VERIFIED: ADR-003, RR-COORD-1, D-01–D-04]

A Phase 1 “hash-valid FramePacket” is not a loose JSON sample. CON-001 requires exact image SHA and RRFP-WIRE-1 metadata; its network-eligible durability fields imply a minimal local evidence/journal path for the proof. Plan only the smallest diagnostic implementation needed for GATE-013, and explicitly avoid claiming Phase 2’s complete crash-safe capture lifecycle. [VERIFIED: `docs/contracts/frame-packet.schema.json`, `docs/canonical/DEVELOPMENT_STRATEGY.md`]

## Architectural Responsibility Map

| Responsibility | Owner in Phase 1 | Must not own |
|---|---|---|
| Canonical fields/lifecycle | Existing JSON Schemas and canonical docs | Runtime-specific convenience models changing meaning |
| Fixture truth | Checked-in language-neutral inputs, expected bytes, digests, rejection classes | Generator output at test time |
| Schema validation | Runtime adapters around the same frozen schemas | Silent coercion, defaults, unknown-field tolerance |
| JCS + SHA | Runtime JCS adapter; platform SHA-256 | Locale-sensitive formatting or custom cryptography |
| RR-COORD-1 math | Pure deterministic contract kernel | AR view/controller state |
| ARKit authority | Native device-proof session | JavaScript/Python or learned provider |
| Orientation gate | Native capture-attempt state machine | Stopping/restarting tracking solely because UI is sideways |
| Gate evidence | Sanitizer + machine-readable report + human checklist | Raw evidence committed to Git or an automated green decision |

## Phase Requirements

<phase_requirements>

| ID | Requirement | Research support |
|---|---|---|
| NFR-COORD-001 | Every producer and consumer implements RR-COORD-1 and explicit world-frame versioning exactly. | Use pure projection/transform functions, one immutable corpus, RR-FLOAT-1 comparisons, synthetic rotation/crop coverage, and a physical checkerboard/reset checklist. |
| NFR-CONTRACT-001 | All capture, scene, artifact, and transaction boundaries use exact versioned schemas and named compatibility migrations. | Validate the five closed Draft 2020-12 schemas in all three runtimes; test unknown fields/versions, paths, framing, identity, digests, and deterministic rejection classes before mutation. |
| OPS-DEVICE-001 | Validate the physical device and toolchain before architecture-sensitive mobile work. | Produce a signed portrait-only app seed, install/launch on the base iPhone, verify permission/tracking/planes without LiDAR semantics, and retain sanitized automated plus human evidence. |

</phase_requirements>

## Project Constraints (from AGENTS.md)

- Read canonical authority before changing product meaning. Human locks outrank Accepted ADRs, then Provisional ADRs inside their gates, contracts/Master Spec, PRD, and supporting documents. Stop and request a human decision when authorities conflict. [VERIFIED: `AGENTS.md`]
- Preserve the two byte-exact archived source files; audit records do not override current authority. [VERIFIED: `AGENTS.md`]
- Use the global GSD 1.7 installation and committed `.planning/` surface. Do not create a repository-local GSD install or generated agent/runtime files. The project already exists. [VERIFIED: `AGENTS.md`]
- Planning and evidence work may proceed; product implementation requires an approved phase plan or direct human instruction. Do not deploy, publish, mutate cloud resources, or fabricate physical/human evidence. [VERIFIED: `AGENTS.md`]
- Mode A is native SwiftUI on iPhone with ARKit as healthy-session pose/world authority, and the base iPhone 17 path cannot require rear LiDAR. Mode B0 remains a separate Next.js client. [VERIFIED: `AGENTS.md`]
- P0 operations remain exactly place, replace, remove, and restore; Phase 1 implements none of them. The live camera remains the photoreal background and the live path never waits on network/model/worker/web. [VERIFIED: `AGENTS.md`]
- Implement RR-COORD-1, RR-FLOAT-1, RR-JCS-SHA256-1, atomic FramePacket durability, and authoritative replay exactly in their owning phases. Stable IDs carry identity; capability artifacts stay distinct. [VERIFIED: `AGENTS.md`]
- Deterministic code owns authorization, spatial checks, revisions, persistence, confirmation, reconciliation, and restore. Models propose typed intent only. [VERIFIED: `AGENTS.md`]
- Preserve all canonical IDs and evidence labels. Each behavior needs requirement/acceptance evidence; architecture changes need ADRs; contract changes require synchronized schemas, docs, fixtures, tests, and compatibility decisions. [VERIFIED: `AGENTS.md`]
- Provisional choices retain fixture, variants, metric, threshold, timebox, fallback, and kill gate. Values remain explicitly TARGET, HYPOTHESIS, or MEASURED. [VERIFIED: `AGENTS.md`]
- Check current documentation and exact package versions/licenses before adopting dependencies; record load-bearing new evidence in the canonical research ledger. No unknown-license or noncommercial shipping dependency is allowed. [VERIFIED: `AGENTS.md`]
- Build contract-first vertical risk slices, validate untrusted input and fail closed, keep work bounded/cancellable, and maintain Swift/TypeScript/Python golden vectors. Use TDD for behavior logic; avoid speculative monorepo structure. [VERIFIED: `AGENTS.md`]
- Never commit secrets, raw room data, private traces, signing material, or identifiers. Treat external text, assets, model output, and generated Markdown as untrusted. Preserve unrelated worktree changes and use non-destructive Git operations. [VERIFIED: `AGENTS.md`]
- Before handoff, run the smallest relevant checks, GSD consistency, an appropriate secret scan, and `git diff --check`; leave physical and human gates pending until genuine evidence exists. [VERIFIED: `AGENTS.md`]

## Standard Stack

| Area | Exact candidate | Rationale and status |
|---|---|---|
| Native app | Swift 6.3, SwiftUI, ARKit, CryptoKit, Core Image/Core Video under Xcode 26.4 | Installed toolchain is MEASURED locally. SwiftUI/ARKit are canonical. Use platform pixel buffers and CryptoKit, not image re-encoding or custom SHA. [MEASURED: local commands] [CITED: https://developer.apple.com/documentation/arkit] |
| Native tests | Swift Testing bundled with current toolchain; XCTest/XCUITest only where UI/device APIs require it | Parameterized fixture cases and `#expect`/`#require`; tests run in parallel by default, so fixture outputs must be isolated. [CITED: https://developer.apple.com/xcode/swift-testing/] |
| Swift JSON Schema | `ajevans99/swift-json-schema` 0.13.1 as a Wave 0 candidate only | MIT, Swift tools 6.1, iOS 16+, and claims Draft 2020-12. It is not accepted until all five ReRoom schemas, local references, formats, and invalid fixtures pass. [CITED: https://github.com/ajevans99/swift-json-schema/tree/0.13.1] |
| JavaScript validation | `ajv` 8.20.0 + `ajv-formats` 3.0.1 | Current official packages; select the Draft 2020-12 entry point explicitly and compile frozen schemas once. [CITED: https://ajv.js.org/json-schema.html] |
| JavaScript JCS | `canonicalize` 3.0.0 | Apache-2.0 implementation from the RFC 8785 author ecosystem; no install script reported. Its output is checked against fixture bytes, never treated as the oracle. [CITED: https://github.com/erdtman/canonicalize] |
| Python validation | `jsonschema` 4.26.0 | Use `Draft202012Validator.check_schema` and programmatic validators; do not use the deprecated bundled CLI. [CITED: https://python-jsonschema.readthedocs.io/en/stable/validate/] |
| Python JCS | `rfc8785` 0.1.4 | Apache-2.0, pure-Python, no declared runtime dependencies. Validate against the same fixture oracle. [CITED: https://github.com/trailofbits/rfc8785.py/tree/v0.1.4] |
| JS/Python tests | Node 22 built-in `node:test`; Python 3.13 `unittest` | Avoids extra Phase 1 test-runner dependencies while supporting parameterized corpus loops. [MEASURED: local toolchain] |

### Package Legitimacy Audit

| Package | Registry result | Decision |
|---|---|---|
| `ajv@8.20.0` | Exists, MIT, official repository, no postinstall, healthy registry use | Accept after lockfile integrity is recorded. [MEASURED: npm metadata and GSD package audit] |
| `ajv-formats@3.0.1` | Exists, MIT, official repository, no postinstall | Accept after lockfile integrity is recorded. [MEASURED: npm metadata and GSD package audit] |
| `canonicalize@3.0.0` | Exists, Apache-2.0, official repository, no postinstall | Accept after fixture parity and lockfile integrity. [MEASURED: npm metadata and GSD package audit] |
| `jsonschema==4.26.0` | Exists, MIT, official repository; GSD seam returned **SUS** solely because PyPI download counts were unavailable | Require a human-verify checkpoint for source/tag/license/hash before adoption; the signal is incomplete, not evidence of maliciousness. [MEASURED: GSD package audit] |
| `rfc8785==0.1.4` | Exists, Apache-2.0, Trail of Bits repository; GSD seam returned **SUS** solely because PyPI download counts were unavailable | Require the same human-verify checkpoint and pin the wheel/sdist hash. [MEASURED: GSD package audit] |
| `swift-json-schema` 0.13.1 | Repository/tag/license and manifest inspected; runtime compatibility unmeasured | Candidate only. Planner must create an explicit accept/fallback task before adding it. [CITED: https://github.com/ajevans99/swift-json-schema/releases/tag/0.13.1] |

If the Swift candidate fails any ReRoom schema keyword/reference case, do not weaken the schemas. Fall back to a narrow in-repo validator for the frozen CON-001–CON-005 profile, accepted by the complete invalid/valid fixture set, while JS/Python remain independent Draft 2020-12 reference validators. Record the choice and license evidence in `RESEARCH_LEDGER.md` only when adopted. [RECOMMENDED]

## Architecture Patterns

### Pattern 1: Immutable oracle, replaceable runners

```text
fixtures/<contract-or-policy>/<version>/<revision>/
               │
       checked-in oracle
     input + bytes + digest
      + rejection class
        ┌──────┼────────┐
        ▼      ▼        ▼
      Swift    JS     Python
        └──────┼────────┘
               ▼
     normalized result digest
               ▼
      revision acceptance report
```

Each runner must emit the same small result envelope, for example `case_id`, `verdict`, `rejection_class`, and `output_digest`. A generator may propose the next revision but cannot overwrite expected results. Revisions are append-only. [VERIFIED: D-09–D-12]

### Pattern 2: Pure kernel beside an imperative device shell

Keep schema loading, strict JSON decoding, JCS, hashing, RR-FLOAT-1, transforms, projection, path validation, and evidence sanitization free of ARKit/UIKit state. The app shell owns permission flow, `ARSession`, plane callbacks, interface orientation, and export UX. This lets most acceptance run on the host while the physical gate proves only what a simulator cannot. [RECOMMENDED] [VERIFIED: OPS-DEVICE-001]

### Pattern 3: Capture-attempt state machine

```text
idle ──portrait+permission+tracking──> staged(frame, epoch, orientation)
  ▲                                      │
  │                                      ├─ orientation changes ─> rejected
  │                                      ├─ frame/epoch changes ─> rejected
  │                                      └─ validate+hash+journal ─> exported
  └──────────────── session remains alive in every outcome ────────────────┘
```

An attempt snapshots exactly one `ARFrame` and its metadata. Later orientation, viewport, or world epoch values must never be mixed into it. Landscape disables the attempt/commit capability and produces coaching, while ARKit continues tracking. [VERIFIED: D-01–D-04, ADR-003]

### Pattern 4: Evidence is a gated state machine

Use `UNRUN`, `RUNNING`, `GREEN`, and `RED`. Automation may produce a passing report but may not set a physical gate GREEN without the signed human checklist. A failure records exact sanitized evidence and routing per D-16. [VERIFIED: D-13–D-16]

## Recommended Project Structure

Create only Phase 1-owned surfaces; do not scaffold later web/provider/compositor packages. [VERIFIED: `AGENTS.md`]

```text
fixtures/
  contracts/1.0.0/rev-001/
  policies/RR-COORD-1/rev-001/
  policies/RR-JCS-SHA256-1/rev-001/
native/
  ReRoomDeviceProof.xcodeproj
  ReRoomDeviceProof/          # SwiftUI + ARKit shell, debug evidence UI
  ReRoomContractKernel/       # pure Swift contract/coordinate code
  ReRoomContractKernelTests/
tools/
  javascript/                 # Ajv/JCS runner and node:test cases
  python/                     # jsonschema/JCS runner and unittest cases
scripts/
  verify-phase-01-contracts   # invokes all three runners, no oracle generation
evidence/
  templates/                  # sanitized report/checklist schemas only
```

Names are planner discretion. The important boundaries are top-level language-neutral fixtures, a reusable native seed, pure testable kernel code, and sanitized evidence separate from raw external artifacts. [VERIFIED: D-05, D-09, D-13]

## Don’t Hand-Roll

- Do not implement SHA-256; use CryptoKit, Node crypto, and Python hashlib. [CITED: https://developer.apple.com/documentation/cryptokit/sha256]
- Do not create a generic JSON Schema engine if `swift-json-schema` passes the compatibility spike. If it fails, implement only the frozen ReRoom keyword/profile surface and fixture every rejection. [RECOMMENDED]
- Do not hand-code image orientation/crop heuristics. Use ARKit’s `displayTransform(for:viewportSize:)` and the exact RR-COORD-1 convention. [CITED: https://developer.apple.com/documentation/arkit/arframe/displaytransform(for:viewportsize:)]
- Do not invent a second wire envelope, ID family, tolerance, gate status, or evidence lifecycle. [VERIFIED: canonical contracts/glossary]
- Do not regenerate expected bytes/digests during ordinary tests. [VERIFIED: D-10]
- Do not use an image re-encode to obtain digest bytes when the contract names the captured payload bytes. [VERIFIED: CON-001]

The exception is a narrow Swift RFC 8785 serializer. No adequate authoritative native implementation was found. It must enforce I-JSON constraints, reject duplicate names/non-finite values/invalid Unicode, preserve strings as-is, serialize numbers compatibly with ECMAScript, sort object keys by UTF-16 code units recursively, emit no whitespace, and hash UTF-8 bytes. Accept only via the immutable corpus. [CITED: https://www.rfc-editor.org/rfc/rfc8785]

## Common Pitfalls

1. **Draft drift:** importing Ajv’s default class instead of its 2020 entry point can silently select different schema semantics. Compile each schema under its declared `$schema` and reject unknown IDs/versions. [CITED: https://ajv.js.org/json-schema.html]
2. **Parser differential before JCS:** common parsers may accept duplicate keys and retain only one. Duplicate detection must occur while parsing, before canonicalization. [CITED: https://www.rfc-editor.org/rfc/rfc8785]
3. **Number drift:** Swift `Double` formatting, Python JSON, and JavaScript stringify are not interchangeable by default. Include boundaries, negative zero, exponent transitions, and rejection of NaN/infinity. [CITED: https://www.rfc-editor.org/rfc/rfc8785]
4. **Orientation race:** reading interface orientation after selecting the frame can bind metadata from a different UI state. Snapshot frame/orientation/viewport/epoch atomically at attempt start. [VERIFIED: RR-COORD-1]
5. **Restarting ARKit in landscape:** that destroys continuity and contradicts D-02. Gate capture capability, not session tracking. [VERIFIED: D-02]
6. **Overclaiming durability:** satisfying the minimal GATE-013 packet proof is not evidence that Phase 2’s five-state crash-safe lifecycle is complete. Label the boundary. [VERIFIED: phase scope]
7. **Accidental diagnostic shipping:** hiding a view is insufficient. Exclude debug controls using build configuration/compilation conditions and add an archive inspection test. [VERIFIED: D-08]
8. **Raw evidence leakage:** device IDs, team IDs, filesystem paths, signing accounts, screenshots, and logs must be sanitized before entering Git. Store only opaque IDs and content digests for raw artifacts. [VERIFIED: D-13–D-15]
9. **Parallel-test collisions:** Swift Testing runs tests in parallel by default. Each fixture case gets its own temporary output location; use serialization only for unavoidable shared device resources. [CITED: https://developer.apple.com/xcode/swift-testing/]

## Code Examples

Illustrative APIs only; names remain planner discretion.

```swift
struct CaptureSnapshot: Sendable {
    let frameID: String
    let worldEpochID: String
    let interfaceOrientation: UIInterfaceOrientation
    let viewportSize: CGSize
    let timestamp: TimeInterval
}

enum CaptureRejection: String, Error, Codable {
    case unsupportedOrientation
    case orientationChanged
    case worldEpochChanged
    case schemaInvalid
    case digestMismatch
}
```

The actor/controller that owns `ARSession` should stage one snapshot and invalidate it on interface-orientation or epoch change; pure code receives the already-snapshotted values. Avoid blanket `@MainActor` on the contract kernel. [RECOMMENDED: project Swift concurrency/SwiftUI skills]

```javascript
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

const ajv = new Ajv2020({ allErrors: true, strict: true });
addFormats(ajv);
// Add the five frozen schemas by canonical $id, then compile and run cases.
```

[CITED: https://ajv.js.org/json-schema.html]

```python
from jsonschema import Draft202012Validator
import rfc8785

Draft202012Validator.check_schema(schema)
errors = sorted(Draft202012Validator(schema).iter_errors(instance),
                key=lambda error: list(error.absolute_path))
canonical_bytes = rfc8785.dumps(instance)
```

[CITED: https://python-jsonschema.readthedocs.io/en/stable/validate/] [CITED: https://github.com/trailofbits/rfc8785.py]

## State of the Art

- JSON Schema Draft 2020-12 remains the declared current dialect used by the repository. All runtimes must select it explicitly rather than relying on library defaults. [CITED: https://json-schema.org/draft/2020-12]
- RFC 8785 remains the relevant JSON canonicalization standard. Current JS and Python implementations exist, but Swift availability is materially weaker; cross-runtime fixture agreement is therefore a first-class gate, not a unit-test detail. [CITED: https://www.rfc-editor.org/rfc/rfc8785] [CITED: https://github.com/cyberphone/json-canonicalization/tree/master]
- ARKit plane detection is opt-in on `ARWorldTrackingConfiguration`, supports horizontal and vertical detection, and delivers `ARPlaneAnchor` updates. It does not imply rear-LiDAR dependence. [CITED: https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/planedetection]
- Swift Testing supports parameterized tests and parallel execution in the current toolchain, fitting the fixture-corpus model. XCTest remains appropriate for UI/device-bound checks. [CITED: https://developer.apple.com/xcode/swift-testing/]

## Assumptions Log

| Assumption | Classification | Planning treatment |
|---|---|---|
| The five checked-in schemas remain unchanged throughout Phase 1 | HYPOTHESIS | Hash them into the fixture manifest; schema changes create a reviewed new fixture revision. |
| `swift-json-schema` 0.13.1 supports every keyword/reference/format used by CON-001–CON-005 | HYPOTHESIS | Resolve in Wave 0 with a timeboxed compatibility matrix and named fallback. |
| A base iPhone 17 can sign/install/launch the seed and run required ARKit plane tracking without LiDAR semantics | HYPOTHESIS | Physical GATE-013; simulator evidence cannot resolve it. |
| Local toolchain versions are Xcode 26.4, Swift 6.3, Node 22.22.3, npm 10.9.8, and Python 3.13.12 | MEASURED | Record exact command output in sanitized build evidence; do not treat this workstation as the required CI baseline. |
| A paired base iPhone 17 is discoverable from the workstation | MEASURED | Device identifier is sensitive and must never enter Git; signing/install/launch remain unmeasured. |
| Minimal GATE-013 capture can be built without completing all Phase 2 durability behavior | HYPOTHESIS | Define the explicit minimal journal/export boundary in the plan and prohibit broader durability claims. |

## Open Questions for Planning

1. What minimum iOS deployment target should the app seed declare? Canonical authority specifies the base device, not a minimum OS. The plan must make this explicit before selecting package/platform settings. [UNRESOLVED]
2. Does `swift-json-schema` 0.13.1 pass all schema features, local `$ref` resolution, format behavior, and deterministic error normalization required by the corpus? [UNRESOLVED — Wave 0]
3. Which precise subset of the FramePacket durability/journal fields constitutes the minimal GATE-013 diagnostic capture without claiming Phase 2 completion? Resolve against CON-001 and the gate wording before implementation. [UNRESOLVED — planning decision within canonical constraints]
4. Who is the named human operator/approver for GATE-002 and GATE-013, and where are raw artifacts retained outside Git? [UNRESOLVED — human input needed before gate execution]

## Environment Availability

| Capability | Status on 2026-07-16 | Consequence |
|---|---|---|
| Xcode / `xcodebuild` / `xcrun` | MEASURED available, Xcode 26.4 build 17E192 | Native build work can begin after plan approval. |
| Swift | MEASURED 6.3 | Swift Testing and CryptoKit approach available. |
| Node/npm | MEASURED 22.22.3 / 10.9.8 | JS fixture runner available. |
| Python | MEASURED 3.13.12 | Python fixture runner available; project dependencies still need isolated pins. |
| `jq`, `git`, `shasum` | MEASURED available | Suitable for orchestration/report checks, not canonical JSON generation. |
| Base iPhone 17 discovery | MEASURED paired/available, with a device-provider warning | Do not record its identifier. Signed build, install, launch, permissions, tracking, and planes are UNRUN. |
| Product code/test infrastructure | MEASURED absent | Wave 0 must create only the minimal Phase 1 structure and test commands. |

## Validation Architecture

### Wave 0 validation tasks

1. Create the immutable fixture manifest, case-ID/rejection taxonomy, and schema hashes before implementation.
2. Build the JS and Python reference runners; independently reproduce expected bytes/digests.
3. Timebox the Swift schema-candidate matrix and Swift JCS kernel against the same cases; invoke the named fallback if any mandatory feature fails.
4. Establish one cross-language command that fails on missing, extra, changed, or disagreeing results.
5. Define sanitized evidence JSON/checklist schemas and assert that forbidden identifier/path fields cannot be serialized.
6. Establish debug/release build checks proving diagnostic controls are absent from the release surface.

### Requirement-to-evidence map

| Requirement/gate | Fast checks | Phase gate evidence |
|---|---|---|
| NFR-CONTRACT-001 | Runtime schema/JCS/wire unit tests for touched cases | All five schemas plus valid/invalid corpus agree across Swift/JS/Python; recorded result digest and immutable revision report |
| NFR-COORD-001 | Pure Swift/JS/Python projection and RR-FLOAT-1 cases | Synthetic transforms within one encoded pixel, duplicated fields agree, physical portrait checkerboard passes, landscape negative coaches, reset emits new epoch/correction |
| OPS-DEVICE-001 / GATE-013 | Generic iOS build and release-surface inspection | Signed base-device install/launch; camera permission, ARKit tracking, plane callbacks, minimal hash-valid packet; sanitized build record; human checklist signature |
| GATE-002 | Synthetic rotation/crop/reset fixtures | Physical portrait pass plus landscape negative and explicit reset evidence; human checklist signature |

Suggested commands are planning targets, not current evidence:

```text
xcodebuild test -project native/ReRoomDeviceProof.xcodeproj -scheme ReRoomDeviceProof -destination 'platform=iOS Simulator,name=iPhone 17'
node --test tools/javascript/test/*.test.mjs
python3 -m unittest discover -s tools/python/tests -p 'test_*.py'
scripts/verify-phase-01-contracts
git diff --check
```

Use focused runtime tests after each task, the cross-language command at each wave boundary, and the full automated suite before any physical run. The device/human checklist is the final gate and cannot be delegated to simulation or fabricated by automation. [VERIFIED: D-14, OPS-DEVICE-001]

## Security Domain

Phase 1 activates ASVS-style input-validation and cryptography concerns, not application authentication/session management. [RECOMMENDED]

- Treat schemas, fixture files, manifests, JSON instances, relative paths, evidence exports, and external package content as untrusted. Enforce file size/depth/count limits, closed schemas, stable ID patterns, and fail-before-mutation behavior. [VERIFIED: NFR-CONTRACT-001]
- Reject absolute paths, `..`, encoded traversal, NUL, symlink escapes, duplicate normalized paths, and digest/path disagreement before opening payloads. Resolve under one allowed root and verify containment after canonicalization. [VERIFIED: contract path invariants]
- Detect duplicate JSON names before JCS; reject non-finite numbers and invalid Unicode. Do not let different runtime parsers normalize invalid input differently. [CITED: https://www.rfc-editor.org/rfc/rfc8785]
- Use platform SHA-256 and compare exact bytes/digests. Fixture manifests should include schema/tool/source hashes so oracle tampering is visible. [VERIFIED: RR-JCS-SHA256-1]
- Make debug evidence UI unavailable in release builds and test that exclusion. Diagnostics must never expose raw device UUIDs, signing team/account, user paths, or room content. [VERIFIED: D-08, D-13–D-15]
- Sanitize first, serialize second. Raw artifacts remain outside Git behind opaque evidence IDs and SHA-256 digests; a secret/identifier scan is part of handoff. [VERIFIED: `AGENTS.md`, D-13]
- Model orientation/capture transitions as a single-owner state machine to prevent mixed-frame metadata and time-of-check/time-of-use publication. [RECOMMENDED]

## Sources

### Canonical repository authority

- `docs/canonical/README.md`
- `docs/adr/ADR-002-native-iphone-and-web-split.md`
- `docs/adr/ADR-003-arkit-authority-and-coordinates.md`
- `docs/adr/ADR-005-realitykit-first-compositor.md`
- `docs/canonical/MASTER_TECHNICAL_SPEC.md`
- `docs/canonical/PRD.md`
- `docs/canonical/DEVELOPMENT_STRATEGY.md`
- `docs/canonical/TEST_AND_EVALUATION_PLAN.md`
- `docs/canonical/RISK_AND_KILL_GATES.md`
- `docs/canonical/GLOSSARY_AND_ID_REGISTRY.md`
- `docs/canonical/RESEARCH_LEDGER.md`
- `docs/contracts/README.md` and all five 1.0.0 schemas
- `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md`, and `01-CONTEXT.md`

### Current external primary sources

- [RFC 8785: JSON Canonicalization Scheme](https://www.rfc-editor.org/rfc/rfc8785)
- [JSON Schema Draft 2020-12](https://json-schema.org/draft/2020-12)
- [Apple ARKit documentation](https://developer.apple.com/documentation/arkit)
- [Apple ARFrame display transform](https://developer.apple.com/documentation/arkit/arframe/displaytransform(for:viewportsize:))
- [Apple Swift Testing](https://developer.apple.com/xcode/swift-testing/)
- [Apple CryptoKit SHA256](https://developer.apple.com/documentation/cryptokit/sha256)
- [Ajv JSON Schema versions](https://ajv.js.org/json-schema.html)
- [python-jsonschema validation API](https://python-jsonschema.readthedocs.io/en/stable/validate/)
- [Swift JSON Schema 0.13.1](https://github.com/ajevans99/swift-json-schema/tree/0.13.1)
- [canonicalize](https://github.com/erdtman/canonicalize)
- [Trail of Bits rfc8785.py](https://github.com/trailofbits/rfc8785.py/tree/v0.1.4)

## Research Metadata

- Research depth: planning-critical, bounded by Phase 1.
- Local canonical confidence: HIGH.
- External API/package confidence: MEDIUM pending lock/hash and compatibility verification.
- Physical-device confidence: UNRUN; discoverability is not gate evidence.
- Research ledger change: none. Dependencies remain candidates; adopted load-bearing evidence must be recorded when the plan resolves them.
- Worktree preservation: the pre-existing `.planning/config.json` modification was not touched.
