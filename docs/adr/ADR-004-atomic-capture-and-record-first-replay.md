# ADR-004: Record-First Capture, Transport, and Replay

Status: Accepted  
Date: 2026-07-14

## Context

The archived plan says frames are enqueued before upload, while the PRD permits recording “before or while” upload. Neither wording defines a crash-safe boundary or which accepted sequence replay must reproduce.

## Project constraints

- Network loss must not destroy the capture.
- Live queues must remain bounded and never create render-loop backpressure.
- Replay must exist before live model integration.

## Alternatives considered

1. Network-first streaming with best-effort recording.
2. Simultaneous local/network queues without a durable ordering rule.
3. Durable record-first capture, binary WebSocket live packets, and HTTP keyframes/artifacts.

## Decision

Adopt alternative 3. The exact lifecycle is `selected → image_and_metadata_durable → journaled → network_eligible → server_acknowledged`; CON-002 event names prefix these values with `frame_`. A frame becomes network-eligible only after its image and metadata are atomically persisted and its reference is appended to the local global journal. The journal has one unique contiguous sequence from zero and is the sole frame/event replay order; accepted-frame and event arrays are exact projections by ID/order/durable sequence/content hash and contiguous per-type sequence. Each event carries a self-omitting RR-JCS record digest used by its journal entry; finalization names the last journal sequence. The phone keeps a bounded latest-useful send queue; stale compute work is dropped but durable capture is retained. Sparse keyframes derive from the same ARFrame and preserve their own transforms/intrinsics. `.rrcap` input digest is recomputed with RR-JCS-SHA256-1 over the ordered journal tuples defined by CON-002; packet metadata includes the SHA-256 of exact image bytes. Neural outputs require pinned providers and tolerance-based evaluation, not a bitwise promise.

## Evidence

- Network-independent rendering and deterministic replay are human-locked architecture quality rules.
- Binary WebSocket packets preserve atomic image/metadata association; regular HTTP is better suited to sparse large keyframes and complete capture upload.

## Consequences

- Mode B0 and regression testing survive live transport failure.
- Local storage throughput and recovery journaling become early device tests.
- Server acceptance and local durability are distinct metrics.

## Risks

- Image/journal crash ordering can create orphans.
- Recording pressure may cause thermal or disk issues.

## Fallback

Reduce selected-frame rate/resolution and pause upload before sacrificing durable capture. On an incomplete session, replay the valid journal prefix and report the truncated tail explicitly.

## Benchmark and kill gate

All unmeasured thresholds, fixture sizes, deadlines, and timeboxes in this gate are `TARGET`, not measured results.

`GATE-001`: use 10-second and 60-second fixtures, network blackholes, and crash injection. Two replays must produce the same ordered packet/event digest; no prior durable record may be corrupted. Deadline: first vertical slice; failure blocks live integration.

## Requirements and contracts affected

`FR-CAPTURE-001`, `FR-B0-001`, `NFR-REPLAY-001`, `SEC-RETENTION-001`, CON-001, and CON-002.

## Supersession

Supersedes the archived enqueue-only and “before or while upload” durability language. No canonical ADR is superseded.
