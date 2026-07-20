from __future__ import annotations

import asyncio

import httpx
import pytest
from pydantic import TypeAdapter

from reframe_vision.contracts import InferenceJob, MetricDepthJob
from reframe_vision.providers import ModelServiceProvider, VisionServiceEndpoints


def test_model_provider_routes_a_typed_job_to_the_segmentation_lane() -> None:
    async def run() -> None:
        requested_paths: list[str] = []
        adapter: TypeAdapter[InferenceJob] = TypeAdapter(InferenceJob)

        async def handler(request: httpx.Request) -> httpx.Response:
            requested_paths.append(request.url.path)
            job: InferenceJob = adapter.validate_json(request.content)
            return httpx.Response(
                200,
                json={
                    "protocol_version": "1.0.0",
                    "request_id": job.request_id,
                    "task": "segment",
                    "provider": {
                        "provider_id": "sam3",
                        "provider_revision": "46957e47805eaa273f4aa7bbbd25a88bca9108ce",
                        "evidence_class": "unmeasured",
                    },
                    "result": {
                        "kind": "mask",
                        "width": 1,
                        "height": 1,
                        "encoding": "binary_rle",
                        "counts": [0, 1],
                        "foreground_pixels": 1,
                        "sha256": (
                            "4bf5122f344554c53bde2ebb8cd2b7e3d1600ad631c385a5d7cce23c7785459a"
                        ),
                    },
                },
            )

        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            provider = ModelServiceProvider(
                VisionServiceEndpoints(
                    segmentation="http://segment",
                    metric_depth="http://depth",
                    reconstruction="http://reconstruct",
                ),
                client=client,
            )
            job: InferenceJob = adapter.validate_python(
                {
                    "protocol_version": "1.0.0",
                    "request_id": "inference_10000000-0000-4000-8000-000000000001",
                    "task": "segment",
                    "image": {
                        "frame_id": "frame_10000000-0000-4000-8000-000000000001",
                        "media_type": "image/jpeg",
                        "data_base64": "/9j/2Q==",
                        "sha256": (
                            "32461d5bd1773012acef0ba15636752949bd7c2ce50f9172159d9f56cf0dd9af"
                        ),
                        "width": 1,
                        "height": 1,
                    },
                    "prompt": {"kind": "point", "x": 0, "y": 0, "label": "foreground"},
                }
            )

            response = await provider.run(job)

        assert response.request_id == job.request_id
        assert response.provider.provider_id == "sam3"
        assert requested_paths == ["/infer"]

    asyncio.run(run())


def test_metric_depth_job_binds_intrinsics_to_encoded_image() -> None:
    job = MetricDepthJob.model_validate(
        {
            "protocol_version": "1.0.0",
            "request_id": "inference_10000000-0000-4000-8000-000000000001",
            "task": "metric_depth",
            "image": {
                "frame_id": "frame_10000000-0000-4000-8000-000000000001",
                "media_type": "image/jpeg",
                "data_base64": "/9j/2Q==",
                "sha256": "32461d5bd1773012acef0ba15636752949bd7c2ce50f9172159d9f56cf0dd9af",
                "width": 1,
                "height": 1,
            },
            "intrinsics_encoded_pixels": {
                "fx": 1.0,
                "fy": 1.0,
                "cx": 0.5,
                "cy": 0.5,
                "width": 1,
                "height": 1,
                "units": "encoded_pixels",
            },
        }
    )

    assert job.intrinsics_encoded_pixels.fx == 1.0

    with pytest.raises(ValueError, match="intrinsics dimensions do not match image"):
        MetricDepthJob.model_validate(
            {
                **job.model_dump(),
                "intrinsics_encoded_pixels": {
                    **job.intrinsics_encoded_pixels.model_dump(),
                    "width": 2,
                },
            }
        )
