import math
from typing import Literal

import pytest

from reframe_vision import TargetView, assess_target_views


def view(
    frame_id: str,
    *,
    position: tuple[float, float, float] = (0.0, 0.0, 0.0),
    yaw_degrees: float = 0.0,
    track_score: float = 0.9,
    tracking_state: Literal["normal", "limited", "unavailable"] = "normal",
) -> TargetView:
    yaw = math.radians(yaw_degrees)
    return TargetView(
        frame_id=frame_id,
        camera_position_world=position,
        camera_forward_world=(math.sin(yaw), 0.0, -math.cos(yaw)),
        track_score=track_score,
        tracking_state=tracking_state,
    )


def test_geometry_gate_accepts_metric_translation_and_selects_at_most_four_views() -> None:
    result = assess_target_views(
        (
            view("frame_1"),
            view("frame_2", position=(0.04, 0.0, 0.0)),
            view("frame_3", position=(0.16, 0.0, 0.0)),
            view("frame_4", position=(0.24, 0.0, 0.0)),
            view("frame_5", position=(0.35, 0.0, 0.0)),
        )
    )

    assert result.decision == "ready"
    assert len(result.selected_frame_ids) == 4
    assert result.max_translation_m == pytest.approx(0.35)
    assert result.rejection_codes == ()


def test_geometry_gate_accepts_view_change_without_translation() -> None:
    result = assess_target_views((view("frame_1"), view("frame_2", yaw_degrees=22.0)))

    assert result.decision == "ready"
    assert result.max_view_change_degrees == pytest.approx(22.0)


def test_geometry_gate_rejects_duplicate_and_non_normal_observations() -> None:
    result = assess_target_views(
        (
            view("frame_1"),
            view("frame_1", position=(0.20, 0.0, 0.0)),
            view(
                "frame_2",
                position=(0.30, 0.0, 0.0),
                tracking_state="limited",
            ),
        )
    )

    assert result.decision == "needs_more_views"
    assert result.selected_frame_ids == ("frame_1",)
    assert result.rejection_codes == ("insufficient_views", "insufficient_baseline")


def test_geometry_gate_requires_track_confidence() -> None:
    result = assess_target_views(
        (
            view("frame_1", track_score=0.49),
            view("frame_2", position=(0.20, 0.0, 0.0)),
        )
    )

    assert result.decision == "needs_more_views"
    assert result.selected_frame_ids == ("frame_2",)


def test_target_view_rejects_zero_forward_vectors() -> None:
    with pytest.raises(ValueError, match="forward vector must be non-zero"):
        TargetView(
            frame_id="frame_1",
            camera_position_world=(0.0, 0.0, 0.0),
            camera_forward_world=(0.0, 0.0, 0.0),
            track_score=0.9,
            tracking_state="normal",
        )
