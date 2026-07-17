"""Pure RR-COORD-1 coordinate, projection, orientation, and float helpers."""

from __future__ import annotations

import json
import math
import struct
from typing import Any, Sequence

from .canonical_json import artifact
from .loader import LoadedFixture, VerificationFailure, parse_json_bytes


FLOAT32_MAX = 3.4028234663852886e38
SCALAR_ABSOLUTE_TOLERANCE = 1e-5
SCALAR_RELATIVE_TOLERANCE = 1e-6
RIGID_TOLERANCE = 1e-4
HOMOGENEOUS_ROW_TOLERANCE = 1e-6


def _number(value: Any) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise VerificationFailure("coordinate_invalid", "coordinate scalar is not numeric")
    converted = float(value)
    if not math.isfinite(converted):
        raise VerificationFailure("numeric_out_of_range", "coordinate scalar is non-finite")
    if abs(converted) > FLOAT32_MAX:
        raise VerificationFailure("numeric_out_of_range", "coordinate scalar exceeds binary32")
    try:
        quantized = struct.unpack(">f", struct.pack(">f", converted))[0]
    except OverflowError as error:
        raise VerificationFailure("numeric_out_of_range", "coordinate scalar exceeds binary32") from error
    if not math.isfinite(quantized):
        raise VerificationFailure("numeric_out_of_range", "coordinate scalar overflows binary32")
    return quantized


def _vector(values: Any, length: int) -> list[float]:
    if not isinstance(values, list) or len(values) != length:
        raise VerificationFailure("coordinate_invalid", "coordinate vector has wrong shape")
    return [_number(value) for value in values]


def _matrix(values: Any, dimension: int) -> list[list[float]]:
    flat = _vector(values, dimension * dimension)
    return [flat[row * dimension : (row + 1) * dimension] for row in range(dimension)]


def multiply_matrix_vector(matrix: Sequence[Sequence[float]], vector: Sequence[float]) -> list[float]:
    if not matrix or any(len(row) != len(vector) for row in matrix):
        raise VerificationFailure("coordinate_invalid", "matrix/vector shapes disagree")
    return [sum(coefficient * value for coefficient, value in zip(row, vector)) for row in matrix]


def multiply_matrices(left: Sequence[Sequence[float]], right: Sequence[Sequence[float]]) -> list[list[float]]:
    if not left or not right or any(len(row) != len(right) for row in left):
        raise VerificationFailure("coordinate_invalid", "matrix shapes disagree")
    columns = list(zip(*right))
    return [
        [sum(a * b for a, b in zip(row, column)) for column in columns]
        for row in left
    ]


def _determinant3(matrix: Sequence[Sequence[float]]) -> float:
    return (
        matrix[0][0] * (matrix[1][1] * matrix[2][2] - matrix[1][2] * matrix[2][1])
        - matrix[0][1] * (matrix[1][0] * matrix[2][2] - matrix[1][2] * matrix[2][0])
        + matrix[0][2] * (matrix[1][0] * matrix[2][1] - matrix[1][1] * matrix[2][0])
    )


def validate_rigid_transform(values: Any) -> list[list[float]]:
    matrix = _matrix(values, 4)
    if any(abs(matrix[3][index] - expected) > HOMOGENEOUS_ROW_TOLERANCE for index, expected in enumerate((0, 0, 0, 1))):
        raise VerificationFailure("coordinate_invalid", "homogeneous row is invalid")
    rotation = [row[:3] for row in matrix[:3]]
    orthogonality_squared = 0.0
    for row in range(3):
        for column in range(3):
            dot = sum(rotation[index][row] * rotation[index][column] for index in range(3))
            difference = dot - (1.0 if row == column else 0.0)
            orthogonality_squared += difference * difference
    if math.sqrt(orthogonality_squared) > RIGID_TOLERANCE:
        raise VerificationFailure("coordinate_invalid", "rotation is not orthonormal")
    if abs(_determinant3(rotation) - 1.0) > RIGID_TOLERANCE:
        raise VerificationFailure("coordinate_invalid", "rotation must be proper, not reflected")
    return matrix


def rr_float_equal(left: Any, right: Any) -> bool:
    a = _number(left)
    b = _number(right)
    return abs(a - b) <= SCALAR_ABSOLUTE_TOLERANCE + SCALAR_RELATIVE_TOLERANCE * max(abs(a), abs(b))


def _validate_rigid_matrix3(values: Any) -> list[list[float]]:
    matrix = _matrix(values, 3)
    orthogonality_squared = 0.0
    for row in range(3):
        for column in range(3):
            dot = sum(matrix[index][row] * matrix[index][column] for index in range(3))
            difference = dot - (1.0 if row == column else 0.0)
            orthogonality_squared += difference * difference
    if (
        math.sqrt(orthogonality_squared) > RIGID_TOLERANCE
        or abs(_determinant3(matrix) - 1.0) > RIGID_TOLERANCE
    ):
        raise VerificationFailure("coordinate_invalid", "camera conversion is not a proper rotation")
    return matrix


def apply_world_correction(document: dict[str, Any]) -> dict[str, Any]:
    source = document.get("from_world_frame_version")
    target = document.get("to_world_frame_version")
    if (
        isinstance(source, bool)
        or isinstance(target, bool)
        or not isinstance(source, int)
        or not isinstance(target, int)
        or source < 1
        or target <= source
    ):
        raise VerificationFailure("coordinate_invalid", "correction must move strictly forward")
    matrix = validate_rigid_transform(document.get("to_from_from_transform"))
    point = _vector(document.get("point_from"), 4)
    return {"point_to": multiply_matrix_vector(matrix, point)}


def transform_intrinsics(document: dict[str, Any]) -> dict[str, Any]:
    intrinsics = document.get("sensor_intrinsics")
    if not isinstance(intrinsics, dict):
        raise VerificationFailure("coordinate_invalid", "sensor intrinsics are missing")
    fx, fy, cx, cy = (_number(intrinsics.get(key)) for key in ("fx", "fy", "cx", "cy"))
    if fx <= 0 or fy <= 0:
        raise VerificationFailure("coordinate_invalid", "focal lengths must be positive")
    encoded_from_sensor = _matrix(document.get("encoded_from_sensor"), 3)
    if any(abs(encoded_from_sensor[2][index] - expected) > HOMOGENEOUS_ROW_TOLERANCE for index, expected in enumerate((0, 0, 1))):
        raise VerificationFailure("coordinate_invalid", "pixel transform is not affine")
    sensor = [[fx, 0.0, cx], [0.0, fy, cy], [0.0, 0.0, 1.0]]
    encoded = multiply_matrices(encoded_from_sensor, sensor)
    encoded_fx = math.hypot(encoded[0][0], encoded[0][1])
    encoded_fy = math.hypot(encoded[1][0], encoded[1][1])
    if encoded_fx <= 0 or encoded_fy <= 0:
        raise VerificationFailure("coordinate_invalid", "encoded focal lengths are degenerate")
    encoded_size = document.get("encoded_size")
    if (
        not isinstance(encoded_size, list)
        or len(encoded_size) != 2
        or any(isinstance(value, bool) or not isinstance(value, int) or value <= 0 for value in encoded_size)
    ):
        raise VerificationFailure("coordinate_invalid", "encoded size is invalid")
    orientation = document.get("orientation")
    if orientation != "up":
        raise VerificationFailure("coordinate_invalid", "encoded orientation must be physically upright")
    return {
        "encoded_intrinsics": {
            "fx": encoded_fx,
            "fy": encoded_fy,
            "cx": encoded[0][2],
            "cy": encoded[1][2],
        },
        "encoded_size": encoded_size,
        "orientation": orientation,
    }


def validate_rr_float(value: Any) -> dict[str, Any]:
    number = _number(value)
    if abs(number) > FLOAT32_MAX:
        raise VerificationFailure("numeric_out_of_range", "value exceeds finite binary32")
    try:
        encoded = struct.pack(">f", number)
    except OverflowError as error:
        raise VerificationFailure("numeric_out_of_range", "value exceeds finite binary32") from error
    if not math.isfinite(struct.unpack(">f", encoded)[0]):
        raise VerificationFailure("numeric_out_of_range", "binary32 result is non-finite")
    return {"binary32_hex": encoded.hex()}


def project(document: dict[str, Any]) -> dict[str, Any]:
    intrinsics = document.get("intrinsics")
    if not isinstance(intrinsics, dict):
        raise VerificationFailure("coordinate_invalid", "projection intrinsics are missing")
    fx, fy, cx, cy = (_number(intrinsics.get(key)) for key in ("fx", "fy", "cx", "cy"))
    if fx <= 0 or fy <= 0:
        raise VerificationFailure("coordinate_invalid", "focal lengths must be positive")
    point = _vector(document.get("camera_point"), 3)
    if document.get("pixel_center") != "half_integer":
        raise VerificationFailure("coordinate_invalid", "pixel center convention is invalid")
    if point[2] == 0:
        raise VerificationFailure("coordinate_invalid", "point lies on the camera plane")
    return {
        "encoded_pixel": [fx * point[0] / point[2] + cx, fy * point[1] / point[2] + cy],
        "visible": point[2] < 0,
    }


def arkit_to_opencv_camera(document: dict[str, Any]) -> dict[str, Any]:
    point = _vector(document.get("camera_point"), 3)
    conversion = _validate_rigid_matrix3(document.get("conversion"))
    return {"opencv_camera_point": multiply_matrix_vector(conversion, point)}


def evaluate_coordinate(document: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    operation = document.get("operation")
    if operation == "apply_world_correction":
        return "matrix", apply_world_correction(document)
    if operation == "transform_intrinsics":
        return "matrix", transform_intrinsics(document)
    if operation == "validate_rr_float":
        return "runner_consensus", validate_rr_float(document.get("value"))
    if operation == "project":
        return "projected_pixels", project(document)
    if operation == "arkit_to_opencv_camera":
        return "matrix", arkit_to_opencv_camera(document)
    if operation == "validate_rigid_transform":
        validate_rigid_transform(document.get("values"))
        return "matrix", {"valid": True}
    raise VerificationFailure("coordinate_invalid", "unknown coordinate operation")


def _normalize_integral_floats(value: Any) -> Any:
    if isinstance(value, float) and value.is_integer():
        return int(value)
    if isinstance(value, dict):
        return {key: _normalize_integral_floats(child) for key, child in value.items()}
    if isinstance(value, list):
        return [_normalize_integral_floats(child) for child in value]
    return value


def execute_coordinate_case(fixture: LoadedFixture, case: dict[str, Any]) -> list[dict[str, Any]]:
    document = parse_json_bytes(
        fixture.read_fixture_file(case["input"]["relative_path"]),
        max_depth=fixture.max_document_depth,
    )
    if not isinstance(document, dict):
        raise VerificationFailure("coordinate_invalid", "coordinate vector must be an object")
    kind, result = evaluate_coordinate(document)
    raw = (
        json.dumps(
            _normalize_integral_floats(result),
            ensure_ascii=False,
            allow_nan=False,
            separators=(",", ":"),
        ).encode("utf-8")
        + b"\n"
    )
    return [artifact(kind, raw)]
