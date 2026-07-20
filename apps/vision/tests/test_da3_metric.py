from __future__ import annotations

import asyncio
import base64
import hashlib
import shutil
import struct
import subprocess
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path

import numpy as np
import numpy.typing as npt
import pytest
from PIL import Image

from reframe_vision.contracts import MetricDepthJob, MetricDepthResult
from reframe_vision.da3_metric import (
    DA3MetricModelEngine,
    DA3MetricProvider,
    DepthPlane,
    verify_file,
    verify_source_checkout,
)
from reframe_vision.providers import ProviderUnavailableError


@dataclass(frozen=True, slots=True)
class FixedEngine:
    plane: DepthPlane

    def infer(
        self,
        jpeg: bytes,
        *,
        expected_width: int,
        expected_height: int,
        process_resolution: int,
    ) -> DepthPlane:
        assert jpeg == b"\xff\xd8\xff\xd9"
        assert expected_width == 2
        assert expected_height == 2
        assert process_resolution == 504
        return self.plane


@dataclass(slots=True)
class RecordingModel:
    process_resolution: int | None = None

    def inference(
        self,
        image: list[Image.Image],
        *,
        process_res: int,
        process_res_method: str,
    ) -> PredictionStub:
        assert len(image) == 1
        assert image[0].size == (4, 3)
        assert process_res_method == "upper_bound_resize"
        self.process_resolution = process_res
        return PredictionStub(depth=np.asarray([[[3.0, 4.0]]], dtype=np.float32))


@dataclass(frozen=True, slots=True)
class PredictionStub:
    depth: npt.NDArray[np.float32]


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


def test_model_engine_decodes_bound_jpeg_and_returns_little_endian_depth() -> None:
    encoded = BytesIO()
    Image.new("RGB", (4, 3), color=(12, 34, 56)).save(encoded, format="JPEG")
    model = RecordingModel()
    engine = DA3MetricModelEngine(model)

    plane = engine.infer(
        encoded.getvalue(),
        expected_width=4,
        expected_height=3,
        process_resolution=224,
    )

    assert (plane.width, plane.height) == (2, 1)
    assert struct.unpack("<2f", plane.data) == pytest.approx((3.0, 4.0))
    assert model.process_resolution == 224

    with pytest.raises(ValueError, match="decoded image dimensions do not match request"):
        engine.infer(
            encoded.getvalue(),
            expected_width=5,
            expected_height=3,
            process_resolution=224,
        )


def test_model_file_verification_is_size_and_digest_bound(tmp_path: Path) -> None:
    model = tmp_path / "model.safetensors"
    model.write_bytes(b"model")

    verify_file(model, expected_bytes=5, expected_sha256=hashlib.sha256(b"model").hexdigest())

    with pytest.raises(RuntimeError, match="model artifact verification failed"):
        verify_file(model, expected_bytes=5, expected_sha256="0" * 64)


def test_source_checkout_verification_rejects_revision_drift(tmp_path: Path) -> None:
    source = tmp_path / "da3"
    api = source / "src" / "depth_anything_3" / "api.py"
    api.parent.mkdir(parents=True)
    api.write_text("# pinned source\n", encoding="utf-8")
    git = shutil.which("git")
    assert git is not None
    run_test_git(git, "init", "-q", str(source))
    run_test_git(git, "-C", str(source), "add", ".")
    run_test_git(
        git,
        "-C",
        str(source),
        "-c",
        "user.name=Reframe Test",
        "-c",
        "user.email=reframe@example.invalid",
        "commit",
        "-qm",
        "source",
    )
    revision = run_test_git(
        git,
        "-C",
        str(source),
        "rev-parse",
        "HEAD",
        capture_output=True,
    ).stdout.strip()

    verify_source_checkout(source, expected_revision=revision)

    api.write_text("# modified source\n", encoding="utf-8")
    with pytest.raises(RuntimeError, match="DA3 source verification failed"):
        verify_source_checkout(source, expected_revision=revision)


def run_test_git(
    git: str,
    *arguments: str,
    capture_output: bool = False,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(  # noqa: S603
        [
            git,
            *arguments,
        ],
        check=True,
        capture_output=capture_output,
        text=True,
    )
