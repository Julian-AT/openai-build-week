from __future__ import annotations

import json
import struct

import pytest

from reframe_vision.wire import (
    FRAME_PACKET_MAGIC,
    FRAME_PACKET_VERSION,
    canonical_json,
    canonical_json_sha256,
    parse_frame_packet,
    project_encoded_pixel_to_opencv_ray,
    world_from_camera_opencv,
)


def metadata() -> dict[str, object]:
    return {
        "protocol_version": 1,
        "session_id": "room_2026_07_13_01",
        "submap_id": 0,
        "frame_id": 842,
        "timestamp_ns": 1_783_918_472_391_823,
        "clock_domain": "ios_monotonic_uptime",
        "image": {
            "codec": "jpeg",
            "width": 640,
            "height": 480,
            "orientation": "up",
            "color_space": "sRGB",
            "payload_bytes": 4,
        },
        "intrinsics_encoded": [514.4, 0, 319.8, 0, 513.9, 239.6, 0, 0, 1],
        "world_from_camera_arkit": [1, 0, 0, 1.42, 0, 1, 0, 1.53, 0, 0, 1, -2.18, 0, 0, 0, 1],
        "tracking": {"state": "normal", "reason": "none", "world_frame_version": 1},
        "capture_quality": {
            "blur_score": 0.08,
            "angular_velocity_rad_s": 0.19,
            "translation_since_last_m": 0.034,
            "rotation_since_last_deg": 3.2,
            "exposure_s": 0.0083,
            "iso": 142,
        },
    }


def packet_bytes() -> bytes:
    encoded_metadata = json.dumps(metadata(), separators=(",", ":")).encode("utf-8")
    image = b"\xff\xd8\xff\xd9"
    return (
        struct.pack(
            "<4sHHIIQ",
            FRAME_PACKET_MAGIC,
            FRAME_PACKET_VERSION,
            0b1001,
            len(encoded_metadata),
            len(image),
            842,
        )
        + encoded_metadata
        + image
    )


def test_python_adapter_matches_the_protocol_frame_packet_and_coordinate_contract() -> None:
    packet = parse_frame_packet(packet_bytes())

    assert packet.flags == 0b1001
    assert packet.metadata == metadata()
    assert world_from_camera_opencv((1, 0, 0, 1.42, 0, 1, 0, 1.53, 0, 0, 1, -2.18, 0, 0, 0, 1)) == (
        1,
        0,
        0,
        1.42,
        0,
        -1,
        0,
        1.53,
        0,
        0,
        -1,
        -2.18,
        0,
        0,
        0,
        1,
    )
    assert project_encoded_pixel_to_opencv_ray((500, 500, 320, 240), (320, 240)) == (0, 0, 1)


def test_python_adapter_canonicalization_and_invalid_packet_fail_closed() -> None:
    assert canonical_json({"z": 1, "a": [True, "x"]}) == '{"a":[true,"x"],"z":1}'
    assert canonical_json_sha256({"z": 1, "a": [True, "x"]}) == canonical_json_sha256(
        {"a": [True, "x"], "z": 1}
    )
    with pytest.raises(ValueError, match="invalid_frame_packet_length"):
        parse_frame_packet(packet_bytes()[:-1])
