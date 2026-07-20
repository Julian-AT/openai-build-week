from __future__ import annotations

import asyncio
import base64
import hashlib
import struct
from dataclasses import dataclass
from pathlib import Path

import pytest

from reframe_vision.contracts import MetricDepthJob, MetricDepthResult
from reframe_vision.da3_metric import DA3MetricProvider, DepthPlane, verify_file
from reframe_vision.providers import ProviderUnavailableError


@dataclass(frozen=True, slots=True)
class FixedEngine:
    plane: DepthPlane

    def infer(self, jpeg: bytes, *, process_resolution: int) -> DepthPlane:
        assert jpeg == b"\xff\xd8\xff\xd9"
        assert process_resolution == 504
        return self.plane


def metric_job() -> MetricDepthJob:
    jpeg = b"\xff\xd8\xff\xd9"
    return MetricDepthJob.model_validate(
        {
            "protocol_version": "1.0.0",
            "request_id": "inference_20000000-0000-4000-8000-000000000001",
            "task": "metric_depth",
            "image": {
                "frame_id": "frame_20000000-0000-4000-8000-000000000001",
                "media_type": "image/jpeg",
                "data_base64": base64.b64encode(jpeg).decode("ascii"),
                "sha256": hashlib.sha256(jpeg).hexdigest(),
                "width": 2,
                "height": 2,
            },
            "intrinsics_encoded_pixels": {
                "fx": 300.0,
                "fy": 600.0,
                "cx": 1.0,
                "cy": 1.0,
                "width": 2,
                "height": 2,
                "units": "encoded_pixels",
            },
        }
    )


def test_da3_metric_provider_applies_official_focal_scaling() -> None:
    async def run() -> None:
        raw = struct.pack("<f", 3.0)
        provider = DA3MetricProvider(FixedEngine(DepthPlane(width=1, height=1, data=raw)))

        response = await provider.run(metric_job())
        readiness = await provider.readiness()

        assert isinstance(response.result, MetricDepthResult)
        depth_bytes = base64.b64decode(response.result.data_base64, validate=True)
        assert struct.unpack("<f", depth_bytes) == pytest.approx((2.25,))
        assert response.result.width == 1
        assert response.result.height == 1
        assert response.result.sha256 == hashlib.sha256(depth_bytes).hexdigest()
        assert response.provider.provider_id == "da3metric-large"
        assert readiness.status == "ready"
        assert readiness.tasks.metric_depth is True
        assert readiness.tasks.segment is False
        assert readiness.tasks.reconstruct is False

    asyncio.run(run())


@pytest.mark.parametrize("value", [float("nan"), float("inf"), 0.0, -1.0, 1_000.0])
def test_da3_metric_provider_rejects_invalid_model_output(value: float) -> None:
    async def run() -> None:
        provider = DA3MetricProvider(
            FixedEngine(DepthPlane(width=1, height=1, data=struct.pack("<f", value)))
        )

        with pytest.raises(ProviderUnavailableError):
            await provider.run(metric_job())

    asyncio.run(run())


def test_model_file_verification_is_size_and_digest_bound(tmp_path: Path) -> None:
    model = tmp_path / "model.safetensors"
    model.write_bytes(b"model")

    verify_file(model, expected_bytes=5, expected_sha256=hashlib.sha256(b"model").hexdigest())

    with pytest.raises(RuntimeError, match="model artifact verification failed"):
        verify_file(model, expected_bytes=5, expected_sha256="0" * 64)
