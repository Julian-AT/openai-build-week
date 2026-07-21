# Fake predictor boundary deliberately mirrors the untyped external SDK.
from __future__ import annotations

import asyncio
import sys
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pytest

from reframe_vision.contracts import ImageInput, SegmentationJob
from reframe_vision.providers import ProviderUnavailableError
from reframe_vision.sam3_provider import (
    SAM3PredictorEngine,
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


def test_predictor_engine_binds_point_prompt_and_reads_target_output(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    class FakePredictor:
        def __init__(self) -> None:
            self.requests: list[dict[str, object]] = []

        def handle_request(self, request: dict[str, object]) -> dict[str, object]:
            self.requests.append(request)
            if request["type"] == "add_prompt":
                return {
                    "outputs": {
                        # The multiplex predictor may normalize a sole object to id 0.
                        "out_obj_ids": np.asarray([0]),
                        "out_binary_masks": np.asarray([[[True]]]),
                        "out_probs": np.asarray([0.88], dtype=np.float32),
                    }
                }
            return {"session_id": "room_alpha"}

    class FakeTorch:
        float32 = "float32"
        int32 = "int32"

        @staticmethod
        def tensor(value: object, *, dtype: object) -> tuple[object, object]:
            return (value, dtype)

    predictor = FakePredictor()
    monkeypatch.setitem(
        sys.modules,
        "torch",
        SimpleNamespace(float32=FakeTorch.float32, int32=FakeTorch.int32, tensor=FakeTorch.tensor),
    )
    engine = SAM3PredictorEngine(predictor, tmp_path)
    image = SegmentationJob.model_validate(job(0)).image
    engine.start_session("room_alpha", image, 0)
    result = engine.segment(
        "room_alpha",
        0,
        image,
        SAMPrompt(kind="point", x=0, y=0, label="foreground"),
    )
    assert result.confidence == pytest.approx(0.88)
    assert result.mask.tolist() == [[True]]
    request = predictor.requests[-1]
    assert request["points"] == ([[0.0, 0.0]], "float32")
    assert request["point_labels"] == ([1], "int32")


def test_predictor_engine_maps_box_prompt_to_normalized_xywh(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    class FakePredictor:
        def __init__(self) -> None:
            self.requests: list[dict[str, object]] = []

        def handle_request(self, request: dict[str, object]) -> dict[str, object]:
            self.requests.append(request)
            if request["type"] == "add_prompt":
                return {
                    "outputs": {
                        "out_obj_ids": np.asarray([1]),
                        "out_binary_masks": np.asarray([[[True]]]),
                        "out_probs": np.asarray([0.8], dtype=np.float32),
                    }
                }
            return {"session_id": "room_alpha"}

    class FakeTorch:
        float32 = "float32"
        int32 = "int32"

        @staticmethod
        def tensor(value: object, *, dtype: object) -> tuple[object, object]:
            return (value, dtype)

    monkeypatch.setitem(
        sys.modules,
        "torch",
        SimpleNamespace(float32=FakeTorch.float32, int32=FakeTorch.int32, tensor=FakeTorch.tensor),
    )
    predictor = FakePredictor()
    engine = SAM3PredictorEngine(predictor, tmp_path)
    image = image_from_job(job(0))
    engine.start_session("room_alpha", image, 0)
    engine.segment("room_alpha", 0, image, SAMPrompt(kind="box", x=0, y=0, width=1, height=1))
    request = predictor.requests[-1]
    assert request["bounding_boxes"] == ([[0.0, 0.0, 1.0, 1.0]], "float32")
    assert request["bounding_box_labels"] == ([1], "int32")


def test_predictor_engine_rejects_multiple_unbound_object_ids(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    class FakePredictor:
        def handle_request(self, request: dict[str, object]) -> dict[str, object]:
            if request["type"] == "add_prompt":
                return {
                    "outputs": {
                        "out_obj_ids": np.asarray([0, 2]),
                        "out_binary_masks": np.asarray([[[True]], [[True]]]),
                        "out_probs": np.asarray([0.8, 0.7], dtype=np.float32),
                    }
                }
            return {"session_id": "room_alpha"}

    class FakeTorch:
        float32 = "float32"
        int32 = "int32"

        @staticmethod
        def tensor(value: object, *, dtype: object) -> tuple[object, object]:
            return (value, dtype)

    monkeypatch.setitem(
        sys.modules,
        "torch",
        SimpleNamespace(float32=FakeTorch.float32, int32=FakeTorch.int32, tensor=FakeTorch.tensor),
    )
    engine = SAM3PredictorEngine(FakePredictor(), tmp_path)
    image = image_from_job(job(0))
    engine.start_session("room_alpha", image, 0)
    with pytest.raises(ProviderUnavailableError):
        engine.segment(
            "room_alpha",
            0,
            image,
            SAMPrompt(kind="point", x=0, y=0, label="foreground"),
        )


def image_from_job(value: SegmentationJob) -> ImageInput:
    return value.image
