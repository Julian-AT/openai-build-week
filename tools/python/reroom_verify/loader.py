"""Bounded, fail-closed loading for immutable verification fixtures."""

from __future__ import annotations

import hashlib
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator, FormatChecker


ABSOLUTE_MAX_FILE_BYTES = 33_554_432
ABSOLUTE_MAX_CASES = 2_048
ABSOLUTE_MAX_DEPTH = 64
ABSOLUTE_MAX_PATH_BYTES = 240


class VerificationFailure(ValueError):
    """A deterministic boundary rejection with a normalized class."""

    def __init__(self, rejection_class: str, message: str = "") -> None:
        super().__init__(message or rejection_class)
        self.rejection_class = rejection_class


def _reject_constant(value: str) -> None:
    raise VerificationFailure("numeric_out_of_range", f"non-finite number: {value}")


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise VerificationFailure("duplicate_name", f"duplicate JSON name: {key}")
        result[key] = value
    return result


def _contains_surrogate(value: str) -> bool:
    return any(0xD800 <= ord(character) <= 0xDFFF for character in value)


def _validate_tree(value: Any, depth: int, max_depth: int) -> None:
    if depth > max_depth:
        raise VerificationFailure("json_parse", "maximum document depth exceeded")
    if isinstance(value, str):
        if _contains_surrogate(value):
            raise VerificationFailure("invalid_unicode", "lone UTF-16 surrogate")
        return
    if isinstance(value, float) and not math.isfinite(value):
        raise VerificationFailure("numeric_out_of_range", "non-finite JSON number")
    if isinstance(value, dict):
        for key, child in value.items():
            if _contains_surrogate(key):
                raise VerificationFailure("invalid_unicode", "lone UTF-16 surrogate in name")
            _validate_tree(child, depth + 1, max_depth)
    elif isinstance(value, list):
        for child in value:
            _validate_tree(child, depth + 1, max_depth)


def parse_json_bytes(raw: bytes, *, max_depth: int = ABSOLUTE_MAX_DEPTH) -> Any:
    """Parse UTF-8 JSON while rejecting duplicate names and invalid scalar values."""

    try:
        text = raw.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise VerificationFailure("invalid_unicode", "input is not strict UTF-8") from error
    try:
        value = json.loads(
            text,
            object_pairs_hook=_unique_object,
            parse_constant=_reject_constant,
        )
    except VerificationFailure:
        raise
    except json.JSONDecodeError as error:
        raise VerificationFailure("json_parse", "invalid JSON") from error
    _validate_tree(value, 0, min(max_depth, ABSOLUTE_MAX_DEPTH))
    return value


def sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def resolve_within(root: Path, relative_path: str, *, max_path_bytes: int) -> Path:
    if not isinstance(relative_path, str) or not relative_path:
        raise VerificationFailure("invalid_path", "path must be a non-empty string")
    if len(relative_path.encode("utf-8")) > min(max_path_bytes, ABSOLUTE_MAX_PATH_BYTES):
        raise VerificationFailure("invalid_path", "path exceeds its byte limit")
    candidate = Path(relative_path)
    if candidate.is_absolute() or "\\" in relative_path or "\x00" in relative_path:
        raise VerificationFailure("invalid_path", "path syntax is unsafe")
    resolved_root = root.resolve(strict=True)
    resolved = (resolved_root / candidate).resolve(strict=True)
    if not resolved.is_relative_to(resolved_root):
        raise VerificationFailure("invalid_path", "path escapes repository root")
    if not resolved.is_file():
        raise VerificationFailure("invalid_path", "path is not a regular file")
    return resolved


def read_bounded(
    root: Path,
    relative_path: str,
    *,
    max_file_bytes: int = ABSOLUTE_MAX_FILE_BYTES,
    max_path_bytes: int = ABSOLUTE_MAX_PATH_BYTES,
) -> bytes:
    path = resolve_within(root, relative_path, max_path_bytes=max_path_bytes)
    limit = min(max_file_bytes, ABSOLUTE_MAX_FILE_BYTES)
    size = path.stat().st_size
    if size > limit:
        raise VerificationFailure("json_parse", "file exceeds its byte limit")
    raw = path.read_bytes()
    if len(raw) != size or len(raw) > limit:
        raise VerificationFailure("json_parse", "file size changed while reading")
    return raw


@dataclass(frozen=True)
class LoadedFixture:
    repo_root: Path
    fixture_root: Path
    manifest_path: Path
    manifest: dict[str, Any]
    manifest_sha256: str
    max_file_bytes: int
    max_path_bytes: int
    max_document_depth: int

    def read_fixture_file(self, relative_path: str) -> bytes:
        return read_bounded(
            self.fixture_root,
            relative_path,
            max_file_bytes=self.max_file_bytes,
            max_path_bytes=self.max_path_bytes,
        )

    def read_repo_file(self, relative_path: str) -> bytes:
        return read_bounded(
            self.repo_root,
            relative_path,
            max_file_bytes=self.max_file_bytes,
            max_path_bytes=self.max_path_bytes,
        )


def _validate_manifest_files(fixture: LoadedFixture) -> None:
    manifest = fixture.manifest
    case_ids = [case["case_id"] for case in manifest["cases"]]
    if len(case_ids) > ABSOLUTE_MAX_CASES or case_ids != sorted(case_ids):
        raise VerificationFailure("semantic_invariant", "cases are not bounded and ordered")
    if len(case_ids) != len(set(case_ids)):
        raise VerificationFailure("semantic_invariant", "duplicate case_id")

    for schema_hash in manifest["schema_hashes"]:
        raw = fixture.read_repo_file(schema_hash["relative_path"])
        if sha256_bytes(raw) != schema_hash["sha256"]:
            raise VerificationFailure("digest_mismatch", "contract schema hash mismatch")
        schema = parse_json_bytes(raw, max_depth=fixture.max_document_depth)
        if schema.get("$id") != schema_hash["schema_id"]:
            raise VerificationFailure("semantic_invariant", "contract schema id mismatch")
        Draft202012Validator.check_schema(schema)

    for case in manifest["cases"]:
        input_raw = fixture.read_fixture_file(case["input"]["relative_path"])
        if len(input_raw) != case["input"]["byte_length"]:
            raise VerificationFailure("digest_mismatch", "fixture input length mismatch")
        if sha256_bytes(input_raw) != case["input"]["sha256"]:
            raise VerificationFailure("digest_mismatch", "fixture input hash mismatch")
        for artifact in case["expected"]["artifacts"]:
            expected_raw = fixture.read_fixture_file(artifact["relative_path"])
            if len(expected_raw) != artifact["byte_length"]:
                raise VerificationFailure("digest_mismatch", "oracle artifact length mismatch")
            if sha256_bytes(expected_raw) != artifact["sha256"]:
                raise VerificationFailure("digest_mismatch", "oracle artifact hash mismatch")


def load_fixture(manifest_path: Path | str, *, repo_root: Path | str) -> LoadedFixture:
    repo = Path(repo_root).resolve(strict=True)
    manifest_file = Path(manifest_path)
    if not manifest_file.is_absolute():
        manifest_file = repo / manifest_file
    manifest_file = manifest_file.resolve(strict=True)
    if not manifest_file.is_relative_to(repo) or not manifest_file.is_file():
        raise VerificationFailure("invalid_path", "manifest is outside the repository")
    raw = manifest_file.read_bytes()
    if len(raw) > ABSOLUTE_MAX_FILE_BYTES:
        raise VerificationFailure("json_parse", "manifest exceeds absolute size bound")
    manifest = parse_json_bytes(raw)
    schema_raw = read_bounded(repo, "fixtures/manifest.schema.json")
    schema = parse_json_bytes(schema_raw)
    Draft202012Validator.check_schema(schema)
    errors = list(
        Draft202012Validator(schema, format_checker=FormatChecker()).iter_errors(manifest)
    )
    if errors:
        raise VerificationFailure("schema_validation", errors[0].message)

    limits = manifest["limits"]
    max_file_bytes = min(limits["max_file_bytes"], ABSOLUTE_MAX_FILE_BYTES)
    max_path_bytes = min(limits["max_path_bytes"], ABSOLUTE_MAX_PATH_BYTES)
    max_document_depth = min(limits["max_document_depth"], ABSOLUTE_MAX_DEPTH)
    if limits["max_cases"] > ABSOLUTE_MAX_CASES:
        raise VerificationFailure("semantic_invariant", "manifest case limit is too large")
    fixture = LoadedFixture(
        repo_root=repo,
        fixture_root=manifest_file.parent,
        manifest_path=manifest_file,
        manifest=manifest,
        manifest_sha256=sha256_bytes(raw),
        max_file_bytes=max_file_bytes,
        max_path_bytes=max_path_bytes,
        max_document_depth=max_document_depth,
    )
    _validate_manifest_files(fixture)
    return fixture
