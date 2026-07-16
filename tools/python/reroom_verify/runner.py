"""Normalized, bounded Python reference runner."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator, FormatChecker

from .canonical_json import digest_sha256, execute_jcs_case
from .loader import LoadedFixture, VerificationFailure, load_fixture, parse_json_bytes
from .schema_validator import execute_contract_case
from .wire_frame import execute_wire_case


RUNNER_NAME = "reroom-python-reference"
RUNNER_VERSION = "1.0.0"


def _execute(fixture: LoadedFixture, case: dict[str, Any]) -> list[dict[str, Any]]:
    case_kind = case["case_kind"]
    if case_kind in {"json_instance", "json_mutation"}:
        return execute_contract_case(fixture, case)
    if case_kind in {"raw_json", "digest_scope"}:
        return execute_jcs_case(fixture, case)
    if case_kind in {"wire_bytes", "wire_mutation"}:
        return execute_wire_case(fixture, case)
    raise VerificationFailure("semantic_invariant", f"unknown case kind: {case_kind}")


def _row(fixture: LoadedFixture, case: dict[str, Any]) -> dict[str, Any]:
    try:
        artifacts = _execute(fixture, case)
    except VerificationFailure as error:
        return {
            "case_id": case["case_id"],
            "verdict": "reject",
            "rejection_class": error.rejection_class,
            "output_artifacts": [],
        }
    return {
        "case_id": case["case_id"],
        "verdict": "accept",
        "rejection_class": None,
        "output_artifacts": artifacts,
    }


def evaluate_case(
    manifest_path: Path | str,
    case_id: str,
    *,
    repo_root: Path | str,
) -> dict[str, Any]:
    fixture = load_fixture(manifest_path, repo_root=repo_root)
    matches = [case for case in fixture.manifest["cases"] if case["case_id"] == case_id]
    if len(matches) != 1:
        raise VerificationFailure("semantic_invariant", "case id is absent or duplicated")
    return _row(fixture, matches[0])


def _validate_result(repo_root: Path, result: dict[str, Any]) -> None:
    result_schema = parse_json_bytes((repo_root / "fixtures/runner-result.schema.json").read_bytes())
    Draft202012Validator.check_schema(result_schema)
    errors = list(
        Draft202012Validator(result_schema, format_checker=FormatChecker()).iter_errors(result)
    )
    if errors:
        raise VerificationFailure("schema_validation", errors[0].message)
    rows = result["case_results"]
    if [row["case_id"] for row in rows] != sorted(row["case_id"] for row in rows):
        raise VerificationFailure("semantic_invariant", "result rows are not ordered")
    if len({row["case_id"] for row in rows}) != len(rows):
        raise VerificationFailure("semantic_invariant", "result has duplicate case rows")
    accepted = sum(row["verdict"] == "accept" for row in rows)
    summary = result["summary"]
    if summary != {
        "total": len(rows),
        "accepted": accepted,
        "rejected": len(rows) - accepted,
    }:
        raise VerificationFailure("semantic_invariant", "result summary disagrees with rows")


def run_fixture(
    manifest_path: Path | str,
    *,
    repo_root: Path | str,
    implementation_revision: str,
) -> dict[str, Any]:
    if not re.fullmatch(r"git:[0-9a-f]{40}", implementation_revision):
        raise VerificationFailure("semantic_invariant", "invalid implementation revision")
    fixture = load_fixture(manifest_path, repo_root=repo_root)
    rows = [_row(fixture, case) for case in fixture.manifest["cases"]]
    accepted = sum(row["verdict"] == "accept" for row in rows)
    result: dict[str, Any] = {
        "schema_version": "1.0.0",
        "runner": {
            "runtime": "python",
            "name": RUNNER_NAME,
            "version": RUNNER_VERSION,
            "implementation_revision": implementation_revision,
        },
        "fixture": {
            "fixture_id": fixture.manifest["fixture_id"],
            "fixture_revision": fixture.manifest["fixture_revision"],
            "manifest_sha256": fixture.manifest_sha256,
        },
        "case_order": "lexicographic_case_id",
        "case_results": rows,
        "summary": {
            "total": len(rows),
            "accepted": accepted,
            "rejected": len(rows) - accepted,
        },
        "oracle_unchanged": True,
        "result_digest_algorithm": "RR-JCS-SHA256-1",
        "result_digest_scope": "entire_runner_result_with_result_digest_sha256_omitted",
    }
    result["result_digest_sha256"] = digest_sha256(result)
    _validate_result(fixture.repo_root, result)
    return result


def _git_revision(repo_root: Path) -> str:
    completed = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=repo_root,
        check=True,
        capture_output=True,
        text=True,
    )
    revision = completed.stdout.strip()
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise VerificationFailure("semantic_invariant", "git returned an invalid revision")
    return "git:" + revision


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--implementation-revision")
    arguments = parser.parse_args(argv)
    repo_root = arguments.repo_root.resolve(strict=True)
    revision = arguments.implementation_revision or _git_revision(repo_root)
    result = run_fixture(
        arguments.manifest,
        repo_root=repo_root,
        implementation_revision=revision,
    )
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":"), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
