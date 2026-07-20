import asyncio

import pytest

from reframe_vision import (
    DisabledRevealFillProvider,
    RevealFillRequest,
    RevealFillUnavailableError,
    RevealMetrics,
    assess_reveal,
)


def test_automated_reveal_readiness_accepts_a_safe_bundle() -> None:
    result = assess_reveal(
        RevealMetrics(
            coverage_p10=0.97,
            coverage_median=0.99,
            largest_uncovered_component_fraction=0.005,
            observed_fraction_outside_hole=0.9,
            foreground_overwrite_fraction=0.0,
            seam_severity="minor",
            severe_surface_order_artifact=False,
        )
    )

    assert result.decision == "ready"
    assert result.rejection_codes == ()


def test_automated_reveal_readiness_reports_every_failed_safety_gate() -> None:
    result = assess_reveal(
        RevealMetrics(
            coverage_p10=0.90,
            coverage_median=0.95,
            largest_uncovered_component_fraction=0.02,
            observed_fraction_outside_hole=0.70,
            foreground_overwrite_fraction=0.001,
            seam_severity="severe",
            severe_surface_order_artifact=True,
        )
    )

    assert result.decision == "rejected"
    assert result.rejection_codes == (
        "coverage_p10",
        "coverage_median",
        "uncovered_component",
        "observed_fraction",
        "foreground_overwrite",
        "seam",
        "surface_order",
    )


def test_disabled_fill_provider_fails_closed_without_modifying_input() -> None:
    request = RevealFillRequest(
        color_png=b"\x89PNG\r\n\x1a\ncolor",
        binary_mask_png=b"\x89PNG\r\n\x1a\nmask",
    )

    with pytest.raises(RevealFillUnavailableError):
        asyncio.run(DisabledRevealFillProvider().fill(request))
