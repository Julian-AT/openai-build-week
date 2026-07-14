# ADR-013: Guaranteed Mode B0 Minimum

Status: Accepted  
Date: 2026-07-14

## Context

The archived inputs make B0 guaranteed but also couple it to learned ordinary-video reconstruction, TSDF output, and a warm GPU. That makes the promised fallback depend on the least mature providers.

## Project constraints

- Recorded/replay processing is human-locked P0.
- B0 must be useful for development, regression, inspection, and demo recovery.
- Network loss during Mode A cannot instantly open a web service; local recording is the immediate protection.

## Alternatives considered

1. Guarantee B0 only when LingBot/TSDF geometry succeeds.
2. Make B0 a developer-only utility.
3. Guarantee provider-independent replay/session/transaction behavior and capability-gate learned geometry.

## Decision

Adopt alternative 3. Required B0 is `.rrcap` upload/import, manifest/hash validation, exact ordered packet/event replay, timeline and processing state, canonical scene/artifact inspection, typed transactions through the shared service, and degraded visualization using available planes, points, proxies, or cached artifacts. Ordinary video upload and deterministic media replay are supported; estimated trajectory/geometry is optional provider output with explicit readiness. B0 never rewrites Mode A identity.

## Evidence

- Human-locked B0 guarantee and record-first rules.
- LingBot’s current runtime and recent KV-cache fixes make it unsuitable as the definition of guaranteed behavior: https://raw.githubusercontent.com/Robbyant/lingbot-map/main/README.md

## Consequences

- B0 can pass without a learned model or GPU.
- Provider failure is visible without destroying the recorded session.
- The web client remains a real product path rather than a footnote.

## Risks

- A degraded viewer may be less visually impressive than a dense twin.
- “Fallback” may be misunderstood as instantaneous/offline failover.

## Fallback

When processing providers fail, preserve upload, replay, timeline, errors, typed fixture transactions, and available sparse artifacts. During live network loss, continue local Mode A rendering/recording and use B0 after connectivity or local transfer is available.

## Benchmark and kill gate

`GATE-008`: with learned providers disabled, import the golden `.rrcap`, verify hashes, replay the exact event digest twice, inspect canonical artifacts, and execute a typed fixture transaction. Ordinary video must upload and replay media with an explicit geometry-unavailable state. Failure blocks P0 B0; LingBot failure does not.

## Requirements and contracts affected

`FR-B0-001`, `FR-CAPTURE-001`, `NFR-REPLAY-001`, `NFR-RESILIENCE-001`, and CON-001 through CON-005.

## Supersession

Supersedes the archived model-dependent B0 definition and instantaneous-network-fallback implication. No canonical ADR is superseded.
