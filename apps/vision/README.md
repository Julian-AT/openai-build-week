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

The package pins CPython `3.12`, accepts the lock-compatible uv
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
uv sync --frozen --extra torch --extra da3
```

Installing PyTorch makes runtime/MPS capability visible at `/readyz`; on Linux
x86_64 the lock selects the official CUDA 12.4 wheel, while other supported
platforms retain the default package index. Model downloads remain an explicit
preparation step. The `geometry` profile accepts
only the official Apache-2.0 DA3Metric-Large source revision
`3fe327a6abe2e5db95b54444ea95463dbfef5610` and checkpoint revision
`4010e39f3634a45bc60553321fb49fb760bd594e`. It verifies the clean source
checkout and the complete checkpoint SHA-256 before loading either CUDA or MPS.

Set `REFRAME_DA3_SOURCE_DIR`, `REFRAME_DA3_MODEL_DIR`, and optionally
`REFRAME_DA3_DEVICE=cuda|mps`, then start with
`REFRAME_VISION_PROFILE=geometry`. The worker applies the official focal-length
conversion to encoded-frame intrinsics and returns digest-bound metric depth.
It does not install, select, or download a model during startup.

The verified CUDA path was exercised on an NVIDIA A100 with Torch 2.6.0+cu124:
the pinned DA3Metric-Large checkpoint cold-loaded in about 42 seconds and a
canonical JPEG completed warm metric-depth inference in about 3 seconds. These
timings are operational evidence, not a performance guarantee for an iPhone
session. SAM semantics, dense TSDF extraction, and reveal generation remain
separate capability gates and must stay disabled until their provider and
quality prerequisites are verified.
