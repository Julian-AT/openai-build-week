from __future__ import annotations

import os

import uvicorn

from .app import InferenceAppOptions, create_inference_app
from .providers import DisabledProvider, FixtureProvider, InferenceProvider

MAX_PORT = 65_535


def main() -> None:
    token = os.environ.get("REROOM_INFERENCE_TOKEN", "")
    profile = os.environ.get("REROOM_INFERENCE_PROFILE", "disabled")
    host = os.environ.get("REROOM_INFERENCE_HOST", "127.0.0.1")
    port = parse_port(os.environ.get("REROOM_INFERENCE_PORT"))
    provider: InferenceProvider
    if profile == "disabled":
        provider = DisabledProvider()
    elif profile == "fixture":
        provider = FixtureProvider()
    else:
        raise RuntimeError("unknown inference profile")
    app = create_inference_app(InferenceAppOptions(token=token, provider=provider))
    uvicorn.run(app, host=host, port=port, access_log=False, workers=1, timeout_keep_alive=5)


def parse_port(value: str | None) -> int:
    if value is None or not value.strip():
        return 8790
    try:
        port = int(value)
    except ValueError as error:
        raise RuntimeError("invalid inference port") from error
    if port < 1 or port > MAX_PORT:
        raise RuntimeError("invalid inference port")
    return port


if __name__ == "__main__":
    main()
