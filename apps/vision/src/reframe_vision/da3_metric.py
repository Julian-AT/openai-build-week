from __future__ import annotations

import asyncio
import base64
import hashlib
import math
import sys
from array import array
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

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


@dataclass(frozen=True, slots=True)
class DepthPlane:
    width: int
    height: int
    data: bytes

    def __post_init__(self) -> None:
        if self.width < 1 or self.height < 1 or len(self.data) != self.width * self.height * 4:
            raise ValueError("invalid depth plane")


class DA3InferenceEngine(Protocol):
    def infer(self, jpeg: bytes, *, process_resolution: int) -> DepthPlane: ...


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
