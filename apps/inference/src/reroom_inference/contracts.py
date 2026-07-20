from __future__ import annotations

import base64
import binascii
import hashlib
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

PROTOCOL_VERSION = "1.0.0"
MAX_IMAGE_BYTES = 2_500_000
MAX_IMAGE_PIXELS = 16_777_216
MAX_BINARY_RESULT_BYTES = 8_000_000
MAX_BINARY_RESULT_BASE64_LENGTH = 10_666_668
MIN_JPEG_BYTES = 4


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, strict=True)


class ImageInput(StrictModel):
    frame_id: str = Field(
        pattern=r"^frame_[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
    )
    media_type: Literal["image/jpeg"]
    data_base64: str = Field(min_length=4, max_length=3_400_000)
    sha256: str = Field(pattern=r"^[0-9a-f]{64}$")
    width: int = Field(ge=1, le=4_096)
    height: int = Field(ge=1, le=4_096)

    @model_validator(mode="after")
    def validate_image(self) -> ImageInput:
        if self.width * self.height > MAX_IMAGE_PIXELS:
            raise ValueError("image dimensions exceed limit")
        try:
            image = base64.b64decode(self.data_base64, validate=True)
        except (binascii.Error, ValueError) as error:
            raise ValueError("invalid image encoding") from error
        if (
            len(image) < MIN_JPEG_BYTES
            or len(image) > MAX_IMAGE_BYTES
            or not image.startswith(b"\xff\xd8")
            or not image.endswith(b"\xff\xd9")
            or hashlib.sha256(image).hexdigest() != self.sha256
        ):
            raise ValueError("invalid image binding")
        return self


class PointPrompt(StrictModel):
    kind: Literal["point"]
    x: int = Field(ge=0)
    y: int = Field(ge=0)
    label: Literal["foreground", "background"]


class SegmentationJob(StrictModel):
    protocol_version: Literal["1.0.0"]
    request_id: str = Field(
        pattern=r"^inference_[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
    )
    task: Literal["segment"]
    image: ImageInput
    prompt: PointPrompt

    @model_validator(mode="after")
    def validate_prompt_bounds(self) -> SegmentationJob:
        if self.prompt.x >= self.image.width or self.prompt.y >= self.image.height:
            raise ValueError("prompt is outside image")
        return self


class MetricDepthJob(StrictModel):
    protocol_version: Literal["1.0.0"]
    request_id: str = Field(
        pattern=r"^inference_[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
    )
    task: Literal["metric_depth"]
    image: ImageInput


class ReconstructionJob(StrictModel):
    protocol_version: Literal["1.0.0"]
    request_id: str = Field(
        pattern=r"^inference_[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
    )
    task: Literal["reconstruct"]
    archive_sha256: str = Field(pattern=r"^[0-9a-f]{64}$")
    frame_ids: tuple[str, ...] = Field(min_length=2, max_length=64)


InferenceJob = Annotated[
    SegmentationJob | MetricDepthJob | ReconstructionJob,
    Field(discriminator="task"),
]


class ProviderIdentity(StrictModel):
    provider_id: str = Field(pattern=r"^[a-z][a-z0-9_-]{0,63}$")
    provider_revision: str = Field(pattern=r"^[A-Za-z0-9._-]{1,128}$")
    evidence_class: Literal["fixture_only", "unmeasured", "measured"]


class TorchReadiness(StrictModel):
    installed: bool
    version: str | None
    mps_available: bool


class TaskReadiness(StrictModel):
    segment: bool
    metric_depth: bool
    reconstruct: bool


class WorkerReadiness(StrictModel):
    protocol_version: Literal["1.0.0"] = PROTOCOL_VERSION
    status: Literal["ready", "disabled", "degraded"]
    provider: ProviderIdentity
    tasks: TaskReadiness
    torch: TorchReadiness


class MaskResult(StrictModel):
    kind: Literal["mask"]
    width: int = Field(ge=1, le=4_096)
    height: int = Field(ge=1, le=4_096)
    encoding: Literal["binary_rle"]
    counts: tuple[int, ...] = Field(min_length=1, max_length=1_000_000)
    foreground_pixels: int = Field(ge=0)
    sha256: str = Field(pattern=r"^[0-9a-f]{64}$")

    @model_validator(mode="after")
    def validate_counts(self) -> MaskResult:
        if any(count < 0 for count in self.counts) or sum(self.counts) != self.width * self.height:
            raise ValueError("invalid mask run lengths")
        if self.foreground_pixels != sum(self.counts[1::2]):
            raise ValueError("invalid foreground count")
        return self


class MetricDepthResult(StrictModel):
    kind: Literal["metric_depth"]
    width: int = Field(ge=1, le=4_096)
    height: int = Field(ge=1, le=4_096)
    encoding: Literal["float32_le_base64"]
    unit: Literal["metre"]
    data_base64: str = Field(min_length=4, max_length=MAX_BINARY_RESULT_BASE64_LENGTH)
    sha256: str = Field(pattern=r"^[0-9a-f]{64}$")

    @model_validator(mode="after")
    def validate_depth(self) -> MetricDepthResult:
        depth = decode_bound_binary(self.data_base64, self.sha256)
        if len(depth) != self.width * self.height * 4:
            raise ValueError("invalid metric-depth byte length")
        return self


class ReconstructionResult(StrictModel):
    kind: Literal["point_cloud"]
    encoding: Literal["ply_binary_little_endian"]
    data_base64: str = Field(min_length=4, max_length=MAX_BINARY_RESULT_BASE64_LENGTH)
    sha256: str = Field(pattern=r"^[0-9a-f]{64}$")

    @model_validator(mode="after")
    def validate_point_cloud(self) -> ReconstructionResult:
        point_cloud = decode_bound_binary(self.data_base64, self.sha256)
        if not point_cloud.startswith(b"ply\nformat binary_little_endian"):
            raise ValueError("invalid point-cloud encoding")
        return self


InferenceResult = Annotated[
    MaskResult | MetricDepthResult | ReconstructionResult,
    Field(discriminator="kind"),
]


class InferenceJobResponse(StrictModel):
    protocol_version: Literal["1.0.0"] = PROTOCOL_VERSION
    request_id: str
    task: Literal["segment", "metric_depth", "reconstruct"]
    provider: ProviderIdentity
    result: InferenceResult


class HealthResponse(StrictModel):
    status: Literal["ok"] = "ok"


def decode_bound_binary(encoded: str, expected_sha256: str) -> bytes:
    try:
        value = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError) as error:
        raise ValueError("invalid binary result encoding") from error
    if (
        not value
        or len(value) > MAX_BINARY_RESULT_BYTES
        or base64.b64encode(value).decode("ascii") != encoded
        or hashlib.sha256(value).hexdigest() != expected_sha256
    ):
        raise ValueError("invalid binary result binding")
    return value
