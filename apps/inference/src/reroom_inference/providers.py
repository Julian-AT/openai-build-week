from __future__ import annotations

import base64
import hashlib
import struct
from typing import Protocol

from .contracts import (
    InferenceJob,
    InferenceJobResponse,
    MaskResult,
    MetricDepthResult,
    ProviderIdentity,
    ReconstructionResult,
    TaskReadiness,
    WorkerReadiness,
)
from .runtime import probe_torch


class InferenceProvider(Protocol):
    async def readiness(self) -> WorkerReadiness: ...

    async def run(self, job: InferenceJob) -> InferenceJobResponse: ...


class ProviderUnavailableError(Exception):
    pass


class DisabledProvider:
    @staticmethod
    def readiness_value() -> WorkerReadiness:
        return WorkerReadiness(
            status="disabled",
            provider=ProviderIdentity(
                provider_id="disabled",
                provider_revision="none",
                evidence_class="unmeasured",
            ),
            tasks=TaskReadiness(segment=False, metric_depth=False, reconstruct=False),
            torch=probe_torch(),
        )

    async def readiness(self) -> WorkerReadiness:
        return self.readiness_value()

    async def run(self, job: InferenceJob) -> InferenceJobResponse:
        del job
        raise ProviderUnavailableError


class FixtureProvider:
    identity = ProviderIdentity(
        provider_id="fixture",
        provider_revision="fixture-v1",
        evidence_class="fixture_only",
    )

    def __init__(self) -> None:
        self.calls = 0

    async def readiness(self) -> WorkerReadiness:
        return WorkerReadiness(
            status="ready",
            provider=self.identity,
            tasks=TaskReadiness(segment=True, metric_depth=True, reconstruct=True),
            torch=probe_torch(),
        )

    async def run(self, job: InferenceJob) -> InferenceJobResponse:
        self.calls += 1
        return self.response_for(job)

    @classmethod
    def response_for(cls, job: InferenceJob) -> InferenceJobResponse:
        if job.task == "segment":
            mask = b"\x01" * (job.image.width * job.image.height)
            result = MaskResult(
                kind="mask",
                width=job.image.width,
                height=job.image.height,
                encoding="binary_rle",
                counts=(0, len(mask)),
                foreground_pixels=len(mask),
                sha256=hashlib.sha256(mask).hexdigest(),
            )
        elif job.task == "metric_depth":
            depth = struct.pack(
                f"<{job.image.width * job.image.height}f",
                *([1.0] * (job.image.width * job.image.height)),
            )
            result = MetricDepthResult(
                kind="metric_depth",
                width=job.image.width,
                height=job.image.height,
                encoding="float32_le_base64",
                unit="metre",
                data_base64=base64.b64encode(depth).decode("ascii"),
                sha256=hashlib.sha256(depth).hexdigest(),
            )
        else:
            point_cloud = b"ply\nformat binary_little_endian 1.0\nend_header\n"
            result = ReconstructionResult(
                kind="point_cloud",
                encoding="ply_binary_little_endian",
                data_base64=base64.b64encode(point_cloud).decode("ascii"),
                sha256=hashlib.sha256(point_cloud).hexdigest(),
            )
        return InferenceJobResponse(
            request_id=job.request_id,
            task=job.task,
            provider=cls.identity,
            result=result,
        )
