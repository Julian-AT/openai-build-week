# AI-SPEC — Phase 09: AI Design Copilot Demo

> AI design contract generated with `$gsd-ai-integration-phase` from the
> approved sprint decisions and verified official OpenAI documentation. It is
> consumed by GSD planning, execution, and eval review.

## 1. System Classification

**System Type:** Hybrid structured extraction and optional conversational
ingress; not an autonomous agent.

**Description:** ReRoom users describe a room-edit intention by text, one
explicitly consented image, or push-to-talk. GPT-5.6 Sol converts that untrusted
input into a typed design proposal over four existing operations and three
local catalog assets. Good output is schema-valid, context-bound, useful enough
to preview, and incapable of authorizing any canonical mutation.

**Critical Failure Modes:**

1. Model output supplies or changes target, transform, session, branch, world,
   revision, confirmation, commit, restore execution, artifact activation, or
   another authority-bearing field.
2. A stale response is previewed against a different native scene revision,
   target, or world-frame epoch.
3. A secret, room frame, prompt, transcript, or model output is retained or
   logged outside the explicitly bounded path.
4. Model/network failure blocks the camera/render loop or the complete typed,
   tap, preview, confirm, commit, and restore journey.
5. The model invents an asset, operation, URL, tool, or constraint outside the
   closed server-owned allowlist.

## 1b. Domain Context

**Industry Vertical:** Consumer spatial computing and interior-design
assistance.

**User Population:** Hackathon judges and users editing one controlled chair or
small table in a real room from an iPhone.

**Stakes Level:** Medium for user trust/privacy; high for deterministic state
integrity. The proposal itself is nonmutating.

**Output Consequence:** A validated output may populate a native preview. A
separate user action and deterministic reducer decide whether any edit commits.

### What Domain Experts Evaluate Against

| Dimension | Good | Bad | Stakes | Source |
|---|---|---|---|---|
| Intent fit | Chooses the requested operation and one plausible local asset | Invents an action/asset or ignores an explicit request | Medium | PRD `FR-AGENT-001`, catalog |
| Spatial humility | Leaves placement, support, collision, visibility, and target authorization to native code | Emits or implies geometry/authority | High | ADR-011, Master Spec |
| Design usefulness | Gives a concise reason grounded in visible/requested style | Generic prose, unsupported scene claims, or an external URL | Medium | Hero demo rubric |
| Ambiguity handling | Requests one bounded clarification when operation/target/design choice is unclear | Guesses a destructive or wrong-target edit | High | `SEC-AGENT-001` |
| Privacy clarity | Uses only the current explicitly consented frame and sanitized telemetry | Silent/repeated capture, retention, or sensitive logs | High | `SEC-CONSENT-001` |

### Known Failure Modes in This Domain

- A visually plausible suggestion masks a wrong stable object or stale world
  epoch; visual plausibility is never authorization.
- Design language such as “move it left” tempts the model to produce geometry;
  CON-006 must reduce this to semantic constraints or clarification.
- An image contains text that attempts prompt/tool injection or requests a URL.
- Voice transcription changes an asset name or operation; the user must see the
  resulting proposal before preview and retain a typed fallback.
- A confident explanation implies a support/collision fact that only ARKit and
  deterministic code can establish.

### Regulatory / Compliance Context

No regulated professional advice is produced. Camera and microphone consent,
data minimization, credential isolation, OpenAI retention configuration, and
repository privacy rules still apply. Shipping/privacy policy approval remains
a human gate.

### Domain Expert Roles for Evaluation

| Role | Responsibility |
|---|---|
| Product owner / demo operator | Label hero prompts, ambiguity, clarity, and fallback behavior |
| Spatial-computing engineer | Verify no model field crosses the ARKit/transaction authority boundary |
| Security reviewer | Calibrate injection, secret, URL, stale-context, and unknown-field cases |
| Design reviewer | Score whether accepted suggestions are useful and concise, never whether they are authoritative |

## 2. Framework Decision

**Selected Framework:** Direct OpenAI Responses and Realtime APIs; official
`openai` JavaScript SDK in the local gateway and native `URLSession` /
`URLSessionWebSocketTask` on iPhone.

**Version:** `openai@6.39.0`, Node `22.22.3`; models `gpt-5.6-sol` and
`gpt-realtime-2.1`.

**Rationale:** The AI path is two bounded linear calls, not an autonomous tool
loop. Direct APIs minimize dependencies, latency, state, and attack surface;
Structured Outputs express the exact semantic boundary. Native deterministic
code already owns every downstream transition, so adding an agent runtime
would create the wrong authority abstraction.

**Alternatives Considered:**

| Framework | Ruled Out Because |
|---|---|
| OpenAI Agents SDK | Handoffs, agent loops, memory, and hosted tracing are unnecessary for one closed extraction call and would blur the non-authoritative boundary. |
| LangGraph / LangChain | Stateful graph/orchestration and model abstraction add dependencies without a corresponding product need in the 24-hour slice. |
| Model call directly from iPhone | Would expose a standard API credential or require broader client authority; the local gateway owns credentials and schema/catalog policy. |
| Learned spatial planner | Violates the locked rule that ARKit and deterministic code own target authorization, geometry, revision, and commit. |

**Vendor Lock-In Accepted:** Partial and explicit. The optional semantic adapter
is OpenAI-specific; CON-006 and the native deterministic product path remain
provider-independent. Removing the adapter leaves P0 complete.

## 3. Framework Quick Reference

### Installation

```bash
cd gateway
npm ci
npm test && npm run typecheck && npm run build
```

### Core Imports

```ts
import OpenAI from "openai";
import { createServer } from "node:http";
```

### Entry Point Pattern

```ts
const response = await openai.responses.create({
  model: "gpt-5.6-sol",
  store: false,
  max_output_tokens: 800,
  instructions: DESIGN_COPILOT_INSTRUCTIONS,
  input: [{ role: "user", content }],
  text: {
    format: {
      type: "json_schema",
      name: "reroom_semantic_proposal",
      strict: true,
      schema: MODEL_PROPOSAL_OUTPUT_SCHEMA,
    },
  },
});

const untrusted = JSON.parse(response.output_text);
const proposal = parseInitialModelOutput(untrusted); // closed runtime check
return bindTrustedContext(proposal, nativeRequestContext); // gateway-owned
```

### Key Abstractions

| Concept | What It Is | When Used |
|---|---|---|
| Responses Structured Outputs | Server-declared strict JSON Schema output | Every Sol proposal |
| CON-006 | Closed nonmutating semantic envelope with exact context/provenance | Gateway-to-native response |
| Ephemeral Realtime secret | 600-second scoped client credential minted by gateway | Optional push-to-talk session |
| Trusted request context | Session/branch/revision/world/selected-object snapshot created by native code | Bound before request and rechecked before preview |
| Frozen CON-005 boundary | Existing typed/tap intent contract and deterministic reducers | Re-entry after CON-006 acceptance |

### Common Pitfalls

1. Structured Outputs constrain shape but do not make content trusted; retain
   independent gateway and native validators.
2. Never ask the model to echo authority-bearing context. Bind the trusted
   context in deterministic gateway code and compare it again on device.
3. WebRTC is the preferred general mobile Realtime transport. The native
   WebSocket path is a bounded hackathon amendment and must remain optional.
4. `output_text` is still untrusted bytes; bound size, parse once, reject unknown
   fields, and never log the raw value.
5. `store: false` does not replace product consent, minimization, retention, and
   privacy review.

### Recommended Project Structure

```text
gateway/
├── src/openai-responses-client.ts
├── src/proposal-service.ts
├── src/realtime-client-secret.ts
├── src/protocol.ts
└── test/
ios/ReRoomDeviceProof/ReRoomDeviceProof/
├── DesignCopilot.swift
└── DesignCopilotView.swift
docs/contracts/semantic-proposal.schema.json
fixtures/semantic-proposals/1.0.0/rev-001/cases.json
```

## 4. Implementation Guidance

**Model Configuration:** Sol uses strict Structured Outputs, `store: false`,
`max_output_tokens: 800`, low-detail optional vision input, and no tools.
Realtime uses PCM16 mono 24 kHz push-to-talk, near-field noise reduction,
English transcription, no turn detection, and a ten-minute credential. The
client commits audio and consumes only the bounded completed transcript event;
Sol performs the final semantic normalization.

**Core Pattern:** Untrusted prompt/image/transcript → server-owned model schema
→ independent closed runtime validation → deterministic trusted-context
binding → strict native decode → exact current-context comparison → frozen
CON-005 proposal → revision-neutral preview → separate explicit confirmation →
deterministic commit.

**Tool Use:** No model tool may mutate product state. The mobile Realtime
session exposes no tools and produces only transcription events. Its completed
transcript routes through Sol/CON-006; no Realtime response or tool result is
accepted as authority.

**State Management:** The gateway is stateless. Native stores only the gateway
root URL in `UserDefaults` and the bearer token in Keychain. Model envelopes are
ephemeral UI state. Canonical scene, transaction, replay, and restore state use
the existing durable deterministic stores.

**Context Window Strategy:** One prompt up to 2,000 characters, zero history,
one optional JPEG up to 1.5 MB / 1,280-pixel long edge, a three-item catalog,
and one response up to 64 KiB. No conversation memory, retrieval, or room-data
corpus is needed.

## 4b. AI Systems Best Practices

### Structured Outputs with Pydantic

The product runtime uses JSON Schema + TypeScript + Swift, not Pydantic. This
Pydantic model is an offline evaluator shape only; it is not a second product
contract and must be derived from CON-006 if an eval runner is added.

```python
from typing import Literal
from pydantic import BaseModel, ConfigDict

class ProposalEval(BaseModel):
    model_config = ConfigDict(extra="forbid")
    case_id: str
    schema_valid: bool
    context_exact: bool
    authority_fields_absent: bool
    expected_operation: Literal["place", "replace", "remove", "restore", "clarify"]
    observed_operation: Literal["place", "replace", "remove", "restore", "clarify"]
```

Validation failure is terminal for that proposal. There is no repair prompt or
best-effort field dropping; the user may retry from a fresh current context.

### Async-First Design

All model, frame-encoding, audio, and network work runs outside the render
loop. Requests have bounded deadlines and cancellation. Realtime audio uses a
bounded queue; overflow terminates the voice attempt rather than corrupting a
turn silently. Preview and commit never await a model.

### Prompt Engineering Discipline

System instructions own the catalog, schema, and prohibitions. User prompt,
image text, and transcript are explicitly untrusted data. The prompt contains
no secrets or canonical state authority; trusted context is added only after
model output. Concise explanations and clarification are bounded to 280
single-line, URL-free characters.

### Context Window Management

No history is carried across calls. The gateway supplies only the current
prompt, optional downscaled frame, fixed catalog names/IDs, and schema. This is
both the token strategy and privacy-minimization strategy.

### Cost and Latency Budget

One Sol request occurs only on Ask or after a completed voice transcript; one
Realtime session occurs only while push-to-talk is active. No automatic retry,
background polling, speculative call, or frame stream exists. Live p50/p95 and
cost remain `PENDING` until measured with a real provider/device run.

## 5. Evaluation Strategy

### Dimensions

| Dimension | Rubric | Measurement | Priority |
|---|---|---|---|
| Contract closure | Pass only if exact CON-006 shape/version/IDs/bounds validate and unknown fields reject | Code | Critical |
| Authority containment | Pass only if no target/transform/context/confirmation/commit/revision/URL can cross model output | Code + security review | Critical |
| Context freshness | Pass only if exact session/branch/revision/world/selection still matches before preview | Code | Critical |
| Operation/asset accuracy | Live set passes when at least 4/5 fixed hero requests yield expected operation and allowed asset or clarification | Code + human | High |
| Ambiguity handling | Ambiguous/injection cases must clarify or reject, never guess authority | Code + human | High |
| Revision neutrality | Decode/apply changes no canonical revision; only later explicit confirm may increment once | Code | Critical |
| Design usefulness | Reviewer accepts concise rationale as relevant and non-authoritative in at least 4/5 hero cases | Human | Medium |
| Fallback independence | Typed/tap full journey passes with gateway/model/network disabled | Integration | Critical |
| Privacy/logging | No secret, prompt, image, transcript, output, raw room data, or public cleartext bearer destination appears in logs/storage | Code + security scan | Critical |

### Eval Tooling

**Primary Tool:** Checked-in immutable vectors, Node test runner, Swift Testing,
and Xcode simulator/device tests. Arize Phoenix is intentionally overridden for
the 24-hour/local-room-data slice: adding hosted or self-hosted tracing would
expand dependencies and data flow without improving the release decision.

**Setup:**

```bash
cd gateway && npm test && npm run typecheck && npm run build
swift test --package-path ios/Packages/ReRoomContracts
# Then run the clean-source Xcode test command from HACKATHON-24H.md.
```

**CI/CD Integration:** The same commands are dependency-locked and
noninteractive. No live OpenAI call runs in CI without a separately approved,
secret-backed evaluation job.

### Reference Dataset

**Size:** 10 immutable deterministic cases now; five fixed live voice/typed
hero requests plus ambiguity and image-injection cases before the demo claim.

**Composition:** Ready replace, ready restore, clarification, unknown asset,
authority injection, transform injection, URL injection, duplicate and
noncanonical constraints, and status/nullability contradiction. Live additions
cover each operation, ambiguous target, image-text injection, network loss, and
stale-context response.

**Labeling:** Product owner labels expected operation/clarification and design
usefulness; spatial/security reviewers label authority containment. Any future
LLM judge must first achieve at least 0.7 correlation with this human set and
cannot judge mutation authority.

## 6. Guardrails

### Online (Real-Time)

| Guardrail | Trigger | Intervention |
|---|---|---|
| Closed request parser | Unknown/oversized/malformed prompt, JPEG, context, or content type | Reject before provider call |
| Closed model parser | Unknown operation/asset/field, noncanonical constraint, URL, unsafe copy, or invalid status pair | Reject entire output |
| Native strict decoder | Shape/version/provenance/stable-ID/bounds mismatch | Reject before UI proposal |
| Context binding | Session/branch/revision/world/selection changed | Mark stale; require fresh Ask |
| Consent | Frame toggle lacks per-send consent | Do not encode or send frame |
| Credential/network boundary | Missing token, expired ephemeral secret, public cleartext HTTP, timeout, queue overflow, or disconnect | End AI/voice attempt; keep typed fallback |
| Deterministic authority | Proposal attempts preview/confirm/commit directly | Impossible by type/API boundary; no mutation |

### Offline (Flywheel)

| Metric | Sampling Strategy | Action on Degradation |
|---|---|---|
| Schema/containment regression | Every checked-in vector on every change | Block merge/demo candidate |
| Operation/asset accuracy | All fixed live hero prompts before demo; failed cases retained without room media | Adjust instructions/schema/catalog or remove AI claim |
| Clarification accuracy | Every ambiguous/injection case | Tighten prompt/parser; never loosen authority checks |
| Latency/failure | Sanitized per-request status/duration during rehearsal | Kill Realtime first, then vision; typed path remains |
| Human usefulness | Five fixed proposals reviewed by product/design owner | Improve catalog/prompt or present AI as experimental |

## 7. Production Monitoring

**Tracing Tool:** Sanitized local structured gateway logs only for this sprint.
Records contain request ID, method, allowlisted path, status, and duration. They
exclude bearer/API/ephemeral secrets, prompts, image bytes, transcripts, model
output, stable room IDs, and raw room data.

**Key Metrics:** proposal success/reject/timeout counts; Realtime credential
success/reject counts; bounded request duration; native stale-context rejects;
human-labeled operation/asset accuracy; typed-fallback success.

**Alert Thresholds:** Any authority/secret/privacy failure is an immediate
block. Any schema vector failure blocks. More than one failure in five fixed
live hero attempts removes the relevant AI path from the rehearsed demo.

**Smart Sampling Strategy:** Retain sanitized failures and deterministic case
IDs, not room media. Prioritize stale-context, clarification, timeout,
voice-transcription mismatch, and user retry signals for human review.

## Checklist

- [x] System type classified
- [x] Critical failure modes identified (at least three)
- [x] Domain context and expert criteria documented
- [x] Regulatory/privacy context explicitly scoped
- [x] Domain expert roles defined
- [x] Framework selected with rationale and exact version
- [x] Alternatives considered and ruled out
- [x] Framework quick reference and pitfalls written
- [x] AI systems practices include offline Pydantic eval shape, async, prompt, and context discipline
- [x] Evaluation dimensions grounded in domain rubric ingredients
- [x] Every dimension has a concrete release consequence
- [x] Eval tooling selected; Phoenix override justified
- [x] Ten-case immutable deterministic reference set checked in
- [x] CI commands specified
- [x] Online guardrails defined
- [x] Sanitized monitoring and sampling strategy defined
- [ ] Live Sol/Realtime/device evaluation recorded — `PENDING`, never inferred from automated evidence
