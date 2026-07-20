from __future__ import annotations

import base64
import binascii
import hashlib
from typing import Literal, Protocol

import httpx
from pydantic import BaseModel, ConfigDict, Field

MIN_COVERAGE_P10 = 0.95
MIN_COVERAGE_MEDIAN = 0.98
MAX_UNCOVERED_COMPONENT_FRACTION = 0.01
MIN_OBSERVED_FRACTION_OUTSIDE_HOLE = 0.80
MAX_FILL_INPUT_BYTES = 8_000_000
MAX_FILL_RESPONSE_BYTES = 24_000_000
MAX_FILL_OUTPUT_BYTES = 16_000_000
MAX_PROVIDER_REVISION_LENGTH = 128
SHA256_HEX_LENGTH = 64
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
SHA256_PATTERN = r"^[0-9a-f]{64}$"


class RevealFillRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, strict=True)

    color_png: bytes = Field(min_length=8)
    binary_mask_png: bytes = Field(min_length=8)


class RevealFillProvider(Protocol):
    async def fill(self, request: RevealFillRequest) -> RevealFillResult: ...


class RevealFillResult(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, strict=True)

    output_png: bytes = Field(min_length=8)
    provider_id: Literal["lama"]
    provider_revision: str = Field(min_length=1, max_length=128)
    checkpoint_sha256: str = Field(pattern=SHA256_PATTERN)
    output_sha256: str = Field(pattern=SHA256_PATTERN)


class _RevealFillWireResponse(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, strict=True)

    protocol_version: Literal["1.0.0"]
    provider_id: Literal["lama"]
    provider_revision: str = Field(min_length=1, max_length=128)
    checkpoint_sha256: str = Field(pattern=SHA256_PATTERN)
    output_png_base64: str = Field(min_length=12, max_length=MAX_FILL_RESPONSE_BYTES)
    output_sha256: str = Field(pattern=SHA256_PATTERN)


class RevealFillUnavailableError(Exception):
    pass


class DisabledRevealFillProvider:
    async def fill(self, request: RevealFillRequest) -> RevealFillResult:
        del request
        raise RevealFillUnavailableError


class HttpRevealFillProvider:
    def __init__(
        self,
        endpoint: str,
        *,
        provider_revision: str,
        checkpoint_sha256: str,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        url = httpx.URL(endpoint)
        if url.scheme not in {"http", "https"} or not url.host or url.query or url.fragment:
            raise ValueError("invalid reveal fill endpoint")
        if not provider_revision or len(provider_revision) > MAX_PROVIDER_REVISION_LENGTH:
            raise ValueError("invalid reveal provider revision")
        if len(checkpoint_sha256) != SHA256_HEX_LENGTH or any(
            character not in "0123456789abcdef" for character in checkpoint_sha256
        ):
            raise ValueError("invalid reveal checkpoint digest")
        self._endpoint = str(url).rstrip("/")
        self._provider_revision = provider_revision
        self._checkpoint_sha256 = checkpoint_sha256
        self._client = client or httpx.AsyncClient(
            timeout=httpx.Timeout(110.0, connect=5.0),
            limits=httpx.Limits(max_connections=1, max_keepalive_connections=1),
        )

    async def fill(self, request: RevealFillRequest) -> RevealFillResult:
        if (
            len(request.color_png) > MAX_FILL_INPUT_BYTES
            or len(request.binary_mask_png) > MAX_FILL_INPUT_BYTES
            or not request.color_png.startswith(PNG_SIGNATURE)
            or not request.binary_mask_png.startswith(PNG_SIGNATURE)
        ):
            raise RevealFillUnavailableError
        payload = {
            "protocol_version": "1.0.0",
            "color_png_base64": base64.b64encode(request.color_png).decode("ascii"),
            "color_sha256": hashlib.sha256(request.color_png).hexdigest(),
            "binary_mask_png_base64": base64.b64encode(request.binary_mask_png).decode("ascii"),
            "binary_mask_sha256": hashlib.sha256(request.binary_mask_png).hexdigest(),
        }
        try:
            response = await self._client.post(f"{self._endpoint}/v1/fill", json=payload)
            response.raise_for_status()
            wire = _parse_wire_response(response.content)
            output = base64.b64decode(wire.output_png_base64, validate=True)
        except (httpx.HTTPError, ValueError, binascii.Error) as error:
            raise RevealFillUnavailableError from error
        output_digest = hashlib.sha256(output).hexdigest()
        if (
            wire.provider_revision != self._provider_revision
            or wire.checkpoint_sha256 != self._checkpoint_sha256
            or len(output) > MAX_FILL_OUTPUT_BYTES
            or not output.startswith(PNG_SIGNATURE)
            or wire.output_sha256 != output_digest
        ):
            raise RevealFillUnavailableError
        return RevealFillResult(
            output_png=output,
            provider_id=wire.provider_id,
            provider_revision=wire.provider_revision,
            checkpoint_sha256=wire.checkpoint_sha256,
            output_sha256=wire.output_sha256,
        )


def _parse_wire_response(content: bytes) -> _RevealFillWireResponse:
    if len(content) > MAX_FILL_RESPONSE_BYTES:
        raise ValueError("oversized reveal response")
    return _RevealFillWireResponse.model_validate_json(content)


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
    if metrics.coverage_p10 < MIN_COVERAGE_P10:
        rejection_codes.append("coverage_p10")
    if metrics.coverage_median < MIN_COVERAGE_MEDIAN:
        rejection_codes.append("coverage_median")
    if metrics.largest_uncovered_component_fraction > MAX_UNCOVERED_COMPONENT_FRACTION:
        rejection_codes.append("uncovered_component")
    if metrics.observed_fraction_outside_hole < MIN_OBSERVED_FRACTION_OUTSIDE_HOLE:
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
