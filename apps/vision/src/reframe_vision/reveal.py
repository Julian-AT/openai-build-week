from __future__ import annotations

from typing import Literal, Protocol

from pydantic import BaseModel, ConfigDict, Field


class RevealFillRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, strict=True)

    color_png: bytes = Field(min_length=8)
    binary_mask_png: bytes = Field(min_length=8)


class RevealFillProvider(Protocol):
    async def fill(self, request: RevealFillRequest) -> bytes: ...


class RevealFillUnavailableError(Exception):
    pass


class DisabledRevealFillProvider:
    async def fill(self, request: RevealFillRequest) -> bytes:
        del request
        raise RevealFillUnavailableError


class RevealMetrics(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, strict=True)

    coverage_p10: float = Field(ge=0.0, le=1.0)
    coverage_median: float = Field(ge=0.0, le=1.0)
    largest_uncovered_component_fraction: float = Field(ge=0.0, le=1.0)
    observed_fraction_outside_hole: float = Field(ge=0.0, le=1.0)
    foreground_overwrite_fraction: float = Field(ge=0.0, le=1.0)
    seam_severity: Literal["none", "minor", "severe"]
    severe_surface_order_artifact: bool


class RevealAssessment(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, strict=True)

    decision: Literal["ready", "rejected"]
    rejection_codes: tuple[str, ...]


def assess_reveal(metrics: RevealMetrics) -> RevealAssessment:
    rejection_codes: list[str] = []
    if metrics.coverage_p10 < 0.95:
        rejection_codes.append("coverage_p10")
    if metrics.coverage_median < 0.98:
        rejection_codes.append("coverage_median")
    if metrics.largest_uncovered_component_fraction > 0.01:
        rejection_codes.append("uncovered_component")
    if metrics.observed_fraction_outside_hole < 0.80:
        rejection_codes.append("observed_fraction")
    if metrics.foreground_overwrite_fraction > 0.0:
        rejection_codes.append("foreground_overwrite")
    if metrics.seam_severity == "severe":
        rejection_codes.append("seam")
    if metrics.severe_surface_order_artifact:
        rejection_codes.append("surface_order")
    return RevealAssessment(
        decision="rejected" if rejection_codes else "ready",
        rejection_codes=tuple(rejection_codes),
    )
