# Reframe Hono API

This Bun service is Reframe's single public application API. Hono owns routing,
bounded ingress, authentication, admission rate limiting, deadlines, and
redacted request logs. The package keeps the standard OpenAI API key off the
iPhone and exposes narrowly scoped, bearer-protected LAN routes. It is not
scene authority: models can return only a CON-006 semantic proposal or a
short-lived Realtime token. Native deterministic code still owns target
authorization, geometry, revisions, preview, confirmation, commit,
reconciliation, and restore.

## Run locally

Use Bun `1.3.11`. From the repository root, install and verify the one exact
lockfile:

```sh
bun install --frozen-lockfile
bun run --cwd apps/api typecheck
bun run --cwd apps/api test
bun run --cwd apps/api build
```

Export the names shown in `.env.example`. `REFRAME_GATEWAY_TOKEN` protects the `/v1` routes and should be a high-entropy local secret. `OPENAI_API_KEY` is read only by OpenAI-backed services and must never enter the native app, source, or logs. The defaults are `0.0.0.0:8787`; bind to `127.0.0.1` unless a physical device needs LAN access.

```sh
bun run --cwd apps/api start
```

If either OpenAI secret is absent, the affected protected route fails closed. `GET
/health` remains unauthenticated liveness so local tooling can distinguish the
process from provider readiness. Protected routes share a process-local
60-request-per-minute admission budget and a 15-second upstream deadline; use a
single API process for the hackathon deployment.

The CV process is separate for Python/PyTorch dependency isolation but is not a
second public API. Configure both `REFRAME_VISION_URL` (normally
`http://127.0.0.1:8790`) and a distinct `REFRAME_VISION_TOKEN`, or configure
neither. A partial pair stops gateway startup; an absent pair leaves inference
routes present but fail-closed. The worker port stays loopback/private and only
Hono knows its bearer credential.

## HTTP surface

- `GET /health` — returns `{"status":"ok"}`.
- `POST /v1/proposals` — bearer-protected JSON; sends optional JPEG vision input to `gpt-5.6-sol` and returns CON-006.
- `POST /v1/realtime/client-secret` — bearer-protected JSON body `{}`; returns only `{value, expires_at, url, model}` for a 600-second `gpt-realtime-2.1` client token. The attached push-to-talk session uses 24 kHz `audio/pcm` input/output, near-field noise reduction, `gpt-4o-mini-transcribe` English transcription, `marin`, and client-owned turn boundaries (`turn_detection: null`). It exposes no tools; native accepts only the exact OpenAI WSS URL, consumes only the completed transcript, and sends that text through the separate Sol/CON-006 path.
- `GET /v1/inference/status` — reports the selected private worker profile,
  task readiness, evidence class, and PyTorch/MPS capability without exposing
  its internal token or endpoint.
- `POST /v1/inference/jobs` — validates and proxies one digest-bound
  `segment`, `metric_depth`, or gated `reconstruct` job. The worker admits one
  job with no backlog; unavailable profiles, saturation, and deadlines stay
  explicit.

`POST /v1/proposals` accepts this closed request shape:

```json
{
  "prompt": "Replace this with a warm chair.",
  "image_data_url": "data:image/jpeg;base64,...",
  "ingress_source": "vision",
  "request_context": {
    "session_id": "session_...",
    "revision_branch_id": "branch_...",
    "base_scene_revision": 7,
    "world_frame_id": "world_...",
    "world_frame_version": 2,
    "selected_object_id": "object_..."
  }
}
```

The image is optional; no client asset allowlist is accepted. The gateway owns the three-item catalog and rejects unknown model-selected assets, noncanonical constraints, model-supplied context, transforms, URLs, confirmation, and mutation fields. Gateway request JSON rejects malformed UTF-8 and duplicate member names before shape validation; SDK output then passes the closed semantic validator before envelope construction. CORS headers are intentionally absent. Request logs contain only request ID, method, path, status, and duration—never bearer headers, prompts, image bytes, API keys, or ephemeral values.

All model-facing calls are implemented in `@reframe/agent` with the OpenAI SDK and
`@ai-sdk/openai`; the official `openai` JavaScript package is not installed.
The exact SDK transport is covered by local fake-HTTPS tests, including strict
Structured Outputs, `store: false`, consented image input, the closed Realtime
session, cancellation, and bounded token responses. Live provider quality and
latency remain evidence gates.

The Python process is covered separately by strict Pydantic/ASGI tests, while
the Hono side independently revalidates request and response bytes, provider
identity, evidence class, task/result binding, canonical base64, and SHA-256.
Depth and point-cloud bodies are bounded; malformed or oversized worker output
becomes a generic gateway failure and is never relayed verbatim.

The request shapes follow the official [Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs), [vision input](https://developers.openai.com/api/docs/guides/images-vision), and [Realtime client-secret](https://developers.openai.com/api/reference/resources/realtime/subresources/client_secrets/methods/create) documentation.
