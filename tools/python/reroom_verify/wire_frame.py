"""Strict RRFP-WIRE-1 encoder and decoder."""

from __future__ import annotations

import hashlib
import struct
from typing import Any

from .canonical_json import artifact, canonical_bytes
from .loader import LoadedFixture, VerificationFailure, parse_json_bytes
from .schema_validator import _validate_schema


MAGIC = b"RRFP"
VERSION_MAJOR = 1
VERSION_MINOR = 0
FIXED_HEADER_BYTES = 24
MAX_JSON_HEADER_BYTES = 65_536
MAX_PAYLOAD_BYTES = 16_777_216
HEADER_STRUCT = struct.Struct(">4sBBHIIQ")


def encode_frame(header: dict[str, Any], payload: bytes) -> bytes:
    header_bytes = canonical_bytes(header)
    if len(header_bytes) > MAX_JSON_HEADER_BYTES or len(payload) > MAX_PAYLOAD_BYTES:
        raise VerificationFailure("wire_length", "wire field exceeds its bound")
    declared_length = header.get("image", {}).get("payload", {}).get("byte_length")
    if declared_length != len(payload):
        raise VerificationFailure("wire_length", "payload length duplicate mismatch")
    if header.get("payload_sha256") != hashlib.sha256(payload).hexdigest():
        raise VerificationFailure("digest_mismatch", "payload digest mismatch")
    sequence = header.get("capture_sequence")
    if not isinstance(sequence, int) or isinstance(sequence, bool) or not 0 <= sequence < 2**64:
        raise VerificationFailure("wire_sequence", "capture sequence is outside uint64")
    fixed = HEADER_STRUCT.pack(
        MAGIC,
        VERSION_MAJOR,
        VERSION_MINOR,
        0,
        len(header_bytes),
        len(payload),
        sequence,
    )
    return fixed + header_bytes + payload


def decode_frame(frame: bytes, *, fixture: LoadedFixture | None = None) -> tuple[dict[str, Any], bytes]:
    if len(frame) < FIXED_HEADER_BYTES:
        raise VerificationFailure("wire_truncated", "fixed header is truncated")
    magic, major, minor, flags, header_length, payload_length, sequence = HEADER_STRUCT.unpack_from(frame)
    if magic != MAGIC:
        raise VerificationFailure("wire_magic", "wire magic mismatch")
    if (major, minor) != (VERSION_MAJOR, VERSION_MINOR):
        raise VerificationFailure("wire_version", "wire version mismatch")
    if flags != 0:
        raise VerificationFailure("wire_flags", "reserved flags must be zero")
    if not 0 < header_length <= MAX_JSON_HEADER_BYTES:
        raise VerificationFailure("wire_length", "JSON header length is invalid")
    if payload_length > MAX_PAYLOAD_BYTES:
        raise VerificationFailure("wire_length", "payload length is invalid")
    expected_length = FIXED_HEADER_BYTES + header_length + payload_length
    if len(frame) < expected_length:
        raise VerificationFailure("wire_truncated", "wire frame is truncated")

    header_bytes = frame[FIXED_HEADER_BYTES : FIXED_HEADER_BYTES + header_length]
    try:
        header = parse_json_bytes(header_bytes)
    except VerificationFailure as error:
        raise VerificationFailure("wire_length", "declared JSON header boundary is invalid") from error
    if not isinstance(header, dict) or canonical_bytes(header) != header_bytes:
        raise VerificationFailure("schema_validation", "wire JSON header is not canonical")
    if fixture is not None:
        _validate_schema(fixture, "docs/contracts/frame-packet.schema.json", header)
    declared_payload_length = header.get("image", {}).get("payload", {}).get("byte_length")
    if declared_payload_length != payload_length:
        raise VerificationFailure("wire_length", "payload length duplicate mismatch")
    if header.get("capture_sequence") != sequence:
        raise VerificationFailure("wire_sequence", "capture sequence duplicate mismatch")
    payload_start = FIXED_HEADER_BYTES + header_length
    payload = frame[payload_start:expected_length]
    if header.get("payload_sha256") != hashlib.sha256(payload).hexdigest():
        raise VerificationFailure("digest_mismatch", "payload digest mismatch")
    if len(frame) > expected_length:
        raise VerificationFailure("wire_trailing_bytes", "wire frame has trailing bytes")
    return header, payload


def _apply_wire_mutations(frame: bytes, mutations: list[dict[str, Any]]) -> bytes:
    value = bytearray(frame)
    for mutation in mutations:
        operation = mutation["op"]
        if operation == "replace_byte":
            offset = mutation["offset"]
            replacement = bytes.fromhex(mutation["value_hex"])
            if len(replacement) != 1 or not 0 <= offset < len(value):
                raise VerificationFailure("semantic_invariant", "invalid byte mutation")
            value[offset] = replacement[0]
        elif operation == "replace_u32be":
            struct.pack_into(">I", value, mutation["offset"], mutation["value"])
        elif operation == "replace_u64be":
            struct.pack_into(">Q", value, mutation["offset"], mutation["value"])
        elif operation == "append_hex":
            value.extend(bytes.fromhex(mutation["value_hex"]))
        elif operation == "truncate":
            value = value[: mutation["byte_length"]]
        else:
            raise VerificationFailure("semantic_invariant", "unknown wire mutation")
    return bytes(value)


def _load_base_hex(fixture: LoadedFixture, relative_path: str) -> bytes:
    try:
        text = fixture.read_fixture_file(relative_path).decode("ascii").strip()
        return bytes.fromhex(text)
    except (UnicodeDecodeError, ValueError) as error:
        raise VerificationFailure("json_parse", "wire oracle is not hexadecimal") from error


def execute_wire_case(fixture: LoadedFixture, case: dict[str, Any]) -> list[dict[str, Any]]:
    spec = parse_json_bytes(
        fixture.read_fixture_file(case["input"]["relative_path"]),
        max_depth=fixture.max_document_depth,
    )
    if case["case_kind"] == "wire_bytes":
        header_path = (fixture.fixture_root / spec["header_source"]).resolve(strict=True)
        if not header_path.is_relative_to(fixture.repo_root):
            raise VerificationFailure("invalid_path", "wire header source escapes repository")
        header = parse_json_bytes(header_path.read_bytes(), max_depth=fixture.max_document_depth)
        try:
            payload = bytes.fromhex(spec["payload_hex"])
        except ValueError as error:
            raise VerificationFailure("json_parse", "wire payload is not hexadecimal") from error
        frame = encode_frame(header, payload)
        decode_frame(frame, fixture=fixture)
        return [artifact("wire_bytes", (frame.hex() + "\n").encode("ascii"))]
    if case["case_kind"] == "wire_mutation":
        frame = _load_base_hex(fixture, spec["base"])
        mutated = _apply_wire_mutations(frame, spec["mutations"])
        decode_frame(mutated, fixture=fixture)
        return []
    raise VerificationFailure("semantic_invariant", "unknown wire case kind")
