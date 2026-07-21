# Fake predictor boundary deliberately mirrors the untyped external SDK.
from __future__ import annotations

import asyncio

import numpy as np
import pytest

from reframe_vision.contracts import ImageInput, SegmentationJob
from reframe_vision.providers import ProviderUnavailableError
from reframe_vision.sam3_provider import (
    SAMPrediction,
    SAMPrompt,
    SAMProvider,
    encode_binary_rle,
)

IMAGE = {
    "frame_id": "frame_10000000-0000-4000-8000-000000000001",
    "media_type": "image/jpeg",
    "data_base64": "/9j/2Q==",
    "sha256": "32461d5bd1773012acef0ba15636752949bd7c2ce50f9172159d9f56cf0dd9af",
    "width": 1,
    "height": 1,
}


class FakeEngine:
    def __init__(self) -> None:
        self.started: list[tuple[str, int]] = []
        self.frames: list[tuple[str, int]] = []

    def start_session(self, session_id: str, image: ImageInput, frame_index: int) -> None:
        del image
        self.started.append((session_id, frame_index))

    def segment(
        self,
        session_id: str,
        frame_index: int,
        image: ImageInput,
        prompt: SAMPrompt,
    ) -> SAMPrediction:
        del image, prompt
        self.frames.append((session_id, frame_index))
        return SAMPrediction(mask=np.asarray([[True]], dtype=np.bool_), confidence=0.91)

    def close_session(self, session_id: str) -> None:
        del session_id


def job(frame_index: int, *, target_id: str = "target_chair") -> SegmentationJob:
    return SegmentationJob.model_validate(
        {
            "protocol_version": "1.0.0",
            "request_id": f"inference_10000000-0000-4000-8000-00000000000{frame_index + 1}",
            "task": "segment",
            "image": {
                **IMAGE,
                "frame_id": f"frame_10000000-0000-4000-8000-00000000000{frame_index + 1}",
            },
            "prompt": {"kind": "point", "x": 0, "y": 0, "label": "foreground"},
            "session_id": "room_alpha",
            "target_id": target_id,
            "frame_index": frame_index,
        }
    )


def test_rle_is_row_major_and_digest_bound() -> None:
    counts, foreground, digest = encode_binary_rle(
        np.asarray([[False, True], [True, False]], dtype=np.bool_)
    )
    assert counts == (1, 2, 1)
    assert foreground == 2
    assert digest == "d5e2d2ac07b741be58f6b9e50ede5fdcf16f3e8053ecef9350e7744b0d8bd90c"


def test_provider_binds_one_target_and_monotonic_frames() -> None:
    async def run() -> None:
        engine = FakeEngine()
        provider = SAMProvider(engine, provider_revision="hfsha-srcsha")
        first = await provider.run(job(0))
        second = await provider.run(job(1))
        assert first.result.kind == second.result.kind == "mask"
        assert engine.started == [("room_alpha", 0)]
        assert engine.frames == [("room_alpha", 0), ("room_alpha", 1)]
        track = provider.track("room_alpha")
        assert track is not None
        assert track.latest_mask is not None
        assert track.latest_mask.frame_id == 1
        with pytest.raises(ProviderUnavailableError):
            await provider.run(job(1))
        with pytest.raises(ProviderUnavailableError):
            await provider.run(job(2, target_id="target_table"))

    asyncio.run(run())


def test_segmentation_contract_rejects_unbound_state() -> None:
    with pytest.raises(ValueError, match="session and target identity"):
        SegmentationJob.model_validate(
            {
                **job(0).model_dump(),
                "target_id": None,
            }
        )


def test_segmentation_contract_accepts_box_prompt_and_rejects_out_of_bounds() -> None:
    accepted = {
        **job(0).model_dump(),
        "prompt": {"kind": "box", "x": 0, "y": 0, "width": 1, "height": 1},
    }
    assert SegmentationJob.model_validate(accepted).prompt.kind == "box"
    with pytest.raises(ValueError, match="prompt box"):
        SegmentationJob.model_validate(
            {
                **accepted,
                "prompt": {"kind": "box", "x": 0, "y": 0, "width": 2, "height": 1},
            }
        )


def test_box_prompt_starts_a_track_from_the_box_center() -> None:
    async def run() -> None:
        provider = SAMProvider(FakeEngine(), provider_revision="hfsha-srcsha")
        boxed = job(0)
        boxed = SegmentationJob.model_validate(
            {
                **boxed.model_dump(),
                "prompt": {"kind": "box", "x": 0, "y": 0, "width": 1, "height": 1},
            }
        )
        await provider.run(boxed)
        track = provider.track("room_alpha")
        assert track is not None
        assert track.seed.pixel_x == 0
        assert track.seed.pixel_y == 0

    asyncio.run(run())
