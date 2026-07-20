# Reframe vision worker

This FastAPI process is the one private, selected computer-vision worker behind
the public Hono API. It validates digest-bound input, admits exactly one job at
a time with no backlog, applies a hard deadline, and returns typed,
provider-identified artifacts. It never owns scene identity, geometry
authorization, revisions, confirmation, commit, reconciliation, or restore.

The default `disabled` profile is the honest no-model fallback. Tests construct
their inputs inline; the product has no synthetic provider profile or checked-in
model-output corpus.

## Environment and verification

The package pins CPython `3.13.12`, accepts the lock-compatible uv
`>=0.9.26,<0.12` line, pins every direct dependency, and retains all resolved
artifacts in `uv.lock`. CI installs one exact uv release. From this directory:

```sh
uv sync --frozen
uv run --frozen pytest -q
uv run --frozen ruff format --check .
uv run --frozen ruff check .
uv run --frozen basedpyright
```

Set a high-entropy `REFRAME_VISION_TOKEN` and keep the default loopback bind,
then start the fail-closed worker:

```sh
REFRAME_VISION_TOKEN=local-only-secret \
  uv run --frozen python -m reframe_vision.main
```

`GET /healthz` is public process liveness. `GET /readyz` and `POST
/v1/jobs` require the private bearer token. Do not expose port `8790` outside
the host; clients use the Hono routes instead.

## PyTorch and real providers

The exact PyTorch runtime is optional so deterministic capture, replay, typed
operations, and the no-dense fallback remain usable without a multi-gigabyte
install:

```sh
uv sync --frozen --extra torch
```

Installing PyTorch makes runtime/MPS capability visible at `/readyz`; it does
not silently select or download a model. A real SAM 3.1 or eligible DA3 adapter
must bind an exact code revision, checkpoint digest, license evidence, input
normalization, output tolerance policy, and its applicable canonical gate
before its profile can be added. Until then, unknown profiles fail startup and
the worker stays disabled.
