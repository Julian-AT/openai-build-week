"""Closed Draft 2020-12 validation and contract semantic boundaries."""

from __future__ import annotations

import copy
import math
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator, FormatChecker

from .loader import LoadedFixture, VerificationFailure, parse_json_bytes


FLOAT32_MAX = 3.4028234663852886e38
SUPPORTED_VERSION = "1.0.0"


def _schema_for_name(name: str) -> str:
    mappings = {
        "con001": "docs/contracts/frame-packet.schema.json",
        "con002": "docs/contracts/rrcap-manifest.schema.json",
        "con003": "docs/contracts/scene-state.schema.json",
        "con004": "docs/contracts/edit-artifacts.schema.json",
        "con005": "docs/contracts/transaction.schema.json",
    }
    for prefix, relative_path in mappings.items():
        if prefix in name:
            return relative_path
    raise VerificationFailure("semantic_invariant", "contract case has no schema mapping")


def _pointer_parent(document: Any, pointer: str) -> tuple[Any, str]:
    if not pointer.startswith("/"):
        raise VerificationFailure("semantic_invariant", "invalid JSON pointer")
    tokens = [token.replace("~1", "/").replace("~0", "~") for token in pointer[1:].split("/")]
    current = document
    for token in tokens[:-1]:
        if isinstance(current, list):
            current = current[int(token)]
        elif isinstance(current, dict) and token in current:
            current = current[token]
        else:
            raise VerificationFailure("semantic_invariant", "mutation pointer is absent")
    return current, tokens[-1]


def _apply_mutations(document: Any, mutations: list[dict[str, Any]]) -> Any:
    result = copy.deepcopy(document)
    for mutation in mutations:
        parent, token = _pointer_parent(result, mutation["pointer"])
        operation = mutation["op"]
        if operation not in {"add", "replace"}:
            raise VerificationFailure("semantic_invariant", "unsupported JSON mutation")
        if isinstance(parent, list):
            index = int(token)
            if operation == "replace" and not 0 <= index < len(parent):
                raise VerificationFailure("semantic_invariant", "mutation index is absent")
            if operation == "add" and index == len(parent):
                parent.append(copy.deepcopy(mutation["value"]))
            else:
                parent[index] = copy.deepcopy(mutation["value"])
        elif isinstance(parent, dict):
            if operation == "replace" and token not in parent:
                raise VerificationFailure("semantic_invariant", "mutation member is absent")
            parent[token] = copy.deepcopy(mutation["value"])
        else:
            raise VerificationFailure("semantic_invariant", "mutation parent is scalar")
    return result


def _walk(value: Any, path: tuple[str, ...] = ()) -> None:
    if isinstance(value, float):
        if not math.isfinite(value) or abs(value) > FLOAT32_MAX:
            raise VerificationFailure("numeric_out_of_range", "float32 value is out of range")
    elif isinstance(value, dict):
        for key, child in value.items():
            if key.endswith("path") and isinstance(child, str):
                parts = child.split("/")
                if (
                    not child
                    or child.startswith("/")
                    or "\\" in child
                    or "\x00" in child
                    or any(part in {"", ".", ".."} for part in parts)
                ):
                    raise VerificationFailure("invalid_path", "unsafe archive-relative path")
            _walk(child, path + (key,))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _walk(child, path + (str(index),))


def _validate_version(document: dict[str, Any]) -> None:
    for key in ("protocol_version", "format_version", "schema_version"):
        if key in document and document[key] != SUPPORTED_VERSION:
            raise VerificationFailure("unsupported_contract_version", f"unsupported {key}")


def _validate_authority(document: dict[str, Any]) -> None:
    authority = document.get("revision_authority")
    if not isinstance(authority, dict):
        return
    expected_prefix = {
        "native_device": "device_",
        "gateway": "gateway_",
    }.get(authority.get("kind"))
    authority_id = authority.get("authority_id")
    if expected_prefix and isinstance(authority_id, str) and not authority_id.startswith(expected_prefix):
        raise VerificationFailure("semantic_invariant", "revision authority kind and id disagree")


def _validate_schema(fixture: LoadedFixture, schema_path: str, document: Any) -> None:
    schema = parse_json_bytes(
        fixture.read_repo_file(schema_path), max_depth=fixture.max_document_depth
    )
    Draft202012Validator.check_schema(schema)
    errors = sorted(
        Draft202012Validator(schema, format_checker=FormatChecker()).iter_errors(document),
        key=lambda error: (list(error.absolute_path), error.message),
    )
    if not errors:
        return
    if any(
        error.validator == "additionalProperties" and "'unknown'" in error.message
        for error in errors
    ):
        raise VerificationFailure("unknown_property", errors[0].message)
    for error in errors:
        leaf = str(list(error.absolute_path)[-1]) if error.absolute_path else ""
        if error.validator == "pattern" and leaf.endswith("_id"):
            raise VerificationFailure("invalid_identity", error.message)
    raise VerificationFailure("schema_validation", errors[0].message)


def execute_contract_case(fixture: LoadedFixture, case: dict[str, Any]) -> list[dict[str, Any]]:
    input_path = case["input"]["relative_path"]
    spec = parse_json_bytes(
        fixture.read_fixture_file(input_path), max_depth=fixture.max_document_depth
    )
    if case["case_kind"] == "json_instance":
        document = spec
        source_name = Path(input_path).name
        mutation_spec: dict[str, Any] = {}
    elif case["case_kind"] == "json_mutation":
        if "migration" in spec:
            source_path = spec.get("source")
            if not (
                spec.get("migration") == "named_1.0_to_1.1"
                and spec.get("source_version") == "1.0.0"
                and spec.get("reader_version") == "1.1.0"
                and spec.get("representable") is True
                and isinstance(source_path, str)
            ):
                raise VerificationFailure(
                    "unsupported_contract_version",
                    "conversion is not exactly representable",
                )
            source = parse_json_bytes(
                fixture.read_fixture_file(source_path),
                max_depth=fixture.max_document_depth,
            )
            if not isinstance(source, dict):
                raise VerificationFailure(
                    "schema_validation", "migration source must be a CON-001 object"
                )
            _validate_version(source)
            _validate_authority(source)
            _walk(source)
            _validate_schema(fixture, "docs/contracts/frame-packet.schema.json", source)
            return []
        base_path = spec.get("base")
        if not isinstance(base_path, str):
            raise VerificationFailure("semantic_invariant", "mutation has no base document")
        base = parse_json_bytes(
            fixture.read_fixture_file(base_path), max_depth=fixture.max_document_depth
        )
        document = _apply_mutations(base, spec.get("mutations", []))
        source_name = Path(base_path).name
        mutation_spec = spec
    else:
        raise VerificationFailure("semantic_invariant", "unknown contract case kind")

    _validate_version(document)
    _validate_authority(document)
    _walk(document)
    payload_hex = mutation_spec.get("payload")
    if payload_hex is not None:
        try:
            payload = bytes.fromhex(payload_hex)
        except ValueError as error:
            raise VerificationFailure("json_parse", "payload is not hex") from error
        import hashlib

        if document.get("payload_sha256") != hashlib.sha256(payload).hexdigest():
            raise VerificationFailure("digest_mismatch", "payload digest mismatch")
    _validate_schema(fixture, _schema_for_name(source_name), document)
    return []
