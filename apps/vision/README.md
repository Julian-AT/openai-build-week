# Reframe vision

[Back to Reframe](../../README.md)

This private Python service isolates spatial inference behind authenticated,
typed, capability-aware endpoints.

## Responsibilities

- Track selected objects and return digest-bound masks.
- Estimate metric depth and conservative target geometry.
- Produce geometry and reveal artifacts with explicit readiness and provenance.
- Bound concurrency, memory, payload sizes, and provider failure behavior.

Vision workers never own public object identity, ARKit pose authority, scene
revisions, catalog eligibility, confirmation, or restore.

## Profiles

`disabled` starts a fail-closed service without model inference. `models`
forwards to isolated capability services. `geometry` loads the configured DA3
provider, and `sam` loads the configured SAM provider. Model sources and
checkpoints are prepared explicitly outside the repository and never downloaded
during service startup.

## Run and verify

```sh
cd apps/vision
uv sync --frozen
uv run --frozen python -m reframe_vision.main
uv run --frozen ruff format --check .
uv run --frozen ruff check .
uv run --frozen basedpyright
uv run --frozen pytest -q
```

Python 3.12 and `uv >=0.9.26,<0.12` are required.

## Configuration

Use `.env.example` for token, profile, host, port, source, checkpoint, revision,
size, and SHA-256 names. Keep the worker on a private network and never commit
models, captures, or generated artifacts.
