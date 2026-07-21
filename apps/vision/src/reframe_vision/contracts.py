from __future__ import annotations

import base64
import binascii
import hashlib
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

PROTOCOL_VERSION = "1.0.0"
MAX_IMAGE_BYTES = 1_750_000
MAX_IMAGE_PIXELS = 16_777_216
MAX_BINARY_RESULT_BYTES = 8_000_000
MAX_BINARY_RESULT_BASE64_LENGTH = 10_666_668
MIN_JPEG_BYTES = 4
FRAME_ID_PATTERN = r"^frame_[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
INFERENCE_ID_PATTERN = (
    r"^inference_[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
)
FrameID = Annotated[str, Field(pattern=FRAME_ID_PATTERN)]


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, strict=True)


class ImageInput(StrictModel):
    frame_id: FrameID
    media_type: Literal["image/jpeg"]
    data_base64: str = Field(min_length=4, max_length=2_333_336)
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


class BoxPrompt(StrictModel):
    kind: Literal["box"]
    x: int = Field(ge=0)
    y: int = Field(ge=0)
    width: int = Field(gt=0)
    height: int = Field(gt=0)


SegmentationPrompt = Annotated[
    PointPrompt | BoxPrompt,
    Field(discriminator="kind"),
]


class SegmentationJob(StrictModel):
    protocol_version: Literal["1.0.0"]
    request_id: str = Field(pattern=INFERENCE_ID_PATTERN)
    task: Literal["segment"]
    image: ImageInput
    prompt: SegmentationPrompt
    session_id: str | None = Field(default=None, min_length=1, max_length=128)
    target_id: str | None = Field(default=None, min_length=1, max_length=128)
    frame_index: int | None = Field(default=None, ge=0)

    @model_validator(mode="after")
    def validate_prompt_bounds(self) -> SegmentationJob:
        if (self.session_id is None) != (self.target_id is None):
            raise ValueError("session and target identity must be supplied together")
        if self.session_id is None and self.frame_index is not None:
            raise ValueError("frame index requires session identity")
        if isinstance(self.prompt, PointPrompt):
            if self.prompt.x >= self.image.width or self.prompt.y >= self.image.height:
                raise ValueError("prompt is outside image")
        elif (
            self.prompt.x + self.prompt.width > self.image.width
            or self.prompt.y + self.prompt.height > self.image.height
        ):
            raise ValueError("prompt box is outside image")
        return self


class EncodedImageIntrinsics(StrictModel):
    fx: float = Field(gt=0, allow_inf_nan=False)
    fy: float = Field(gt=0, allow_inf_nan=False)
    cx: float = Field(allow_inf_nan=False)
    cy: float = Field(allow_inf_nan=False)
    width: int = Field(ge=1, le=4_096)
    height: int = Field(ge=1, le=4_096)
    units: Literal["encoded_pixels"]


class MetricDepthJob(StrictModel):
    protocol_version: Literal["1.0.0"]
    request_id: str = Field(pattern=INFERENCE_ID_PATTERN)
    task: Literal["metric_depth"]
    image: ImageInput
    intrinsics_encoded_pixels: EncodedImageIntrinsics

    @model_validator(mode="after")
    def validate_intrinsics_dimensions(self) -> MetricDepthJob:
        if (
            self.intrinsics_encoded_pixels.width != self.image.width
            or self.intrinsics_encoded_pixels.height != self.image.height
        ):
            raise ValueError("intrinsics dimensions do not match image")
        return self


class ReconstructionJob(StrictModel):
    protocol_version: Literal["1.0.0"]
    request_id: str = Field(pattern=INFERENCE_ID_PATTERN)
    task: Literal["reconstruct"]
    archive_sha256: str = Field(pattern=r"^[0-9a-f]{64}$")
    frame_ids: tuple[FrameID, ...] = Field(min_length=2, max_length=64)

    @model_validator(mode="after")
    def validate_frame_ids(self) -> ReconstructionJob:
        if len(set(self.frame_ids)) != len(self.frame_ids):
            raise ValueError("frame IDs must be unique")
        return self


InferenceJob = Annotated[
    SegmentationJob | MetricDepthJob | ReconstructionJob,
    Field(discriminator="task"),
]


class ProviderIdentity(StrictModel):
    provider_id: str = Field(pattern=r"^[a-z][a-z0-9_-]{0,63}$")
    provider_revision: str = Field(pattern=r"^[A-Za-z0-9._-]{1,128}$")
    evidence_class: Literal["unmeasured", "measured"]


class TorchReadiness(StrictModel):
    installed: bool
    version: str | None = Field(default=None, min_length=1, max_length=64)
    mps_available: bool

    @model_validator(mode="after")
    def validate_runtime_state(self) -> TorchReadiness:
        if self.installed != (self.version is not None) or (
            self.mps_available and not self.installed
        ):
            raise ValueError("invalid torch readiness")
        return self


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
        pixel_count = self.width * self.height
        if (
            pixel_count > MAX_IMAGE_PIXELS
            or any(count < 0 or count > MAX_IMAGE_PIXELS for count in self.counts)
            or sum(self.counts) != pixel_count
        ):
            raise ValueError("invalid mask run lengths")
        if self.foreground_pixels != sum(self.counts[1::2]):
            raise ValueError("invalid foreground count")
        digest = hashlib.sha256()
        for index, count in enumerate(self.counts):
            byte = b"\x01" if index % 2 else b"\x00"
            remaining = count
            while remaining:
                chunk_length = min(remaining, 65_536)
                digest.update(byte * chunk_length)
                remaining -= chunk_length
        if digest.hexdigest() != self.sha256:
            raise ValueError("invalid mask binding")
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
    request_id: str = Field(pattern=INFERENCE_ID_PATTERN)
    task: Literal["segment", "metric_depth", "reconstruct"]
    provider: ProviderIdentity
    result: InferenceResult

    @model_validator(mode="after")
    def validate_result_kind(self) -> InferenceJobResponse:
        expected_kind = {
            "segment": "mask",
            "metric_depth": "metric_depth",
            "reconstruct": "point_cloud",
        }[self.task]
        if self.result.kind != expected_kind:
            raise ValueError("result kind does not match task")
        return self


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
