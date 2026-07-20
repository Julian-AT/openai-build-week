from __future__ import annotations

import hashlib
import json
import math
import struct
from dataclasses import dataclass
from typing import Final, cast

FRAME_PACKET_MAGIC: Final[bytes] = b"RFFP"
FRAME_PACKET_VERSION: Final[int] = 1
FRAME_PACKET_HEADER_BYTES: Final[int] = 24
MATRIX_ENTRY_COUNT: Final[int] = 16
MIN_JPEG_BYTES: Final[int] = 4
C_ARKIT_FROM_OPENCV_ROW_MAJOR: Final[tuple[float, ...]] = (
    1,
    0,
    0,
    0,
    0,
    -1,
    0,
    0,
    0,
    0,
    -1,
    0,
    0,
    0,
    0,
    1,
)


@dataclass(frozen=True)
class FramePacket:
    protocol_version: int
    flags: int
    frame_id: int
    metadata: dict[str, object]
    image: bytes


def canonical_json(value: object) -> str:
    try:
        return json.dumps(
            value,
            allow_nan=False,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        )
    except (TypeError, ValueError) as error:
        raise ValueError("invalid_canonical_json") from error


def canonical_json_sha256(value: object) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def world_from_camera_opencv(world_from_camera_arkit: tuple[float, ...]) -> tuple[float, ...]:
    if len(world_from_camera_arkit) != MATRIX_ENTRY_COUNT or not all(
        math.isfinite(value) for value in world_from_camera_arkit
    ):
        raise ValueError("invalid_row_major_matrix")
    return tuple(
        sum(
            world_from_camera_arkit[row * 4 + index]
            * C_ARKIT_FROM_OPENCV_ROW_MAJOR[index * 4 + column]
            for index in range(4)
        )
        for row in range(4)
        for column in range(4)
    )


def project_encoded_pixel_to_opencv_ray(
    intrinsics: tuple[float, float, float, float], pixel: tuple[float, float]
) -> tuple[float, float, float]:
    fx, fy, cx, cy = intrinsics
    x, y = pixel
    if not all(math.isfinite(value) for value in (fx, fy, cx, cy, x, y)) or fx <= 0 or fy <= 0:
        raise ValueError("invalid_encoded_intrinsics")
    ray_x = (x - cx) / fx
    ray_y = (y - cy) / fy
    norm = math.sqrt(ray_x * ray_x + ray_y * ray_y + 1)
    return (ray_x / norm, ray_y / norm, 1 / norm)


def parse_frame_packet(value: bytes) -> FramePacket:
    if len(value) < FRAME_PACKET_HEADER_BYTES:
        raise ValueError("invalid_frame_packet_length")
    unpacked = cast(
        "tuple[bytes, int, int, int, int, int]",
        struct.unpack("<4sHHIIQ", value[:FRAME_PACKET_HEADER_BYTES]),
    )
    magic, protocol_version, flags, metadata_length, image_length, frame_id = unpacked
    if magic != FRAME_PACKET_MAGIC:
        raise ValueError("invalid_frame_packet_magic")
    if protocol_version != FRAME_PACKET_VERSION:
        raise ValueError("unsupported_frame_packet_version")
    if len(value) != FRAME_PACKET_HEADER_BYTES + metadata_length + image_length:
        raise ValueError("invalid_frame_packet_length")
    try:
        decoded_metadata = cast(
            "object",
            json.loads(
                value[
                    FRAME_PACKET_HEADER_BYTES : FRAME_PACKET_HEADER_BYTES + metadata_length
                ].decode("utf-8", errors="strict")
            ),
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError("invalid_frame_packet_metadata") from error
    if not isinstance(decoded_metadata, dict):
        raise TypeError("invalid_frame_packet_metadata")
    raw_metadata = cast("dict[object, object]", decoded_metadata)
    if not all(isinstance(key, str) for key in raw_metadata):
        raise TypeError("invalid_frame_packet_metadata")
    metadata_value = {cast("str", key): nested for key, nested in raw_metadata.items()}
    image = value[FRAME_PACKET_HEADER_BYTES + metadata_length :]
    validate_frame_metadata(metadata_value, image, frame_id)
    return FramePacket(protocol_version, flags, frame_id, metadata_value, image)


def validate_frame_metadata(metadata: dict[str, object], image: bytes, frame_id: int) -> None:
    required = {
        "protocol_version",
        "session_id",
        "submap_id",
        "frame_id",
        "timestamp_ns",
        "clock_domain",
        "image",
        "intrinsics_encoded",
        "world_from_camera_arkit",
        "tracking",
        "capture_quality",
    }
    if set(metadata) != required:
        raise ValueError("invalid_frame_packet_metadata")
    image_metadata = _strict_object(
        metadata["image"],
        {"codec", "width", "height", "orientation", "color_space", "payload_bytes"},
    )
    tracking = _strict_object(metadata["tracking"], {"state", "reason", "world_frame_version"})
    quality = _strict_object(
        metadata["capture_quality"],
        {
            "blur_score",
            "angular_velocity_rad_s",
            "translation_since_last_m",
            "rotation_since_last_deg",
            "exposure_s",
            "iso",
        },
    )
    blur_score = _finite_number(quality["blur_score"])
    angular_velocity = _finite_number(quality["angular_velocity_rad_s"])
    translation = _finite_number(quality["translation_since_last_m"])
    rotation = _finite_number(quality["rotation_since_last_deg"])
    exposure = _finite_number(quality["exposure_s"])
    if (
        metadata["protocol_version"] != FRAME_PACKET_VERSION
        or metadata["frame_id"] != frame_id
        or not isinstance(metadata["session_id"], str)
        or not metadata["session_id"].startswith("room_")
        or not _bounded_integer(metadata["submap_id"], 0, 2**31 - 1)
        or not _bounded_integer(metadata["frame_id"], 0, 2**53 - 1)
        or not _bounded_integer(metadata["timestamp_ns"], 0, 2**53 - 1)
        or metadata["clock_domain"] != "ios_monotonic_uptime"
        or image_metadata["codec"] != "jpeg"
        or not _bounded_integer(image_metadata["width"], 1, 4096)
        or not _bounded_integer(image_metadata["height"], 1, 4096)
        or image_metadata["orientation"] != "up"
        or image_metadata["color_space"] != "sRGB"
        or image_metadata["payload_bytes"] != len(image)
        or len(image) < MIN_JPEG_BYTES
        or not image.startswith(b"\xff\xd8")
        or not image.endswith(b"\xff\xd9")
        or not _finite_numeric_array(metadata["intrinsics_encoded"], 9)
        or not _finite_numeric_array(metadata["world_from_camera_arkit"], 16)
        or tracking["state"] not in {"normal", "limited", "not_available"}
        or not isinstance(tracking["reason"], str)
        or not _bounded_integer(tracking["world_frame_version"], 0, 2**31 - 1)
        or not all(
            isinstance(component, (float, int)) and math.isfinite(component)
            for component in quality.values()
        )
        or blur_score < 0
        or angular_velocity < 0
        or translation < 0
        or rotation < 0
        or exposure <= 0
        or not _bounded_integer(quality["iso"], 1, 102400)
    ):
        raise ValueError("invalid_frame_packet")


def _bounded_integer(value: object, minimum: int, maximum: int) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and minimum <= value <= maximum


def _finite_numeric_array(value: object, length: int) -> bool:
    if not isinstance(value, list):
        return False
    values = cast("list[object]", value)
    return len(values) == length and all(
        isinstance(component, (float, int)) and math.isfinite(component) for component in values
    )


def _strict_object(value: object, expected_keys: set[str]) -> dict[str, object]:
    if not isinstance(value, dict):
        raise TypeError("invalid_frame_packet")
    raw_value = cast("dict[object, object]", value)
    if not all(isinstance(key, str) for key in raw_value):
        raise ValueError("invalid_frame_packet")
    result = {cast("str", key): nested for key, nested in raw_value.items()}
    if set(result) != expected_keys:
        raise ValueError("invalid_frame_packet")
    return result


def _finite_number(value: object) -> float:
    if not isinstance(value, (float, int)) or isinstance(value, bool) or not math.isfinite(value):
        raise ValueError("invalid_frame_packet")
    return float(value)
