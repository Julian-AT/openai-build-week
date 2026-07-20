from __future__ import annotations

import asyncio
import base64
import hashlib
import importlib
import math
import shutil
import subprocess
import sys
import types
from array import array
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from typing import Protocol, cast

import numpy as np
import numpy.typing as npt
from PIL import Image, UnidentifiedImageError

from .contracts import (
    InferenceJob,
    InferenceJobResponse,
    MetricDepthJob,
    MetricDepthResult,
    ProviderIdentity,
    TaskReadiness,
    WorkerReadiness,
)
from .providers import ProviderUnavailableError
from .runtime import probe_torch

DA3_SOURCE_REVISION = "3fe327a6abe2e5db95b54444ea95463dbfef5610"
DA3_CHECKPOINT_REVISION = "4010e39f3634a45bc60553321fb49fb760bd594e"
DA3_CHECKPOINT_BYTES = 1_336_734_448
DA3_CHECKPOINT_SHA256 = "bbea5b0b3ee389849cffa7ddae89de064a90abd2b055fc5aa99aac68db324776"
DA3_METRIC_DIVISOR = 300.0
MAX_METRIC_DEPTH_M = 500.0
HASH_CHUNK_BYTES = 1024 * 1024
MIN_PROCESS_RESOLUTION = 224
MAX_PROCESS_RESOLUTION = 1_008
DEPTH_PLANE_DIMENSIONS = 3
GIT_TIMEOUT_SECONDS = 10.0


@dataclass(frozen=True, slots=True)
class DepthPlane:
    width: int
    height: int
    data: bytes

    def __post_init__(self) -> None:
        if self.width < 1 or self.height < 1 or len(self.data) != self.width * self.height * 4:
            raise ValueError("invalid depth plane")


class DA3InferenceEngine(Protocol):
    def infer(
        self,
        jpeg: bytes,
        *,
        expected_width: int,
        expected_height: int,
        process_resolution: int,
    ) -> DepthPlane: ...


class DA3Prediction(Protocol):
    @property
    def depth(self) -> npt.NDArray[np.float32]: ...


class DA3LoadedModel(Protocol):
    def inference(
        self,
        image: list[Image.Image],
        *,
        process_res: int,
        process_res_method: str,
    ) -> DA3Prediction: ...


class DA3TransferableModel(DA3LoadedModel, Protocol):
    def to(self, device: str) -> DA3LoadedModel: ...


class DA3ModelFactory(Protocol):
    def from_pretrained(self, model_path: str) -> DA3TransferableModel: ...


class AcceleratorBackend(Protocol):
    def is_available(self) -> bool: ...


class TorchBackends(Protocol):
    mps: AcceleratorBackend


class TorchRuntime(Protocol):
    cuda: AcceleratorBackend
    backends: TorchBackends


class DA3MetricModelEngine:
    def __init__(self, model: DA3LoadedModel) -> None:
        self._model = model

    def infer(
        self,
        jpeg: bytes,
        *,
        expected_width: int,
        expected_height: int,
        process_resolution: int,
    ) -> DepthPlane:
        try:
            with Image.open(BytesIO(jpeg)) as decoded:
                if decoded.format != "JPEG" or decoded.size != (expected_width, expected_height):
                    raise ValueError("decoded image dimensions do not match request")
                image = decoded.convert("RGB")
                image.load()
        except (OSError, UnidentifiedImageError) as error:
            raise ValueError("invalid JPEG image") from error
        prediction = self._model.inference(
            [image],
            process_res=process_resolution,
            process_res_method="upper_bound_resize",
        )
        depth = np.asarray(prediction.depth, dtype="<f4")
        if (
            depth.ndim != DEPTH_PLANE_DIMENSIONS
            or depth.shape[0] != 1
            or depth.shape[1] < 1
            or depth.shape[2] < 1
        ):
            raise ValueError("invalid DA3 prediction shape")
        depth_plane = np.ascontiguousarray(depth[0], dtype="<f4")
        return DepthPlane(
            width=depth.shape[2],
            height=depth.shape[1],
            data=memoryview(depth_plane).cast("B").tobytes(),
        )


class DA3MetricProvider:
    identity = ProviderIdentity(
        provider_id="da3metric-large",
        provider_revision="4010e39f3634a45b-src-3fe327a6abe2",
        evidence_class="unmeasured",
    )

    def __init__(self, engine: DA3InferenceEngine, *, process_resolution: int = 504) -> None:
        if not MIN_PROCESS_RESOLUTION <= process_resolution <= MAX_PROCESS_RESOLUTION:
            raise ValueError("invalid DA3 process resolution")
        self._engine = engine
        self._process_resolution = process_resolution

    async def readiness(self) -> WorkerReadiness:
        return WorkerReadiness(
            status="ready",
            provider=self.identity,
            tasks=TaskReadiness(segment=False, metric_depth=True, reconstruct=False),
            torch=probe_torch(),
        )

    async def run(self, job: InferenceJob) -> InferenceJobResponse:
        if not isinstance(job, MetricDepthJob):
            raise ProviderUnavailableError
        jpeg = base64.b64decode(job.image.data_base64, validate=True)
        try:
            plane = await asyncio.to_thread(
                self._engine.infer,
                jpeg,
                expected_width=job.image.width,
                expected_height=job.image.height,
                process_resolution=self._process_resolution,
            )
            metric_depth = scale_metric_depth(plane, job)
            digest = hashlib.sha256(metric_depth).hexdigest()
            result = MetricDepthResult(
                kind="metric_depth",
                width=plane.width,
                height=plane.height,
                encoding="float32_le_base64",
                unit="metre",
                data_base64=base64.b64encode(metric_depth).decode("ascii"),
                sha256=digest,
            )
        except (ArithmeticError, OSError, RuntimeError, ValueError) as error:
            raise ProviderUnavailableError from error
        return InferenceJobResponse(
            request_id=job.request_id,
            task=job.task,
            provider=self.identity,
            result=result,
        )


def scale_metric_depth(plane: DepthPlane, job: MetricDepthJob) -> bytes:
    intrinsics = job.intrinsics_encoded_pixels
    scale_x = plane.width / job.image.width
    scale_y = plane.height / job.image.height
    processed_focal = ((intrinsics.fx * scale_x) + (intrinsics.fy * scale_y)) / 2.0
    metric_scale = processed_focal / DA3_METRIC_DIVISOR

    values = array("f")
    values.frombytes(plane.data)
    if sys.byteorder != "little":
        values.byteswap()
    for index, value in enumerate(values):
        metric_value = value * metric_scale
        if (
            not math.isfinite(metric_value)
            or metric_value <= 0
            or metric_value > MAX_METRIC_DEPTH_M
        ):
            raise ValueError("invalid DA3 metric depth")
        values[index] = metric_value
    if sys.byteorder != "little":
        values.byteswap()
    return values.tobytes()


def verify_file(path: Path, *, expected_bytes: int, expected_sha256: str) -> None:
    try:
        if path.stat().st_size != expected_bytes:
            raise RuntimeError("model artifact verification failed")
        digest = hashlib.sha256()
        with path.open("rb") as source:
            while chunk := source.read(HASH_CHUNK_BYTES):
                digest.update(chunk)
        if digest.hexdigest() != expected_sha256:
            raise RuntimeError("model artifact verification failed")
    except OSError as error:
        raise RuntimeError("model artifact verification failed") from error


def verify_source_checkout(
    source_dir: Path,
    *,
    expected_revision: str = DA3_SOURCE_REVISION,
) -> None:
    api = source_dir / "src" / "depth_anything_3" / "api.py"
    git = shutil.which("git")
    if git is None or not api.is_file():
        raise RuntimeError("DA3 source verification failed")
    try:
        revision = _run_git(git, source_dir, "rev-parse", "HEAD")
        status = _run_git(git, source_dir, "status", "--porcelain", "--untracked-files=normal")
    except (OSError, subprocess.SubprocessError) as error:
        raise RuntimeError("DA3 source verification failed") from error
    if revision != expected_revision or status:
        raise RuntimeError("DA3 source verification failed")


def load_da3_metric_engine(
    source_dir: Path,
    model_dir: Path,
    *,
    requested_device: str = "auto",
) -> DA3MetricModelEngine:
    verify_source_checkout(source_dir)
    verify_file(
        model_dir / "model.safetensors",
        expected_bytes=DA3_CHECKPOINT_BYTES,
        expected_sha256=DA3_CHECKPOINT_SHA256,
    )
    package_root = (source_dir / "src").resolve(strict=True)
    if any(
        name == "depth_anything_3" or name.startswith("depth_anything_3.") for name in sys.modules
    ):
        raise RuntimeError("DA3 was imported before source verification")
    sys.path.insert(0, str(package_root))
    _install_disabled_export_boundary()
    try:
        api_module = importlib.import_module("depth_anything_3.api")
        factory = cast("DA3ModelFactory", api_module.DepthAnything3)
        model = factory.from_pretrained(str(model_dir)).to(select_accelerator(requested_device))
    except (AttributeError, ImportError, OSError, RuntimeError, ValueError) as error:
        raise RuntimeError("DA3 model initialization failed") from error
    return DA3MetricModelEngine(model)


def select_accelerator(requested_device: str) -> str:
    try:
        torch = cast("TorchRuntime", importlib.import_module("torch"))
    except (ImportError, OSError) as error:
        raise RuntimeError("PyTorch is unavailable") from error
    available = {
        "cuda": torch.cuda.is_available(),
        "mps": torch.backends.mps.is_available(),
    }
    if requested_device == "auto":
        for candidate in ("cuda", "mps"):
            if available[candidate]:
                return candidate
        raise RuntimeError("no supported accelerator is available")
    if requested_device not in available or not available[requested_device]:
        raise RuntimeError("requested accelerator is unavailable")
    return requested_device


def _run_git(git: str, source_dir: Path, *arguments: str) -> str:
    completed = subprocess.run(  # noqa: S603
        [git, "-C", str(source_dir), *arguments],
        check=False,
        capture_output=True,
        text=True,
        timeout=GIT_TIMEOUT_SECONDS,
    )
    if completed.returncode != 0:
        raise subprocess.SubprocessError
    return completed.stdout.strip()


def _install_disabled_export_boundary() -> None:
    module_name = "depth_anything_3.utils.export"
    export_module = types.ModuleType(module_name)
    export_module.export = _disabled_export  # type: ignore[attr-defined]
    sys.modules[module_name] = export_module


def _disabled_export(*_args: object, **_kwargs: object) -> None:
    raise RuntimeError("DA3 exporters are disabled in the metric-depth worker")
