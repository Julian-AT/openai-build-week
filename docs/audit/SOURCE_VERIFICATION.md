# Source Verification

Status: readable audit summary  
Research window: 2026-07-13 through 2026-07-14  
Detailed claim authority: `docs/canonical/RESEARCH_LEDGER.md`

External material was treated as untrusted evidence. Official product documentation, repositories, released files, and licenses were preferred. Absence of documentation was not treated as proof of capability.

## Verified current facts

| Fact | Status | Primary source | Architectural effect |
|---|---|---|---|
| The base iPhone 17 specification lists the A19 and rear cameras but no LiDAR Scanner. | VERIFIED | https://www.apple.com/iphone-17/specs/ | P0 cannot depend on rear LiDAR. |
| ARKit scene depth and scene reconstruction require device support associated with LiDAR-capable hardware. | VERIFIED | https://developer.apple.com/documentation/arkit/displaying-a-point-cloud-using-scene-depth and https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/supportsscenereconstruction(_:) | Scene depth/mesh are forbidden dependencies; runtime support checks remain mandatory. |
| ARKit world tracking supports plane detection/raycasting; raw feature points are unstable observations. | VERIFIED | https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration and https://developer.apple.com/documentation/arkit/arframe/rawfeaturepoints | Planes/rays support fast proxies; feature points cannot be canonical geometry. |
| `capturedImage` is not pre-adjusted for orientation/view crop; `displayTransform` describes normalized rotation/aspect handling. | VERIFIED | https://developer.apple.com/documentation/arkit/arframe/displaytransform(for:viewportsize:) | `encoded_from_sensor`, encoded intrinsics, and projection fixtures are required. |
| RealityKit has occlusion materials, custom material depth controls, and a Metal postprocess callback. | VERIFIED capability; project result unverified | https://developer.apple.com/documentation/realitykit/occlusionmaterial and https://developer.apple.com/documentation/realitykit/arview/rendercallbacks-swift.struct/postprocess | Supports a RealityKit-first spike, not an unmeasured quality claim. |
| GPT-5.6 Sol is a current model with function calling/Structured Outputs. | VERIFIED | https://developers.openai.com/api/docs/models/gpt-5.6-sol | Strict gateway planning is supported. |
| GPT-Realtime-2.1 supports audio/text/image input and function calling but not Structured Outputs. | VERIFIED | https://developers.openai.com/api/docs/models/gpt-realtime-2.1 | Realtime is noncanonical intent ingress only. |
| Current Realtime WebRTC uses a server-minted ephemeral client secret; standard API keys remain server-side. | VERIFIED | https://developers.openai.com/api/docs/guides/realtime-webrtc | Direct iPhone WebRTC plus gateway token endpoint is supported. |
| SAM 3.1 was released 2026-03-27; it is an 848M model and its current repo requires Python 3.12+, PyTorch 2.7+, and CUDA 12.6+. Checkpoint access requires authentication/approval. | VERIFIED | https://raw.githubusercontent.com/facebookresearch/sam3/main/RELEASE_SAM3p1.md and https://raw.githubusercontent.com/facebookresearch/sam3/main/README.md | Valid bake-off candidate, high access/runtime risk. |
| SAM 2.1 provides Tiny/Small/Base+/Large public checkpoints; Small is 46M and supports point/box-prompted video propagation. | VERIFIED | https://raw.githubusercontent.com/facebookresearch/sam2/main/README.md | Best-supported initial one-target provider. |
| DA3Metric-Large exists for monocular metric depth; DA3 Small/Base support pose conditioning. | VERIFIED | https://raw.githubusercontent.com/ByteDance-Seed/Depth-Anything-3/main/README.md | Valid provider candidates; selection remains empirical. |
| LingBot-Map is an Apache-licensed streaming reconstruction project whose recommended path uses PyTorch 2.8/CUDA 12.8/FlashInfer and whose repository recorded material 2026 KV-cache fixes. | VERIFIED | https://raw.githubusercontent.com/Robbyant/lingbot-map/main/README.md and https://raw.githubusercontent.com/Robbyant/lingbot-map/main/pyproject.toml | Too immature/heavy to define guaranteed B0. |
| Open3D VoxelBlockGrid exposes TSDF integration, extraction, and raycasting on supported CPU/CUDA builds. | VERIFIED capability; packaging/performance unverified | https://www.open3d.org/docs/latest/tutorial/t_reconstruction_system/integration.html and https://www.open3d.org/docs/latest/python_api/open3d.t.geometry.VoxelBlockGrid.html | Optional dense provider only. |
| Current Next.js production route handling does not provide application WebSocket upgrades for matched app/page routes. | VERIFIED for pinned source | https://github.com/vercel/next.js/blob/v16.2.10/packages/next/src/server/next-server.ts | Gateway owns production WebSockets, session replication/reconciliation, and stateful processing—not active Mode A branch revisions. |

## Contradicted or materially weakened archived claims

| Archived claim/position | Finding | Canonical treatment |
|---|---|---|
| Five independent owners/workstreams are available. | Contradicted by human-locked two-developer capacity. | Dependency slices; no person-based ownership. |
| Removal can be omitted/demoted after its gate while P0 remains complete. | Contradicts exact four-operation P0. | Unsupported sessions may hide remove; hero-fixture failure blocks P0 or requires human escalation. |
| SAM 3.1 is the frozen best P0 semantic choice. | Existence is verified, optimality is not; its scale/access/license add risk. | SAM 2.1 Small is provisional default; shared bake-off may upgrade it. |
| LingBot is a universal B0 fallback. | Current runtime/maturity makes it a risky provider dependency. | Optional ordinary-video geometry only; B0 baseline is provider-independent. |
| B0 is an immediate fallback during live network loss. | Web/backend use still requires transport or later transfer. | Immediate fallback is local rendering/recording/restore; B0 is later recovery/replay. |
| Enqueue-before-send is a record-first guarantee. | Enqueue does not establish crash-safe durability. | Atomic image/metadata persistence and journal precede network eligibility. |
| Undo changes the original transaction to an undone state. | Conflicts with immutable history/replay. | New compensating restore transaction; original stays committed. |
| A warm specific GPU deployment is architectural. | Violates hardware-agnostic locked decision and was not benchmarked. | Capability tiers and selected worker profiles; deployment remains separate. |
| Next.js can own all web/session WebSockets. | Not supported by the pinned production server path. | Separate gateway owns stateful sockets/session replication, not active Mode A branch revisions. |
| Fast proxy validation is “physical validation.” | Visual hulls, OBBs, and planes are estimated proxies. | Use measured minimum-clearance/proxy-fit language. |

## License findings

| Component | Verified license finding | Decision |
|---|---|---|
| SAM 3/3.1 | Custom SAM License with redistribution, compliance, trade-control, and use obligations. https://raw.githubusercontent.com/facebookresearch/sam3/main/LICENSE | Legal/team acceptance and checkpoint access are prerequisites; not default. |
| SAM 2/2.1 code/checkpoints | Apache-2.0. https://raw.githubusercontent.com/facebookresearch/sam2/main/LICENSE | Permitted provisional default; still pin source/checkpoint hashes. |
| DA3 repository | Apache-2.0; model table marks DA3Metric-Large, DA3 Small/Base, and DA3Mono-Large Apache-2.0, while DA3 Large/Giant/Nested any-view models are CC BY-NC 4.0. https://raw.githubusercontent.com/ByteDance-Seed/Depth-Anything-3/main/README.md | P0 candidates are restricted to exact Apache-listed checkpoints. |
| LingBot-Map | Apache-2.0 repository license. https://raw.githubusercontent.com/Robbyant/lingbot-map/main/LICENSE.txt | License-compatible optional provider; maturity remains a separate risk. |
| Open3D | MIT license in the official repository; exact release/build still must be pinned. https://github.com/isl-org/Open3D/blob/main/LICENSE | Permitted optional geometry dependency. |
| LaMa/fill implementation | Exact implementation and checkpoint were not pinned in the archived inputs. | Do not place neural fill on P0 until exact code/weight licenses are recorded; deterministic fill is fallback. |
| Assets | No final asset list/license ledger existed in the archived inputs. | Each asset must pass GATE-011 before inclusion. |

## Version findings

- RFC 8785 is the pinned primary basis for deterministic JSON canonicalization; ReRoom separately versions each digest scope and tests exact Swift/JavaScript/Python vectors.
- Exact OpenAI model IDs are current, but production code should still record the invoked model/snapshot and API behavior.
- SAM 3.1 requires the latest repository code matching its checkpoint; “SAM 3” alone is not a sufficient pin.
- SAM 2.1 checkpoint/config pairs must match; the public performance table was measured on A100 and is not a ReRoom hardware benchmark.
- DA3’s refreshed `-1.1` suffix applies to some large/nested checkpoints, but the P0 candidates must use exact model-card identifiers and licenses rather than a family shorthand.
- LingBot repository behavior changed materially in April and June 2026; a commit pin is mandatory if used.
- Open3D API documentation demonstrates capability, not that a particular Python wheel contains the required CUDA build.
- Next.js WebSocket evidence is pinned to v16.2.10 source; the gateway split remains valid even if future versions add support.

## Claims downgraded to targets or hypotheses

- 60 FPS target / 45 FPS minimum, memory, thermal, and four-minute stability.
- Target tracking and replace-ready p50/p95 latency.
- Voice-command-to-visible-change latency and 4/5 intent success.
- DA3 inference latency, metric accuracy, temporal stability, and Open3D fusion quality.
- Visual-hull OBB quality and target-projection coverage.
- Reveal coverage, synthesized fraction, seam quality, and foreground correctness.
- LingBot throughput and reconstruction quality on indoor ordinary video.
- Artifact byte budgets and client activation latency.
- Any claim of reliable real-world occlusion beyond validated proxies.

## Claims requiring benchmark

The unresolved empirical set is exactly GATE-001 through GATE-014 as routed in the ADRs and canonical risk plan. Load-bearing architecture gates are compositor (003), semantics (004), fast volume (005), reveal (006), dense provider (007), B0 baseline (008), transactions/network (009), voice (010), asset/license (011), runtime tier (012), signing/device preflight (013), and B1 isolation (014). No benchmark may silently change the human-locked scope.
