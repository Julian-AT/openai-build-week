#!/usr/bin/env python3
"""Fail-closed integrity and normalized-result comparator for Phase 01 fixtures."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Sequence

from jsonschema import Draft202012Validator


MAX_JSON_BYTES = 33_554_432
MAX_DEPTH = 64
REGISTERED_SCHEMAS = {
    "CON-001": ("urn:reroom:schema:frame-packet:1", "docs/contracts/frame-packet.schema.json"),
    "CON-002": ("urn:reroom:schema:rrcap-manifest:1", "docs/contracts/rrcap-manifest.schema.json"),
    "CON-003": ("urn:reroom:schema:scene-state:1", "docs/contracts/scene-state.schema.json"),
    "CON-004": ("urn:reroom:schema:edit-artifacts:1", "docs/contracts/edit-artifacts.schema.json"),
    "CON-005": ("urn:reroom:schema:transaction:1", "docs/contracts/transaction.schema.json"),
}


class ComparisonError(RuntimeError):
    """A deterministic, sanitized verification failure."""


@dataclass(frozen=True)
class VerifiedFixture:
    fixture_id: str
    fixture_revision: str
    manifest_sha256: str
    manifest: dict[str, Any]


def _duplicate_rejector(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise ComparisonError("json_duplicate_name")
        value[key] = item
    return value


def _depth(value: Any) -> int:
    maximum = 0
    stack = [(value, 1)]
    while stack:
        current, level = stack.pop()
        maximum = max(maximum, level)
        if maximum > MAX_DEPTH:
            return maximum
        if isinstance(current, dict):
            stack.extend((item, level + 1) for item in current.values())
        elif isinstance(current, list):
            stack.extend((item, level + 1) for item in current)
    return maximum


def _read_bytes(path: Path, mismatch: str, limit: int = MAX_JSON_BYTES) -> bytes:
    try:
        size = path.stat().st_size
    except (OSError, ValueError) as error:
        raise ComparisonError(f"{mismatch}:missing") from error
    if size > limit:
        raise ComparisonError(f"{mismatch}:size_limit")
    try:
        data = path.read_bytes()
    except OSError as error:
        raise ComparisonError(f"{mismatch}:unreadable") from error
    if len(data) != size:
        raise ComparisonError(f"{mismatch}:changed_during_read")
    return data


def _read_json(path: Path, mismatch: str) -> tuple[dict[str, Any], bytes]:
    data = _read_bytes(path, mismatch)
    try:
        value = json.loads(data, object_pairs_hook=_duplicate_rejector)
    except ComparisonError:
        raise
    except (UnicodeDecodeError, json.JSONDecodeError, RecursionError) as error:
        raise ComparisonError(f"{mismatch}:malformed_json") from error
    if not isinstance(value, dict):
        raise ComparisonError(f"{mismatch}:root_type")
    if _depth(value) > MAX_DEPTH:
        raise ComparisonError(f"{mismatch}:depth_limit")
    return value, data


def _schema_validate(value: Any, schema_path: Path, mismatch: str) -> None:
    schema, _ = _read_json(schema_path, f"{mismatch}_schema")
    errors = sorted(Draft202012Validator(schema).iter_errors(value), key=lambda item: tuple(str(part) for part in item.absolute_path))
    if errors:
        location = ".".join(str(part) for part in errors[0].absolute_path) or "root"
        raise ComparisonError(f"{mismatch}:{location}")


def _contained(base: Path, relative_path: str, mismatch: str) -> Path:
    try:
        candidate = (base / relative_path).resolve(strict=True)
        candidate.relative_to(base.resolve(strict=True))
    except (OSError, ValueError) as error:
        raise ComparisonError(f"{mismatch}:invalid_path") from error
    return candidate


def _verify_file(base: Path, reference: dict[str, Any], prefix: str) -> None:
    path = _contained(base, reference["relative_path"], prefix)
    data = _read_bytes(path, prefix, int(reference["byte_length"]) + 1)
    if len(data) != reference["byte_length"]:
        raise ComparisonError(f"{prefix}_byte_length")
    if hashlib.sha256(data).hexdigest() != reference["sha256"]:
        raise ComparisonError(f"{prefix}_sha256")


def verify_fixture(manifest_path: Path | str, *, repo_root: Path | str | None = None) -> VerifiedFixture:
    manifest_path = Path(manifest_path).resolve()
    root = Path(repo_root).resolve() if repo_root is not None else Path(__file__).resolve().parents[2]
    manifest, raw = _read_json(manifest_path, "manifest")
    _schema_validate(manifest, root / "fixtures/manifest.schema.json", "manifest_schema")

    case_ids = [case["case_id"] for case in manifest["cases"]]
    if len(case_ids) != len(set(case_ids)):
        raise ComparisonError("duplicate_case")
    if case_ids != sorted(case_ids):
        raise ComparisonError("case_order")

    for schema_ref in manifest["schema_hashes"]:
        registered = REGISTERED_SCHEMAS.get(schema_ref["contract_id"])
        if registered != (schema_ref["schema_id"], schema_ref["relative_path"]):
            raise ComparisonError(f"schema_tuple:{schema_ref['contract_id']}")
        schema_path = _contained(root, schema_ref["relative_path"], "schema_path")
        schema_bytes = _read_bytes(schema_path, "schema_file")
        if hashlib.sha256(schema_bytes).hexdigest() != schema_ref["sha256"]:
            raise ComparisonError(f"schema_sha256:{schema_ref['contract_id']}")
        schema_value, _ = _read_json(schema_path, "contract_schema")
        if schema_value.get("$id") != schema_ref["schema_id"]:
            raise ComparisonError(f"schema_id:{schema_ref['contract_id']}")

    fixture_root = manifest_path.parent
    for case in manifest["cases"]:
        case_id = case["case_id"]
        _verify_file(fixture_root, case["input"], f"{case_id}:input")
        for index, artifact in enumerate(case["expected"]["artifacts"]):
            _verify_file(fixture_root, artifact, f"{case_id}:artifact_{index}")

    return VerifiedFixture(
        fixture_id=manifest["fixture_id"],
        fixture_revision=manifest["fixture_revision"],
        manifest_sha256=hashlib.sha256(raw).hexdigest(),
        manifest=manifest,
    )


def _canonical_bytes(value: Any) -> bytes:
    # RunnerResultV1 contains only integers, strings, booleans, null, arrays and
    # objects. This is the RR-JCS-SHA256-1 encoding for that closed domain.
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def _case_shape_diagnostic(expected_ids: list[str], rows: Any) -> None:
    if not isinstance(rows, list) or not all(isinstance(row, dict) and isinstance(row.get("case_id"), str) for row in rows):
        return
    actual_ids = [row["case_id"] for row in rows]
    if len(actual_ids) != len(set(actual_ids)):
        raise ComparisonError("duplicate_case")
    missing = sorted(set(expected_ids) - set(actual_ids))
    extra = sorted(set(actual_ids) - set(expected_ids))
    if missing:
        raise ComparisonError(f"missing_case:{missing[0]}")
    if extra:
        raise ComparisonError(f"extra_case:{extra[0]}")
    if actual_ids != expected_ids:
        raise ComparisonError("case_order")


def _expected_artifacts(case: dict[str, Any]) -> list[dict[str, Any]]:
    keys = ("kind", "byte_length", "sha256", "value_sha256")
    return [{key: artifact[key] for key in keys if key in artifact} for artifact in case["expected"]["artifacts"]]


def _verify_result(verified: VerifiedFixture, result_path: Path, root: Path) -> tuple[str, tuple[Any, ...]]:
    result, _ = _read_json(result_path, "runner_result")
    expected_ids = [case["case_id"] for case in verified.manifest["cases"]]
    _case_shape_diagnostic(expected_ids, result.get("case_results"))
    _schema_validate(result, root / "fixtures/runner-result.schema.json", "result_schema")

    fixture = result["fixture"]
    for field, expected in (
        ("fixture_id", verified.fixture_id),
        ("fixture_revision", verified.fixture_revision),
        ("manifest_sha256", verified.manifest_sha256),
    ):
        if fixture[field] != expected:
            raise ComparisonError(field)

    rows = result["case_results"]
    consensus: list[Any] = []
    for expected_case, row in zip(verified.manifest["cases"], rows, strict=True):
        case_id = expected_case["case_id"]
        expected = expected_case["expected"]
        if row["verdict"] != expected["verdict"]:
            raise ComparisonError(f"{case_id}:verdict")
        if row["rejection_class"] != expected["rejection_class"]:
            raise ComparisonError(f"{case_id}:rejection_class")
        expected_artifacts = _expected_artifacts(expected_case)
        actual_artifacts = row["output_artifacts"]
        if len(actual_artifacts) != len(expected_artifacts):
            raise ComparisonError(f"{case_id}:artifact_count")
        for index, (actual, oracle) in enumerate(zip(actual_artifacts, expected_artifacts, strict=True)):
            for field in ("kind", "byte_length", "sha256", "value_sha256"):
                if actual.get(field) != oracle.get(field):
                    raise ComparisonError(f"{case_id}:artifact_{field}")
        consensus.append((case_id, row["verdict"], row["rejection_class"], actual_artifacts))

    accepted = sum(row["verdict"] == "accept" for row in rows)
    expected_summary = {"total": len(rows), "accepted": accepted, "rejected": len(rows) - accepted}
    if result["summary"] != expected_summary:
        raise ComparisonError("summary")

    unsigned = {key: value for key, value in result.items() if key != "result_digest_sha256"}
    digest = hashlib.sha256(_canonical_bytes(unsigned)).hexdigest()
    if result["result_digest_sha256"] != digest:
        raise ComparisonError("result_digest_sha256")
    return result["runner"]["runtime"], tuple(consensus)


def compare_runner_results(
    manifest_path: Path | str,
    result_paths: Sequence[Path | str],
    *,
    repo_root: Path | str | None = None,
    required_runtimes: Iterable[str] = (),
) -> tuple[str, ...]:
    root = Path(repo_root).resolve() if repo_root is not None else Path(__file__).resolve().parents[2]
    verified = verify_fixture(manifest_path, repo_root=root)
    if not result_paths:
        raise ComparisonError("missing_result")
    results: dict[str, tuple[Any, ...]] = {}
    for result_path in result_paths:
        runtime, consensus = _verify_result(verified, Path(result_path), root)
        if runtime in results:
            raise ComparisonError(f"duplicate_runtime:{runtime}")
        results[runtime] = consensus
    missing = sorted(set(required_runtimes) - set(results))
    if missing:
        raise ComparisonError(f"missing_runtime:{missing[0]}")
    consensus_values = list(results.values())
    if any(value != consensus_values[0] for value in consensus_values[1:]):
        raise ComparisonError("runner_disagreement")
    return tuple(sorted(results))


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    integrity = subparsers.add_parser("fixture-integrity")
    integrity.add_argument("--manifest", action="append", required=True, type=Path)
    compare = subparsers.add_parser("compare")
    compare.add_argument("--manifest", required=True, type=Path)
    compare.add_argument("--result", action="append", required=True, type=Path)
    compare.add_argument("--require-runtime", action="append", default=[])
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.command == "fixture-integrity":
            for manifest in args.manifest:
                verify_fixture(manifest)
            print(f"fixture-integrity: PASS ({len(args.manifest)} manifests)")
        else:
            runtimes = compare_runner_results(args.manifest, args.result, required_runtimes=args.require_runtime)
            print(f"compare: PASS ({','.join(runtimes)})")
    except ComparisonError as error:
        print(f"compare: FAIL ({error})", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
