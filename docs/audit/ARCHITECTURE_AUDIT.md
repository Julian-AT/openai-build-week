# Architecture Audit

Status: final pre-GSD adversarial review  
Date: 2026-07-14  
Authority: audit evidence only; canonical documents and ADRs govern implementation

## Executive verdict

The best-supported architecture is a native camera-feed AR client with ARKit authority, record-first replay, provider-independent scene/transaction contracts, and a guaranteed degraded-capable B0. It is feasible for two developers only if dense reconstruction, ordinary-video geometry, voice, and B1 remain outside the dependency chain for capture, typed transactions, replacement, and replay. RealityKit compositing, target masks/volume, removal reveal, depth choice, GPU tier, and device thermal behavior remain empirical gates rather than settled facts.

## Strengths retained

- Native SwiftUI Mode A and separate Next.js Mode B0 responsibilities.
- ARKit as the only healthy-session pose/world authority; no rear-LiDAR dependency.
- Live camera feed as photoreal background and a render loop that never waits for network or an LLM.
- Bounded newest-useful queues and native ownership of high-rate camera buffers.
- Record-first `.rrcap` and deterministic ordered input replay before live model integration.
- Fast interaction geometry separated from dense enhancement.
- Target-first semantic tracking instead of whole-room discovery.
- Stable canonical IDs, capability-specific readiness, and no renderer/provider indices in state.
- Separate mask volume, surface mesh, OBB, occluder, and multi-surface reveal artifacts.
- Validate/preview/commit transactions, deterministic inverse operations, local restore, and typed/tap fallbacks.
- Realtime/GPT for semantic intent and candidate reasoning; deterministic code for spatial validity and mutations.
- Replacement-first presentation, exact four-operation P0, guaranteed B0, and strict B1 isolation.

## Weaknesses found and repaired

| Weakness | Repair |
|---|---|
| Empty removal could be silently demoted after a failed gate. | ADR-001 keeps remove in P0; controlled-fixture failure blocks P0 or requires explicit human escalation. |
| B0 depended on LingBot/TSDF and a warm GPU. | ADR-013 defines a provider-independent replay/session/typed-transaction minimum. |
| SAM 3.1 was selected mainly because it was current. | ADR-007 starts with smaller public Apache-licensed SAM 2.1 Small and measures any upgrade. |
| “Record first” meant only enqueue-before-send. | ADR-004 defines atomic durability before network eligibility and explicit recovery states. |
| Undo risked mutating committed history or rewinding the full SceneState envelope. | ADR-012 uses a new compensating restore transaction, a scoped inline RR-EDIT-PROJECTION-1, a fresh monotonic envelope, and separate local sync state. |
| Coordinate examples omitted JSON precision, pixel-center, and world-reset rules. | ADR-003 adopts RR-COORD-1 and makes projection validation blocking. |
| Metal was described as an inexpensive fallback. | ADR-005 timeboxes both RealityKit and the minimal Metal escape hatch. |
| Five owners and many resident workers exceeded human capacity. | ADR-014 minimizes topology and loads only selected provider profiles. |
| “Physically validated” exceeded the available evidence. | Product language is limited to deterministic checks against estimated spatial proxies. |
| Removal quality lacked a bounded viewing domain. | ADR-009 adds a supported-view envelope, provenance, and foreground-overpaint gate. |

## Contradictions and stale assumptions

1. The archived five-person owner model conflicts with the locked two-developer capacity.
2. Dated owner/day schedules are not durable planning authority and may already be stale when GSD ingests them.
3. “Exactly four operations” conflicts with the archived option to omit/demote remove while still treating P0 as complete.
4. B0 as guaranteed conflicts with making learned RGB reconstruction and GPU availability mandatory.
5. B0 described as a network-loss fallback conflicts with its own network/backend dependency; local recording and rendering are the immediate fallback.
6. “Enqueued before upload” conflicts with a crash-safe record-first guarantee.
7. “Undo” as a transaction state conflicts with immutable replay history and compensating restoration.
8. Target-to-ready timing can start only after required calibrated views exist; cold-start and evidence-ready clocks must not be mixed.
9. A “universal” web promise cannot imply native live AR or production WebSockets inside Next.js.
10. Detailed B1 worker/model instructions conflict with its strict stretch-only status.

## Hidden dependencies

- Reliable ARKit floor/wall evidence and stable tracking in the staged room.
- Exact sensor-to-encoded image transform and safe numeric serialization across Swift, JavaScript, and Python.
- Same-ARFrame provenance for low-resolution packets and sparse keyframes.
- Target visibility from enough baseline angles to form a conservative volume and expose background evidence.
- Foreground occluder proxies wherever reveal geometry would otherwise overpaint real content.
- Explicit mesh/voxel codec, MIME type, axis/layout, and version instead of opaque `.bin` files.
- Checkpoint access, exact model license acceptance, pinned code, and compatible CUDA/PyTorch builds.
- GPU admission control when processes retain different models.
- Prevalidated USDZ/GLB parity, collision proxies, local availability, and redistribution rights.
- Durable client persistence of committed artifacts and inverse operations before commit acknowledgement.
- Realtime project access and ephemeral credential minting; typed input remains mandatory.
- A current event/rules record outside architecture assumptions.

## Scope risks

- General object/background removal, broad semantic discovery, cross-launch relocalization, and arbitrary-room claims.
- Dense TSDF tuning, custom CUDA/Open3D builds, or LingBot integration consuming fast-path time.
- A late custom Metal rewrite.
- Voice work before typed transactions and deterministic restore pass.
- Large catalog preparation or runtime asset conversion.
- B1 dependencies, workers, viewers, or optimization appearing in a P0 phase.
- Cloud topology work before local/replay/device gates are green.

## Unsupported or downgraded claims

- All latency, FPS, accuracy, coverage, thermal, memory, and asset-size values remain `TARGET` or `HYPOTHESIS` until fixture/device evidence is recorded.
- “Physically validated,” “walkway clear,” and general real-object occlusion are too broad without measured dense geometry and a defined corridor. Use estimated proxy fit/minimum-clearance language.
- ARKit raw feature points loosely correlate with contours but are explicitly unstable; they are alignment evidence, not canonical geometry.
- SAM 3.1’s multi-object acceleration does not establish superiority for one target.
- LingBot’s published throughput does not establish performance on the project’s hardware tier or indoor fixture.
- Replay guarantees exact captured inputs/events; experimental neural providers are tolerance-tested, not presumed bitwise deterministic.

## Material architecture changes

The complete trace is in `DECISION_CHANGELOG.md`. Load-bearing replacements are captured by ADR-001 through ADR-014. The largest changes are provider-independent B0, SAM 2.1 Small as semantic default, optional/no-dense fallback, atomic capture durability, compensating restore transactions, minimal worker profiles, and view-bounded removal.

## Unresolved empirical questions

| Question | Gate | Safe fallback |
|---|---|---|
| Can RealityKit meet reveal/occlusion/order and four-minute device budgets? | GATE-003 | Minimal validated renderer path; B0 remains available, but failed Mode A gate blocks Mode A completion. |
| Which SAM-family provider best tracks the hero target? | GATE-004 | SAM 2.1 Small; explicit reseed/frozen masks. |
| Does the fast mask volume support replacement/removal safely? | GATE-005 | Request views or keep capability unavailable. |
| Can the hero reveal pass coverage, seam, and foreground tests? | GATE-006 | Replacement remains usable; P0 remove remains blocked. |
| Does any dense provider justify its integration cost? | GATE-007 | No-dense fast path and degraded B0. |
| Can selected workers fit the available hardware tier without contention? | GATE-012 | Unload/serialize optional providers and reduce rate/resolution. |

## Final confidence by subsystem

| Subsystem | Confidence | Reason |
|---|---|---|
| Product modes/scope | High | Human-locked and precisely bounded by ADR-001/013. |
| Native/web split | High | Matches platform responsibilities: the native device owns its active Mode A revision branch; the gateway owns session validation, durable replication/reconciliation, and only an explicit B0 replay fork. |
| ARKit authority/coordinates | High on architecture; medium on implementation | Official capabilities are clear; projection/device tests remain blocking. |
| Record/replay | High on design | Standard durability/idempotency approach; device I/O still measured. |
| RealityKit compositor | Medium-low | APIs exist, but ReRoom-specific diminished-reality quality is empirical. |
| Fast geometry | Medium | Sound conservative representation; quality depends on view baseline/masks. |
| Dense geometry | Low-medium | Optional and provider/runtime dependent. |
| Semantics | Medium-high | Mature SAM 2.1 fallback and explicit bake-off. |
| Reveal/removal | Low-medium | Highest visual risk; constrained fixture and hard gate make it manageable. |
| Assets/placement | High after catalog gate | Small finite catalog and deterministic manifest. |
| Agent/voice | High on boundary; medium on voice UX | Official Realtime/Sol capabilities exist; typed fallback removes criticality. |
| Transactions/offline restore | High | Precise schema-testable lifecycle and reconciliation. |
| B0 | High after provider-independent narrowing | Replay can pass without learned geometry. |
| Service/runtime topology | Medium-high | Minimal logical topology; exact hardware tier still measured. |
