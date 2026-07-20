from __future__ import annotations

import asyncio
import base64
import hashlib
import json
from typing import TYPE_CHECKING, Final, cast

import httpx
import pytest
from pydantic import ValidationError
from starlette.types import ASGIApp

from reroom_inference import (
    DisabledProvider,
    FixtureProvider,
    InferenceAppOptions,
    create_inference_app,
)

if TYPE_CHECKING:
    from reroom_inference.contracts import InferenceJob, InferenceJobResponse, WorkerReadiness

from reroom_inference.contracts import MetricDepthResult, ReconstructionResult

TOKEN: Final = "fixture-internal-token"
JPEG_BYTES: Final = b"\xff\xd8\xff\xd9"


def image_input() -> dict[str, object]:
    return {
        "frame_id": "frame_00000000-0000-4000-8000-000000000001",
        "media_type": "image/jpeg",
        "data_base64": base64.b64encode(JPEG_BYTES).decode("ascii"),
        "sha256": hashlib.sha256(JPEG_BYTES).hexdigest(),
        "width": 1,
        "height": 1,
    }


def segmentation_job() -> dict[str, object]:
    return {
        "protocol_version": "1.0.0",
        "request_id": "inference_00000000-0000-4000-8000-000000000001",
        "task": "segment",
        "image": image_input(),
        "prompt": {"kind": "point", "x": 0, "y": 0, "label": "foreground"},
    }


def headers() -> dict[str, str]:
    return {"authorization": f"Bearer {TOKEN}", "content-type": "application/json"}


def request(
    app: ASGIApp,
    method: str,
    path: str,
    *,
    headers: dict[str, str] | None = None,
    json_body: object | None = None,
    content: bytes | None = None,
) -> httpx.Response:
    async def scenario() -> httpx.Response:
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://worker") as client:
            return await client.request(
                method,
                path,
                headers=headers,
                json=json_body,
                content=content,
            )

    return asyncio.run(scenario())


def test_health_is_minimal_and_readiness_is_private() -> None:
    app = create_inference_app(InferenceAppOptions(token=TOKEN, provider=FixtureProvider()))
    health = request(app, "GET", "/healthz")
    denied = request(app, "GET", "/readyz")
    ready = request(app, "GET", "/readyz", headers={"authorization": f"Bearer {TOKEN}"})

    assert health.status_code == 200
    assert health.json() == {"status": "ok"}
    assert denied.status_code == 401
    assert denied.json() == {"error": "unauthorized"}
    assert ready.status_code == 200
    assert ready.json() == {
        "protocol_version": "1.0.0",
        "status": "ready",
        "provider": {
            "provider_id": "fixture",
            "provider_revision": "fixture-v1",
            "evidence_class": "fixture_only",
        },
        "tasks": {"segment": True, "metric_depth": True, "reconstruct": True},
        "torch": {"installed": False, "version": None, "mps_available": False},
    }


def test_fixture_segmentation_is_digest_bound_and_deterministic() -> None:
    app = create_inference_app(InferenceAppOptions(token=TOKEN, provider=FixtureProvider()))
    first = request(app, "POST", "/v1/jobs", headers=headers(), json_body=segmentation_job())
    second = request(app, "POST", "/v1/jobs", headers=headers(), json_body=segmentation_job())

    assert first.status_code == 200
    assert first.json() == second.json()
    body = cast("dict[str, object]", first.json())
    provider_body = cast("dict[str, object]", body["provider"])
    assert provider_body["evidence_class"] == "fixture_only"
    assert body["result"] == {
        "kind": "mask",
        "width": 1,
        "height": 1,
        "encoding": "binary_rle",
        "counts": [0, 1],
        "foreground_pixels": 1,
        "sha256": "4bf5122f344554c53bde2ebb8cd2b7e3d1600ad631c385a5d7cce23c7785459a",
    }


def test_unknown_fields_and_digest_mismatch_fail_before_provider_use() -> None:
    provider = FixtureProvider()
    app = create_inference_app(InferenceAppOptions(token=TOKEN, provider=provider))
    unknown = segmentation_job()
    unknown["authority"] = "model"
    mismatch = segmentation_job()
    image = dict(cast("dict[str, object]", mismatch["image"]))
    image["sha256"] = "0" * 64
    mismatch["image"] = image

    unknown_response = request(app, "POST", "/v1/jobs", headers=headers(), json_body=unknown)
    mismatch_response = request(app, "POST", "/v1/jobs", headers=headers(), json_body=mismatch)

    assert unknown_response.status_code == 400
    assert unknown_response.json() == {"error": "invalid_request"}
    assert mismatch_response.status_code == 400
    assert mismatch_response.json() == {"error": "invalid_request"}
    assert provider.calls == 0


def test_jobs_require_json_and_all_routes_reject_query_parameters() -> None:
    provider = FixtureProvider()
    app = create_inference_app(InferenceAppOptions(token=TOKEN, provider=provider))
    raw_json = json.dumps(segmentation_job()).encode("utf-8")

    wrong_media = request(
        app,
        "POST",
        "/v1/jobs",
        headers={"authorization": f"Bearer {TOKEN}"},
        content=raw_json,
    )
    decorated = request(app, "GET", "/readyz?debug=true", headers=headers())

    assert wrong_media.status_code == 415
    assert wrong_media.json() == {"error": "unsupported_media_type"}
    assert decorated.status_code == 404
    assert decorated.json() == {"error": "not_found"}
    assert provider.calls == 0


def test_body_limit_and_disabled_provider_fail_closed() -> None:
    disabled = create_inference_app(
        InferenceAppOptions(token=TOKEN, provider=DisabledProvider(), maximum_body_bytes=512)
    )
    too_large = request(
        disabled,
        "POST",
        "/v1/jobs",
        headers=headers(),
        content=b" " * 513,
    )
    unavailable = request(
        disabled,
        "POST",
        "/v1/jobs",
        headers=headers(),
        json_body=segmentation_job(),
    )

    assert too_large.status_code == 413
    assert too_large.json() == {"error": "payload_too_large"}
    assert unavailable.status_code == 503
    assert unavailable.json() == {"error": "provider_unavailable"}


class BlockingProvider:
    def __init__(self) -> None:
        self.entered = asyncio.Event()
        self.release = asyncio.Event()

    async def readiness(self) -> WorkerReadiness:
        return DisabledProvider.readiness_value()

    async def run(self, job: InferenceJob) -> InferenceJobResponse:
        self.entered.set()
        await self.release.wait()
        return FixtureProvider.response_for(job)


def test_the_single_lane_rejects_backlog_instead_of_queueing() -> None:
    async def scenario() -> None:
        provider = BlockingProvider()
        app = create_inference_app(InferenceAppOptions(token=TOKEN, provider=provider))
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://worker") as client:
            first_task = asyncio.create_task(
                client.post("/v1/jobs", headers=headers(), json=segmentation_job())
            )
            await provider.entered.wait()
            rejected = await client.post("/v1/jobs", headers=headers(), json=segmentation_job())
            provider.release.set()
            first = await first_task

        assert first.status_code == 200
        assert rejected.status_code == 429
        assert rejected.json() == {"error": "worker_busy"}

    asyncio.run(scenario())


class SlowProvider:
    async def readiness(self) -> WorkerReadiness:
        return DisabledProvider.readiness_value()

    async def run(self, job: InferenceJob) -> InferenceJobResponse:
        del job
        await asyncio.sleep(1)
        raise AssertionError("deadline did not cancel provider")


def test_worker_deadline_cancels_provider_work() -> None:
    app = create_inference_app(
        InferenceAppOptions(token=TOKEN, provider=SlowProvider(), deadline_seconds=0.01)
    )
    response = request(
        app,
        "POST",
        "/v1/jobs",
        headers=headers(),
        json_body=segmentation_job(),
    )

    assert response.status_code == 504
    assert response.json() == {"error": "worker_timeout"}


def test_binary_results_require_canonical_base64_and_matching_digests() -> None:
    encoded_depth = base64.b64encode(b"\x00\x00\x80?").decode("ascii")

    with pytest.raises(ValidationError):
        MetricDepthResult(
            kind="metric_depth",
            width=1,
            height=1,
            encoding="float32_le_base64",
            unit="metre",
            data_base64=encoded_depth,
            sha256="0" * 64,
        )

    with pytest.raises(ValidationError):
        ReconstructionResult(
            kind="point_cloud",
            encoding="ply_binary_little_endian",
            data_base64="not+canonical===",
            sha256="0" * 64,
        )
