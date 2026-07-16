"""RR-JCS-SHA256-1 canonical JSON and digest helpers."""

from __future__ import annotations

import hashlib
from typing import Any

import rfc8785

from .loader import LoadedFixture, VerificationFailure, parse_json_bytes, sha256_bytes


def canonical_bytes(value: Any) -> bytes:
    try:
        return rfc8785.dumps(value)
    except rfc8785.FloatDomainError as error:
        raise VerificationFailure("numeric_out_of_range", "number is outside JCS domain") from error
    except rfc8785.IntegerDomainError as error:
        raise VerificationFailure("numeric_out_of_range", "integer is outside JCS domain") from error
    except rfc8785.CanonicalizationError as error:
        raise VerificationFailure("invalid_unicode", "value is outside JCS domain") from error


def digest_sha256(value: Any) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def artifact(kind: str, raw: bytes, *, value_sha256: str | None = None) -> dict[str, Any]:
    result: dict[str, Any] = {
        "kind": kind,
        "byte_length": len(raw),
        "sha256": sha256_bytes(raw),
    }
    if value_sha256 is not None:
        result["value_sha256"] = value_sha256
    return result


def execute_jcs_case(fixture: LoadedFixture, case: dict[str, Any]) -> list[dict[str, Any]]:
    raw = fixture.read_fixture_file(case["input"]["relative_path"])
    value = parse_json_bytes(raw, max_depth=fixture.max_document_depth)
    canonical = canonical_bytes(value)
    digest = hashlib.sha256(canonical).hexdigest()
    return [
        artifact("canonical_bytes", canonical),
        artifact("digest", (digest + "\n").encode("ascii"), value_sha256=digest),
    ]
