from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

import httpx

from .contracts import (
    InferenceJob,
    InferenceJobResponse,
    ProviderIdentity,
    TaskReadiness,
    WorkerReadiness,
)
from .runtime import probe_torch

HTTP_OK = 200


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


@dataclass(frozen=True, slots=True)
class VisionServiceEndpoints:
    segmentation: str
    metric_depth: str
    reconstruction: str

    def for_task(self, task: str) -> str:
        return {
            "segment": self.segmentation,
            "metric_depth": self.metric_depth,
            "reconstruct": self.reconstruction,
        }[task]


class ModelServiceProvider:
    identity = ProviderIdentity(
        provider_id="reframe_vision",
        provider_revision="sam3.1-da3metric-lingbotdepth",
        evidence_class="unmeasured",
    )

    def __init__(
        self,
        endpoints: VisionServiceEndpoints,
        *,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self._endpoints = endpoints
        self._client = client or httpx.AsyncClient(
            timeout=httpx.Timeout(110.0, connect=5.0),
            limits=httpx.Limits(max_connections=3, max_keepalive_connections=3),
        )

    async def readiness(self) -> WorkerReadiness:
        checks: list[bool] = []
        for url in (
            self._endpoints.segmentation,
            self._endpoints.metric_depth,
            self._endpoints.reconstruction,
        ):
            try:
                response = await self._client.get(f"{url.rstrip('/')}/readyz")
                checks.append(response.status_code == HTTP_OK)
            except httpx.HTTPError:
                checks.append(False)
        tasks = TaskReadiness(
            segment=checks[0],
            metric_depth=checks[1],
            reconstruct=checks[2],
        )
        return WorkerReadiness(
            status="ready" if all(checks) else "degraded",
            provider=self.identity,
            tasks=tasks,
            torch=probe_torch(),
        )

    async def run(self, job: InferenceJob) -> InferenceJobResponse:
        url = f"{self._endpoints.for_task(job.task).rstrip('/')}/infer"
        try:
            response = await self._client.post(url, content=job.model_dump_json())
            response.raise_for_status()
            parsed = InferenceJobResponse.model_validate_json(response.content)
        except (httpx.HTTPError, ValueError) as error:
            raise ProviderUnavailableError from error
        if parsed.request_id != job.request_id or parsed.task != job.task:
            raise ProviderUnavailableError
        return parsed
