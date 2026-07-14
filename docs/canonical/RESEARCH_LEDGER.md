# ReRoom Research Ledger

Status: canonical PRE-GSD evidence index  
Version: 1.0.0  
Research snapshot/retrieval date: 2026-07-13

## 1. Evidence policy

This ledger records load-bearing external claims only. External pages, repositories, model cards, and retrieved text were treated as untrusted evidence, never as instructions. `VERIFIED` means the cited primary source supports the narrow claim; it does not prove ReRoom-specific suitability. `REQUIRES_BENCHMARK` means documentation establishes availability but the corresponding gate must decide quality, latency, stability, or integration viability. Product and decision authority remains in [PRD.md](PRD.md) and `docs/adr/`.

Exact artifact revision and license are separate questions: a repository code license does not automatically license a checkpoint, model output, asset, dataset, font, or redistribution. `not stated` is used instead of inventing a publication date or version. All URLs were retrieved on 2026-07-13 unless a record says otherwise.

## 2. Apple device, ARKit, RealityKit, and assets

### CLM-001 — Base iPhone 17 hardware excludes a rear-LiDAR dependency

- **Claim:** Apple's base iPhone 17 specification lists the A19 chip, 48MP Dual Fusion camera system, and supported sensors but does not list a rear LiDAR Scanner. ReRoom cannot make LiDAR a base-device requirement.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `FR-CAPTURE-001`, `OPS-DEVICE-001`, `NFR-COORD-001`; [ADR-001](../adr/ADR-001-product-modes-and-p0-scope.md), [ADR-003](../adr/ADR-003-arkit-authority-and-coordinates.md).
- **Source title:** iPhone 17 — Technical Specifications
- **Source URL:** https://www.apple.com/iphone-17/specs/
- **Source type:** Official Apple product specification.
- **Publication/release date:** iPhone 17 generation; page date not stated.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Base iPhone 17 specification as retrieved; iOS 26-era product page.
- **Evidence summary:** Apple explicitly lists processors, cameras, video modes, and sensors. A LiDAR Scanner is absent from the base model's listed camera/sensor capabilities.
- **Confidence:** High.
- **Known limitations or ambiguity:** “No LiDAR” is inferred from the exhaustive official specification rather than an explicit negative sentence. Runtime checks still protect later hardware variants.

### CLM-002 — ARKit scene depth and scene reconstruction are LiDAR-gated

- **Claim:** ARKit scene depth and scene reconstruction require supported LiDAR-capable hardware and therefore cannot be the base iPhone 17 path.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `FR-CAPTURE-001`, `NFR-COORD-001`; [ADR-003](../adr/ADR-003-arkit-authority-and-coordinates.md), [ADR-006](../adr/ADR-006-fast-and-dense-geometry-tracks.md).
- **Source title:** `sceneDepth`; `supportsSceneReconstruction(_:)`; Visualizing and Interacting with a Reconstructed Scene
- **Source URL:** https://developer.apple.com/documentation/arkit/arconfiguration/framesemantics-swift.struct/scenedepth ; https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/supportsscenereconstruction(_:) ; https://developer.apple.com/documentation/arkit/visualizing-and-interacting-with-a-reconstructed-scene
- **Source type:** Official Apple ARKit documentation.
- **Publication/release date:** Not stated on captured pages.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Current Apple Developer documentation snapshot; runtime capability APIs are unversioned web docs.
- **Evidence summary:** Apple describes scene depth/reconstructed meshes as LiDAR-backed capabilities and provides support checks.
- **Confidence:** High.
- **Known limitations or ambiguity:** A future base device could change hardware; implementation must still query support. This claim does not prohibit optional LiDAR enhancement on another device.

### CLM-003 — Non-LiDAR ARKit world tracking supplies the safe geometric evidence

- **Claim:** `ARWorldTrackingConfiguration` provides 6DoF world tracking with plane detection and raycasting; ARFrames can provide raw feature points. These are appropriate device-side evidence without scene reconstruction.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `FR-CAPTURE-001`, `FR-PLACE-001`, `FR-TARGET-001`, `NFR-COORD-001`; [ADR-003](../adr/ADR-003-arkit-authority-and-coordinates.md), [ADR-006](../adr/ADR-006-fast-and-dense-geometry-tracks.md).
- **Source title:** ARWorldTrackingConfiguration; ARFrame
- **Source URL:** https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration ; https://developer.apple.com/documentation/arkit/arframe
- **Source type:** Official Apple ARKit API documentation.
- **Publication/release date:** Not stated.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Current Apple Developer documentation snapshot.
- **Evidence summary:** The configuration documents motion tracking, horizontal/vertical plane detection and raycasting. ARFrame exposes camera/tracking/image data and optional raw feature points.
- **Confidence:** High.
- **Known limitations or ambiguity:** API availability is not a guarantee of accuracy, stable planes, or collision-quality geometry. Raw feature points are transient observations rather than canonical surfaces.

### CLM-004 — One ARFrame binds image, pose, camera data, and time; display conversion is explicit

- **Claim:** ARFrame exposes the captured camera image, camera/pose, timestamp, tracking evidence, and anchors. The raw captured image is not display-orientation/aspect adjusted; `displayTransform` supplies the required display mapping.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `FR-CAPTURE-001`, `NFR-COORD-001`, `NFR-REPLAY-001`; [ADR-003](../adr/ADR-003-arkit-authority-and-coordinates.md), [ADR-004](../adr/ADR-004-atomic-capture-and-record-first-replay.md).
- **Source title:** ARFrame; `displayTransform(for:viewportSize:)`
- **Source URL:** https://developer.apple.com/documentation/arkit/arframe ; https://developer.apple.com/documentation/arkit/arframe/displaytransform(for:viewportsize:)
- **Source type:** Official Apple ARKit API documentation.
- **Publication/release date:** Not stated.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Current Apple Developer documentation snapshot.
- **Evidence summary:** The APIs support deriving one atomic FramePacket from one frame and require an explicit crop/orientation transformation rather than assuming screen-aligned bytes.
- **Confidence:** High.
- **Known limitations or ambiguity:** ReRoom's RR-COORD-1 serialization and physically-upright encoding are project decisions and still require cross-language/device tests.

### CLM-005 — ARKit supports a custom Metal camera-feed renderer

- **Claim:** Apple documents retrieving ARFrame video/tracking data, drawing the camera image as a Metal backdrop, and rendering overlays with a custom Metal renderer.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `NFR-RENDER-001`, `FR-REPLACE-001`, `FR-REMOVE-001`; [ADR-005](../adr/ADR-005-realitykit-first-compositor.md).
- **Source title:** Displaying an AR Experience with Metal
- **Source URL:** https://developer.apple.com/documentation/arkit/displaying-an-ar-experience-with-metal
- **Source type:** Official Apple sample/documentation.
- **Publication/release date:** Not stated.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Current Apple Developer sample snapshot.
- **Evidence summary:** Apple describes converting the biplanar captured image through Metal textures/shaders and using ARKit tracking to draw virtual content.
- **Confidence:** High for API capability.
- **Known limitations or ambiguity:** The sample does not establish ReRoom's reveal ordering, edge quality, development cost, or frame/thermal budget. Those remain `GATE-003` measurements.

### CLM-006 — RealityKit exposes occlusion and final-frame Metal postprocessing, but suitability is empirical

- **Claim:** RealityKit supplies `OcclusionMaterial` and postprocess context textures/command resources that can support a RealityKit-first compositor with a bounded Metal escape hatch.
- **Status:** `REQUIRES_BENCHMARK`
- **Decision or requirement affected:** `FR-REPLACE-001`, `FR-REMOVE-001`, `NFR-RENDER-001`; [ADR-005](../adr/ADR-005-realitykit-first-compositor.md), [ADR-009](../adr/ADR-009-multi-surface-reveal.md); `GATE-003`.
- **Source title:** OcclusionMaterial; ARView.PostProcessContext; Implementing Postprocess Effects Using Metal Compute Functions
- **Source URL:** https://developer.apple.com/documentation/realitykit/occlusionmaterial ; https://developer.apple.com/documentation/realitykit/arview/postprocesscontext ; https://developer.apple.com/documentation/realitykit/implementing-postprocess-effects-using-metal-compute-functions
- **Source type:** Official Apple RealityKit documentation.
- **Publication/release date:** Postprocessing documented for iOS 15 and later; page dates not stated.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Current Apple Developer documentation snapshot.
- **Evidence summary:** The APIs expose invisible occluding geometry and GPU final-frame processing with source color/depth and target textures.
- **Confidence:** High for existence; low for ReRoom-specific visual/performance fitness.
- **Known limitations or ambiguity:** Documentation cannot settle transparent reveal edges, foreground ordering, depth writes, four-minute thermal stability, or the cost of a renderer switch. `GATE-003` is authoritative.

### CLM-007 — RealityKit and the web have documented USDZ/GLB loading paths

- **Claim:** RealityKit loads USD-family files including `.usdz`; Three.js `GLTFLoader` loads glTF 2.0 including `.glb`. Separate prevalidated derivatives are supportable, but parity is not automatic.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `FR-PLACE-001`, `FR-REPLACE-001`, `NFR-CONTRACT-001`, `OPS-LICENSE-001`; [ADR-010](../adr/ADR-010-asset-contract.md).
- **Source title:** Loading Entities from a File; Three.js GLTFLoader
- **Source URL:** https://developer.apple.com/documentation/realitykit/loading-entities-from-a-file ; https://threejs.org/docs/#examples/en/loaders/GLTFLoader
- **Source type:** Official Apple documentation and official Three.js documentation.
- **Publication/release date:** Not stated.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Three.js web derivative target `0.180.0` where used; RealityKit SDK version follows the pinned Xcode build.
- **Evidence summary:** Apple lists USD/USDZ and Reality formats; Three.js documents glTF 2.0 loading and `.glb` examples.
- **Confidence:** High for format-loading capability.
- **Known limitations or ambiguity:** Loading support does not establish material, animation, collision, dimensions, origin, axis, or visual parity. `GATE-011` requires device/web validation and exact asset licenses.

## 3. Next.js and browser fallback

### CLM-008 — Browser APIs belong in Next.js Client Components

- **Claim:** Current Next.js App Router documentation requires Client Components for state, events, lifecycle effects, and browser-only APIs; Server Components remain appropriate for server data/secrets.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `FR-WEB-001`, `FR-B0-001`, `NFR-CONTRACT-001`; [ADR-002](../adr/ADR-002-native-iphone-and-web-split.md), [ADR-013](../adr/ADR-013-mode-b0-guarantee.md).
- **Source title:** Server and Client Components; Static Exports
- **Source URL:** https://nextjs.org/docs/app/getting-started/server-and-client-components ; https://nextjs.org/docs/app/guides/static-exports
- **Source type:** Official Next.js documentation.
- **Publication/release date:** Not stated.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Next.js `16.2.9`; official tag https://github.com/vercel/next.js/releases/tag/v16.2.9 ; code license MIT at https://github.com/vercel/next.js/blob/v16.2.9/license.md .
- **Evidence summary:** Camera, IndexedDB, WebCodecs, interactive replay, and capability detection must execute on the client. Secrets and privileged session APIs stay server-side.
- **Confidence:** High.
- **Known limitations or ambiguity:** Next.js documentation does not grant ARKit-equivalent pose/plane/intrinsics authority to a browser.

### CLM-009 — Vercel/Next.js WebSockets are not a safe hidden P0 state boundary

- **Claim:** Vercel Functions WebSockets were Beta, require Fluid compute, pin a connection only for an instance lifetime, close at maximum function duration, and require durable state/reconnect handling; Next.js does not expose a WebSocket upgrade API and Vercel documents an experimental workaround.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `FR-WEB-001`, `NFR-RESILIENCE-001`, `NFR-LATENCY-001`; [ADR-002](../adr/ADR-002-native-iphone-and-web-split.md), [ADR-014](../adr/ADR-014-service-topology-and-hardware-tiers.md).
- **Source title:** WebSockets on Vercel
- **Source URL:** https://vercel.com/docs/functions/websockets
- **Source type:** Official Vercel platform documentation.
- **Publication/release date:** Page last updated 2026-07-02.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Vercel Functions WebSockets Beta; experimental `experimental_upgradeWebSocket()` path as documented.
- **Evidence summary:** The service lifetime/routing and framework-upgrade constraints make Next.js/Vercel unsuitable as ReRoom's canonical live session state owner.
- **Confidence:** High for documented platform state.
- **Known limitations or ambiguity:** Vercel may later stabilize the feature. A future ADR can re-evaluate it, but P0 cannot rely on the Beta/experimental path.

### CLM-010 — Browser camera access is permission- and secure-context-controlled

- **Claim:** `getUserMedia()` requires a secure context and user permission; device constraints are negotiated by the user agent and may fail.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `FR-WEB-001`, `SEC-CONSENT-001`; [ADR-002](../adr/ADR-002-native-iphone-and-web-split.md), [ADR-013](../adr/ADR-013-mode-b0-guarantee.md).
- **Source title:** Media Capture and Streams
- **Source URL:** https://www.w3.org/TR/mediacapture-streams/
- **Source type:** W3C standard/specification.
- **Publication/release date:** Current TR snapshot; exact date not recorded in the evidence extract.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Media Capture and Streams TR snapshot.
- **Evidence summary:** The spec defines permission/security checks and errors such as denial or unsatisfied constraints.
- **Confidence:** High.
- **Known limitations or ambiguity:** Browser/device policy and supported constraints vary. The web path must capability-detect and retain upload/replay fallback.

### CLM-011 — WebCodecs defines interfaces, not codec or acceleration availability

- **Claim:** WebCodecs exposes low-level media interfaces but does not guarantee that a codec or hardware acceleration is available on a particular browser/device.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `FR-WEB-001`, `FR-B0-001`, `NFR-CONTRACT-001`; [ADR-013](../adr/ADR-013-mode-b0-guarantee.md).
- **Source title:** WebCodecs
- **Source URL:** https://www.w3.org/TR/webcodecs/
- **Source type:** W3C Working Draft.
- **Publication/release date:** Working Draft revision 2026-06-09.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** 2026-06-09 Working Draft snapshot.
- **Evidence summary:** Availability is user-agent/platform dependent, so ordinary-video replay needs capability detection and a non-WebCodecs path.
- **Confidence:** High.
- **Known limitations or ambiguity:** Specific browser support changes rapidly; the declared test matrix, not the spec alone, decides shipping support.

### CLM-012 — IndexedDB can persist browser data but quota failures remain possible

- **Claim:** IndexedDB supplies transactional browser key/value storage, but writes may fail with quota exhaustion and it is not the sole durable authority for acknowledged edits.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `FR-WEB-001`, `NFR-RESILIENCE-001`, `SEC-RETENTION-001`; [ADR-012](../adr/ADR-012-transaction-and-offline-restore.md), [ADR-013](../adr/ADR-013-mode-b0-guarantee.md).
- **Source title:** Indexed Database API 3.0
- **Source URL:** https://www.w3.org/TR/IndexedDB-3/
- **Source type:** W3C specification.
- **Publication/release date:** Not recorded in the evidence extract.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** IndexedDB 3.0 TR snapshot.
- **Evidence summary:** The API supports transactions/object stores and defines quota-related failure.
- **Confidence:** High.
- **Known limitations or ambiguity:** Browser eviction/storage policy differs. ReRoom must test quota failure and use server/local-file authority appropriate to the mode.

## 4. OpenAI Realtime, Responses, models, and Codex

### CLM-013 — WebRTC plus server-minted client credentials is the supported client Realtime path

- **Claim:** OpenAI recommends WebRTC for browser/mobile Realtime clients. A trusted server either mints an ephemeral client secret or performs the unified session bootstrap; a standard API key remains server-side.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `FR-AGENT-001`, `SEC-CREDENTIAL-001`, `SEC-AGENT-001`; [ADR-011](../adr/ADR-011-agent-and-deterministic-boundary.md).
- **Source title:** Realtime API with WebRTC; Realtime API with WebSocket
- **Source URL:** https://developers.openai.com/api/docs/guides/realtime-webrtc ; https://developers.openai.com/api/docs/guides/realtime-websocket
- **Source type:** Official OpenAI API documentation.
- **Publication/release date:** Not stated on captured guide.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Current Realtime guide; documented client-secret/unified-call flows.
- **Evidence summary:** WebRTC carries audio and a data channel; the server authenticates with the standard credential and the client receives only scoped session material.
- **Confidence:** High.
- **Known limitations or ambiguity:** Availability and end-to-end latency remain external-service conditions. Typed/tap fallback is required.

### CLM-014 — GPT-Realtime-2.1 supports function calls but not Structured Outputs

- **Claim:** The official GPT-Realtime-2.1 model page lists function calling support and no Structured Outputs support.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `FR-AGENT-001`, `SEC-AGENT-001`; [ADR-011](../adr/ADR-011-agent-and-deterministic-boundary.md); `GATE-010`.
- **Source title:** GPT-Realtime-2.1 Model
- **Source URL:** https://developers.openai.com/api/docs/models/gpt-realtime-2.1
- **Source type:** Official OpenAI model documentation.
- **Publication/release date:** Page release date not reliably stated in the captured evidence.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Model identifier `gpt-realtime-2.1`.
- **Evidence summary:** Realtime can emit function-call arguments, but ReRoom must expose only the nonmutating `submit_user_intent` boundary and validate every argument.
- **Confidence:** High.
- **Known limitations or ambiguity:** Function calling does not imply authorization, semantic correctness, idempotency, or mutation safety.

### CLM-015 — GPT-5.6 Sol supports Responses function calling and Structured Outputs

- **Claim:** The official GPT-5.6 Sol page lists function calling and Structured Outputs support, and current Responses documentation defines strict JSON-schema output/tool forms.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `FR-AGENT-001`, `SEC-AGENT-001`; [ADR-011](../adr/ADR-011-agent-and-deterministic-boundary.md).
- **Source title:** GPT-5.6 Sol Model; Function Calling; Structured Outputs
- **Source URL:** https://developers.openai.com/api/docs/models/gpt-5.6-sol ; https://developers.openai.com/api/docs/guides/function-calling ; https://developers.openai.com/api/docs/guides/structured-outputs
- **Source type:** Official OpenAI model/API documentation.
- **Publication/release date:** Model page observed in the 2026 documentation set; exact release date not used as an architecture invariant.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Official model page/alias `gpt-5.6-sol`; resolve the deployable account-visible model identifier again at implementation.
- **Evidence summary:** Responses can constrain output/tool argument shape. ReRoom uses that for semantic/design proposals only.
- **Confidence:** High for documented capability.
- **Known limitations or ambiguity:** Structured schema conformance is not physical validation, access control, target correctness, or permission to commit. The implementation must not invent an unavailable model ID.

### CLM-016 — The application executes tools and must own transaction safety

- **Claim:** OpenAI function-calling documentation requires the application to receive a tool call, execute application code, and return tool output linked by `call_id`; model output does not execute the mutation itself.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `FR-TRANSACTION-001`, `FR-AGENT-001`, `SEC-AGENT-001`; [ADR-011](../adr/ADR-011-agent-and-deterministic-boundary.md), [ADR-012](../adr/ADR-012-transaction-and-offline-restore.md).
- **Source title:** Function Calling
- **Source URL:** https://developers.openai.com/api/docs/guides/function-calling
- **Source type:** Official OpenAI API documentation.
- **Publication/release date:** Not stated.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Current Responses/function-tool documentation snapshot.
- **Evidence summary:** The documented control loop leaves application execution and tool results outside the model, supporting deterministic allowlisting, revisions, validation, confirmation, and idempotency.
- **Confidence:** High.
- **Known limitations or ambiguity:** Exactly-once commit and offline restore are ReRoom requirements, not guarantees supplied by the API.

### CLM-017 — Codex stable version and project configuration are current and trust-gated

- **Claim:** The latest stable Codex release at the research snapshot was `rust-v0.144.3`; official documentation supports trusted project `.codex/config.toml`, workspace-write sandbox/network controls, MCP server tables, and bounded subagent settings.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** PRE-GSD Codex/Firecrawl preparation, `SEC-CREDENTIAL-001`; development trace for `OPS-SUBMISSION-001`.
- **Source title:** Codex 0.144.3 release; Codex Configuration Reference; MCP; Subagents
- **Source URL:** https://github.com/openai/codex/releases/tag/rust-v0.144.3 ; https://developers.openai.com/codex/config-reference ; https://developers.openai.com/codex/mcp ; https://developers.openai.com/codex/subagents
- **Source type:** Official OpenAI release and documentation.
- **Publication/release date:** `rust-v0.144.3` published 2026-07-13.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Codex `0.144.3`; release tag `rust-v0.144.3`; npm snapshot observed `@openai/codex@0.144.2` shortly before the GitHub release, so install resolution must be checked.
- **Evidence summary:** Project config loads only for trusted projects. Official keys include `sandbox_mode`, `approval_policy`, `[sandbox_workspace_write].network_access`, `[agents].max_threads/max_depth`, and stdio/HTTP `[mcp_servers.*]` settings such as command/args/env variable names, optional/required behavior and timeouts.
- **Confidence:** High.
- **Known limitations or ambiguity:** GitHub and npm can briefly lag each other. The repository should inherit the user's selected model and must not hard-code a speculative model ID.

### CLM-018 — Firecrawl MCP package and secretless project wiring are versionable

- **Claim:** The official Firecrawl MCP server package at the research snapshot was `firecrawl-mcp@3.22.3`, MIT-licensed, requiring Node `>=22.0.0`; it supports search/scrape/map/crawl/agent/extract capabilities and accepts `FIRECRAWL_API_KEY` by environment.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** PRE-GSD Firecrawl setup, research reproducibility, `SEC-CREDENTIAL-001`.
- **Source title:** Firecrawl MCP Server; npm package metadata; official MCP documentation
- **Source URL:** https://github.com/firecrawl/firecrawl-mcp-server ; https://registry.npmjs.org/firecrawl-mcp/3.22.3 ; https://docs.firecrawl.dev/mcp-server
- **Source type:** Official repository, npm registry metadata, and vendor documentation.
- **Publication/release date:** Repository version bump commit dated 2026-07-08.
- **Retrieval date:** 2026-07-14.
- **Exact version/tag/revision:** `firecrawl-mcp@3.22.3`; repository main commit `3eb1115b1f2883ff2fb74e61b5c4acf5a9ac0fb0`; MIT; Node `>=22.0.0`.
- **Evidence summary:** A pinned stdio launch can use `npx --yes firecrawl-mcp@3.22.3` while Codex passes only the environment variable name `FIRECRAWL_API_KEY`; optional startup and a read/research tool allowlist avoid making research availability fatal. The final direct official-registry scrape reconfirmed version, MIT license, Node `>=22.0.0`, and the expected executable mapping.
- **Confidence:** High.
- **Known limitations or ambiguity:** Tool inventory and hosted/free-tier limits may change. Firecrawl failure degrades research capability but must not redefine permissions or block Codex startup.

## 5. Runtime/service topology

### CLM-019 — RunPod Queue-based and Load Balancing endpoints have different semantics

- **Claim:** RunPod Queue-based endpoints provide queued sequential processing, automatic retries, and sync/async job modes; Load Balancing endpoints route directly to workers for real-time/custom streaming APIs without automatic retries.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `NFR-LATENCY-001`, `NFR-RESILIENCE-001`, `FR-B0-001`; [ADR-014](../adr/ADR-014-service-topology-and-hardware-tiers.md).
- **Source title:** Serverless Endpoints Overview
- **Source URL:** https://docs.runpod.io/serverless/endpoints/overview
- **Source type:** Official RunPod documentation.
- **Publication/release date:** Not stated on page.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** `runpod/docs` main file blob `2a4f55dc2d4b428b3ee6d787dd7e0d9a2240b1c3` as retrieved.
- **Evidence summary:** The official comparison assigns batch/guaranteed execution to Queue-based and real-time/streaming to Load Balancing.
- **Confidence:** High.
- **Known limitations or ambiguity:** Endpoint type alone does not supply ReRoom session durability or exactly-once semantics.

### CLM-020 — RunPod persistent WebSockets and warm workers have explicit lifecycle/storage costs

- **Claim:** Load-balanced workers support WebSockets; persistent connections require exposed HTTP/TCP ports. Active workers stay warm and are continuously billed; idle/execution timeouts govern worker/job life; network volumes persist across restarts but add latency and region constraints. Pods provide fuller environment control and persistent lease/network storage.
- **Status:** `REQUIRES_BENCHMARK`
- **Decision or requirement affected:** `NFR-LATENCY-001`, `NFR-RESILIENCE-001`; [ADR-014](../adr/ADR-014-service-topology-and-hardware-tiers.md); `GATE-012`.
- **Source title:** Build a Load Balancing Worker; Endpoint Settings; Pods Overview
- **Source URL:** https://docs.runpod.io/serverless/load-balancing/build-a-worker ; https://docs.runpod.io/serverless/endpoints/endpoint-configurations ; https://docs.runpod.io/pods/overview
- **Source type:** Official RunPod documentation.
- **Publication/release date:** Not stated.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Retrieved `runpod/docs` file blobs `76eb5495da80ee7b71b5008a585d8e9654f9d302`, `fa428e9f4af443fd1f3357b586abf7b5de708a85`, and `e8b639568d6435fc63ca95609fe0cc11c7c61603`.
- **Evidence summary:** The docs establish available topology/lifecycle controls and cold-start risk. They support one warm stateful Pod as the conservative live option and batch endpoints for offline jobs, subject to measurement.
- **Confidence:** High for documented controls; medium for best deployment choice.
- **Known limitations or ambiguity:** Reconnect routing, GPU availability, latency, cost and state recovery are deployment-specific. No cloud deployment was performed; `GATE-012` must measure any later declared tier.

## 6. Semantic, depth, reconstruction, reveal, and B1 candidates

### CLM-021 — Depth Anything 3 licenses differ by weight family

- **Claim:** Depth Anything 3 code is Apache-2.0; DA3Metric-Large and DA3 Base/Small model artifacts are Apache-2.0, while the listed Giant/Large/Nested weight families are CC BY-NC 4.0 and ineligible for a shipping permissive-only path.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `NFR-COORD-001`, `OPS-LICENSE-001`; [ADR-007](../adr/ADR-007-segmentation-and-depth-providers.md); `GATE-007`, `GATE-011`.
- **Source title:** Depth Anything 3 repository/model table and Hugging Face model metadata
- **Source URL:** https://github.com/ByteDance-Seed/Depth-Anything-3 ; https://huggingface.co/depth-anything/DA3METRIC-LARGE ; https://huggingface.co/depth-anything/DA3-BASE ; https://huggingface.co/depth-anything/DA3-SMALL
- **Source type:** Official model repository, license, and publisher model cards/API metadata.
- **Publication/release date:** Code pin dated 2026-07-13; model artifacts last modified 2025-11-13 through 2025-11-15.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Code `e74fd796e96b7e781a5506fd8503b6bd7232513c`; DA3METRIC-LARGE `4010e39f3634a45bc60553321fb49fb760bd594e`; DA3-BASE `f4a6c9b3c95e41c82048423d3493a81ec3fa810e`; DA3-SMALL `e08cab65ca0ec38e7826075418411ab90cab4da3`.
- **Evidence summary:** The publisher's model table and artifact metadata distinguish permissive Metric/Base/Small variants from noncommercial larger families.
- **Confidence:** High for listed artifacts/licenses.
- **Known limitations or ambiguity:** License does not establish metric/temporal/runtime fitness. Provider choice remains `REQUIRES_BENCHMARK` under `GATE-007`.

### CLM-022 — SAM 2.1 Hiera Small is public and Apache-2.0

- **Claim:** Meta's SAM 2 repository and checkpoints are Apache-2.0; the public SAM 2.1 Hiera Small checkpoint is available without gating and has explicit publisher metadata.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `FR-TARGET-001`, `OPS-LICENSE-001`; [ADR-007](../adr/ADR-007-segmentation-and-depth-providers.md); `GATE-004`.
- **Source title:** SAM 2 repository README/LICENSE; `facebook/sam2.1-hiera-small`
- **Source URL:** https://github.com/facebookresearch/sam2 ; https://github.com/facebookresearch/sam2/blob/main/LICENSE ; https://huggingface.co/facebook/sam2.1-hiera-small
- **Source type:** Official publisher repository/license and Hugging Face model card/API metadata.
- **Publication/release date:** SAM 2.1 checkpoints released 2024-09-29/30; repository pin dated 2024-12-16; artifact last modified 2025-08-15.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Code `2b90b9f5ceec907a1c18123530e92e794ad901a4`; HF artifact `ee5bba1d82bb8749febdf90f45e84b687142ba03`; Apache-2.0; ungated.
- **Evidence summary:** The README explicitly states checkpoint/code licensing and lists the Small checkpoint/runtime requirements.
- **Confidence:** High for provenance/license/access.
- **Known limitations or ambiguity:** Publisher FPS is measured on unrelated A100 conditions and is not a ReRoom latency claim. Selection remains `GATE-004`.

### CLM-023 — SAM 3.1 is gated and uses a custom restricted license

- **Claim:** SAM 3.1 was released 2026-03-27, its checkpoint is access-gated, and SAM materials use Meta's custom non-OSI SAM License rather than Apache/MIT.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `FR-TARGET-001`, `OPS-LICENSE-001`, `SEC-AGENT-001`; [ADR-007](../adr/ADR-007-segmentation-and-depth-providers.md); `GATE-004`, `GATE-011`.
- **Source title:** SAM 3 repository/license; SAM 3.1 release notes; `facebook/sam3.1`
- **Source URL:** https://github.com/facebookresearch/sam3 ; https://github.com/facebookresearch/sam3/blob/main/LICENSE ; https://github.com/facebookresearch/sam3/blob/main/RELEASE_SAM3p1.md ; https://huggingface.co/facebook/sam3.1
- **Source type:** Official publisher repository, custom license, release note, and model card.
- **Publication/release date:** SAM 3.1 release 2026-03-27; code pin dated 2026-06-15.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Code `5dd401d1c5c1d5c3eedff06d41b77af824517619`; HF artifact `daa63191845a41281374e725f4c9e51c7a824460`; gated; `license: other`/SAM License.
- **Evidence summary:** The custom license imposes use/redistribution restrictions and acceptance obligations. Access and exact applicable terms must be retained before evaluation/shipping.
- **Confidence:** High.
- **Known limitations or ambiguity:** Published multiplex speed uses H100 and many objects; it is not evidence for one-target ReRoom latency. Legal suitability requires project review; SAM 2.1 is the tie/timebox fallback.

### CLM-024 — LingBot-Map is an optional heavy offline provider with incomplete artifact metadata

- **Claim:** LingBot-Map code is Apache-2.0 and the official README describes a modern CUDA/PyTorch/FlashInfer environment; the Hugging Face artifact has an exact revision but its API card lacked explicit license metadata at retrieval.
- **Status:** `PLAUSIBLE`
- **Decision or requirement affected:** `FR-B0-001`, `NFR-COORD-001`, `OPS-LICENSE-001`; [ADR-007](../adr/ADR-007-segmentation-and-depth-providers.md), [ADR-013](../adr/ADR-013-mode-b0-guarantee.md).
- **Source title:** LingBot-Map repository/license and Hugging Face artifact
- **Source URL:** https://github.com/Robbyant/lingbot-map ; https://huggingface.co/robbyant/lingbot-map
- **Source type:** Official publisher repository/license/README and model card/API metadata.
- **Publication/release date:** Code pin dated 2026-07-12; artifact last modified 2026-07-11.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Code `7ff6f3ed0913d4d326f8f13bbb429c4ffc0195c2`; HF artifact `204754b72bb24f561f8d7e7e1e4e4cd9e809adf9`; repository `LICENSE.txt` Apache-2.0.
- **Evidence summary:** The code license is clear, while artifact metadata is less explicit. Recent runtime/cache changes and large environment/storage needs increase one-week risk.
- **Confidence:** High for code revision/license; medium for checkpoint license and runtime suitability.
- **Known limitations or ambiguity:** Author-reported performance is hardware/fixture dependent. LingBot is not part of guaranteed B0 and receives no P0 time before `GATE-008` is green.

### CLM-025 — Open3D supplies a permissive sparse TSDF reference, not a performance guarantee

- **Claim:** Open3D `0.19.0` is MIT-licensed; its tensor `VoxelBlockGrid` API supports sparse TSDF/weight/color attributes, integration, raycasting, and mesh extraction, including documented CUDA device use.
- **Status:** `REQUIRES_BENCHMARK`
- **Decision or requirement affected:** `NFR-COORD-001`, `FR-B0-001`, `OPS-LICENSE-001`; [ADR-006](../adr/ADR-006-fast-and-dense-geometry-tracks.md), [ADR-007](../adr/ADR-007-segmentation-and-depth-providers.md); `GATE-007`.
- **Source title:** Open3D tensor reconstruction documentation; PyPI metadata; repository license
- **Source URL:** https://www.open3d.org/docs/release/python_api/open3d.t.geometry.VoxelBlockGrid.html ; https://pypi.org/project/open3d/ ; https://github.com/isl-org/Open3D/blob/main/LICENSE
- **Source type:** Official project documentation, PyPI registry, and repository license.
- **Publication/release date:** `0.19.0` uploaded 2025-01-08; development main evidence pin dated 2026-07-11.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Shipping/evaluation candidate `open3d==0.19.0`; MIT. Moving-main evidence observed at `4eb88654eeb48832c902fd0cf3ccb78f58e45549` but is not the runtime pin.
- **Evidence summary:** The API can serve as a swappable server-side dense-fusion reference when depth passes its own gate.
- **Confidence:** High for API/license; low until packaged GPU/runtime behavior is measured.
- **Known limitations or ambiguity:** CUDA wheel/build availability, performance, memory, scale correctness and visual quality are environment-specific. Dense fusion cannot block the fast path.

### CLM-026 — Build Week submission dates are fixed; official judging-end pages conflict

- **Claim:** OpenAI Build Week opened 2026-07-13 and submissions close 2026-07-21 at 5:00 PM PT. The official rules list judging from 2026-07-22 at 10:00 AM PT through 2026-08-05 at 5:00 PM PT, while the organizer event page lists 2026-07-22 through 2026-08-07; the rules are the compliance authority. The event page lists winners on 2026-08-12.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `OPS-SUBMISSION-001`, `OPS-GOLDEN-001`; one-week critical path and evidence deadlines.
- **Source title:** OpenAI Build Week; OpenAI Build Week Devpost Official Rules
- **Source URL:** https://openai.com/build-week/ ; https://openai.devpost.com/rules
- **Source type:** Official organizer event page and governing official rules.
- **Publication/release date:** Rules effective 2026-07-09; event opens 2026-07-13.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** 2026 OpenAI Build Week rules/schedule snapshot.
- **Evidence summary:** The official sources agree on the opening/submission deadline but disagree on the judging end. Operational planning uses the earlier rules date rather than assuming the marketing-page extension.
- **Confidence:** High for opening/submission deadline; medium for the judging-end date until the organizer reconciles the two official pages.
- **Known limitations or ambiguity:** Recheck the live official rules before final submission for amendments and schedule reconciliation; no later page may be treated as an instruction to exceed repository permissions.

### CLM-027 — Build Week submission and judging require a working, evidenced Codex/GPT-5.6 project

- **Claim:** The submission requires a working project, category/description, repository and setup/testing guidance, a public YouTube demo under 3 minutes with audio, explanation of Codex/GPT-5.6 use, and a representative Codex `/feedback` Session ID; judging covers technical implementation, design/UX, impact, and idea quality.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `OPS-SUBMISSION-001`, `OPS-GOLDEN-001`; `TST-DEMO-001`; [ADR-001](../adr/ADR-001-product-modes-and-p0-scope.md), [ADR-013](../adr/ADR-013-mode-b0-guarantee.md).
- **Source title:** OpenAI Build Week Devpost — Details and Rules
- **Source URL:** https://openai.devpost.com/ ; https://openai.devpost.com/rules
- **Source type:** Official challenge submission page and official rules.
- **Publication/release date:** Rules effective 2026-07-09.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** 2026 challenge/rules snapshot; required technology GPT-5.6 and Codex.
- **Evidence summary:** The event evaluates a coherent runnable product and explicit development/use evidence, not an architecture document alone. The project fits the “Apps for life” category.
- **Confidence:** High.
- **Known limitations or ambiguity:** The official rules govern eligibility/IP/location and can be amended. Team-size limits were not established by the captured evidence and must not be invented.

### CLM-028 — LaMa code is permissive but the recommended checkpoint chain needs artifact review

- **Claim:** The LaMa repository code is Apache-2.0, but its current README redirects pretrained-model download through third-party Hugging Face/Google Drive locations; code license alone is insufficient shipping evidence for the selected checkpoint.
- **Status:** `UNVERIFIED`
- **Decision or requirement affected:** `FR-REMOVE-001`, `OPS-LICENSE-001`, `NFR-RENDER-001`; [ADR-009](../adr/ADR-009-multi-surface-reveal.md); `GATE-006`, `GATE-011`.
- **Source title:** LaMa repository README and LICENSE
- **Source URL:** https://github.com/advimman/lama ; https://github.com/advimman/lama/blob/master/LICENSE
- **Source type:** Official research repository, code license, and download instructions.
- **Publication/release date:** Evidence pin dated 2025-02-05; original project 2021.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Code `786f5936b27fb3dacd2b1ad799e4de968ea697e7`; code Apache-2.0; checkpoint digest/license not yet approved.
- **Evidence summary:** LaMa may be evaluated only after observed atlas and only when a specific checkpoint's digest and applicable terms are recorded.
- **Confidence:** High for code license; low for a shipping checkpoint.
- **Known limitations or ambiguity:** Old dependency stack and 2D image completion do not establish temporally stable multi-surface 3D reveal. Missing checkpoint evidence excludes it.

### CLM-029 — MapAnything has separate noncommercial and Apache weight families

- **Claim:** MapAnything code is Apache-2.0; default `facebook/map-anything` weights are CC BY-NC 4.0, while `facebook/map-anything-apache` is the publisher's Apache-2.0 alternative.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `STR-B1-001`, `OPS-LICENSE-001`; [ADR-001](../adr/ADR-001-product-modes-and-p0-scope.md), [ADR-014](../adr/ADR-014-service-topology-and-hardware-tiers.md); `GATE-014`.
- **Source title:** MapAnything repository/model table; `facebook/map-anything-apache`
- **Source URL:** https://github.com/facebookresearch/map-anything ; https://huggingface.co/facebook/map-anything-apache
- **Source type:** Official publisher repository, license/model table, and model card/API metadata.
- **Publication/release date:** Code pin dated 2026-05-30; Apache artifact last modified 2026-02-04.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Code `c845b8f4f6cde0c20aecd87573656c3f69f5b2b0`; Apache weight revision `00f9c245bbcb60522d1ed7f9e9d88462c6e3f38a`.
- **Evidence summary:** If post-P0 B1 is authorized, only the Apache artifact is eligible for a permissive path.
- **Confidence:** High.
- **Known limitations or ambiguity:** No ReRoom quality/runtime measurement exists, and B1 is disabled while any P0 gate is red.

### CLM-030 — gsplat is a permissive Gaussian-splat optimization/rendering component

- **Claim:** `gsplat` is Apache-2.0; PyPI stable was `1.5.3`, while current development main had newer Torch build requirements. It is a component for Gaussian splatting, not a complete scene-reconstruction solution.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `STR-B1-001`, `OPS-LICENSE-001`; [ADR-014](../adr/ADR-014-service-topology-and-hardware-tiers.md); `GATE-014`.
- **Source title:** gsplat repository/LICENSE and PyPI metadata
- **Source URL:** https://github.com/nerfstudio-project/gsplat ; https://pypi.org/project/gsplat/
- **Source type:** Official repository/license and PyPI registry.
- **Publication/release date:** PyPI `1.5.3` released 2025-07-04; main evidence pin dated 2026-07-09.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** PyPI `gsplat==1.5.3`; main `77ab983ffe43420b2131669cb35776b883ca4c3c`; Apache-2.0; current main build metadata requires Torch `>=2.7`.
- **Evidence summary:** The library could optimize/render Gaussian primitives in B1 but supplies neither camera/geometry truth nor P0 identity.
- **Confidence:** High for package/license; no ReRoom suitability claim.
- **Known limitations or ambiguity:** Stable PyPI and moving main differ. Any B1 experiment must select one exact compatible pin after P0.

### CLM-031 — Spark 2.1.0 is an MIT Three.js Gaussian-splat viewer

- **Claim:** `@sparkjsdev/spark@2.1.0` is an MIT-licensed Three.js Gaussian-splat renderer with a `three >=0.180.0` peer dependency.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `STR-B1-001`, `FR-WEB-001`, `OPS-LICENSE-001`; [ADR-014](../adr/ADR-014-service-topology-and-hardware-tiers.md); `GATE-014`.
- **Source title:** Spark repository package manifest, README, and LICENSE
- **Source URL:** https://github.com/sparkjsdev/spark ; https://www.npmjs.com/package/@sparkjsdev/spark
- **Source type:** Official repository/package manifest/license and npm registry.
- **Publication/release date:** Evidence pin dated 2026-06-24.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** `@sparkjsdev/spark@2.1.0`; commit `750812dcc15f3a7444765bf43af4942133fa3bcc`; MIT; Three.js peer `>=0.180.0`.
- **Evidence summary:** Spark is suitable only as an optional B1 browser render skin after a splat asset exists.
- **Confidence:** High for package/license.
- **Known limitations or ambiguity:** Publisher portability/performance statements are not ReRoom measurements. It is not needed by guaranteed B0 or P0.

## 7. GSD Core version and configuration

### CLM-032 — GSD Core stable is pinned to 1.6.1 rather than the release candidate

- **Claim:** The verified stable `@opengsd/gsd-core` release is `1.6.1`, tag `v1.6.1`, commit/npm `gitHead` `1c352d1ea37b010e99b8353905eb5def4f784100`, MIT; `1.7.0-rc.6` is prerelease and not the onboarding pin.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** Manual post-preparation GSD onboarding, version lock, profile templates, ingest/runbook syntax.
- **Source title:** GSD Core v1.6.1 release, package manifest, npm metadata
- **Source URL:** https://github.com/open-gsd/gsd-core/releases/tag/v1.6.1 ; https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/package.json ; https://registry.npmjs.org/@opengsd%2Fgsd-core/1.6.1
- **Source type:** Official release, source manifest, and npm registry metadata.
- **Publication/release date:** Release date not used as an invariant; retrieved stable state 2026-07-13.
- **Retrieval date:** 2026-07-14.
- **Exact version/tag/revision:** `@opengsd/gsd-core@1.6.1`; `v1.6.1`; `1c352d1ea37b010e99b8353905eb5def4f784100`; MIT.
- **Evidence summary:** Pinning stable prevents command/config drift during the week. The final Firecrawl recheck of the official release and tagged package manifest again returned `v1.6.1`, install target `@opengsd/gsd-core@1.6.1`, visible commit prefix `1c352d1`, and package version `1.6.1`.
- **Confidence:** High.
- **Known limitations or ambiguity:** No GSD command was executed during PRE-GSD preparation. A deliberate upgrade requires revalidating commands, schema keys, profiles, and ingest behavior.

### CLM-033 — GSD 1.6.1 package engines supersede a stale Node 18+ install statement

- **Claim:** GSD Core `1.6.1` package engines require Node `>=22.0.0` and npm `>=10.0.0`, with `.nvmrc` 22. A generic install-guide statement of Node 18+ is contradicted by the released package metadata and must not drive onboarding.
- **Status:** `CONTRADICTED`
- **Decision or requirement affected:** Manual GSD preflight and onboarding runbook.
- **Source title:** GSD Core package.json; `.nvmrc`; Install on Your Runtime
- **Source URL:** https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/package.json ; https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/.nvmrc ; https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/docs/how-to/install-on-your-runtime.md
- **Source type:** Official released source manifests and documentation.
- **Publication/release date:** GSD `1.6.1` release snapshot.
- **Retrieval date:** 2026-07-14.
- **Exact version/tag/revision:** Commit `1c352d1ea37b010e99b8353905eb5def4f784100`; Node `>=22.0.0`; npm `>=10.0.0`.
- **Evidence summary:** The executable package metadata is the higher-confidence compatibility source for the exact pin. A final direct official-registry Firecrawl scrape reconfirmed Node `>=22.0.0`, npm `>=10.0.0`, MIT, and the exact `gitHead`.
- **Confidence:** High.
- **Known limitations or ambiguity:** Future documentation/package releases may reconcile the discrepancy. Recheck only when intentionally changing the pin.

### CLM-034 — GSD 1.6.1 requires current Codex and uses skill syntax

- **Claim:** GSD documents Codex minimum `0.130.0` and recommends `>=0.137.0` for the stable hook schema; Codex skills are invoked as `$gsd-*`. The stable local installation command is version-pinned, and Codex should be restarted rather than using an unverified `codex --reload` command.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** Manual GSD onboarding runbook and verification.
- **Source title:** GSD runtime installation guide; OpenAI Codex Skills
- **Source URL:** https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/docs/how-to/install-on-your-runtime.md ; https://developers.openai.com/codex/build-skills
- **Source type:** Official GSD released documentation and official OpenAI Codex documentation.
- **Publication/release date:** GSD `1.6.1`/Codex documentation snapshot.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** GSD `1.6.1`; Codex minimum `0.130.0`, recommended `>=0.137.0`; researched Codex stable `0.144.3` satisfies both.
- **Evidence summary:** The version relationship and `$<skill-name>` convention support a reproducible manual onboarding sequence after this run.
- **Confidence:** High.
- **Known limitations or ambiguity:** The runbook commands remain manual and unexecuted. Skill discovery must be verified after installation.

### CLM-035 — GSD profile keys must come from the released schema/capability registry

- **Claim:** For GSD `1.6.1`, supported configuration is the union of the released central schema manifest and capability registry/defaults. Proposed `gates.*`, `safety.*`, and numeric/plan/task parallelization controls are unsupported; the reliable top-level parallelization control is boolean. `planning.commit_docs` defaults true and is recommended.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `quality-fast.config.json`, `maximum-assurance.config.json`, GSD key matrix, validation script, and onboarding runbook.
- **Source title:** GSD config schema/default manifests and released capability registry
- **Source URL:** https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/gsd-core/bin/shared/config-schema.manifest.json ; https://github.com/open-gsd/gsd-core/blob/1c352d1ea37b010e99b8353905eb5def4f784100/gsd-core/bin/shared/config-defaults.manifest.json
- **Source type:** Official released machine-readable configuration manifests/source.
- **Publication/release date:** GSD `1.6.1` release snapshot.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** Commit `1c352d1ea37b010e99b8353905eb5def4f784100`.
- **Evidence summary:** Templates must omit attractive but unsupported controls and validate only known keys/types.
- **Confidence:** High.
- **Known limitations or ambiguity:** Capability-scoped keys can be easy to miss when inspecting only one manifest. Any template change must rerun the version-locked key validation.

### CLM-036 — RFC 8785 provides the structured JSON canonicalization basis

- **Claim:** RFC 8785 defines JCS as a deterministic, hashable JSON representation using I-JSON constraints, ECMAScript primitive serialization, and deterministic property sorting; duplicate property names, invalid Unicode, NaN, and Infinity are invalid inputs.
- **Status:** `VERIFIED`
- **Decision or requirement affected:** `FR-CAPTURE-001`, `FR-TRANSACTION-001`, `NFR-REPLAY-001`, `NFR-CONTRACT-001`; CON-001 through CON-005; `GATE-001`, `GATE-009`.
- **Source title:** RFC 8785 — JSON Canonicalization Scheme (JCS)
- **Source URL:** https://www.rfc-editor.org/rfc/rfc8785
- **Source type:** Primary RFC Editor publication.
- **Publication/release date:** June 2020.
- **Retrieval date:** 2026-07-13.
- **Exact version/tag/revision:** RFC 8785, Informational RFC; no moving version alias.
- **Evidence summary:** JCS supplies the cross-language canonical JSON bytes used by RR-JCS-SHA256-1. ReRoom still defines each digest's exact member scope and applies stricter binary32 bounds for spatial values.
- **Confidence:** High.
- **Known limitations or ambiguity:** RFC 8785 is informational and canonicalizes structured JSON only; it does not define ReRoom's raw-file hashing, self-member omission, journal tuple scope, or transaction membership, which remain explicit ReRoom contract rules and golden vectors.

## 8. Decision summary and unresolved empirical claims

The evidence establishes safe APIs, versions, provenance, and license boundaries. It does **not** establish the following as facts: sustained base-device FPS/thermal behavior, semantic target quality, learned metric-depth accuracy, reveal credibility, provider latency/VRAM, reconnect recovery, or end-to-end voice reliability. Those are intentionally `REQUIRES_BENCHMARK` and are controlled by `GATE-003`, `GATE-004`, `GATE-006`, `GATE-007`, `GATE-010`, and `GATE-012` in [RISK_AND_KILL_GATES.md](RISK_AND_KILL_GATES.md).

The shipping bill of materials must reference the exact artifact records above or add new `CLM-NNN` records before adopting another version. Moving `main`, an unpinned model alias, a repository code license standing in for checkpoint terms, or an author-reported benchmark is never sufficient shipping evidence.
