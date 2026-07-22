# Reframe web

[Back to Reframe](../../README.md)

The Next.js application presents Reframe's browser experience: an interactive
room model at the root and gateway-backed capture and replay foundations.

## Responsibilities

- Render the apartment point cloud and reconstructed 3D surface with Three.js.
- Broker room creation without exposing the gateway token to the browser.
- Validate session IDs and ordered capture events before replay.
- Load verified scene and asset data without claiming native ARKit authority.

The root room viewer is standalone. Replay, capture handoff, and Realtime voice
use the trusted gateway when configured.

## Run

```sh
bun run --cwd apps/web dev
bun run --cwd apps/web test
bun run --cwd apps/web typecheck
bun run --cwd apps/web build
```

Open [localhost:3000](http://localhost:3000) for the room viewer. Replay routes
use `/replay/<room-session-id>`.

## Configuration

Gateway-backed server routes use `REFRAME_GATEWAY_URL` and
`REFRAME_GATEWAY_TOKEN`. Browser replay uses
`NEXT_PUBLIC_REFRAME_GATEWAY_URL`; never put a secret in a `NEXT_PUBLIC_`
variable. The standalone room viewer requires none of these values.
