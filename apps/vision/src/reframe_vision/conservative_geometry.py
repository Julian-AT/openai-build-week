from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Literal

import numpy as np
from numpy.typing import NDArray

MIN_GEOMETRY_POINTS = 8
MIN_FLOOR_SUPPORT_RATIO = 0.5
DEFAULT_FLOOR_TOLERANCE_M = 0.04
CONSERVATIVE_PADDING_M = 0.01
MATRIX_DIMENSIONS = 2

Vector3 = tuple[float, float, float]


@dataclass(frozen=True, slots=True)
class EncodedIntrinsics:
    fx: float
    fy: float
    cx: float
    cy: float


@dataclass(frozen=True, slots=True)
class ConservativeGeometry:
    decision: Literal["ready", "needs_more_geometry"]
    center_camera_m: Vector3
    extents_camera_m: Vector3
    floor_y_camera_m: float | None
    floor_support_ratio: float
    point_count: int
    rejection_codes: tuple[str, ...]


def estimate_conservative_geometry(
    mask: NDArray[np.bool_],
    depth_m: NDArray[np.float32],
    intrinsics: EncodedIntrinsics,
    *,
    floor_y_camera_m: float | None = None,
    floor_tolerance_m: float = DEFAULT_FLOOR_TOLERANCE_M,
) -> ConservativeGeometry:
    """Estimate a bounded camera-space OBB from one mask/depth pair.

    This is deliberately a fast replacement-readiness gate, not a dense scene
    reconstruction. It never invents points for missing or invalid depth.
    """
    _validate_inputs(mask, depth_m, intrinsics, floor_tolerance_m)
    ys, xs = np.nonzero(mask)
    values = np.asarray(depth_m[ys, xs], dtype=np.float64)
    valid = np.isfinite(values) & (values > 0.0)
    xs = xs[valid].astype(np.float64)
    ys = ys[valid].astype(np.float64)
    values = values[valid]
    rejection_codes: list[str] = []
    if values.size < MIN_GEOMETRY_POINTS:
        rejection_codes.append("insufficient_depth_points")
    if values.size:
        points = np.column_stack(
            (
                (xs - intrinsics.cx) * values / intrinsics.fx,
                (ys - intrinsics.cy) * values / intrinsics.fy,
                values,
            )
        )
        minimum = np.min(points, axis=0)
        maximum = np.max(points, axis=0)
        center = (minimum + maximum) / 2.0
        extents = np.maximum(maximum - minimum + CONSERVATIVE_PADDING_M, 0.0)
    else:
        points = np.empty((0, 3), dtype=np.float64)
        center = np.zeros(3, dtype=np.float64)
        extents = np.zeros(3, dtype=np.float64)

    support_ratio = 0.0
    if floor_y_camera_m is not None and len(points):
        support_ratio = float(np.mean(np.abs(points[:, 1] - floor_y_camera_m) <= floor_tolerance_m))
        if support_ratio < MIN_FLOOR_SUPPORT_RATIO:
            rejection_codes.append("insufficient_floor_support")
    elif floor_y_camera_m is None:
        rejection_codes.append("floor_support_unavailable")

    return ConservativeGeometry(
        decision="needs_more_geometry" if rejection_codes else "ready",
        center_camera_m=_vector(center),
        extents_camera_m=_vector(extents),
        floor_y_camera_m=floor_y_camera_m,
        floor_support_ratio=support_ratio,
        point_count=int(values.size),
        rejection_codes=tuple(rejection_codes),
    )


def _validate_inputs(
    mask: NDArray[np.bool_],
    depth_m: NDArray[np.float32],
    intrinsics: EncodedIntrinsics,
    floor_tolerance_m: float,
) -> None:
    if (
        mask.ndim != MATRIX_DIMENSIONS
        or depth_m.ndim != MATRIX_DIMENSIONS
        or mask.shape != depth_m.shape
    ):
        raise ValueError("mask and depth dimensions must match")
    if not all(
        math.isfinite(value) and value > 0.0
        for value in (intrinsics.fx, intrinsics.fy, intrinsics.cx, intrinsics.cy)
    ):
        raise ValueError("intrinsics must be finite and positive")
    if not math.isfinite(floor_tolerance_m) or floor_tolerance_m <= 0.0:
        raise ValueError("invalid floor tolerance")


def _vector(value: NDArray[np.float64]) -> Vector3:
    return (float(value[0]), float(value[1]), float(value[2]))
