from __future__ import annotations

import os
from pathlib import Path

import uvicorn

from .app import InferenceAppOptions, create_inference_app
from .da3_metric import DA3MetricProvider, load_da3_metric_engine
from .providers import (
    DisabledProvider,
    InferenceProvider,
    ModelServiceProvider,
    VisionServiceEndpoints,
)
from .sam3_provider import create_sam_provider_from_environment

MAX_PORT = 65_535


def main() -> None:
    token = os.environ.get("REFRAME_VISION_TOKEN", "")
    profile = os.environ.get("REFRAME_VISION_PROFILE", "disabled")
    host = os.environ.get("REFRAME_VISION_HOST", "127.0.0.1")
    port = parse_port(os.environ.get("REFRAME_VISION_PORT"))
    provider: InferenceProvider
    if profile == "disabled":
        provider = DisabledProvider()
    elif profile == "models":
        provider = ModelServiceProvider(
            VisionServiceEndpoints(
                segmentation=require_url("REFRAME_SEGMENTATION_URL"),
                metric_depth=require_url("REFRAME_METRIC_DEPTH_URL"),
                reconstruction=require_url("REFRAME_RECONSTRUCTION_URL"),
            )
        )
    elif profile == "geometry":
        provider = DA3MetricProvider(
            load_da3_metric_engine(
                require_path("REFRAME_DA3_SOURCE_DIR"),
                require_path("REFRAME_DA3_MODEL_DIR"),
                requested_device=os.environ.get("REFRAME_DA3_DEVICE", "auto"),
            )
        )
    elif profile == "sam":
        provider = create_sam_provider_from_environment()
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


def require_url(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value.startswith(("http://", "https://")):
        message = f"invalid {name.lower()}"
        raise RuntimeError(message)
    return value


def require_path(name: str) -> Path:
    value = os.environ.get(name, "").strip()
    if not value:
        message = f"invalid {name.lower()}"
        raise RuntimeError(message)
    return Path(value).expanduser().resolve()


if __name__ == "__main__":
    main()
