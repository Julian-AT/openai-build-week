from __future__ import annotations

import numpy as np
import pytest

from reframe_vision.conservative_geometry import (
    EncodedIntrinsics,
    estimate_conservative_geometry,
)


def test_estimates_camera_space_bounds_and_floor_support() -> None:
    mask = np.ones((4, 4), dtype=np.bool_)
    depth = np.full((4, 4), 2.0, dtype=np.float32)
    result = estimate_conservative_geometry(
        mask,
        depth,
        EncodedIntrinsics(fx=100.0, fy=100.0, cx=1.5, cy=1.5),
        floor_y_camera_m=0.0,
    )
    assert result.decision == "ready"
    assert result.point_count == 16
    assert result.floor_support_ratio == 1.0
    assert result.extents_camera_m[2] == pytest.approx(0.01)


def test_rejects_missing_floor_support_and_sparse_depth() -> None:
    mask = np.zeros((4, 4), dtype=np.bool_)
    mask[0, 0] = True
    depth = np.full((4, 4), 2.0, dtype=np.float32)
    result = estimate_conservative_geometry(
        mask,
        depth,
        EncodedIntrinsics(fx=100.0, fy=100.0, cx=1.5, cy=1.5),
    )
    assert result.decision == "needs_more_geometry"
    assert set(result.rejection_codes) == {"insufficient_depth_points", "floor_support_unavailable"}
