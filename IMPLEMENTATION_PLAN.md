# Reframe implementation completion plan

Status: active implementation plan

This document defines the remaining work required to turn the current Reframe
foundation into the product specified by the Master Technical Prompt. It is
written for an engineer continuing implementation from a clean checkout.

The Master Technical Prompt remains the sole product and architecture
authority. This plan sequences work and defines completion gates; it does not
change product meaning. If this plan and the Master Technical Prompt disagree,
the Master Technical Prompt wins and this plan must be corrected.

## 1. Completion definition

Reframe is complete for the current core release only when one controlled
iPhone session can perform the following real path without synthetic product
state:

1. Capture a room using ARKit while durably recording the same session.
2. Select one freestanding chair or small table by reticle, tap, or the pointer
   snapshot attached to a spoken command.
3. Establish a stable SAM track, conservative object volume, OBB, and floor
   support relation.
4. Retrieve only validated, injection-ready catalog products whose dimensions,
   category, and requested attributes are compatible with the target.
5. Let GPT-5.6 interpret and refine design intent through bounded, typed,
   non-mutating tools.
6. Preview a fitting normalized asset and, when required, its reveal bundle.
7. Commit exactly one compare-and-swap transaction after explicit spoken or
   tapped confirmation.
8. Keep the edit visible locally without a network connection.
9. Restore the previous state through an exact compensating transaction.
10. Upload or replay the same capture through the web application and inspect
    its authoritative scene, artifacts, and transaction history.

The 60 Hz phone renderer must remain independent of networks, models, workers,
the catalog, and the web application throughout this path.

## 2. Current foundation and known gaps

The repository currently contains useful contract-first foundations:

- Reframe-branded SwiftUI and ARKit application shell;
- shared schemas for frames, captures, target seeds, scenes, artifacts,
  proposals, and transactions;
- deterministic transaction and replacement-coverage logic;
- typed gateway routes and an in-memory scene authority;
- bounded GPT tool orchestration, a GPT-5.6 Responses adapter, and a Realtime
  session adapter;
- a provider boundary and real DA3Metric-Large implementation;
- target-volume and reveal-quality domain logic;
- catalog acquisition, enrichment, Qdrant, eligibility, retrieval, and delivery
  boundaries;
- a basic Next.js shell.

The repository-wide TypeScript and Python checks pass, the Swift package tests
pass, and the Reframe simulator target builds. These results prove the current
foundations, not the complete product path.

The principal gaps are:

- stale CI and residual legacy naming;
- no production session persistence, capture ingest, or artifact fan-out;
- no complete phone-to-gateway FramePacket transport;
- no real SAM 3.1 provider or stateful video tracking;
- no robust ARKit-to-depth alignment or Open3D TSDF integration;
- no complete plane-atlas and safe LaMa reveal worker;
- no end-to-end asset preparation into an injection-ready state;
- no live Qdrant catalog verification with a meaningful IKEA corpus;
- no complete iOS preview, commit, rendering, offline cache, and restore flow;
- no complete web upload, replay, twin, catalog, or session UI;
- no live OpenAI Realtime and GPT-5.6 acceptance run;
- no physical-device performance, thermal, drift, visual-quality, or recovery
  acceptance.

## 3. Mandatory repository and Reframe identity cleanup

This is the first implementation slice. Reframe must not carry live product,
build, test, CI, documentation, or package surfaces that still belong to
ReRoom. Every legacy item must be removed when obsolete or deliberately
adapted when it still implements a valid Reframe requirement.

The cleanup includes:

- replace all `ReRoom`, `reroom`, and `REROOM` names in tracked files;
- remove the old `ReRoomDeviceProof` and `ReRoomContracts` project/package
  references from CI and local build settings;
- change CI to build the Reframe Xcode project and test SpatialCore;
- change the stale vision workspace path from the former inference application
  to the Reframe vision application;
- update the stale workspace identity embedded in the Bun lockfile;
- replace the old `RR` brand mark and all old demo/gate copy in the web client;
- inspect Xcode targets, schemes, bundle identifiers, product names, module
  names, Swift symbols, tests, environment keys, caches, and generated settings;
- remove ignored legacy ReRoom directories from developer machines after
  confirming that they contain no unique user work;
- review old protocol abbreviations rather than preserving them accidentally;
  in particular, the capture manifest format must agree with the `.rfcap`
  Reframe contract instead of retaining an unexplained legacy acronym;
- remove obsolete GSD and planning-state comments or ignore rules; repository
  operation is governed by AGENTS.md and the Master Technical Prompt;
- keep the repository root intentionally small and do not recreate root
  planning, fixture, evidence, script, test, tool, or generated-output trees.

Reusable modules should use capability names such as SpatialCore, Capture,
Catalog, Agent, Protocol, Render, and Transactions. Only the application and
user-facing product surface should need the Reframe brand. No new module should
be named as a proof, demo, hack, spike, or device proof.

The cleanup gate is:

- case-insensitive source search finds no ReRoom reference in the current
  working tree;
- no obsolete project, scheme, directory, package, lockfile identity, CI path,
  fixture label, or user-facing mark remains;
- Reframe CI runs the same current targets that pass locally;
- the worktree contains no tracked GSD state and no ignored legacy ReRoom
  project directory;
- repository checks, Swift tests, and the Reframe simulator build still pass.

Git history is not rewritten. Historical commit messages are historical facts;
all current files, artifacts, and automation must use Reframe.

## 4. Execution principles

All remaining work follows these rules:

- Build vertical, independently verifiable slices in the order below.
- Add behavior through typed ports before binding an external provider.
- Make every queue bounded and every background task cancellable.
- Never make the phone renderer wait for network or inference.
- Keep models advisory. Deterministic code owns identity, geometry, revisions,
  validation, confirmation, commit, persistence, and restore.
- Treat product pages, browser output, metadata, GLBs, model output, and images
  as untrusted input.
- Keep credentials, models, captures, catalog data, content-addressed binaries,
  databases, and generated reports outside Git.
- Commit after every coherent green slice with a Conventional Commit subject.
- Do not represent a mock, fixture, local unit test, or successful HTTP status as
  evidence that a live external integration works.

## 5. IKEA catalog acquisition strategy

### 5.1 Upstream downloader assessment

The
[IKEA 3D Model Batch Downloader](https://github.com/apinanaivot/IKEA-3d-model-batch-downloader)
is useful evidence that IKEA product pages can expose downloadable GLB model
URLs. At the reviewed revision
[`3a036f1`](https://github.com/apinanaivot/IKEA-3d-model-batch-downloader/commit/3a036f1820c44b470aded71e651a1e791fd5d022),
the project:

- opens IKEA category and product pages with Selenium;
- discovers product links and color variants;
- reads the `pip-xr-viewer-model` payload to obtain a GLB URL;
- downloads GLB files; and
- records URL, name, color, GLB URL, and download state in SQLite.

It is not itself a Reframe-ready catalog pipeline. It is tested only against
IKEA Finland, relies on page-specific selectors and unbounded scrolling, stores
very limited metadata, performs no secure asset validation or normalization,
does not create USDZ or collision derivatives, and is
[licensed GPL-3.0](https://github.com/apinanaivot/IKEA-3d-model-batch-downloader/blob/main/LICENSE).

Reframe must therefore use it in one of two isolated ways:

1. Run the pinned tool externally as a research/acquisition utility and import
   its SQLite/GLB outputs through a typed Reframe importer; or
2. Use the observed acquisition mechanism as research for an independently
   implemented, authorized Reframe source adapter without copying or vendoring
   GPL code.

The upstream repository must not be copied into a distributed Reframe service,
and its dependency tree must not enter the application images. Its output is
untrusted data and passes through the same quarantine pipeline as every other
source.

The external-output importer accepts an operator-selected SQLite database and
download directory. It reads only the upstream `url`, `name`, `color`,
`glb_url`, and `downloaded` columns, validates the schema version it knows,
resolves each binary by content rather than trusting its filename, computes the
hash, and emits normal Reframe discovery/acquisition records. It must never
execute the upstream script, import its Python module, or write directly to
Qdrant. Re-importing identical outputs is idempotent.

### 5.2 Authorization and content rights gate

The downloader's software license does not grant rights to IKEA product pages,
metadata, imagery, trademarks, or model files. IKEA's current US terms restrict
automated scraping and reuse without prior permission. Acquisition must
therefore be enabled only for markets, locales, endpoints, metadata fields, and
assets for which the project has recorded authorization.

The source adapter must support an authorization policy with:

- source and owner;
- market and locale;
- permitted discovery mechanism;
- permitted metadata and binary types;
- permitted internal, demo, or distribution use;
- attribution obligations;
- authorization reference and review date;
- retention and deletion requirements;
- an explicit disabled state when authorization is absent or withdrawn.

No environment variable or command-line flag may silently bypass this policy.
The pipeline must fail closed before starting a crawl or download when the
configured frontier is not authorized.

### 5.3 Meaning of catalog completeness

“Get all IKEA products we can” means:

> Enumerate the complete discoverable and authorized product frontier for every
> configured market and locale, retain every valid variant and all permitted
> metadata, acquire every discoverable permitted GLB, and report every omission
> or failure explicitly.

It does not mean that every IKEA SKU is guaranteed to have a public 3D model.
IKEA states that a product may be absent from IKEA Kreativ because no 3D model
has been created for it. Catalog coverage is therefore measured, not assumed.

Each catalog run must produce durable machine-readable counters for:

- category pages and product pages discovered;
- canonical products and variants discovered;
- products with and without a model reference;
- model URLs observed;
- assets downloaded, unchanged, deduplicated, retried, and failed;
- assets quarantined by each validation reason;
- assets normalized and derived successfully;
- products enriched and embedded;
- products indexed;
- products eligible for placement;
- products eligible for replacement; and
- products synchronized to the primary client cache.

A crawl that terminates early, encounters a selector change, or indexes zero
injection-ready assets must fail its completeness gate visibly.

### 5.4 Source discovery and checkpointing

Implement acquisition behind a `CatalogSource` port. A source yields immutable
discovery records and never writes directly to Qdrant.

The IKEA source must provide:

- market- and locale-scoped frontiers;
- category discovery and pagination/continuation detection;
- product canonicalization and variant relationships;
- controlled browser observation only where static metadata is insufficient;
- bounded concurrency and per-origin rate limits;
- retry with jittered exponential backoff and a finite retry budget;
- ETag and Last-Modified support where available;
- resumable checkpoints keyed by source, market, locale, and frontier revision;
- tombstone detection without destroying the last valid catalog record;
- raw response hashes and parser version;
- selector-drift detection with a failed health state;
- deterministic idempotency across repeated runs.

Never use a browser session as the database. Persist discovery state before
downloading binaries so a run can resume without re-enumerating successful
pages.

### 5.5 Product metadata model

Keep raw source facts separate from normalized and AI-enriched facts. At
minimum, retain:

- stable Reframe product ID and source product/article ID;
- parent product and variant IDs;
- market, locale, language, canonical product URL, and source timestamps;
- display name, product family, category, subcategory, description, and variant
  label;
- source-provided color, material, style, dimensions, package facts, and weight
  when permitted and available;
- current price, currency, and availability with an observation timestamp,
  never as immutable product truth;
- primary and gallery image references with provenance;
- observed GLB URL, response validators, content type, byte length, and hash;
- source authorization, distribution eligibility, attribution, and rights
  status;
- parser version and raw-record hash;
- normalized dimensions, origin, forward axis, collision facts, derivative
  references, and validation results;
- GPT-derived visual description and tags with model, prompt, and source-image
  references;
- embedding model, vector schema version, and input digest.

Model-derived descriptions may augment retrieval but must never overwrite
source facts. Product instructions or text found on pages are data and are not
included as executable agent instructions.

### 5.6 Secure GLB acquisition and quarantine

Binary acquisition writes first to a quarantine area in the catalog volume.
Before parsing or deriving an asset:

- allowlist the expected HTTPS origins and reject credentials in URLs;
- bound redirects, response time, compressed and expanded byte sizes;
- verify content type and GLB magic before trusting file extensions;
- compute SHA-256 while streaming and store by content hash;
- deduplicate identical assets across product variants;
- parse in an isolated worker with CPU, memory, and execution limits;
- reject path traversal, remote external resources, unsupported extensions,
  malformed accessors, invalid buffer ranges, excessive geometry, excessive
  texture dimensions, and decoder failures;
- record every rejection without indexing the asset as eligible;
- retain the source-to-content mapping separately from the content object.

The content-addressed source GLB becomes immutable after validation. Derived
artifacts are versioned by source hash plus processor configuration digest.

### 5.7 Asset normalization and derivatives

An asset becomes prepared only after a deterministic processing worker has:

1. Loaded the validated source GLB.
2. Resolved source units and checked metadata dimensions against computed mesh
   bounds.
3. Converted geometry to metres without semantically resizing the product.
4. Set a floor-contact-center origin and the canonical forward axis.
5. Removed or rejected unsupported animation, camera, light, or executable-like
   extension content.
6. Repacked materials and textures within mobile and web budgets.
7. Generated bounded levels of detail where needed.
8. Generated a low-poly collision proxy distinct from visible geometry.
9. Produced the compressed delivery GLB.
10. Produced a compliant USDZ derivative for RealityKit.
11. Rendered a canonical turntable and thumbnail from the delivered geometry.
12. Reopened and validated both delivery assets.
13. Recorded byte lengths, SHA-256 hashes, processor versions, and provenance.

The USDZ must be tested through the same RealityKit loading path used by the
phone. The GLB must be tested through the same Three.js path used by the web
client. Merely creating the files is insufficient.

### 5.8 Catalog lifecycle and eligibility

Use explicit monotonic processing states:

```text
discovered
  -> metadata_ready
  -> acquired
  -> source_validated
  -> normalized
  -> derivatives_ready
  -> enriched
  -> indexed
  -> injection_ready
```

Any stage may transition to `quarantined`, `source_unavailable`, `rights_blocked`,
or `retired`, with a reason and prior valid state preserved.

`injection_ready` is true only when the product has:

- valid authorization and distribution status;
- stable Reframe and source identities;
- validated source metadata and dimensions;
- normalized visible geometry;
- a verified collision proxy;
- verified GLB and USDZ derivatives within budgets;
- hashes and provenance for every delivered artifact; and
- a compatible category and support classification.

The current pipeline does not construct its prepared-asset record, so current
live imports would be indexed as ineligible. Wire acquisition, normalization,
derivation, validation, enrichment, and indexing into one resumable state
machine before claiming live catalog readiness.

## 6. Qdrant and catalog RAG

### 6.1 Storage boundary

Qdrant is a retrieval index, not the catalog authority. Canonical metadata,
processing state, rights, source relationships, and asset manifests belong in
the catalog store. Qdrant points carry stable IDs and denormalized filter fields
needed for retrieval.

Keep the current versioned named-vector design:

- `semantic_v1`: 1,024-dimensional text-plus-visual-description embedding;
- `visual_v1`: reserved for a separately versioned local image embedding.

Do not insert incompatible vectors into one unnamed field. A model change
creates a new named vector or collection migration with an explicit reindex
operation.

### 6.2 Semantic vector construction

Construct the semantic input from normalized fields in a stable order:

- category and product family;
- display name and source description;
- color, material, style, and form tags;
- metric dimensions and support type;
- GPT-5.6 visual description generated from permitted product imagery;
- market and locale where semantically relevant.

Store the exact input digest, embedding model, dimensions, and schema version.
Do not embed volatile price or availability into the semantic vector; keep them
as filterable payload values.

### 6.3 Image-based retrieval

The first complete path uses GPT-5.6 vision to convert canonical turntables and
target crops into the same bounded vocabulary used by semantic retrieval. The
later `visual_v1` path may use a pinned local image encoder after its license,
quality, latency, and vector dimension are verified.

Image retrieval must:

- use only selected target crops, not the full room video;
- bind crops to object and frame IDs;
- redact or discard irrelevant background where practical;
- return stable product IDs and scores;
- remain optional when OpenAI or the visual encoder is unavailable;
- never bypass geometric eligibility.

### 6.4 Retrieval order

Candidate selection is deliberately hybrid:

1. Filter deterministically by authorization, injection readiness, category,
   support type, dimensions, delivery availability, market, and explicit user
   constraints.
2. Rank the surviving bounded set by `semantic_v1` and, when available,
   `visual_v1` similarity.
3. Calculate deterministic fit, collision, clearance, and replacement coverage.
4. Give GPT-5.6 at most the bounded validated candidate set for preference
   reranking and explanation.
5. Prepare at most one typed preview proposal.

The model never receives a direct Qdrant mutation tool and never promotes an
ineligible point. Empty or stale indexes produce a typed unavailable result and
leave manual placement functional.

### 6.5 Live catalog acceptance

Catalog completion requires a live, persistent Qdrant run rather than mocked
ports. Prove:

- collection creation and payload indexes are idempotent;
- a repeated import produces no duplicate products or assets;
- changed metadata updates the intended point without changing stable IDs;
- removed rights immediately exclude a product from retrieval;
- only `injection_ready` products are returned;
- natural-language style/color/material queries return relevant products;
- dimension filters reject physically incompatible products;
- target-image queries improve or preserve bounded candidate relevance;
- every search result resolves to hash-verified GLB and USDZ delivery;
- Qdrant restart and snapshot restore preserve the index;
- the coverage report reconciles catalog-store and Qdrant counts.

## 7. Protocol and cross-runtime completion

Before adding more product behavior, finish the shared protocol as the single
wire authority:

- complete schemas for sessions, plane events, pointer contexts, capability
  states, artifact activation, reconnect, catalog manifests, and processing
  states;
- generate or maintain strict Swift, TypeScript, and Python adapters from the
  same definitions;
- reject unknown state-changing fields and incompatible major versions;
- implement canonical JSON SHA-256 behavior identically across runtimes;
- implement row-major matrix serialization and ARKit/OpenCV transforms exactly;
- prove the known-ray projection and encoded-intrinsics transformations;
- preserve FramePacket byte layout, flags, queue semantics, and frame identity;
- make `.rfcap` append/durability/replay behavior byte- and order-consistent;
- complete authoritative replay, CAS, idempotency-fingerprint, inverse, and
  divergence tests.

Contract changes must update all runtime adapters and their tests in the same
commit. No application may declare a parallel copy of a public wire type.

## 8. Gateway and persistence

Replace process-local demo state with the Master Technical Prompt's durable
single authority:

- room-scoped authentication and short-lived JWTs;
- durable session lifecycle in SQLite WAL;
- atomic frame acceptance and `.rfcap` persistence before network fan-out;
- one binary frame ingest WebSocket per phone;
- five-second/64-frame recent ring for target semantics;
- latest-only bounded geometry queue;
- plane, pointer, target, and tracking-state event ingest;
- signed high-resolution keyframe and artifact upload/download;
- canonical scene store and append-only transaction journal;
- explicit preview records that do not change scene revision;
- CAS commit with idempotency-key and request-fingerprint binding;
- immutable committed history and exact compensating restore;
- artifact event WebSocket with reconnect delta/full-snapshot behavior;
- client artifact activation acknowledgement;
- session deletion covering files, database rows, derived artifacts, and
  sensitive logs;
- a bounded GPU lane coordinator enforcing the specified priority order.

Every worker request must be authenticated, session-bound, idempotent where
appropriate, cancellable, and guarded by size and timeout limits.

## 9. Vision pipeline

### 9.1 NVIDIA runtime gate

On the NVIDIA host, verify the pinned Python environment, CUDA visibility,
driver compatibility, model hashes, cold-load behavior, warm inference, peak
VRAM, and OOM behavior. Keep model sources, environments, and weights in the
external Reframe data volume.

DA3, SAM, LaMa, TSDF extraction, and any mapping provider must not launch
uncoordinated heavy work. The GPU coordinator retains only the newest eligible
depth frame and prioritizes an active target request.

### 9.2 Depth and alignment

Complete the DA3 path by:

- accepting the exact encoded-image intrinsics and provider input digest;
- converting output to OpenCV optical-axis Z depth in metres;
- projecting distributed ARKit feature points and plane intersections;
- fitting bounded robust scale first and affine bias only when justified;
- applying temporal smoothing only to accepted estimates;
- rejecting low-support or high-residual frames;
- recording frame-level provider, alignment, timing, and rejection diagnostics;
- comparing the metric and pose-conditioned DA3 providers through the same
  recorded capture before selecting the active ARKit provider.

LingBot-Map remains an isolated ordinary-video provider. It must not replace
ARKit poses during a healthy native session.

### 9.3 SAM 3.1 semantics

After the human license gate and checkpoint hash are recorded:

- create the isolated semantics service and readiness contract;
- accept only point/box seeds bound to exact encoded pixels and frame IDs;
- maintain one bounded stateful primary target track per active session;
- store compressed RLE masks, confidence, and provenance;
- request additional views when baseline or confidence is insufficient;
- preserve stable object identity across mask revisions;
- retire or mark uncertain contradictory and lost tracks;
- prioritize target work above background depth and extraction;
- verify coordinate round trips against iOS target seeds.

### 9.4 Conservative fast geometry

Implement the first-edit path independently of dense TSDF:

- collect calibrated masks from useful baselines;
- establish the bounded 3D ROI from rays, room bounds, and support plane;
- accumulate weighted voxel occupancy rather than strict all-view intersection;
- close, fill, and conservatively dilate the result;
- extract the OBB, floor support, mask volume, and optional mask mesh;
- expose independent `tracked`, `geometry_ready`, `replace_ready`, and
  `remove_ready` states;
- fail closed when view diversity or support is insufficient.

### 9.5 Dense TSDF

After alignment is accepted, implement Open3D CUDA `VoxelBlockGrid` fusion:

- confidence filtering and edge erosion before integration;
- target/dynamic-object exclusion where required;
- bounded room envelope and active block count;
- canonical block addressing independent of Open3D buffer positions;
- bounded extraction cadence and interaction-triggered extraction;
- retained-scene occluder chunks, surface meshes, plane refinements,
  dimensions, collision proxies, raycasts, and Mode B0 geometry;
- atomic artifact revisions that upgrade existing stable object IDs.

### 9.6 Reveal generation and LaMa

LaMa is a background-fill fallback, not the replacement engine and not the
segmentation model.

Complete the reveal path by:

- assembling metric floor and wall atlases from observed pixels;
- rejecting foreground pixels with masks and validated geometry;
- retaining per-texel observed/synthesized provenance;
- using observed samples first and deterministic local fill second;
- converting the official LaMa checkpoint through a restricted one-time
  process into a tensor-only artifact before application loading;
- running LaMa only in the isolated reveal worker;
- generating multi-surface reveal polygons, textures, alpha, provenance, and
  view envelopes;
- calculating the required sampled-view coverage and seam/texture gates;
- leaving `remove_ready` false when any gate fails while allowing safe
  replacement to proceed;
- freezing committed reveal revisions unless an objective improvement passes
  the update threshold.

## 10. Native iPhone application

Complete the native product as capability-oriented modules:

- ARSession configuration, tracking-state handling, floor/wall plane events,
  raycasts, and world-version discontinuity handling;
- frame selection with bounded encoding and transport queues;
- atomic `.rfcap` recording before upload;
- sparse high-resolution keyframe capture with independent transformed
  intrinsics;
- target seed creation from reticle dwell, tap, and utterance-time pointer;
- room-scoped authentication, frame WebSocket, event WebSocket, signed uploads,
  and reconnect reconciliation;
- artifact download, size/hash verification, RealityKit resource creation, and
  activation acknowledgement;
- camera-background compositor with occluders, reveal surfaces, assets,
  shadows, light adaptation, reticle, coaching, and capability UI;
- immediate local placement ghost and smooth server correction;
- replacement preview without revision mutation;
- explicit spoken or tapped confirmation;
- committed EditKit cache and offline continuation;
- immediate local inverse followed by canonical restore synchronization;
- graceful voice, network, model, and tracking failure states.

Verify RealityKit behavior on a physical target device. If ordering,
occlusion, alpha/depth behavior, or sustained rendering cannot meet the Master
Technical Prompt, implement the defined Metal compositor fallback rather than
weakening the requirement.

## 11. Agentic OpenAI path

The assistant must be useful, live, and visibly agentic while remaining outside
canonical authority.

Complete the gateway/OpenAI integration with:

- server-minted ephemeral Realtime credentials; the standard API key never
  reaches iOS or web clients;
- direct iPhone WebRTC connection for full-duplex, interruptible speech;
- the single narrow Realtime function `submit_user_turn`;
- server binding of session, scene revision, identity, and pointer context;
- one repair or concise clarification for malformed or ambiguous input;
- GPT-5.6 Responses planning with strict schemas and no additional properties;
- only the five public read-only/preview tools defined by the Master Technical
  Prompt;
- at most six tool calls, eight validated candidates, and one pending proposal
  per turn;
- preservation of required Responses continuation items across tool calls;
- cancellation and barge-in propagation;
- typed input using the exact same planning path when voice is unavailable;
- redacted tracing containing request IDs, tool decisions, timings, and
  validation outcomes without raw room video, unrestricted audio, secrets, or
  sensitive full prompts.

OpenAI's current tool guidance supports strict custom functions through the
Responses API, and its Realtime WebRTC guidance requires standard credentials
to remain on the server while the client receives an ephemeral credential.
Keep the implementation aligned with those official API contracts.

The live acceptance scenario is:

> Replace this chair with something warmer and red, but keep the walkway clear.

The system must resolve the selected target, retrieve eligible products,
receive deterministic rejection or acceptance, revise the choice when needed,
explain the result, and prepare one preview. It must never manufacture spatial
facts or commit the edit itself.

## 12. Placement, replacement, and restore

Complete deterministic edit behavior in this order:

1. **Place:** ARKit raycast, local ghost, normalized floor-contact asset,
   collision/bounds/wall/clearance validation, preview, confirmation, CAS commit.
2. **Replace:** resolved target, dimensional filtering, exact delivered opaque
   geometry coverage, bounded yaw/translation search, optional reveal support,
   preview, confirmation, atomic target/reveal/asset commit.
3. **Remove:** same target resolution, but enabled only when the reveal bundle
   passes every automatic coverage and quality gate.
4. **Restore:** verified captured-exact inverse, immediate local application,
   immutable prior history, and a new canonical compensating transaction.

No fifth public undo operation is introduced. Preview never increments the
revision. A stale base revision revalidates or rejects; it never auto-merges.

## 13. Web Mode B0

Replace the static shell with the guaranteed universal client:

- landing and concise product explanation;
- session list, create, deletion, and status;
- `.rfcap` and ordinary video upload with resumable progress;
- low-priority browser video capture;
- synchronized frame/pose/event replay;
- Three.js mesh or point twin with stable scene IDs;
- target selection and the same typed/voice proposal path;
- catalog browsing with injection-readiness and delivery status;
- artifact, capability, revision, transaction, and worker diagnostics;
- reconnect and session authorization behavior;
- responsive desktop and mobile operation;
- meaningful component, contract, route, and user-flow tests.

Ordinary video routes through LingBot-Map. Native `.rfcap` sessions retain
ARKit as pose authority. Mode B1 remains disabled until the complete Mode A and
Mode B0 acceptance gates pass.

## 14. Runtime, deployment, and operations

Provide the Master Technical Prompt's explicit services and profiles:

- web;
- trusted API gateway;
- semantics worker;
- geometry worker;
- ordinary-video mapping worker;
- reveal worker;
- Qdrant;
- optional disabled polish worker.

Use one shared mounted data volume for sessions, models, assets, Qdrant, and
redacted logs. Model preparation is an explicit operation with pinned sources
and hashes; service startup must never download a model.

Add health, readiness, and dependency reporting that distinguishes:

- process alive;
- model loaded and hash verified;
- GPU usable;
- provider ready;
- catalog store ready;
- Qdrant ready and schema-compatible;
- artifact storage writable;
- external OpenAI connectivity available;
- degraded but locally usable product behavior.

Production startup must reject missing secrets, unsafe public worker binding,
schema incompatibility, unverified model artifacts, and unwritable durable
storage. Shutdown must drain or cancel bounded work without corrupting accepted
captures or committed transactions.

## 15. Privacy, security, and supply chain

Before end-to-end acceptance:

- implement explicit capture/upload consent and recording/network indicators;
- distinguish room-frame processing from OpenAI audio and selected-crop use;
- use encrypted transport, short-lived room-scoped credentials, and signed
  artifact URLs;
- enforce session isolation on every worker and artifact access;
- delete raw uploaded frames by the configured default retention policy;
- implement complete session deletion;
- prevent raw imagery, audio, secrets, and user identifiers from ordinary logs;
- pin and inventory every dependency, model, converter, and external source;
- record license, checkpoint/source revision, download URL, byte length, and
  SHA-256 before use;
- scan downloaded assets and derived packages before delivery;
- ensure GPL research tooling is not linked into or distributed with Reframe;
- keep all product and asset rights distinct from source-code licenses.

## 16. Verification matrix

### 16.1 Repository gate

- clean tracked worktree;
- no active ReRoom or GSD residue;
- formatting, lint, typecheck, unit tests, and builds pass;
- Swift package tests pass;
- Reframe simulator build passes;
- CI uses current paths and reproduces the local gates;
- lockfiles are current and no credentials or generated corpora are tracked.

### 16.2 Contract gate

- cross-runtime coordinate vectors agree;
- canonical JSON and SHA-256 agree;
- FramePacket parsing rejects corrupt lengths and unknown incompatible versions;
- capture replay preserves frames, timestamps, poses, intrinsics, and events;
- transaction CAS, idempotency, divergence, inverse, and restore behavior pass;
- artifact activation cannot advance on a hash or resource-creation failure.

### 16.3 Catalog gate

- authorized discovery resumes and deduplicates correctly;
- coverage counters reconcile every discovered product and asset;
- malformed or hostile assets are quarantined;
- normalized dimensions and origins match product truth;
- GLB, USDZ, collision, thumbnail, provenance, and hashes are present;
- a real Qdrant instance returns only injection-ready products;
- semantic and image-assisted searches return compatible candidates;
- each returned product resolves to verified deliverable artifacts;
- client primary-cache sync is explicit and reproducible.

### 16.4 GPU and vision gate

- pinned CUDA environments load each verified model;
- scheduler priority and backpressure work under load;
- target seeds maintain exact frame/pixel identity;
- multi-view volume produces stable OBB and support;
- depth alignment rejects weak frames and satisfies metric checks;
- TSDF remains bounded and exports canonical geometry;
- reveal coverage and seam gates control `remove_ready` honestly;
- worker restart never corrupts canonical scene or catalog state.

### 16.5 Agent gate

- live Realtime WebRTC connects using only ephemeral client credentials;
- typed fallback uses the identical planning boundary;
- strict GPT-5.6 tools bind authoritative server context;
- tool and candidate limits are enforced;
- ambiguous, stale, rejected, cancelled, and timeout paths are safe;
- no model call can commit, restore, or directly mutate canonical state;
- traces are useful and redacted.

### 16.6 Physical product gate

Run the controlled chair/table scenario on the target iPhone and verify:

- sustained camera/compositor performance and acceptable thermal state;
- stable target identity and world anchoring;
- replacement coverage from the captured view envelope;
- coherent retained-scene occlusion and contact;
- no visible real-object fragments in accepted replacement views;
- reveal quality when removal is enabled;
- immediate local restore;
- tracking-loss, network-loss, and reconnect behavior;
- replay and inspection of the same session in the web application.

Physical and visual checks remain pending until performed by a human on real
hardware. They cannot be replaced by generated screenshots or unit tests.

### 16.7 Performance and resource gate

Measure the targets defined by the Master Technical Prompt rather than merely
confirming functional output:

- phone rendering targets 60 FPS and must remain at or above the defined hard
  fallback threshold;
- capture, model, queue, artifact, and transaction latency are recorded by
  frame, request, and revision IDs;
- accepted-frame and worker queues show no sustained growth;
- target tracking, replacement readiness, reveal readiness, spoken-command,
  validation, and artifact-activation latency meet their percentile targets;
- phone memory and thermal state remain within the target-device envelope;
- mask volumes, meshes, reveal bundles, occluders, assets, deltas, and
  keyframes remain within their artifact budgets;
- peak GPU memory and model residency conform to the coordinator policy;
- any missed target produces an explicit degraded behavior or failed gate, not
  a revised target hidden in implementation configuration.

## 17. Ordered implementation slices

Complete and commit these slices in order. A later slice may begin only when
its required preceding boundary is green.

1. Repository identity purge and current CI.
2. Protocol gaps and cross-runtime contract vectors.
3. Durable gateway sessions, capture ingest, journal, and artifact transport.
4. NVIDIA environment and live DA3 CUDA verification.
5. SAM 3.1 provider, target tracking, and target-seed round trip.
6. Conservative multi-view volume, OBB, support, and capability states.
7. Authorized IKEA discovery evaluation and external-downloader importer.
8. Secure content-addressed acquisition and catalog state machine.
9. GLB normalization, collision, USDZ, delivery validation, and client cache.
10. Live Qdrant indexing, retrieval, coverage reporting, and catalog UI.
11. Robust depth alignment and bounded Open3D TSDF.
12. Plane atlases, deterministic fill, safe LaMa provider, and reveal bundles.
13. iOS networking, artifact cache, compositor, preview, commit, and restore.
14. Live Realtime and GPT-5.6 proposal loop.
15. Web session upload, replay, twin, catalog, and typed edit path.
16. End-to-end recovery, privacy, security, performance, and physical-device
    acceptance.

Each slice requires behavior tests, failure tests, package checks, secret scan,
diff validation, and one focused commit. Record unavailable hardware, external
authorization, model-license acceptance, and human visual checks as explicit
open gates rather than silently weakening the completion definition.

## 18. Primary external references

- [Reframe Master Technical Prompt](MASTER_TECHNICAL_PROMPT.md)
- [IKEA 3D Model Batch Downloader](https://github.com/apinanaivot/IKEA-3d-model-batch-downloader)
- [IKEA US Terms and Conditions](https://www.ikea.com/us/en/customer-service/terms-conditions/)
- [IKEA Kreativ model availability explanation](https://www.ikea.com/us/en/customer-service/knowledge/articles/1d6d3f2c-ddb7-4186-g00c-3g887c99cfgd.html)
- [OpenAI Responses tools](https://developers.openai.com/api/docs/guides/tools)
- [OpenAI Realtime over WebRTC](https://developers.openai.com/api/docs/guides/realtime-webrtc)
- [SAM 3 source](https://github.com/facebookresearch/sam3)
- [Depth Anything 3 source](https://github.com/ByteDance-Seed/Depth-Anything-3)
- [LingBot-Map source](https://github.com/robbyant/lingbot-map)
- [Open3D tensor reconstruction](https://www.open3d.org/docs/latest/tutorial/t_reconstruction_system/integration.html)
