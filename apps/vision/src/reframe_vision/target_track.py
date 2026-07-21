from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

MAX_MASK_PIXELS = 16_777_216
MAX_TARGET_ID_LENGTH = 128
MIN_TRACK_CONFIDENCE = 0.5


class TargetTrackError(ValueError):
    pass


class _StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, strict=True)


class TargetSeedBinding(_StrictModel):
    session_id: str = Field(min_length=1, max_length=128)
    frame_id: int = Field(ge=0)
    encoded_width: int = Field(ge=1, le=4_096)
    encoded_height: int = Field(ge=1, le=4_096)
    pixel_x: int = Field(ge=0)
    pixel_y: int = Field(ge=0)

    @model_validator(mode="after")
    def validate_pixel_bounds(self) -> TargetSeedBinding:
        if self.pixel_x >= self.encoded_width or self.pixel_y >= self.encoded_height:
            raise ValueError("target seed pixel is outside the encoded frame")
        return self


class TargetMaskObservation(_StrictModel):
    session_id: str = Field(min_length=1, max_length=128)
    target_id: str = Field(min_length=1, max_length=128)
    frame_id: int = Field(ge=0)
    encoded_width: int = Field(ge=1, le=4_096)
    encoded_height: int = Field(ge=1, le=4_096)
    counts: tuple[int, ...] = Field(min_length=1, max_length=1_000_000)
    confidence: float = Field(ge=0.0, le=1.0, allow_inf_nan=False)
    sha256: str = Field(pattern=r"^[0-9a-f]{64}$")
    provider_id: str = Field(pattern=r"^[a-z][a-z0-9._-]{0,63}$")
    provider_revision: str = Field(pattern=r"^[A-Za-z0-9._-]{1,128}$")

    @model_validator(mode="after")
    def validate_rle_digest(self) -> TargetMaskObservation:
        pixel_count = self.encoded_width * self.encoded_height
        if (
            pixel_count > MAX_MASK_PIXELS
            or any(count < 0 or count > pixel_count for count in self.counts)
            or sum(self.counts) != pixel_count
        ):
            raise ValueError("invalid target mask run lengths")
        digest = hashlib.sha256()
        for index, count in enumerate(self.counts):
            if count:
                digest.update((b"\x01" if index % 2 else b"\x00") * count)
        if digest.hexdigest() != self.sha256:
            raise ValueError("invalid target mask binding")
        return self


class TargetTrack(_StrictModel):
    target_id: str
    seed: TargetSeedBinding
    revision: int = Field(ge=1)
    status: Literal["tracked", "uncertain", "lost"]
    latest_mask: TargetMaskObservation | None


@dataclass(slots=True)
class TargetTrackStore:
    _tracks: dict[str, TargetTrack]

    def __init__(self) -> None:
        self._tracks = {}

    def begin(self, seed: TargetSeedBinding, *, target_id: str) -> TargetTrack:
        if not target_id or len(target_id) > MAX_TARGET_ID_LENGTH:
            raise TargetTrackError("invalid target identity")
        track = TargetTrack(
            target_id=target_id,
            seed=seed,
            revision=1,
            status="tracked",
            latest_mask=None,
        )
        self._tracks[seed.session_id] = track
        return track

    def current(self, session_id: str) -> TargetTrack | None:
        return self._tracks.get(session_id)

    def mark_lost(self, session_id: str, *, target_id: str) -> TargetTrack:
        current = self._tracks.get(session_id)
        if current is None or current.target_id != target_id:
            raise TargetTrackError("unknown primary target")
        track = TargetTrack(
            target_id=current.target_id,
            seed=current.seed,
            revision=current.revision + 1,
            status="lost",
            latest_mask=current.latest_mask,
        )
        self._tracks[session_id] = track
        return track

    def record(self, observation: TargetMaskObservation) -> TargetTrack:
        current = self._tracks.get(observation.session_id)
        if current is None or current.target_id != observation.target_id:
            raise TargetTrackError("unknown primary target")
        if current.status == "lost":
            raise TargetTrackError("target track is lost")
        if current.latest_mask is not None and observation.frame_id <= current.latest_mask.frame_id:
            raise TargetTrackError("target mask frame is not newer")
        track = TargetTrack(
            target_id=current.target_id,
            seed=current.seed,
            revision=current.revision + 1,
            status="tracked" if observation.confidence >= MIN_TRACK_CONFIDENCE else "uncertain",
            latest_mask=observation,
        )
        self._tracks[observation.session_id] = track
        return track
