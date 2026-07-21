import hashlib

import pytest

from reframe_vision.target_track import (
    TargetMaskObservation,
    TargetSeedBinding,
    TargetTrackStore,
)


def test_primary_track_preserves_identity_across_a_valid_mask_revision() -> None:
    store = TargetTrackStore()
    seed = TargetSeedBinding(
        session_id="room_alpha",
        frame_id=42,
        encoded_width=4,
        encoded_height=3,
        pixel_x=2,
        pixel_y=1,
    )

    started = store.begin(seed, target_id="target_chair")
    pixels = bytes((0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0))
    revised = store.record(
        TargetMaskObservation(
            session_id="room_alpha",
            target_id="target_chair",
            frame_id=43,
            encoded_width=4,
            encoded_height=3,
            counts=(5, 2, 2, 2, 1),
            confidence=0.92,
            sha256=hashlib.sha256(pixels).hexdigest(),
            provider_id="sam3.1",
            provider_revision="checkpoint_abc",
        )
    )

    assert started.target_id == revised.target_id == "target_chair"
    assert revised.revision == 2
    assert revised.status == "tracked"
    assert revised.latest_mask is not None
    assert revised.latest_mask.frame_id == 43


def test_track_rejects_a_model_attempt_to_change_the_session_target() -> None:
    store = TargetTrackStore()
    seed = TargetSeedBinding(
        session_id="room_alpha",
        frame_id=42,
        encoded_width=2,
        encoded_height=2,
        pixel_x=1,
        pixel_y=1,
    )
    started = store.begin(seed, target_id="target_chair")
    pixels = bytes((0, 1, 1, 0))

    with pytest.raises(ValueError, match="unknown primary target"):
        store.record(
            TargetMaskObservation(
                session_id="room_alpha",
                target_id="target_table",
                frame_id=43,
                encoded_width=2,
                encoded_height=2,
                counts=(1, 2, 1),
                confidence=0.92,
                sha256=hashlib.sha256(pixels).hexdigest(),
                provider_id="sam3.1",
                provider_revision="checkpoint_abc",
            )
        )

    assert store.current("room_alpha") == started


def test_lost_track_cannot_be_silently_resurrected_by_a_later_mask() -> None:
    store = TargetTrackStore()
    seed = TargetSeedBinding(
        session_id="room_alpha",
        frame_id=42,
        encoded_width=2,
        encoded_height=2,
        pixel_x=1,
        pixel_y=1,
    )
    store.begin(seed, target_id="target_chair")
    lost = store.mark_lost("room_alpha", target_id="target_chair")
    pixels = bytes((0, 1, 1, 0))

    with pytest.raises(ValueError, match="target track is lost"):
        store.record(
            TargetMaskObservation(
                session_id="room_alpha",
                target_id="target_chair",
                frame_id=43,
                encoded_width=2,
                encoded_height=2,
                counts=(1, 2, 1),
                confidence=0.92,
                sha256=hashlib.sha256(pixels).hexdigest(),
                provider_id="sam3.1",
                provider_revision="checkpoint_abc",
            )
        )

    assert lost.status == "lost"
    assert lost.revision == 2
    assert store.current("room_alpha") == lost
