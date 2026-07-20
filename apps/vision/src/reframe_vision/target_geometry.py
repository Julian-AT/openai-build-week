from __future__ import annotations

import math
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

Vector3 = tuple[float, float, float]
MINIMUM_DIRECTION_NORM = 1e-6
MINIMUM_VIEW_COUNT = 2
MAXIMUM_SELECTED_VIEW_COUNT = 4


class TargetView(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, strict=True)

    frame_id: str = Field(min_length=1)
    camera_position_world: Vector3
    camera_forward_world: Vector3
    track_score: float = Field(ge=0.0, le=1.0)
    tracking_state: Literal["normal", "limited", "unavailable"]

    @field_validator("camera_position_world", "camera_forward_world")
    @classmethod
    def require_finite_vector(cls, value: Vector3) -> Vector3:
        if not all(math.isfinite(component) for component in value):
            raise ValueError("camera vectors must be finite")
        return value

    @field_validator("camera_forward_world")
    @classmethod
    def require_direction(cls, value: Vector3) -> Vector3:
        if _norm(value) < MINIMUM_DIRECTION_NORM:
            raise ValueError("camera forward vector must be non-zero")
        return value


class TargetViewAssessment(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, strict=True)

    decision: Literal["ready", "needs_more_views"]
    selected_frame_ids: tuple[str, ...]
    max_translation_m: float = Field(ge=0.0)
    max_view_change_degrees: float = Field(ge=0.0, le=180.0)
    rejection_codes: tuple[Literal["insufficient_views", "insufficient_baseline"], ...]


def assess_target_views(
    views: tuple[TargetView, ...],
    *,
    minimum_track_score: float = 0.5,
    minimum_translation_m: float = 0.15,
    minimum_view_change_degrees: float = 12.0,
) -> TargetViewAssessment:
    eligible = _unique_eligible_views(views, minimum_track_score)
    max_translation, max_angle = _maximum_baseline(eligible)
    selected = _select_views(eligible)

    rejection_codes: list[Literal["insufficient_views", "insufficient_baseline"]] = []
    if len(eligible) < MINIMUM_VIEW_COUNT:
        rejection_codes.append("insufficient_views")
    if max_translation < minimum_translation_m and max_angle < minimum_view_change_degrees:
        rejection_codes.append("insufficient_baseline")

    return TargetViewAssessment(
        decision="needs_more_views" if rejection_codes else "ready",
        selected_frame_ids=tuple(view.frame_id for view in selected),
        max_translation_m=max_translation,
        max_view_change_degrees=max_angle,
        rejection_codes=tuple(rejection_codes),
    )


def _unique_eligible_views(
    views: tuple[TargetView, ...], minimum_track_score: float
) -> tuple[TargetView, ...]:
    accepted: list[TargetView] = []
    seen_frame_ids: set[str] = set()
    for view in views:
        if view.frame_id in seen_frame_ids:
            continue
        seen_frame_ids.add(view.frame_id)
        if view.tracking_state == "normal" and view.track_score >= minimum_track_score:
            accepted.append(view)
    return tuple(accepted)


def _maximum_baseline(views: tuple[TargetView, ...]) -> tuple[float, float]:
    max_translation = 0.0
    max_angle = 0.0
    for left_index, left in enumerate(views):
        for right in views[left_index + 1 :]:
            max_translation = max(
                max_translation,
                _distance(left.camera_position_world, right.camera_position_world),
            )
            max_angle = max(
                max_angle,
                _angle_degrees(left.camera_forward_world, right.camera_forward_world),
            )
    return max_translation, max_angle


def _select_views(views: tuple[TargetView, ...]) -> tuple[TargetView, ...]:
    if len(views) <= MAXIMUM_SELECTED_VIEW_COUNT:
        return views

    selected = [views[0]]
    remaining = list(views[1:])
    while remaining and len(selected) < MAXIMUM_SELECTED_VIEW_COUNT:
        candidate = max(
            remaining,
            key=lambda view: min(_view_separation(view, existing) for existing in selected),
        )
        selected.append(candidate)
        remaining.remove(candidate)
    return tuple(selected)


def _view_separation(left: TargetView, right: TargetView) -> float:
    return _distance(left.camera_position_world, right.camera_position_world) + (
        _angle_degrees(left.camera_forward_world, right.camera_forward_world) / 180.0
    )


def _distance(left: Vector3, right: Vector3) -> float:
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(left, right, strict=True)))


def _norm(vector: Vector3) -> float:
    return math.sqrt(sum(component**2 for component in vector))


def _angle_degrees(left: Vector3, right: Vector3) -> float:
    denominator = _norm(left) * _norm(right)
    cosine = sum(a * b for a, b in zip(left, right, strict=True)) / denominator
    return math.degrees(math.acos(max(-1.0, min(1.0, cosine))))
