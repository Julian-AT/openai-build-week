#!/usr/bin/env python3
"""Bounded semantic verifier for sanitized ReRoom gate evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[2]
MAX_BYTES = 1_048_576
MAX_FIXTURES = 256
UUID_PATTERN = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-"
    r"[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}"
)
ABSOLUTE_PATH_PATTERN = re.compile(r"^(?:/|[A-Za-z]:[\\/]|\\\\)")
FORBIDDEN_KEYS = {
    "device_uuid",
    "udid",
    "team_id",
    "account",
    "user_path",
    "raw_room_bytes",
    "raw_logs",
    "signing_material",
    "private_key",
}


class VerificationFailure(ValueError):
    pass


def reject_duplicate_names(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise VerificationFailure(f"duplicate JSON name: {key}")
        result[key] = value
    return result


def read_json(path: Path) -> tuple[bytes, Any]:
    if not path.is_file():
        raise VerificationFailure(f"missing file: {path}")
    if path.stat().st_size > MAX_BYTES:
        raise VerificationFailure(f"file exceeds {MAX_BYTES} bytes: {path}")
    raw = path.read_bytes()
    try:
        value = json.loads(raw, object_pairs_hook=reject_duplicate_names)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise VerificationFailure(f"invalid JSON: {path}: {error}") from error
    return raw, value


def load_validator(name: str) -> Draft202012Validator:
    _, schema = read_json(ROOT / "evidence" / "templates" / name)
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema)


def assert_schema_valid(validator: Draft202012Validator, value: Any, label: str) -> None:
    errors = sorted(validator.iter_errors(value), key=lambda item: list(item.absolute_path))
    if errors:
        first = errors[0]
        location = ".".join(str(part) for part in first.absolute_path) or "<root>"
        raise VerificationFailure(f"{label}: schema rejection at {location}: {first.message}")


def assert_privacy_safe(value: Any, path: tuple[str, ...] = ()) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key.lower() in FORBIDDEN_KEYS:
                raise VerificationFailure(f"forbidden private field: {'.'.join(path + (key,))}")
            assert_privacy_safe(child, path + (key,))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            assert_privacy_safe(child, path + (str(index),))
    elif isinstance(value, str):
        if ABSOLUTE_PATH_PATTERN.search(value):
            raise VerificationFailure(f"private path value: {'.'.join(path)}")
        if "-----BEGIN" in value or "PRIVATE KEY" in value.upper():
            raise VerificationFailure(f"signing material value: {'.'.join(path)}")
        if UUID_PATTERN.search(value):
            raise VerificationFailure(f"device-like UUID value: {'.'.join(path)}")
        if path and path[0] == "environment":
            lowered = value.lower()
            if "team id" in lowered or "account" in lowered or "@" in value:
                raise VerificationFailure(f"private environment value: {'.'.join(path)}")


def verify_report(value: Any, validator: Draft202012Validator, label: str) -> None:
    assert_schema_valid(validator, value, label)
    assert_privacy_safe(value)
    if value["decision_actor"] == "automation" and value["gate_state"] not in {
        "UNRUN",
        "RUNNING",
        "RED",
    }:
        raise VerificationFailure(f"{label}: automation attempted human-only state")
    for artifact in value["evidence_artifacts"]:
        if not artifact["opaque_artifact_id"].startswith("opaque-"):
            raise VerificationFailure(f"{label}: artifact reference is not opaque")
        if artifact["external_retention"] is not True:
            raise VerificationFailure(f"{label}: raw artifact is not externally retained")


def verify_fixture_corpus(fixtures: Path) -> None:
    report_validator = load_validator("gate-report.schema.json")
    checklist_validator = load_validator("operator-checklist.schema.json")
    valid_paths = sorted((fixtures / "valid").glob("*.json"))
    invalid_paths = sorted((fixtures / "invalid").glob("*.json"))
    if not valid_paths or not invalid_paths or len(valid_paths) + len(invalid_paths) > MAX_FIXTURES:
        raise VerificationFailure("fixture corpus count is missing or out of bounds")

    for path in valid_paths:
        _, value = read_json(path)
        validator = report_validator if path.name.startswith("gate-report.") else checklist_validator
        assert_schema_valid(validator, value, path.name)
        assert_privacy_safe(value)

    for path in invalid_paths:
        _, value = read_json(path)
        validator = report_validator if path.name.startswith("gate-report.") else checklist_validator
        if not list(validator.iter_errors(value)):
            raise VerificationFailure(f"invalid fixture unexpectedly accepted: {path.name}")


def verify_files(report_path: Path, checklist_path: Path | None) -> None:
    report_validator = load_validator("gate-report.schema.json")
    checklist_validator = load_validator("operator-checklist.schema.json")
    _, report = read_json(report_path)
    verify_report(report, report_validator, report_path.name)

    human_state = report["gate_state"] in {"GREEN", "WAIVED_BY_HUMAN"}
    if checklist_path is None:
        if human_state:
            raise VerificationFailure("human-bound report requires its external checklist")
        return

    checklist_bytes, checklist = read_json(checklist_path)
    assert_schema_valid(checklist_validator, checklist, checklist_path.name)
    assert_privacy_safe(checklist)
    if checklist["gate_id"] != report["gate_id"]:
        raise VerificationFailure("checklist gate identity does not match report")
    if checklist["decision"] != report["gate_state"]:
        raise VerificationFailure("checklist decision does not match report state")
    if checklist["report_sha256"] != report["automated_report_sha256"]:
        raise VerificationFailure("checklist is not bound to the automated report digest")
    checklist_sha = hashlib.sha256(checklist_bytes).hexdigest()
    if checklist_sha != report["operator_checklist_sha256"]:
        raise VerificationFailure("gate report is not bound to the checklist bytes")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--fixtures", type=Path)
    group.add_argument("--file", type=Path)
    parser.add_argument("--checklist", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.fixtures is not None:
            if args.checklist is not None:
                raise VerificationFailure("--checklist requires --file")
            verify_fixture_corpus(args.fixtures)
        else:
            verify_files(args.file, args.checklist)
    except (OSError, VerificationFailure) as error:
        print(f"evidence verification: FAIL ({error})", file=sys.stderr)
        return 1
    print("evidence verification: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
