#!/usr/bin/env python3
"""Fail-closed fixture verifier and exact three-runtime ReplayReport comparator."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Sequence

from jsonschema import Draft202012Validator


MAXIMUM_JSON_BYTES = 33_554_432
MAXIMUM_DEPTH = 64
PINNED_FIXTURE_SHA256 = "3b4519d2730e158df73e938f7b841664c6ce5f7d65ed2650c90ca8e89c7a7610"
PINNED_REPORT_SCHEMA_SHA256 = "821784ce1a3e4f45c2fe4db70f8f16643284f2e3e9f6effe85a7aee3e17bb9a9"
REPORT_SUFFIX = ".replay-report.json"
DIGEST = re.compile(r"[0-9a-f]{64}")
RUNTIME_IDENTITIES = {
    "swift": {
        "evaluator": {"name": "ReRoomReplayCore", "platform": "swift", "version": "1.0.0"},
        "runtime": "swift",
        "build_id": "ReRoomReplayCore-1.0.0",
    },
    "node": {
        "evaluator": {"name": "ReRoomReplayNode", "platform": "javascript", "version": "1.0.0"},
        "runtime": "node-v22.22.3",
        "build_id": "ReRoomReplayNode-1.0.0",
    },
    "python": {
        "evaluator": {"name": "ReRoomReplayPython", "platform": "python", "version": "1.0.0"},
        "runtime": "python-3.13.12",
        "build_id": "ReRoomReplayPython-1.0.0",
    },
}


class ReplayComparisonError(RuntimeError):
    """A stable, sanitized replay comparison failure."""


@dataclass(frozen=True)
class VerifiedFixture:
    manifest: dict[str, Any]
    manifest_sha256: str
    root: Path
    case_ids: tuple[str, ...]


@dataclass(frozen=True)
class RuntimeOutput:
    runtime: str
    directory_sha256: str
    byte_length: int
    report_count: int
    cases: tuple[tuple[str, str, str | None, str], ...]


@dataclass(frozen=True)
class AgreedCase:
    case_id: str
    verdict: str
    rejection_class: str | None
    artifact_sha256: str


@dataclass(frozen=True)
class ReplayAgreement:
    runtimes: tuple[str, ...]
    cases: tuple[AgreedCase, ...]
    outputs: tuple[RuntimeOutput, ...]
    missing_cases: int = 0
    extra_cases: int = 0
    semantic_disagreements: int = 0


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_bytes(value: Any) -> bytes:
    """RR-JCS-SHA256-1 bytes for ReplayReport's closed integer/string domain."""

    try:
        return json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError, UnicodeEncodeError) as error:
        raise ReplayComparisonError("canonical_json") from error


def _duplicate_rejector(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ReplayComparisonError("json_duplicate_name")
        result[key] = value
    return result


def _validate_strings(value: Any) -> None:
    stack = [(value, 1)]
    while stack:
        current, depth = stack.pop()
        if depth > MAXIMUM_DEPTH:
            raise ReplayComparisonError("json_depth_limit")
        if isinstance(current, str):
            if any(0xD800 <= ord(character) <= 0xDFFF for character in current):
                raise ReplayComparisonError("json_invalid_unicode")
        elif isinstance(current, dict):
            for key, item in current.items():
                _validate_strings(key)
                stack.append((item, depth + 1))
        elif isinstance(current, list):
            stack.extend((item, depth + 1) for item in current)


def _regular_bytes(path: Path, mismatch: str, maximum: int = MAXIMUM_JSON_BYTES) -> bytes:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise ReplayComparisonError(f"{mismatch}:missing") from error
    if not stat.S_ISREG(metadata.st_mode) or path.is_symlink():
        raise ReplayComparisonError(f"{mismatch}:not_regular")
    if not (0 < metadata.st_size <= maximum):
        raise ReplayComparisonError(f"{mismatch}:size_limit")
    try:
        data = path.read_bytes()
    except OSError as error:
        raise ReplayComparisonError(f"{mismatch}:unreadable") from error
    if len(data) != metadata.st_size:
        raise ReplayComparisonError(f"{mismatch}:changed_during_read")
    return data


def _read_json(path: Path, mismatch: str) -> tuple[dict[str, Any], bytes]:
    raw = _regular_bytes(path, mismatch)
    try:
        value = json.loads(raw, object_pairs_hook=_duplicate_rejector)
    except ReplayComparisonError:
        raise
    except (UnicodeDecodeError, json.JSONDecodeError, RecursionError) as error:
        raise ReplayComparisonError(f"{mismatch}:malformed_json") from error
    if not isinstance(value, dict):
        raise ReplayComparisonError(f"{mismatch}:root_type")
    _validate_strings(value)
    return value, raw


def _safe_existing(root: Path, relative: str, expected: str, mismatch: str) -> Path:
    if (
        not isinstance(relative, str)
        or not relative
        or relative.startswith("/")
        or "\\" in relative
        or any(part in {"", ".", ".."} for part in relative.split("/"))
    ):
        raise ReplayComparisonError(f"{mismatch}:invalid_path")
    candidate = root
    for component in relative.split("/"):
        candidate = candidate / component
        try:
            mode = candidate.lstat().st_mode
        except OSError as error:
            raise ReplayComparisonError(f"{mismatch}:missing") from error
        if candidate.is_symlink():
            raise ReplayComparisonError(f"{mismatch}:symlink")
    if (expected == "file" and not stat.S_ISREG(mode)) or (
        expected == "directory" and not stat.S_ISDIR(mode)
    ):
        raise ReplayComparisonError(f"{mismatch}:wrong_type")
    return candidate


def _all_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for current, directories, names in os.walk(root, topdown=True, followlinks=False):
        base = Path(current)
        directories.sort()
        names.sort()
        for name in directories:
            path = base / name
            if path.is_symlink() or not stat.S_ISDIR(path.lstat().st_mode):
                raise ReplayComparisonError("fixture_inventory:non_regular")
        for name in names:
            path = base / name
            if path.is_symlink() or not stat.S_ISREG(path.lstat().st_mode):
                raise ReplayComparisonError("fixture_inventory:non_regular")
            files.append(path)
    return sorted(files)


def _schema_validate(value: dict[str, Any], schema_path: Path, mismatch: str) -> None:
    schema, _ = _read_json(schema_path, f"{mismatch}_schema")
    errors = sorted(
        Draft202012Validator(schema).iter_errors(value),
        key=lambda item: tuple(str(part) for part in item.absolute_path),
    )
    if errors:
        location = ".".join(str(part) for part in errors[0].absolute_path) or "root"
        raise ReplayComparisonError(f"{mismatch}:{location}")


def verify_fixture_integrity(
    manifest_path: Path | str, *, repo_root: Path | str | None = None
) -> VerifiedFixture:
    root = Path(repo_root).resolve() if repo_root is not None else Path(__file__).resolve().parents[2]
    manifest_path = Path(manifest_path).resolve()
    manifest, raw = _read_json(manifest_path, "fixture_manifest")
    if _sha256(raw) != PINNED_FIXTURE_SHA256:
        raise ReplayComparisonError("fixture_manifest_sha256")
    if (
        manifest.get("fixture_id") != "FX-CAPTURE-001"
        or manifest.get("fixture_revision") != "rev-001"
        or not isinstance(manifest.get("files"), list)
        or not isinstance(manifest.get("directories"), list)
    ):
        raise ReplayComparisonError("fixture_manifest_identity")
    fixture_root = manifest_path.parent
    expected_paths: list[str] = []
    for entry in manifest["files"]:
        if not isinstance(entry, dict) or set(entry) != {"relative_path", "byte_length", "sha256"}:
            raise ReplayComparisonError("fixture_file_binding")
        relative = entry["relative_path"]
        path = _safe_existing(fixture_root, relative, "file", "fixture_file")
        data = _regular_bytes(path, "fixture_file", int(entry["byte_length"]) + 1)
        if len(data) != entry["byte_length"]:
            raise ReplayComparisonError("fixture_file_byte_length")
        if _sha256(data) != entry["sha256"]:
            raise ReplayComparisonError("fixture_file_sha256")
        expected_paths.append(relative)
    if expected_paths != sorted(expected_paths) or len(expected_paths) != len(set(expected_paths)):
        raise ReplayComparisonError("fixture_file_order")
    archives = _safe_existing(fixture_root, "archives", "directory", "fixture_archives")
    physical = [path.relative_to(fixture_root).as_posix() for path in _all_files(archives)]
    if physical != expected_paths:
        raise ReplayComparisonError("fixture_inventory_membership")
    for entry in manifest["directories"]:
        if not isinstance(entry, dict) or set(entry) != {
            "relative_path", "byte_length", "file_count", "tree_sha256"
        }:
            raise ReplayComparisonError("fixture_directory_binding")
        directory = _safe_existing(
            fixture_root, entry["relative_path"], "directory", "fixture_directory"
        )
        bindings = []
        for path in _all_files(directory):
            data = _regular_bytes(path, "fixture_directory_file")
            bindings.append(
                {
                    "relative_path": path.relative_to(fixture_root).as_posix(),
                    "byte_length": len(data),
                    "sha256": _sha256(data),
                }
            )
        if len(bindings) != entry["file_count"]:
            raise ReplayComparisonError("fixture_directory_file_count")
        if sum(binding["byte_length"] for binding in bindings) != entry["byte_length"]:
            raise ReplayComparisonError("fixture_directory_byte_length")
        if _sha256(canonical_bytes(bindings)) != entry["tree_sha256"]:
            raise ReplayComparisonError("fixture_directory_tree_sha256")
    archives_by_name = {item["archive_name"]: item for item in manifest["archives"]}
    case_ids = sorted(
        [f"archive.{name[:-len('.rrcap')]}" for name in archives_by_name]
        + [item["case_id"] for item in manifest["edge_probes"]]
        + ["sec-consent.denied"]
    )
    if len(case_ids) != 16 or len(case_ids) != len(set(case_ids)):
        raise ReplayComparisonError("fixture_case_set")
    schema_ref = manifest.get("report_schema")
    if not isinstance(schema_ref, dict) or schema_ref.get("sha256") != PINNED_REPORT_SCHEMA_SHA256:
        raise ReplayComparisonError("report_schema_binding")
    schema_path = _safe_existing(root, schema_ref["relative_path"], "file", "report_schema")
    schema_raw = _regular_bytes(schema_path, "report_schema", int(schema_ref["byte_length"]) + 1)
    if len(schema_raw) != schema_ref["byte_length"] or _sha256(schema_raw) != PINNED_REPORT_SCHEMA_SHA256:
        raise ReplayComparisonError("report_schema_sha256")
    return VerifiedFixture(manifest, PINNED_FIXTURE_SHA256, fixture_root, tuple(case_ids))


def _snapshot_descriptor(fixture: VerifiedFixture, case_id: str) -> tuple[dict[str, Any], str, str | None]:
    manifest = fixture.manifest
    archives = {entry["archive_name"]: entry for entry in manifest["archives"]}
    if case_id.startswith("archive."):
        archive_name = case_id[len("archive."):] + ".rrcap"
        descriptor = archives[archive_name]
        return descriptor, descriptor["expected"]["verdict"], descriptor["expected"]["rejection_class"]
    if case_id == "sec-consent.denied":
        consent = manifest["consent_denied_case"]
        return archives["finalized-empty.rrcap"], consent["expected_verdict"], consent["rejection_class"]
    probe = next(item for item in manifest["edge_probes"] if item["case_id"] == case_id)
    baseline = "finalized-empty.rrcap" if case_id == "fr-b0.empty" else "finalized-one-frame.rrcap"
    return archives[baseline], probe["expected"]["verdict"], probe["expected"]["rejection_class"]


def _verify_oracle(
    fixture: VerifiedFixture, runtime: str, case_id: str, report: dict[str, Any]
) -> None:
    descriptor, verdict, rejection_class = _snapshot_descriptor(fixture, case_id)
    expected = descriptor["expected"]
    if report["verdict"] != verdict:
        raise ReplayComparisonError(f"oracle_mismatch:{runtime}:{case_id}:verdict")
    actual_rejection = report["rejection"]
    actual_class = None if actual_rejection is None else actual_rejection["rejection_class"]
    if actual_class != rejection_class:
        raise ReplayComparisonError(f"oracle_mismatch:{runtime}:{case_id}:rejection_class")
    if actual_rejection is not None and actual_rejection["detail"] != f"frozen fixture expected {rejection_class}":
        raise ReplayComparisonError(f"oracle_mismatch:{runtime}:{case_id}:rejection_detail")
    archive = report["archive"]
    expected_archive = {
        "case_id": case_id,
        "archive_name": descriptor["archive_name"],
        "finalization_state": expected["finalization_state"],
        "manifest_sha256": json.loads(
            (fixture.root / descriptor["directory"]["relative_path"] / "manifest.json").read_bytes()
        )["finalization"]["manifest_sha256"],
        "accepted_frame_count": expected["accepted_frame_count"],
        "event_count": expected["event_count"],
        "journal_record_count": expected["journal_record_count"],
    }
    if archive != expected_archive:
        raise ReplayComparisonError(f"oracle_mismatch:{runtime}:{case_id}:archive")
    expected_digests = {
        "journal_tuple_sha256": expected["journal_tuple_sha256"],
        "frame_projection_sha256": expected["frame_projection_sha256"],
        "event_projection_sha256": expected["event_projection_sha256"],
        "revision_trace_sha256": expected["revision_trace_sha256"],
    }
    if report["digests"] != expected_digests:
        raise ReplayComparisonError(f"oracle_mismatch:{runtime}:{case_id}:digests")


def _verify_runtime_output(
    fixture: VerifiedFixture,
    runtime: str,
    report_root: Path,
    repository_root: Path,
    implementation_revision: str,
) -> RuntimeOutput:
    if runtime not in RUNTIME_IDENTITIES:
        raise ReplayComparisonError(f"runtime_identity:{runtime}")
    try:
        mode = report_root.lstat().st_mode
    except OSError as error:
        raise ReplayComparisonError(f"missing_runtime:{runtime}") from error
    if not stat.S_ISDIR(mode) or report_root.is_symlink():
        raise ReplayComparisonError(f"runtime_root:{runtime}")
    paths = sorted(report_root.iterdir(), key=lambda path: path.name)
    for path in paths:
        if path.is_symlink() or not stat.S_ISREG(path.lstat().st_mode):
            raise ReplayComparisonError(f"runtime_member:{runtime}")
    actual_names = [path.name for path in paths]
    expected_names = [f"{case_id}{REPORT_SUFFIX}" for case_id in fixture.case_ids]
    missing = sorted(set(expected_names) - set(actual_names))
    extra = sorted(set(actual_names) - set(expected_names))
    if missing:
        raise ReplayComparisonError(f"missing_case:{runtime}:{missing[0][:-len(REPORT_SUFFIX)]}")
    if extra:
        name = extra[0]
        case_id = name[:-len(REPORT_SUFFIX)] if name.endswith(REPORT_SUFFIX) else name
        raise ReplayComparisonError(f"extra_case:{runtime}:{case_id}")
    if actual_names != expected_names:
        raise ReplayComparisonError(f"case_order:{runtime}")
    identity = RUNTIME_IDENTITIES[runtime]
    cases: list[tuple[str, str, str | None, str]] = []
    directory_scope = bytearray()
    total_bytes = 0
    schema_path = repository_root / "fixtures/replay-report.schema.json"
    for case_id, path in zip(fixture.case_ids, paths, strict=True):
        report, raw = _read_json(path, f"report:{runtime}:{case_id}")
        _schema_validate(report, schema_path, f"report_schema:{runtime}:{case_id}")
        if raw != canonical_bytes(report):
            raise ReplayComparisonError(f"report_encoding:{runtime}:{case_id}")
        if report["archive"]["case_id"] != case_id:
            raise ReplayComparisonError(f"case_identity:{runtime}:{case_id}")
        if report["fixture"] != {
            "fixture_id": "FX-CAPTURE-001",
            "fixture_revision": "rev-001",
            "manifest_sha256": fixture.manifest_sha256,
        }:
            raise ReplayComparisonError(f"fixture_identity:{runtime}:{case_id}")
        implementation = report["implementation"]
        if implementation["repository_revision"] != implementation_revision:
            raise ReplayComparisonError(f"stale_result:{runtime}:{case_id}")
        if (
            report["evaluator"] != identity["evaluator"]
            or implementation["runtime"] != identity["runtime"]
            or implementation["build_id"] != identity["build_id"]
        ):
            raise ReplayComparisonError(f"runtime_identity:{runtime}:{case_id}")
        unsigned = dict(report)
        del unsigned["report_sha256"]
        if report["report_sha256"] != _sha256(canonical_bytes(unsigned)):
            raise ReplayComparisonError(f"report_digest:{runtime}:{case_id}")
        _verify_oracle(fixture, runtime, case_id, report)
        normalized = {
            key: value
            for key, value in report.items()
            if key not in {"evaluator", "implementation", "report_sha256"}
        }
        artifact_sha256 = _sha256(canonical_bytes(normalized))
        rejection_class = None if report["rejection"] is None else report["rejection"]["rejection_class"]
        cases.append((case_id, report["verdict"], rejection_class, artifact_sha256))
        raw_sha = _sha256(raw)
        directory_scope.extend(f"{path.name}\0{raw_sha}\n".encode("utf-8"))
        total_bytes += len(raw)
    return RuntimeOutput(
        runtime,
        _sha256(bytes(directory_scope)),
        total_bytes,
        len(cases),
        tuple(cases),
    )


def compare_replay_reports(
    manifest_path: Path | str,
    report_roots: Mapping[str, Path | str],
    *,
    repo_root: Path | str | None = None,
    implementation_revision: str,
) -> ReplayAgreement:
    root = Path(repo_root).resolve() if repo_root is not None else Path(__file__).resolve().parents[2]
    fixture = verify_fixture_integrity(manifest_path, repo_root=root)
    if tuple(report_roots) != tuple(RUNTIME_IDENTITIES):
        missing = sorted(set(RUNTIME_IDENTITIES) - set(report_roots))
        extra = sorted(set(report_roots) - set(RUNTIME_IDENTITIES))
        if missing:
            raise ReplayComparisonError(f"missing_runtime:{missing[0]}")
        if extra:
            raise ReplayComparisonError(f"extra_runtime:{extra[0]}")
        raise ReplayComparisonError("runtime_order")
    outputs = tuple(
        _verify_runtime_output(
            fixture,
            runtime,
            Path(report_roots[runtime]),
            root,
            implementation_revision,
        )
        for runtime in RUNTIME_IDENTITIES
    )
    baseline = outputs[0].cases
    for output in outputs[1:]:
        for left, right in zip(baseline, output.cases, strict=True):
            if left != right:
                raise ReplayComparisonError(f"semantic_disagreement:{output.runtime}:{right[0]}")
    cases = tuple(AgreedCase(*case) for case in baseline)
    return ReplayAgreement(tuple(RUNTIME_IDENTITIES), cases, outputs)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--implementation-revision", required=True)
    for runtime in RUNTIME_IDENTITIES:
        parser.add_argument(f"--{runtime}-root", required=True, type=Path)
    return parser


def main(arguments: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(arguments)
    try:
        result = compare_replay_reports(
            args.manifest,
            {runtime: getattr(args, f"{runtime}_root") for runtime in RUNTIME_IDENTITIES},
            repo_root=args.repo_root,
            implementation_revision=args.implementation_revision,
        )
    except ReplayComparisonError as error:
        print(f"replay-comparison: FAIL ({error})", file=sys.stderr)
        return 1
    print(f"replay-comparison: PASS ({len(result.cases)} cases)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
