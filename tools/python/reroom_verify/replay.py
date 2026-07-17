"""Independent, bounded ReplayReportV1 runner for the frozen capture corpus."""

from __future__ import annotations

import hashlib
import json
import math
import os
import platform
import re
import shutil
import struct
import sys
import uuid
from pathlib import Path
from typing import Any, NoReturn


EXACT_PYTHON_VERSION = "3.13.12"
PINNED_FIXTURE_MANIFEST_SHA256 = (
    "3b4519d2730e158df73e938f7b841664c6ce5f7d65ed2650c90ca8e89c7a7610"
)
PINNED_REPORT_SCHEMA_SHA256 = (
    "821784ce1a3e4f45c2fe4db70f8f16643284f2e3e9f6effe85a7aee3e17bb9a9"
)
MAXIMUM_FILE_BYTES = 33_554_432
MAXIMUM_MEMBERS = 2_048
MAXIMUM_DEPTH = 64
MAXIMUM_PATH_BYTES = 240
REVISION = re.compile(r"^git:[0-9a-f]{40}$")
DIGEST = re.compile(r"^[0-9a-f]{64}$")
SESSION_ID = re.compile(
    r"^session_[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
)
ARCHIVE_PATH = re.compile(
    r"^(?!/)(?![A-Za-z]:)(?!.*(?:^|/)\.{1,2}(?:/|$))(?!.*\\)"
    r"[A-Za-z0-9_-][A-Za-z0-9._-]*(?:/[A-Za-z0-9_-][A-Za-z0-9._-]*)*$"
)
ARCHIVE_NAMES = (
    "finalized-empty.rrcap",
    "finalized-one-frame.rrcap",
    "recovered-prefix.rrcap",
)
PROBE_IDS = (
    "fr-b0.adjacency",
    "fr-b0.concurrency",
    "fr-b0.empty",
    "fr-b0.ordering",
    "fr-capture.adjacency",
    "fr-capture.boundary",
    "fr-capture.concurrency",
    "fr-capture.empty",
    "fr-capture.ordering",
    "fr-capture.precision",
    "nfr-replay.assumption",
    "sec-consent.concurrent-session-separation",
)
FIXTURE_KEYS = {
    "archives", "consent_denied_case", "description", "directories", "edge_probes",
    "files", "fixture_id", "fixture_revision", "privacy", "report_schema", "schema_version",
}
ARCHIVE_MANIFEST_KEYS = {
    "accepted_frame_order", "capture_kind", "capture_settings", "coordinate_convention",
    "events", "files", "finalization", "format_version", "journal", "keyframes", "privacy",
    "replay", "session_id", "source",
}
SUPPORTED_CODECS = {
    "json_jcs_1", "jsonl_utf8_1", "jpeg", "png", "hevc_intra", "hevc_video",
    "h264_video", "glb2", "usdz", "ply_binary_little_endian_1_0", "npy_1_0", "ktx2_2_0",
}


class ReplayFailure(ValueError):
    """Fail-closed runner rejection with no private path detail."""


def _require(condition: Any, message: str) -> None:
    if not condition:
        raise ReplayFailure(message)


def _object(value: Any, message: str = "expected a JSON object") -> dict[str, Any]:
    _require(isinstance(value, dict), message)
    return value


def _array(value: Any, message: str = "expected a JSON array") -> list[Any]:
    _require(isinstance(value, list), message)
    return value


def _integer(value: Any, message: str = "expected an exact nonnegative integer") -> int:
    _require(isinstance(value, int) and not isinstance(value, bool) and value >= 0, message)
    return value


def _exact_keys(value: dict[str, Any], expected: set[str], message: str) -> None:
    _require(set(value) == expected, message)


def _subset_keys(
    value: dict[str, Any], required: set[str], allowed: set[str], message: str
) -> None:
    actual = set(value)
    _require(required <= actual <= allowed, message)


def _lexical_unique(values: list[str], message: str) -> None:
    _require(values == sorted(values) and len(values) == len(set(values)), message)


def _reject_constant(value: str) -> NoReturn:
    raise ReplayFailure(f"non-finite JSON number: {value}")


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ReplayFailure("duplicate JSON member name")
        result[key] = value
    return result


def _validate_json(value: Any, depth: int = 0) -> None:
    _require(depth <= MAXIMUM_DEPTH, "JSON document exceeds the depth bound")
    if isinstance(value, str):
        _require(
            not any(0xD800 <= ord(character) <= 0xDFFF for character in value),
            "JSON contains a lone Unicode surrogate",
        )
    elif isinstance(value, float):
        _require(math.isfinite(value), "JSON contains a non-finite number")
    elif isinstance(value, int) and not isinstance(value, bool):
        _require(abs(value) <= 9_007_199_254_740_991, "JSON integer is outside the JCS domain")
    elif isinstance(value, dict):
        for key, child in value.items():
            _validate_json(key, depth + 1)
            _validate_json(child, depth + 1)
    elif isinstance(value, list):
        for child in value:
            _validate_json(child, depth + 1)


def parse_json_bytes(raw: bytes) -> Any:
    try:
        text = raw.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise ReplayFailure("JSON input is not strict UTF-8") from error
    _require(not text.startswith("\ufeff"), "JSON input must not contain a byte-order mark")
    try:
        value = json.loads(
            text,
            object_pairs_hook=_unique_object,
            parse_constant=_reject_constant,
        )
    except ReplayFailure:
        raise
    except json.JSONDecodeError as error:
        raise ReplayFailure("invalid JSON") from error
    _validate_json(value)
    return value


def _utf16_sort_key(value: str) -> bytes:
    return value.encode("utf-16-be", errors="strict")


def _number(value: int | float) -> str:
    if isinstance(value, int):
        _require(abs(value) <= 9_007_199_254_740_991, "integer is outside the JCS domain")
        return str(value)
    _require(math.isfinite(value), "number is outside the JCS domain")
    if value == 0:
        return "0"
    negative = value < 0
    absolute = -value if negative else value
    text = repr(absolute).lower()
    if "e" in text:
        mantissa, exponent_text = text.split("e", 1)
        exponent = int(exponent_text)
        digits = mantissa.replace(".", "")
        decimal_position = (mantissa.index(".") if "." in mantissa else len(mantissa)) + exponent
        if 1e-6 <= absolute < 1e21:
            if decimal_position <= 0:
                rendered = "0." + "0" * (-decimal_position) + digits
            elif decimal_position >= len(digits):
                rendered = digits + "0" * (decimal_position - len(digits))
            else:
                rendered = digits[:decimal_position] + "." + digits[decimal_position:]
        else:
            significand = digits[0] + (("." + digits[1:]) if len(digits) > 1 else "")
            scientific_exponent = decimal_position - 1
            sign = "+" if scientific_exponent >= 0 else ""
            rendered = f"{significand}e{sign}{scientific_exponent}"
    elif absolute >= 1e21:
        digits = text.replace(".", "").rstrip("0")
        exponent = len(text.split(".", 1)[0]) - 1
        significand = digits[0] + (("." + digits[1:]) if len(digits) > 1 else "")
        rendered = f"{significand}e+{exponent}"
    else:
        rendered = text
    return ("-" if negative else "") + rendered


def _canonical_text(value: Any) -> str:
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return _number(value)
    if isinstance(value, str):
        _validate_json(value)
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    if isinstance(value, list):
        return "[" + ",".join(_canonical_text(child) for child in value) + "]"
    if isinstance(value, dict):
        keys = sorted(value, key=_utf16_sort_key)
        return "{" + ",".join(
            f"{_canonical_text(key)}:{_canonical_text(value[key])}" for key in keys
        ) + "}"
    raise ReplayFailure("value is outside the JCS domain")


def canonical_bytes(value: Any) -> bytes:
    """Encode strict I-JSON with RFC 8785 key order and number spelling."""

    _validate_json(value)
    return _canonical_text(value).encode("utf-8", errors="strict")


def _digest(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def _regular_bytes(path: Path, maximum: int = MAXIMUM_FILE_BYTES) -> bytes:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise ReplayFailure("referenced file is unavailable") from error
    _require(path.is_file() and not path.is_symlink() and metadata.st_size <= maximum,
             "input is not a bounded regular file")
    raw = path.read_bytes()
    _require(len(raw) == metadata.st_size, "input changed while being read")
    return raw


def _require_directory(path: Path, message: str) -> None:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise ReplayFailure(message) from error
    _require(path.is_dir() and not path.is_symlink() and metadata.st_mode != 0, message)


def _safe_existing(root: Path, relative_path: str, expected: str) -> Path:
    _require(
        isinstance(relative_path, str)
        and len(relative_path.encode("utf-8")) <= MAXIMUM_PATH_BYTES
        and ARCHIVE_PATH.fullmatch(relative_path) is not None,
        "unsafe archive path",
    )
    root = root.resolve(strict=True)
    candidate = root
    for component in relative_path.split("/"):
        candidate = candidate / component
        try:
            metadata = candidate.lstat()
        except OSError as error:
            raise ReplayFailure("referenced archive path is unavailable") from error
        _require(not candidate.is_symlink() and metadata.st_mode != 0,
                 "archive paths may not traverse symlinks")
    _require(candidate.is_relative_to(root), "archive path escapes its root")
    _require(candidate.is_file() if expected == "file" else candidate.is_dir(),
             f"archive {expected} has the wrong type")
    return candidate


def _all_regular_files(root: Path) -> list[Path]:
    _require_directory(root, "inventory root is not a directory")
    result: list[Path] = []

    def visit(directory: Path) -> None:
        with os.scandir(directory) as entries:
            for entry in sorted(entries, key=lambda item: item.name):
                candidate = directory / entry.name
                _require(not entry.is_symlink(), "inventory contains a symlink")
                if entry.is_dir(follow_symlinks=False):
                    visit(candidate)
                else:
                    _require(entry.is_file(follow_symlinks=False),
                             "inventory contains an unsupported filesystem entry")
                    result.append(candidate)

    visit(root)
    return sorted(result)


def _file_binding(path: Path, root: Path) -> dict[str, Any]:
    raw = _regular_bytes(path)
    return {
        "relative_path": path.relative_to(root).as_posix(),
        "byte_length": len(raw),
        "sha256": hashlib.sha256(raw).hexdigest(),
    }


def _verify_fixture_inventory(fixture: dict[str, Any], fixture_root: Path) -> None:
    inventory = _array(fixture["files"], "fixture file inventory is absent")
    _require(len(inventory) <= MAXIMUM_MEMBERS, "fixture file inventory exceeds the bound")
    paths: list[str] = []
    for raw_entry in inventory:
        entry = _object(raw_entry, "fixture file binding is invalid")
        _exact_keys(entry, {"byte_length", "relative_path", "sha256"},
                    "fixture file binding is not closed")
        relative_path = entry["relative_path"]
        _require(isinstance(relative_path, str) and DIGEST.fullmatch(entry["sha256"]),
                 "fixture file identity is invalid")
        paths.append(relative_path)
        raw = _regular_bytes(
            _safe_existing(fixture_root, relative_path, "file"),
            _integer(entry["byte_length"]) + 1,
        )
        _require(
            len(raw) == entry["byte_length"]
            and hashlib.sha256(raw).hexdigest() == entry["sha256"],
            "fixture file digest mismatch",
        )
    _lexical_unique(paths, "fixture file inventory is duplicated or unsorted")
    physical = [
        path.relative_to(fixture_root).as_posix()
        for path in _all_regular_files(_safe_existing(fixture_root, "archives", "directory"))
    ]
    _require(physical == paths, "fixture raw inventory is incomplete or contains an extra file")

    directory_paths: list[str] = []
    for raw_entry in _array(fixture["directories"], "fixture directory inventory is absent"):
        entry = _object(raw_entry, "fixture directory binding is invalid")
        _exact_keys(
            entry,
            {"byte_length", "file_count", "relative_path", "tree_sha256"},
            "fixture directory binding is not closed",
        )
        relative_path = entry["relative_path"]
        _require(isinstance(relative_path, str) and DIGEST.fullmatch(entry["tree_sha256"]),
                 "fixture directory identity is invalid")
        directory_paths.append(relative_path)
        directory = _safe_existing(fixture_root, relative_path, "directory")
        bindings = [_file_binding(path, fixture_root) for path in _all_regular_files(directory)]
        _require(len(bindings) == entry["file_count"], "fixture directory file count mismatch")
        _require(sum(item["byte_length"] for item in bindings) == entry["byte_length"],
                 "fixture directory byte length mismatch")
        _require(_digest(bindings) == entry["tree_sha256"],
                 "fixture directory tree digest mismatch")
    _lexical_unique(directory_paths, "fixture directory inventory is duplicated or unsorted")


def _load_fixture(
    manifest_path: Path, repo_root: Path
) -> tuple[dict[str, Any], Path]:
    _require_directory(repo_root, "repository root is invalid")
    manifest_path = manifest_path.resolve(strict=True)
    raw = _regular_bytes(manifest_path)
    _require(hashlib.sha256(raw).hexdigest() == PINNED_FIXTURE_MANIFEST_SHA256,
             "capture fixture manifest drifted")
    fixture = _object(parse_json_bytes(raw), "capture fixture manifest is not an object")
    _exact_keys(fixture, FIXTURE_KEYS,
                "capture fixture manifest has unknown or missing properties")
    _require(
        fixture["schema_version"] == "1.0.0"
        and fixture["fixture_id"] == "FX-CAPTURE-001"
        and fixture["fixture_revision"] == "rev-001",
        "capture fixture identity is invalid",
    )
    fixture_root = manifest_path.parent
    _verify_fixture_inventory(fixture, fixture_root)

    report_schema = _object(fixture["report_schema"], "report schema binding is invalid")
    _exact_keys(report_schema, {"byte_length", "relative_path", "sha256"},
                "report schema binding is not closed")
    _require(report_schema["sha256"] == PINNED_REPORT_SCHEMA_SHA256,
             "report schema binding drifted")
    schema_raw = _regular_bytes(
        _safe_existing(repo_root, report_schema["relative_path"], "file"),
        _integer(report_schema["byte_length"]) + 1,
    )
    _require(
        len(schema_raw) == report_schema["byte_length"]
        and hashlib.sha256(schema_raw).hexdigest() == PINNED_REPORT_SCHEMA_SHA256,
        "report schema drifted",
    )
    schema = _object(parse_json_bytes(schema_raw), "report schema is invalid JSON")
    _require(
        schema.get("$id") == "https://reroom.dev/schemas/replay-report/1.0.0"
        and schema.get("additionalProperties") is False,
        "report schema identity is invalid",
    )

    archives = _array(fixture["archives"], "archive descriptors are absent")
    _require([_object(item)["archive_name"] for item in archives] == list(ARCHIVE_NAMES),
             "archive set is incomplete, duplicated, or unsorted")
    probes = _array(fixture["edge_probes"], "edge probes are absent")
    _require([_object(item)["case_id"] for item in probes] == list(PROBE_IDS),
             "edge probe set is incomplete, duplicated, or unsorted")
    consent = _object(fixture["consent_denied_case"], "consent-denied case is absent")
    _require(
        consent.get("archive_created") is False
        and consent.get("consent_granted") is False
        and consent.get("expected_verdict") == "reject"
        and consent.get("rejection_class") == "semantic_invariant"
        and isinstance(consent.get("session_id"), str)
        and SESSION_ID.fullmatch(consent["session_id"]),
        "consent-denied case is invalid",
    )
    return fixture, fixture_root


def _replay_archive(descriptor: dict[str, Any], fixture_root: Path) -> dict[str, Any]:
    _exact_keys(descriptor, {"archive_name", "directory", "expected", "quarantine"},
                "archive descriptor is not closed")
    archive_name = descriptor["archive_name"]
    _require(isinstance(archive_name, str) and archive_name in ARCHIVE_NAMES,
             "archive identity is invalid")
    directory = _object(descriptor["directory"], "archive directory binding is invalid")
    _require(directory.get("relative_path") == f"archives/{archive_name}",
             "archive directory path is invalid")
    archive_root = _safe_existing(fixture_root, directory["relative_path"], "directory")
    manifest_raw = _regular_bytes(_safe_existing(archive_root, "manifest.json", "file"))
    manifest = _object(parse_json_bytes(manifest_raw), "archive manifest is invalid JSON")
    _require(canonical_bytes(manifest) == manifest_raw,
             "archive manifest is not exact JCS bytes")
    _exact_keys(manifest, ARCHIVE_MANIFEST_KEYS,
                "archive manifest has unknown or missing properties")
    _require(manifest["format_version"] == "1.0.0"
             and manifest["capture_kind"] == "native_arkit",
             "unsupported archive contract version")
    _require(isinstance(manifest["session_id"], str)
             and SESSION_ID.fullmatch(manifest["session_id"]),
             "archive session identity is invalid")
    _require(_array(manifest["keyframes"]) == [], "fixture archive keyframes must be empty")

    finalization = _object(manifest["finalization"], "archive finalization is invalid")
    _exact_keys(
        finalization,
        {"last_durable_journal_sequence", "manifest_sha256", "manifest_sha256_algorithm",
         "manifest_sha256_scope", "state"},
        "archive finalization is not closed",
    )
    _require(
        finalization["manifest_sha256_algorithm"] == "RR-JCS-SHA256-1"
        and finalization["manifest_sha256_scope"]
        == "entire_manifest_with_finalization_manifest_sha256_member_omitted"
        and finalization["state"] in {"finalized", "recovered_prefix"}
        and DIGEST.fullmatch(finalization["manifest_sha256"]),
        "archive finalization identity is invalid",
    )
    unsigned_manifest = json.loads(json.dumps(manifest))
    del unsigned_manifest["finalization"]["manifest_sha256"]
    _require(_digest(unsigned_manifest) == finalization["manifest_sha256"],
             "archive manifest digest mismatch")

    files = _array(manifest["files"], "archive file inventory is invalid")
    _require(len(files) <= MAXIMUM_MEMBERS, "archive inventory exceeds its bound")
    inventory: dict[str, dict[str, Any]] = {}
    file_paths: list[str] = []
    for raw_entry in files:
        entry = _object(raw_entry, "archive file binding is invalid")
        _exact_keys(
            entry,
            {"byte_length", "codec", "media_type", "relative_path", "role", "sha256"},
            "archive file binding is not closed",
        )
        _require(
            isinstance(entry["relative_path"], str)
            and entry["codec"] in SUPPORTED_CODECS
            and DIGEST.fullmatch(entry["sha256"]),
            "archive file binding is invalid",
        )
        file_paths.append(entry["relative_path"])
        raw = _regular_bytes(
            _safe_existing(archive_root, entry["relative_path"], "file"),
            _integer(entry["byte_length"]) + 1,
        )
        _require(
            len(raw) == entry["byte_length"]
            and hashlib.sha256(raw).hexdigest() == entry["sha256"],
            "archive inventory digest mismatch",
        )
        inventory[entry["relative_path"]] = entry
    _lexical_unique(file_paths, "archive file inventory is duplicated or unsorted")

    journal = _array(manifest["journal"], "archive journal is invalid")
    _require(0 < len(journal) <= MAXIMUM_MEMBERS, "archive journal count is invalid")
    for index, raw_entry in enumerate(journal):
        entry = _object(raw_entry, "journal entry is invalid")
        _exact_keys(
            entry,
            {"content_sha256", "entry_type", "journal_sequence",
             "monotonic_timestamp_ns", "reference_id"},
            "journal entry is not closed",
        )
        _require(
            _integer(entry["journal_sequence"]) == index
            and entry["entry_type"] in {"event", "frame"}
            and isinstance(entry["reference_id"], str)
            and DIGEST.fullmatch(entry["content_sha256"])
            and isinstance(entry["monotonic_timestamp_ns"], str)
            and re.fullmatch(r"^(0|[1-9][0-9]*)$", entry["monotonic_timestamp_ns"]),
            "non-contiguous or invalid journal entry",
        )

    events = _array(manifest["events"], "event projection is invalid")
    journal_events = [entry for entry in journal if entry["entry_type"] == "event"]
    _require(len(events) == len(journal_events), "event projection count mismatch")
    for index, raw_event in enumerate(events):
        event = _object(raw_event, "event projection member is invalid")
        _exact_keys(
            event,
            {"durable_journal_sequence", "event_id", "event_sequence",
             "monotonic_timestamp_ns", "payload_path", "payload_sha256", "record_sha256",
             "record_sha256_algorithm", "record_sha256_scope", "type"},
            "event projection member is not closed",
        )
        durable = _integer(event["durable_journal_sequence"])
        _require(
            _integer(event["event_sequence"]) == index
            and durable < len(journal)
            and isinstance(event["event_id"], str)
            and isinstance(event["payload_path"], str)
            and DIGEST.fullmatch(event["payload_sha256"])
            and DIGEST.fullmatch(event["record_sha256"])
            and event["record_sha256_algorithm"] == "RR-JCS-SHA256-1"
            and event["record_sha256_scope"]
            == "entire_event_record_with_record_sha256_member_omitted",
            "event projection member is invalid",
        )
        payload = inventory.get(event["payload_path"])
        _require(payload is not None and payload["sha256"] == event["payload_sha256"],
                 "event payload is not bound by inventory")
        unsigned_event = dict(event)
        del unsigned_event["record_sha256"]
        _require(_digest(unsigned_event) == event["record_sha256"],
                 "event record digest mismatch")
        journal_entry = journal[durable]
        _require(
            journal_entry["entry_type"] == "event"
            and journal_entry["reference_id"] == event["event_id"]
            and journal_entry["content_sha256"] == event["record_sha256"]
            and journal_entry["monotonic_timestamp_ns"] == event["monotonic_timestamp_ns"]
            and canonical_bytes(journal_entry) == canonical_bytes(journal_events[index]),
            "event projection is not the exact journal projection",
        )

    frames = _array(manifest["accepted_frame_order"], "frame projection is invalid")
    journal_frames = [entry for entry in journal if entry["entry_type"] == "frame"]
    _require(len(frames) == len(journal_frames), "frame projection count mismatch")
    required_frame_keys = {
        "durable_journal_sequence", "frame_id", "packet_path", "packet_sha256", "sequence",
    }
    allowed_frame_keys = required_frame_keys | {"server_acknowledged"}
    for index, raw_frame in enumerate(frames):
        frame = _object(raw_frame, "frame projection member is invalid")
        _subset_keys(frame, required_frame_keys, allowed_frame_keys,
                     "frame projection member is not closed")
        durable = _integer(frame["durable_journal_sequence"])
        _require(
            _integer(frame["sequence"]) == index
            and durable < len(journal)
            and isinstance(frame["frame_id"], str)
            and isinstance(frame["packet_path"], str)
            and DIGEST.fullmatch(frame["packet_sha256"]),
            "frame projection member is invalid",
        )
        packet_binding = inventory.get(frame["packet_path"])
        _require(packet_binding is not None
                 and packet_binding["sha256"] == frame["packet_sha256"],
                 "frame packet is not bound by inventory")
        journal_entry = journal[durable]
        _require(
            journal_entry["entry_type"] == "frame"
            and journal_entry["reference_id"] == frame["frame_id"]
            and journal_entry["content_sha256"] == frame["packet_sha256"]
            and canonical_bytes(journal_entry) == canonical_bytes(journal_frames[index]),
            "frame projection is not the exact journal projection",
        )
        packet_raw = _regular_bytes(_safe_existing(archive_root, frame["packet_path"], "file"))
        packet = _object(parse_json_bytes(packet_raw), "frame packet is invalid JSON")
        _require(canonical_bytes(packet) == packet_raw, "frame packet is not exact JCS bytes")
        image = _object(packet.get("image"), "frame image binding is invalid")
        payload = _object(image.get("payload"), "frame payload binding is invalid")
        _require(
            packet.get("protocol_version") == "1.0.0"
            and packet.get("coordinate_convention") == "RR-COORD-1"
            and packet.get("frame_id") == frame["frame_id"]
            and _integer(packet.get("capture_sequence")) == index
            and image.get("codec") == "png"
            and payload.get("kind") == "rrcap_file"
            and isinstance(payload.get("relative_path"), str)
            and DIGEST.fullmatch(payload.get("sha256", ""))
            and packet.get("payload_sha256") == payload["sha256"],
            "frame packet identity or payload binding is invalid",
        )
        image_binding = inventory.get(payload["relative_path"])
        _require(
            image_binding is not None
            and image_binding["sha256"] == payload["sha256"]
            and image_binding["byte_length"] == _integer(payload["byte_length"]),
            "frame image bytes are not bound by inventory",
        )

    referenced = {event["payload_path"] for event in events}
    for frame in frames:
        referenced.add(frame["packet_path"])
        packet = _object(parse_json_bytes(
            _regular_bytes(_safe_existing(archive_root, frame["packet_path"], "file"))
        ))
        referenced.add(_object(_object(packet["image"])["payload"])["relative_path"])
    _require(referenced == set(inventory),
             "archive inventory is not the exact frame/event projection closure")

    replay = _object(manifest["replay"], "replay digest block is invalid")
    _exact_keys(
        replay,
        {"input_digest", "input_digest_algorithm", "input_digest_scope", "neural_determinism",
         "ordering_authority", "provider_lock"},
        "replay digest block is not closed",
    )
    journal_tuple_sha256 = _digest([
        [entry["journal_sequence"], entry["entry_type"], entry["reference_id"], entry["content_sha256"]]
        for entry in journal
    ])
    _require(
        replay["ordering_authority"] == "global_journal_sequence"
        and replay["input_digest_algorithm"] == "RR-JCS-SHA256-1"
        and replay["input_digest_scope"]
        == "jcs_array_of_journal_sequence_entry_type_reference_id_content_sha256"
        and _array(replay["provider_lock"]) == []
        and replay["input_digest"] == journal_tuple_sha256,
        "journal tuple input digest mismatch",
    )
    _require(_integer(finalization["last_durable_journal_sequence"]) == len(journal) - 1,
             "final journal sequence mismatch")
    revision_trace = [{
        "journal_sequence": 0,
        "revision_id": re.sub(r"^session_", "revision_", manifest["session_id"]),
        "source": "capture_baseline",
    }]
    snapshot = {
        "archive_name": archive_name,
        "finalization_state": finalization["state"],
        "manifest_sha256": finalization["manifest_sha256"],
        "accepted_frame_count": len(frames),
        "event_count": len(events),
        "journal_record_count": len(journal),
        "digests": {
            "journal_tuple_sha256": journal_tuple_sha256,
            "frame_projection_sha256": _digest(frames),
            "event_projection_sha256": _digest(events),
            "revision_trace_sha256": _digest(revision_trace),
        },
    }
    expected = _object(descriptor["expected"], "archive equality oracle is invalid")
    _require(expected.get("verdict") == "accept" and expected.get("rejection_class") is None,
             "archive equality oracle verdict is invalid")
    _require(
        expected["finalization_state"] == snapshot["finalization_state"]
        and expected["journal_record_count"] == snapshot["journal_record_count"]
        and expected["accepted_frame_count"] == snapshot["accepted_frame_count"]
        and expected["event_count"] == snapshot["event_count"]
        and expected["journal_tuple_sha256"] == snapshot["digests"]["journal_tuple_sha256"]
        and expected["frame_projection_sha256"] == snapshot["digests"]["frame_projection_sha256"]
        and expected["event_projection_sha256"] == snapshot["digests"]["event_projection_sha256"]
        and expected["revision_trace_sha256"] == snapshot["digests"]["revision_trace_sha256"],
        "independent archive replay disagrees with the frozen equality oracle",
    )
    return snapshot


def _contiguous(values: Any) -> bool:
    return isinstance(values, list) and all(
        isinstance(value, int) and not isinstance(value, bool) and value == index
        for index, value in enumerate(values)
    )


def _evaluate_probe(probe: dict[str, Any]) -> tuple[str, str | None]:
    input_value = _object(probe["input"], "edge probe input is invalid")
    case_id = probe["case_id"]
    if case_id == "fr-b0.adjacency":
        accepted = (isinstance(input_value.get("prior_revision"), int)
                    and input_value.get("next_revision") == input_value["prior_revision"] + 1)
        outcome = ("accept", None) if accepted else ("reject", "semantic_invariant")
    elif case_id == "fr-b0.concurrency":
        sequences = _array(input_value.get("journal_sequences"))
        reader_count = _integer(input_value.get("reader_count"))
        digests = {_digest(sequences) for _ in range(reader_count)}
        outcome = ("accept", None) if reader_count >= 2 and _contiguous(sequences) and len(digests) == 1 else ("reject", "semantic_invariant")
    elif case_id == "fr-b0.empty":
        outcome = ("accept", None) if input_value.get("accepted_frame_count") == 0 and _integer(input_value.get("event_count")) > 0 else ("reject", "semantic_invariant")
    elif case_id == "fr-b0.ordering":
        outcome = ("accept", None) if _contiguous(input_value.get("journal_sequences")) else ("reject", "non_contiguous_journal")
    elif case_id == "fr-capture.adjacency":
        sequences = _array(input_value.get("capture_sequences"))
        outcome = ("accept", None) if input_value.get("frame_ids_distinct") is True and _contiguous(sequences) else ("reject", "semantic_invariant")
    elif case_id == "fr-capture.boundary":
        maximum = _integer(input_value.get("payload_max_bytes"))
        neighbors = [_integer(value) for value in _array(input_value.get("neighbors"))]
        outcome = ("reject", "wire_length_mismatch") if any(value > maximum for value in neighbors) else ("accept", None)
    elif case_id == "fr-capture.concurrency":
        durable = _integer(input_value.get("durable_journal_sequence"))
        acknowledgement = _integer(input_value.get("acknowledgement_journal_sequence"))
        outcome = ("accept", None) if acknowledgement > durable else ("reject", "semantic_invariant")
    elif case_id == "fr-capture.empty":
        outcome = ("accept", None) if _integer(input_value.get("image_byte_length")) > 0 else ("reject", "schema_validation")
    elif case_id == "fr-capture.ordering":
        lifecycle = _array(input_value.get("lifecycle"))
        required = ["selected", "image_and_metadata_durable", "journaled", "network_eligible", "server_acknowledged"]
        positions = [required.index(value) if value in required else -1 for value in lifecycle]
        valid = (all(position >= 0 and (index == 0 or positions[index - 1] < position)
                     for index, position in enumerate(positions))
                 and ("network_eligible" not in lifecycle or "journaled" in lifecycle)
                 and ("journaled" not in lifecycle or "image_and_metadata_durable" in lifecycle))
        outcome = ("accept", None) if valid else ("reject", "semantic_invariant")
    elif case_id == "fr-capture.precision":
        binary = input_value.get("binary32_hex")
        _require(isinstance(binary, str) and re.fullmatch(r"[0-9a-f]{8}", binary),
                 "precision probe binary32 bytes are invalid")
        value = struct.unpack(">f", bytes.fromhex(binary))[0]
        quantized = struct.unpack(">f", struct.pack(">f", input_value.get("decimal_input")))[0]
        outcome = ("accept", None) if math.isfinite(value) and value == quantized else ("reject", "numeric_out_of_range")
    elif case_id == "nfr-replay.assumption":
        outcome = ("accept", None) if _integer(input_value.get("controlled_capture_minutes")) > 0 and input_value.get("evidence_classification") == "HYPOTHESIS" else ("reject", "semantic_invariant")
    elif case_id == "sec-consent.concurrent-session-separation":
        outcome = ("accept", None) if input_value.get("candidate_session_id") == input_value.get("consented_session_id") else ("reject", "semantic_invariant")
    else:
        raise ReplayFailure("unknown edge probe case")
    expected = _object(probe["expected"], "edge probe equality oracle is invalid")
    _require(expected.get("verdict") == outcome[0]
             and expected.get("rejection_class") == outcome[1],
             f"independent edge probe {case_id} disagrees with the frozen equality oracle")
    return outcome


def _make_report(
    snapshot: dict[str, Any],
    case_id: str,
    outcome: tuple[str, str | None],
    implementation_revision: str,
) -> bytes:
    verdict, rejection_class = outcome
    report: dict[str, Any] = {
        "report_version": "1.0.0",
        "evaluator": {"name": "ReRoomReplayPython", "version": "1.0.0", "platform": "python"},
        "fixture": {
            "fixture_id": "FX-CAPTURE-001",
            "fixture_revision": "rev-001",
            "manifest_sha256": PINNED_FIXTURE_MANIFEST_SHA256,
        },
        "archive": {
            "case_id": case_id,
            "archive_name": snapshot["archive_name"],
            "finalization_state": snapshot["finalization_state"],
            "manifest_sha256": snapshot["manifest_sha256"],
            "accepted_frame_count": snapshot["accepted_frame_count"],
            "event_count": snapshot["event_count"],
            "journal_record_count": snapshot["journal_record_count"],
        },
        "implementation": {
            "repository_revision": implementation_revision,
            "runtime": f"python-{EXACT_PYTHON_VERSION}",
            "build_id": "ReRoomReplayPython-1.0.0",
        },
        "verdict": verdict,
        "digests": snapshot["digests"],
        "rejection": None if rejection_class is None else {
            "rejection_class": rejection_class,
            "detail": f"frozen fixture expected {rejection_class}",
        },
        "metrics": {
            "max_queue_depth": 0,
            "dropped_stale_candidates": 0,
            "recovered_prefix_records": snapshot["journal_record_count"]
            if snapshot["finalization_state"] == "recovered_prefix" else 0,
            "quarantined_suffix_records": 1
            if snapshot["finalization_state"] == "recovered_prefix" else 0,
        },
    }
    report["report_sha256"] = _digest(report)
    return canonical_bytes(report)


def _validate_output(output_root: Path) -> None:
    _require(not output_root.exists() and not output_root.is_symlink(),
             "output root must not exist")
    _require_directory(output_root.parent, "output parent is invalid")


def _durable_write(path: Path, raw: bytes) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "wb", closefd=False) as handle:
            handle.write(raw)
            handle.flush()
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _sync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _publish_reports(reports: dict[str, bytes], output_root: Path) -> None:
    _validate_output(output_root)
    stage = output_root.parent / f".reroom-python-replay-staging-{uuid.uuid4()}"
    published = False
    try:
        stage.mkdir(mode=0o700)
        for case_id in sorted(reports):
            _durable_write(stage / f"{case_id}.replay-report.json", reports[case_id])
        names = sorted(path.name for path in stage.iterdir())
        expected = [f"{case_id}.replay-report.json" for case_id in sorted(reports)]
        _require(names == expected, "staged replay report set is incomplete")
        _sync_directory(stage)
        _validate_output(output_root)
        stage.rename(output_root)
        published = True
        _sync_directory(output_root.parent)
    finally:
        if not published and stage.exists():
            shutil.rmtree(stage)


def run_replay(
    manifest_path: Path | str,
    output_root: Path | str,
    repo_root: Path | str,
    implementation_revision: str,
    *,
    runtime_version: str | None = None,
) -> None:
    """Verify and replay all frozen cases, then publish one exclusive report directory."""

    _require((runtime_version or platform.python_version()) == EXACT_PYTHON_VERSION,
             "exact Python 3.13.12 is required before replay")
    _require(isinstance(implementation_revision, str)
             and REVISION.fullmatch(implementation_revision),
             "implementation revision must be git:<40-lowercase-hex>")
    output = Path(output_root).resolve(strict=False)
    _validate_output(output)
    fixture, fixture_root = _load_fixture(Path(manifest_path), Path(repo_root).resolve(strict=True))

    snapshots: dict[str, dict[str, Any]] = {}
    reports: dict[str, bytes] = {}
    for raw_descriptor in _array(fixture["archives"]):
        descriptor = _object(raw_descriptor)
        snapshot = _replay_archive(descriptor, fixture_root)
        snapshots[snapshot["archive_name"]] = snapshot
        case_id = f"archive.{snapshot['archive_name'][:-len('.rrcap')]}"
        reports[case_id] = _make_report(snapshot, case_id, ("accept", None), implementation_revision)
    ordinary = snapshots.get("finalized-one-frame.rrcap")
    empty = snapshots.get("finalized-empty.rrcap")
    _require(ordinary is not None and empty is not None, "baseline replay snapshots are absent")
    for raw_probe in _array(fixture["edge_probes"]):
        probe = _object(raw_probe)
        outcome = _evaluate_probe(probe)
        snapshot = empty if probe["case_id"] == "fr-b0.empty" else ordinary
        reports[probe["case_id"]] = _make_report(
            snapshot, probe["case_id"], outcome, implementation_revision
        )
    reports["sec-consent.denied"] = _make_report(
        empty, "sec-consent.denied", ("reject", "semantic_invariant"), implementation_revision
    )
    expected_case_ids = sorted(
        [f"archive.{name[:-len('.rrcap')]}" for name in ARCHIVE_NAMES]
        + list(PROBE_IDS)
        + ["sec-consent.denied"]
    )
    _require(len(reports) == 16 and sorted(reports) == expected_case_ids,
             "complete replay report set is invalid")
    _publish_reports(reports, output)


def _parse_cli(arguments: list[str]) -> tuple[Path, Path, Path, str]:
    allowed = {"--manifest", "--output-root", "--repo-root", "--implementation-revision"}
    _require(len(arguments) == 8, "exactly four named arguments are required")
    values: dict[str, str] = {}
    for index in range(0, len(arguments), 2):
        name, value = arguments[index:index + 2]
        _require(name in allowed and name not in values, "unsupported or duplicate argument")
        values[name] = value
    _require(set(values) == allowed, "all exact replay arguments are required")
    return (
        Path(values["--manifest"]),
        Path(values["--output-root"]),
        Path(values["--repo-root"]),
        values["--implementation-revision"],
    )


def main(arguments: list[str] | None = None) -> int:
    try:
        run_replay(*_parse_cli(list(sys.argv[1:] if arguments is None else arguments)))
        return 0
    except ReplayFailure as error:
        print(f"replay-python: FAIL: {error}", file=sys.stderr)
        return 1
    except Exception:
        print("replay-python: FAIL: unexpected replay failure", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
