# ADR-002: Native iPhone Hero and Separate Web Client

Status: Accepted  
Date: 2026-07-14

## Context

Mode A needs direct ARKit frames, transforms, recording, native rendering, and predictable thermal behavior. Mode B0 needs upload, replay, debugging, sharing, and cross-device inspection.

## Project constraints

- The live hero must run on a physical base iPhone 17.
- High-rate buffers may not cross a WebView or scripting bridge.
- The web client must not be represented as equivalent to native live AR.

## Alternatives considered

1. One browser/PWA client for all modes.
2. A cross-platform wrapper such as Unity, Flutter, or Capacitor.
3. Native SwiftUI/ARKit Mode A plus a separate Next.js Mode B0 client.

## Decision

Adopt alternative 3. SwiftUI owns application flow and UI; a native AR rendering/session boundary owns `ARSession`, camera buffers, capture, and compositing. Next.js is a separate browser UI for sessions, upload, replay, fallback inspection, sharing, and typed B0 transactions. The gateway, not a Next.js route handler, owns production WebSockets and stateful processing.

## Evidence

- Apple exposes the AR session through RealityKit’s `ARView`: https://developer.apple.com/documentation/realitykit/arview/session
- Current Next.js production route handling does not supply application WebSocket upgrades: https://github.com/vercel/next.js/blob/v16.2.10/packages/next/src/server/next-server.ts
- Human-locked client split in the governing prompt.

## Consequences

- Native-only capabilities are explicit.
- Both clients share versioned scene, capture, artifact, and transaction contracts rather than rendering internals.
- The project has two presentation surfaces, so contract fixtures must precede UI integration.

## Risks

- Two clients increase integration surface.
- A planning agent may incorrectly put stateful inference inside Next.js.

## Fallback

If native visual gates fail, B0 remains the guaranteed recorded/replay product; retain only native slices that pass. If web deployment constraints conflict, host the gateway separately and keep Next.js client-side for replay and inspection.

## Benchmark and kill gate

`GATE-003` validates the native compositor. `GATE-008` independently validates B0. Neither client may be declared a substitute before its own gate passes.

## Requirements and contracts affected

`NFR-RENDER-001`, `FR-B0-001`, `FR-CAPTURE-001`, `NFR-CONTRACT-001`, and CON-001 through CON-005.

## Supersession

Supersedes any archived implication of one universal live client. No canonical ADR is superseded.
