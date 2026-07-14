# ADR-014: Minimal Service Topology and Hardware Tiers

Status: Accepted  
Date: 2026-07-14

## Context

The archived plan assigns five owners, several always-on GPU services, multiple incompatible model environments, and a specific warm-cloud posture. Two developers cannot debug all of those simultaneously, and a specific GPU must not become a hidden dependency.

## Project constraints

- Two developers with limited parallel integration capacity.
- No cloud provisioning or deployment during preparation.
- Hardware-agnostic contracts with measured benchmark tiers.
- Live queues and GPU work must remain bounded.

## Alternatives considered

1. Many always-on microservices with every model resident.
2. One process containing all Node/Python/model dependencies.
3. Minimal logical topology: web UI, gateway replica/reconciliation authority, explicit per-branch revision authority, and selected CV worker profiles with optional environment isolation.

## Decision

Adopt alternative 3. The gateway owns sessions, ingest routing, recent-frame retention, durable replication, validation, reconciliation, credentials, and artifact events. It does not compete for revisions on an active Mode A branch: that branch's declared native device is its sole writer. A separate frozen B0 replay fork may declare the gateway as its sole authority. Next.js is a client/UI; while a phone branch is active its mutations are proposals routed to the device authority. Every scene/transaction records authority and branch IDs, and divergence is quarantined rather than automatically merged. Only provider profiles selected by gates are started; incompatible environments may be isolated, but are not all resident. SQLite WAL plus content-addressed filesystem storage is the P0 persistence baseline. GPU scheduling is bounded, priority-based, and admits no background backlog. Hardware is documented as capability tiers measured by VRAM, latency, and stability, never by a mandatory SKU. B1 profiles remain disabled under ADR-001.

## Evidence

- SAM 3.1, SAM 2.1, DA3, LingBot, Open3D, and optional fill stacks have different runtime and memory characteristics.
- Next.js does not own the production WebSocket/stateful worker boundary; see ADR-002.

## Consequences

- Fewer concurrent failure surfaces fit the human capacity.
- A later deployment can split logical workers without changing contracts.
- Local/replay development and demo hosting use the same service responsibilities.

## Risks

- Selected models may still exceed the available tier.
- SQLite/filesystem storage does not provide multi-host coordination.
- Separate worker processes can contend for VRAM if admission control fails.

## Fallback

Unload mutually exclusive providers, serialize GPU lanes, reduce input resolution/rate, disable dense work, and preserve capture/B0. Do not add Redis, PostgreSQL, Kubernetes, or a new cloud service during the week without a measured failure and superseding ADR.

## Benchmark and kill gate

All unmeasured thresholds, fixture sizes, deadlines, and timeboxes in this gate are `TARGET`, not measured results.

`GATE-012`: on each declared tier, load only the selected live profile and run a four-minute replay/live-equivalent workload. Pass requires no OOM/crash, zero unbounded queue growth, and documented p50/p95 latency/VRAM. Failure drops optional providers or the tier. `GATE-014` prevents B1 resource contention while P0 is active.

## Requirements and contracts affected

`NFR-REPLAY-001`, `NFR-LATENCY-001`, `NFR-RESILIENCE-001`, CON-001, CON-002, CON-003, and CON-005.

## Supersession

Supersedes archived five-owner, always-resident-service, and specific deployment-posture assumptions. No canonical ADR is superseded.
