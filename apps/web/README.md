# Reframe web

The submission surface is a single full-viewport Gaussian-splat room rendered
with Three.js. It has no visible capture, voice, replay, catalog, or debug UI.
The deterministic scene is presentation only and never enters canonical room
state.

The broader Next.js foundations remain available for later Mode B0 work, but
they must use real uploaded sessions and the gateway's authoritative scene.
The web client never owns ARKit tracking, spatial truth, scene revisions,
confirmation, commit, or restore.

Read the [submission status and cleanup plan](SUBMISSION_STATUS.md) before
continuing product work.

## Commands

```sh
bun run dev
bun test
bun run typecheck
bun run build
```

The landing scene has no runtime service dependency. WebGL failure uses a CSS
fallback. Captures, Gaussian binaries, catalog assets, and generated output
stay outside Git.

## Known limitations

The fixed scene is not a capture replay or photoreal Mode B1 output. Existing
capture/replay foundations are incomplete and must not fabricate ARKit facts
for ordinary video. See the cleanup plan for the required authority fixes.
