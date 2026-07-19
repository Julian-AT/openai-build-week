#!/usr/bin/env python3
"""Generate or verify narrow exact-source Phase 02.1 automated evidence."""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Iterator, Sequence


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / "evidence/capture/phase-02/trust-boundary-closure.json"
FIXTURE_ROOT = "fixtures/capture/1.0.0/rev-001"
PHASE_SOURCE_BASE = "766577c72732e03ab0f3aeeecad430b7020ac340"
MAX_CAPTURED_OUTPUT_BYTES = 1_048_576

CANDIDATE_FINDING_IDS = ("CR-03", "CR-04", "CR-12")
REMAINING_FINDING_IDS = (
    "CR-01",
    "CR-02",
    "CR-05",
    "CR-06",
    "CR-07",
    "CR-08",
    "CR-09",
    "CR-10",
    "CR-11",
    "WR-01",
    "WR-02",
    "WR-03",
    "WR-04",
    "WR-05",
    "WR-06",
    "WR-07",
    "WR-08",
)

BEHAVIOR_SOURCE_PATHS = (
    "ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/ArchiveVerifier.swift",
    "ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureFileSystem.swift",
    "ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/CaptureRecovery.swift",
    "ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/DurablePrefixReconstructor.swift",
    "ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/RecoveryPublication.swift",
    "ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/ReplayCore.swift",
    "ios/Packages/ReRoomContracts/Sources/ReRoomReplayRunner/main.swift",
    "ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/ArchiveVerifierTests.swift",
    "ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureCrashMatrixTests.swift",
    "ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/CaptureRecoveryTests.swift",
    "ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/RecoveryPublicationRaceTests.swift",
    "ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/RecoveryPublicationTests.swift",
    "ios/Packages/ReRoomContracts/Tests/ReRoomCaptureCoreTests/ReplayCoreTests.swift",
    "ios/Packages/ReRoomContracts/Tests/ReRoomReplayRunnerTests/ReplayRunnerTests.swift",
    "ios/ReRoomDeviceProof/ReRoomDeviceProof/CaptureSessionAdapter.swift",
    "ios/ReRoomDeviceProof/ReRoomDeviceProofTests/CaptureSessionAdapterTests.swift",
    "tools/verify/tests/test_phase_02_1_trust_boundary.py",
    "tools/verify/verify_phase_02_1_trust_boundary.py",
)
SCHEMA_PATHS = (
    "docs/contracts/frame-packet.schema.json",
    "docs/contracts/rrcap-manifest.schema.json",
    "fixtures/replay-report.schema.json",
)

PHYSICAL_NOT_RUN = "not_run_not_required_for_phase_02_1"
OUTER_STATUS = {
    "phase_2": "OPEN",
    "gate_001": "PENDING",
    "milestone_v1_0": "OPEN",
    "physical_evidence": PHYSICAL_NOT_RUN,
    "human_evidence": PHYSICAL_NOT_RUN,
}
PRIVACY_STATUS = {
    "credentials_included": False,
    "human_observations_included": False,
    "physical_observations_included": False,
    "private_host_paths_included": False,
    "raw_room_bytes_included": False,
    "signing_identity_included": False,
}
LIMITATIONS = (
    "This record is automated software evidence for review candidates CR-03, CR-04, and CR-12 only.",
    "Physical-device and human evidence were not run and are not required for Phase 02.1.",
    "Independent phase verification and code review retain closure authority.",
    "Phase 2, GATE-001, milestone v1.0, every other CR, and every WR remain open or pending.",
)
ENVIRONMENT_FIELDS = ("platform", "python", "swift", "xcode")

ACTIVE_GENERATION_INVENTORY_FORMAT: dict[str, Any] = {
    "format_id": "recovery-generation-inventory-1.0.0",
    "canonicalization": "RR-JCS-SHA256-1",
    "generation_id_scope": "entire_canonical_inventory",
    "inventory_fields": {
        "root": [
            "accepted_prefix",
            "archive",
            "format_version",
            "members",
            "quarantine",
            "source",
        ],
        "source": ["identity_sha256", "manifest_sha256", "session_id"],
        "archive": ["finalization_state", "manifest_bytes_sha256", "manifest_sha256"],
        "accepted_prefix": [
            "accepted_frame_count",
            "event_count",
            "journal_record_count",
            "journal_sha256",
            "last_durable_journal_sequence",
        ],
        "quarantine": [
            "first_invalid_journal_sequence",
            "metadata_byte_count",
            "metadata_sha256",
            "suffix_byte_count",
            "suffix_sha256",
        ],
        "member": ["byte_count", "path", "role", "sha256"],
    },
    "active_pointer_fields": [
        "format_version",
        "generation_id",
        "inventory_sha256",
        "source_identity_sha256",
    ],
    "visibility_rule": "verified_pointer_last",
}

_SHA256 = re.compile(r"^[0-9a-f]{64}$")
_REVISION = re.compile(r"^git:([0-9a-f]{40})$")
_PRIVATE_PATH = re.compile(r"(?:^|[\s\"'])(?:/Users/|/home/|[A-Za-z]:\\)")
_ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


class EvidenceVerificationError(ValueError):
    """A stable fail-closed evidence rejection."""

    def __init__(self, code: str, message: str):
        super().__init__(f"{code}: {message}")
        self.code = code


@dataclass(frozen=True)
class CommandSpec:
    check_id: str
    argv: tuple[str, ...]


def canonical_json_bytes(value: Any) -> bytes:
    try:
        return json.dumps(
            value,
            ensure_ascii=False,
            allow_nan=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
    except (TypeError, ValueError) as error:
        raise EvidenceVerificationError("INVALID_JSON", "record is not canonicalizable") from error


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _require(condition: bool, code: str, message: str) -> None:
    if not condition:
        raise EvidenceVerificationError(code, message)


def _set_digest(members: Sequence[dict[str, Any]]) -> str:
    return sha256_bytes(canonical_json_bytes(list(members)))


def _binding(path: str, reader: Callable[[str], bytes], code: str) -> dict[str, Any]:
    try:
        data = reader(path)
    except Exception as error:
        raise EvidenceVerificationError(code, f"bound file is unavailable: {path}") from error
    _require(isinstance(data, bytes), code, f"bound file is not bytes: {path}")
    return {"path": path, "byte_length": len(data), "sha256": sha256_bytes(data)}


def _bindings(
    paths: Sequence[str], reader: Callable[[str], bytes], code: str
) -> list[dict[str, Any]]:
    _require(tuple(paths) == tuple(sorted(set(paths))), code, "binding paths are not closed and lexical")
    return [_binding(path, reader, code) for path in paths]


def _format_binding(revision_reader: Callable[[str], bytes]) -> dict[str, str]:
    implementation_path = (
        "ios/Packages/ReRoomContracts/Sources/ReRoomCaptureCore/RecoveryPublication.swift"
    )
    implementation = _binding(implementation_path, revision_reader, "INVENTORY_FORMAT")
    return {
        "format_id": ACTIVE_GENERATION_INVENTORY_FORMAT["format_id"],
        "format_sha256": sha256_bytes(canonical_json_bytes(ACTIVE_GENERATION_INVENTORY_FORMAT)),
        "implementation_path": implementation_path,
        "implementation_sha256": implementation["sha256"],
    }


def command_specs(revision: str) -> tuple[CommandSpec, ...]:
    _require(re.fullmatch(r"[0-9a-f]{40}", revision) is not None, "REVISION_IMMUTABLE", "revision is not a full commit hash")
    package = "ios/Packages/ReRoomContracts"
    focused = (
        ("archive_verifier_tests", "ArchiveVerifierTests"),
        ("replay_core_tests", "ReplayCoreTests"),
        ("capture_recovery_tests", "CaptureRecoveryTests"),
        ("capture_crash_matrix_tests", "CaptureCrashMatrixTests"),
        ("recovery_publication_tests", "RecoveryPublicationTests"),
        ("recovery_publication_race_tests", "RecoveryPublicationRaceTests"),
        ("capture_core_tests", "ReRoomCaptureCoreTests"),
        ("replay_runner_tests", "ReplayRunnerTests"),
    )
    values = [
        CommandSpec(
            check_id,
            ("swift", "test", "--package-path", package, "--filter", filter_name),
        )
        for check_id, filter_name in focused
    ]
    values.extend(
        [
            CommandSpec("full_package_tests", ("swift", "test", "--package-path", package)),
            CommandSpec(
                "replay_runner_build",
                ("swift", "build", "--package-path", package, "--product", "ReRoomReplayRunner"),
            ),
            CommandSpec(
                "native_capture_adapter_tests",
                (
                    "xcodebuild",
                    "-project",
                    "ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj",
                    "-scheme",
                    "ReRoomDeviceProof",
                    "-destination",
                    "platform=iOS Simulator,name=iPhone 17",
                    "-only-testing:ReRoomDeviceProofTests/CaptureSessionAdapterTests",
                    "CODE_SIGNING_ALLOWED=NO",
                    "test",
                ),
            ),
            CommandSpec(
                "native_simulator_build",
                (
                    "xcodebuild",
                    "-project",
                    "ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj",
                    "-scheme",
                    "ReRoomDeviceProof",
                    "-destination",
                    "generic/platform=iOS Simulator",
                    "CODE_SIGNING_ALLOWED=NO",
                    "build",
                ),
            ),
            CommandSpec(
                "native_release_build",
                (
                    "xcodebuild",
                    "-project",
                    "ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj",
                    "-scheme",
                    "ReRoomDeviceProof",
                    "-configuration",
                    "Release",
                    "-destination",
                    "generic/platform=iOS Simulator",
                    "CODE_SIGNING_ALLOWED=NO",
                    "build",
                ),
            ),
            CommandSpec("release_surface", ("scripts/verify-reroom-release-surface",)),
            CommandSpec(
                "tracked_secret_scan",
                (
                    "python3",
                    "tools/verify/verify_phase_02_1_trust_boundary.py",
                    "--tracked-secret-scan",
                ),
            ),
            CommandSpec(
                "diff_check",
                (
                    "git",
                    "diff",
                    "--check",
                    PHASE_SOURCE_BASE,
                    revision,
                    "--",
                    *BEHAVIOR_SOURCE_PATHS,
                    *SCHEMA_PATHS,
                ),
            ),
        ]
    )
    return tuple(values)


REQUIRED_CHECK_IDS = tuple(
    spec.check_id for spec in command_specs("0" * 40)
)


def _bounded_output(data: bytes) -> str:
    if len(data) > MAX_CAPTURED_OUTPUT_BYTES:
        half = MAX_CAPTURED_OUTPUT_BYTES // 2
        data = data[:half] + b"\n<bounded-output-omitted>\n" + data[-half:]
    return data.decode("utf-8", errors="replace")


def _output_summary(check_id: str, output: str, exit_code: int) -> str:
    normalized = _ANSI.sub("", output).replace("\r", "\n")
    if exit_code != 0:
        return "command:failed"
    test_marker = f"{check_id}: deterministic pass"
    if test_marker in normalized:
        return "\n".join(line.strip() for line in normalized.splitlines() if line.strip())
    if check_id == "native_capture_adapter_tests":
        _require("** TEST SUCCEEDED **" in normalized, "COMMAND_OUTPUT", "native test pass marker is absent")
        count = len(re.findall(r"Test case 'CaptureSessionAdapterTests/.+?' passed", normalized))
        _require(count > 0, "COMMAND_OUTPUT", "native adapter suite ran no tests")
        return f"xcode-test:pass:passed-lines={count}"
    if check_id.endswith("_tests"):
        matches = re.findall(
            r"Test run with ([0-9]+) tests? in ([0-9]+) suites? passed after [0-9.]+ seconds",
            normalized,
        )
        if matches:
            count, suites = matches[-1]
            _require(int(count) > 0, "COMMAND_OUTPUT", f"{check_id} ran no tests")
            return f"swift-testing:pass:tests={count}:suites={suites}"
        matches = re.findall(
            r"Executed ([0-9]+) tests?, with 0 failures(?: \([0-9]+ unexpected\))? in [0-9.]+ \([0-9.]+\) seconds",
            normalized,
        )
        if matches:
            count = matches[-1]
            _require(int(count) > 0, "COMMAND_OUTPUT", f"{check_id} ran no tests")
            return f"xctest:pass:tests={count}"
        raise EvidenceVerificationError("COMMAND_OUTPUT", f"{check_id} lacks a passing test summary")
    if check_id == "replay_runner_build":
        _require(
            re.search(r"Build(?: of product '[^']+')? complete!", normalized) is not None,
            "COMMAND_OUTPUT",
            "Swift build pass marker is absent",
        )
        return "swift-build:pass"
    if check_id in {"native_simulator_build", "native_release_build"}:
        _require("** BUILD SUCCEEDED **" in normalized, "COMMAND_OUTPUT", f"{check_id} pass marker is absent")
        return "xcode-build:pass"
    if check_id == "release_surface":
        _require("release surface verification: PASS" in normalized, "COMMAND_OUTPUT", "release-surface pass marker is absent")
        return "release-surface:pass"
    if check_id == "tracked_secret_scan":
        _require("tracked secret scan: PASS" in normalized, "COMMAND_OUTPUT", "secret-scan pass marker is absent")
        return "tracked-secret-scan:pass"
    if check_id == "diff_check":
        _require(normalized.strip() == "", "COMMAND_OUTPUT", "diff check emitted output")
        return "git-diff-check:pass"
    raise EvidenceVerificationError("COMMAND_OUTPUT", f"unknown output policy: {check_id}")


def _sanitize_command_result(spec: CommandSpec, raw: Any) -> dict[str, Any]:
    _require(isinstance(raw, dict), "COMMAND_RESULT_SHAPE", f"{spec.check_id} result is not an object")
    _require(
        set(raw) == {"check_id", "argv", "exit_code", "output"},
        "COMMAND_RESULT_SHAPE",
        f"{spec.check_id} result fields are not closed",
    )
    _require(raw["check_id"] == spec.check_id, "COMMAND_INVENTORY", "command result is reordered")
    _require(raw["argv"] == list(spec.argv), "COMMAND_INVENTORY", f"{spec.check_id} argv drifted")
    _require(type(raw["exit_code"]) is int, "COMMAND_RESULT_SHAPE", f"{spec.check_id} exit code is invalid")
    _require(isinstance(raw["output"], str), "COMMAND_RESULT_SHAPE", f"{spec.check_id} output is invalid")
    _require(raw["exit_code"] == 0, "COMMAND_FAILED", f"{spec.check_id} failed")
    summary = _output_summary(spec.check_id, raw["output"], raw["exit_code"])
    return {
        "check_id": spec.check_id,
        "argv": list(spec.argv),
        "exit_code": 0,
        "status": "PASS",
        "sanitized_output_sha256": sha256_bytes(summary.encode("utf-8")),
    }


def _candidate_findings() -> list[dict[str, str]]:
    return [
        {"review_id": review_id, "status": "AUTOMATED_REVIEW_CANDIDATE"}
        for review_id in CANDIDATE_FINDING_IDS
    ]


def _remaining_findings() -> list[dict[str, str]]:
    return [{"review_id": review_id, "status": "OPEN"} for review_id in REMAINING_FINDING_IDS]


def build_candidate_record(
    *,
    revision: str,
    command_results: Sequence[dict[str, Any]],
    environment: dict[str, str],
    revision_reader: Callable[[str], bytes],
    fixture_paths: Sequence[str],
) -> dict[str, Any]:
    match = _REVISION.fullmatch(revision)
    _require(match is not None, "REVISION_IMMUTABLE", "implementation revision must be git:<40 lowercase hex>")
    specs = command_specs(match.group(1))
    _require(len(command_results) == len(specs), "COMMAND_INVENTORY", "a required command result is missing")
    commands = [
        _sanitize_command_result(spec, raw)
        for spec, raw in zip(specs, command_results, strict=True)
    ]
    _require(
        isinstance(environment, dict)
        and tuple(sorted(environment)) == ENVIRONMENT_FIELDS
        and all(isinstance(value, str) and value for value in environment.values()),
        "ENVIRONMENT_BINDING",
        "environment is not the closed sanitized shape",
    )
    behavior = _bindings(BEHAVIOR_SOURCE_PATHS, revision_reader, "SOURCE_BINDING")
    schemas = _bindings(SCHEMA_PATHS, revision_reader, "SCHEMA_BINDING")
    fixture_members = _bindings(tuple(fixture_paths), revision_reader, "FIXTURE_BINDING")
    value: dict[str, Any] = {
        "schema_version": "1.0.0",
        "evidence_id": "evidence_phase_02_1_trust_boundary_closure_rev_001",
        "evidence_kind": "automated_review_candidate",
        "candidate_findings": _candidate_findings(),
        "remaining_findings": _remaining_findings(),
        "outer_status": dict(OUTER_STATUS),
        "implementation": {
            "revision": revision,
            "revision_kind": "immutable_git_commit",
            "behavior_sources": behavior,
            "behavior_source_set_sha256": _set_digest(behavior),
            "schemas": schemas,
            "schema_set_sha256": _set_digest(schemas),
            "fixture_inventory": {
                "root": FIXTURE_ROOT,
                "members": fixture_members,
                "inventory_sha256": _set_digest(fixture_members),
            },
            "active_generation_inventory_format": _format_binding(revision_reader),
        },
        "environment": {key: environment[key] for key in ENVIRONMENT_FIELDS},
        "verification": {
            "mode": "fresh_rerun_required",
            "output_policy": "bounded_semantic_summary_v1",
            "commands": commands,
        },
        "privacy": dict(PRIVACY_STATUS),
        "limitations": list(LIMITATIONS),
    }
    value["record_sha256"] = sha256_bytes(canonical_json_bytes(value))
    return value


def _assert_privacy_safe(value: Any) -> None:
    encoded = canonical_json_bytes(value).decode("utf-8")
    _require(_PRIVATE_PATH.search(encoded) is None, "PRIVACY_UNSAFE", "private host path is present")
    prohibited = (
        "-----BEGIN " + "PRIVATE KEY-----",
        "-----BEGIN RSA " + "PRIVATE KEY-----",
        "-----BEGIN OPENSSH " + "PRIVATE KEY-----",
    )
    _require(not any(marker in encoded for marker in prohibited), "PRIVACY_UNSAFE", "credential material is present")


def _verify_field_sets(record: dict[str, Any]) -> None:
    _require(
        set(record)
        == {
            "candidate_findings",
            "environment",
            "evidence_id",
            "evidence_kind",
            "implementation",
            "limitations",
            "outer_status",
            "privacy",
            "record_sha256",
            "remaining_findings",
            "schema_version",
            "verification",
        },
        "FIELD_SET",
        "record root contains an unknown or missing field",
    )
    _require(
        isinstance(record.get("implementation"), dict)
        and set(record["implementation"])
        == {
            "active_generation_inventory_format",
            "behavior_source_set_sha256",
            "behavior_sources",
            "fixture_inventory",
            "revision",
            "revision_kind",
            "schema_set_sha256",
            "schemas",
        },
        "FIELD_SET",
        "implementation fields are not closed",
    )
    _require(
        isinstance(record.get("verification"), dict)
        and set(record["verification"]) == {"commands", "mode", "output_policy"},
        "FIELD_SET",
        "verification fields are not closed",
    )


def _verify_self_digest(record: dict[str, Any]) -> None:
    payload = dict(record)
    recorded = payload.pop("record_sha256", None)
    _require(
        isinstance(recorded, str)
        and _SHA256.fullmatch(recorded) is not None
        and recorded == sha256_bytes(canonical_json_bytes(payload)),
        "SELF_DIGEST",
        "record self-digest is absent or stale",
    )


def _verify_scope(record: dict[str, Any]) -> None:
    candidate = record.get("candidate_findings")
    _require(candidate == _candidate_findings(), "SCOPE_IDS", "candidate scope is not exactly CR-03/CR-04/CR-12")
    _require(
        record.get("remaining_findings") == _remaining_findings(),
        "REMAINING_FINDINGS",
        "another CR/WR is absent or promoted",
    )
    outer = record.get("outer_status")
    _require(isinstance(outer, dict), "OUTER_STATUS", "outer status is absent")
    _require(
        outer.get("physical_evidence") == PHYSICAL_NOT_RUN
        and outer.get("human_evidence") == PHYSICAL_NOT_RUN,
        "PHYSICAL_CLAIM",
        "physical or human evidence was claimed",
    )
    _require(outer == OUTER_STATUS, "OUTER_STATUS", "phase, gate, or milestone status was promoted")


def _verify_static_record(record: dict[str, Any], environment: dict[str, str]) -> str:
    _require(isinstance(record, dict), "FIELD_SET", "record root is not an object")
    _verify_field_sets(record)
    _verify_self_digest(record)
    _assert_privacy_safe(record)
    _require(record["schema_version"] == "1.0.0", "FIELD_SET", "record version is unsupported")
    _require(
        record["evidence_id"] == "evidence_phase_02_1_trust_boundary_closure_rev_001"
        and record["evidence_kind"] == "automated_review_candidate",
        "FIELD_SET",
        "record identity or kind is invalid",
    )
    revision = record["implementation"].get("revision")
    match = _REVISION.fullmatch(revision) if isinstance(revision, str) else None
    _require(match is not None, "REVISION_IMMUTABLE", "implementation revision is mutable or malformed")
    _require(
        record["implementation"].get("revision_kind") == "immutable_git_commit",
        "REVISION_IMMUTABLE",
        "revision kind is not immutable",
    )
    _verify_scope(record)
    _require(record.get("privacy") == PRIVACY_STATUS, "PRIVACY_UNSAFE", "privacy declaration is not exact")
    _require(tuple(record.get("limitations", ())) == LIMITATIONS, "LIMITATIONS", "limitations are absent or changed")
    _require(
        record.get("environment") == {key: environment[key] for key in ENVIRONMENT_FIELDS},
        "ENVIRONMENT_BINDING",
        "execution environment is stale",
    )
    verification = record["verification"]
    _require(
        verification["mode"] == "fresh_rerun_required"
        and verification["output_policy"] == "bounded_semantic_summary_v1",
        "COMMAND_RESULT_SHAPE",
        "verification policy is invalid",
    )
    return match.group(1)


def _verify_file_bindings(
    record: dict[str, Any],
    revision_reader: Callable[[str], bytes],
    working_reader: Callable[[str], bytes],
    fixture_paths: Sequence[str],
) -> None:
    implementation = record["implementation"]
    expected_behavior = _bindings(BEHAVIOR_SOURCE_PATHS, revision_reader, "SOURCE_BINDING")
    _require(
        implementation["behavior_sources"] == expected_behavior
        and implementation["behavior_source_set_sha256"] == _set_digest(expected_behavior),
        "SOURCE_BINDING",
        "behavior-source digest set is stale",
    )
    for path in BEHAVIOR_SOURCE_PATHS:
        try:
            current = working_reader(path)
            immutable = revision_reader(path)
        except Exception as error:
            raise EvidenceVerificationError("DIRTY_BEHAVIOR_SOURCE", f"behavior source is unavailable: {path}") from error
        _require(current == immutable, "DIRTY_BEHAVIOR_SOURCE", f"behavior source differs from the recorded commit: {path}")

    expected_schemas = _bindings(SCHEMA_PATHS, revision_reader, "SCHEMA_BINDING")
    _require(
        implementation["schemas"] == expected_schemas
        and implementation["schema_set_sha256"] == _set_digest(expected_schemas),
        "SCHEMA_BINDING",
        "schema digest set is stale",
    )
    for path in SCHEMA_PATHS:
        _require(
            working_reader(path) == revision_reader(path),
            "SCHEMA_BINDING",
            f"schema differs from the recorded commit: {path}",
        )

    expected_fixture = _bindings(tuple(fixture_paths), revision_reader, "FIXTURE_BINDING")
    expected_inventory = {
        "root": FIXTURE_ROOT,
        "members": expected_fixture,
        "inventory_sha256": _set_digest(expected_fixture),
    }
    _require(
        implementation["fixture_inventory"] == expected_inventory,
        "FIXTURE_BINDING",
        "fixture inventory is stale or incomplete",
    )
    for path in fixture_paths:
        _require(
            working_reader(path) == revision_reader(path),
            "FIXTURE_BINDING",
            f"fixture member differs from the recorded commit: {path}",
        )

    _require(
        implementation["active_generation_inventory_format"] == _format_binding(revision_reader),
        "INVENTORY_FORMAT",
        "active-generation inventory format is stale",
    )


def _verify_command_inventory(record: dict[str, Any], revision: str) -> tuple[CommandSpec, ...]:
    specs = command_specs(revision)
    commands = record["verification"].get("commands")
    _require(isinstance(commands, list), "COMMAND_RESULT_SHAPE", "command results are not an array")
    ids = tuple(item.get("check_id") for item in commands if isinstance(item, dict))
    _require(
        len(commands) == len(specs) and ids == tuple(spec.check_id for spec in specs),
        "COMMAND_INVENTORY",
        "required focused/full/build/safety command inventory is incomplete or reordered",
    )
    for spec, item in zip(specs, commands, strict=True):
        _require(
            isinstance(item, dict)
            and set(item)
            == {"argv", "check_id", "exit_code", "sanitized_output_sha256", "status"},
            "COMMAND_RESULT_SHAPE",
            f"{spec.check_id} stored result is verdict-only or open-ended",
        )
        _require(
            item["check_id"] == spec.check_id
            and item["argv"] == list(spec.argv)
            and item["exit_code"] == 0
            and item["status"] == "PASS"
            and isinstance(item["sanitized_output_sha256"], str)
            and _SHA256.fullmatch(item["sanitized_output_sha256"]) is not None,
            "COMMAND_RESULT_SHAPE",
            f"{spec.check_id} stored command binding is invalid",
        )
    return specs


def verify_candidate_record(
    record: dict[str, Any],
    *,
    revision_reader: Callable[[str], bytes],
    working_reader: Callable[[str], bytes],
    fixture_paths: Sequence[str],
    command_runner: Callable[[CommandSpec], dict[str, Any]],
    environment: dict[str, str],
) -> None:
    revision = _verify_static_record(record, environment)
    _verify_file_bindings(record, revision_reader, working_reader, fixture_paths)
    specs = _verify_command_inventory(record, revision)
    for spec, stored in zip(specs, record["verification"]["commands"], strict=True):
        fresh = _sanitize_command_result(spec, command_runner(spec))
        _require(fresh["exit_code"] == 0, "COMMAND_FAILED", f"{spec.check_id} rerun failed")
        _require(
            fresh["sanitized_output_sha256"] == stored["sanitized_output_sha256"],
            "COMMAND_OUTPUT",
            f"{spec.check_id} sanitized result differs from the recorded run",
        )


def serialize_record(record: dict[str, Any]) -> bytes:
    return canonical_json_bytes(record) + b"\n"


def decode_record(data: bytes) -> dict[str, Any]:
    def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise EvidenceVerificationError("DUPLICATE_KEY", f"duplicate object key: {key}")
            result[key] = value
        return result

    try:
        value = json.loads(data, object_pairs_hook=reject_duplicates)
    except EvidenceVerificationError:
        raise
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise EvidenceVerificationError("MALFORMED_RECORD", "evidence is not valid UTF-8 JSON") from error
    _require(isinstance(value, dict), "FIELD_SET", "record root is not an object")
    _require(data == serialize_record(value), "NONCANONICAL_RECORD", "evidence bytes are not canonical JSON plus newline")
    return value


def _git(arguments: Sequence[str], *, root: Path = ROOT, timeout: int = 60) -> bytes:
    try:
        completed = subprocess.run(
            ("git", *arguments),
            cwd=root,
            check=False,
            capture_output=True,
            timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise EvidenceVerificationError("GIT_STATE", "Git command is unavailable") from error
    _require(completed.returncode == 0, "GIT_STATE", "Git state cannot be resolved")
    return completed.stdout


def _current_revision() -> str:
    revision = _git(("rev-parse", "--verify", "HEAD^{commit}")).decode("ascii").strip()
    _require(re.fullmatch(r"[0-9a-f]{40}", revision) is not None, "REVISION_IMMUTABLE", "HEAD did not resolve to a full commit")
    return revision


def _require_commit(revision: str) -> None:
    object_type = _git(("cat-file", "-t", revision)).decode("ascii").strip()
    _require(object_type == "commit", "REVISION_IMMUTABLE", "recorded revision is not a commit")
    try:
        completed = subprocess.run(
            ("git", "merge-base", "--is-ancestor", PHASE_SOURCE_BASE, revision),
            cwd=ROOT,
            check=False,
            capture_output=True,
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise EvidenceVerificationError("REVISION_IMMUTABLE", "phase ancestry cannot be checked") from error
    _require(completed.returncode == 0, "REVISION_IMMUTABLE", "recorded revision is outside the Phase 02.1 lineage")


def _revision_reader(revision: str) -> Callable[[str], bytes]:
    def read(path: str) -> bytes:
        return _git(("show", f"{revision}:{path}"), timeout=60)

    return read


def _working_reader(path: str) -> bytes:
    candidate = ROOT / path
    _require(candidate.is_file() and not candidate.is_symlink(), "DIRTY_BEHAVIOR_SOURCE", f"working file is unavailable: {path}")
    try:
        return candidate.read_bytes()
    except OSError as error:
        raise EvidenceVerificationError("DIRTY_BEHAVIOR_SOURCE", f"working file cannot be read: {path}") from error


def _fixture_paths(revision: str) -> tuple[str, ...]:
    output = _git(("ls-tree", "-r", "--name-only", revision, "--", FIXTURE_ROOT))
    paths = tuple(sorted(line for line in output.decode("utf-8").splitlines() if line))
    _require(paths and paths == tuple(sorted(set(paths))), "FIXTURE_BINDING", "fixture inventory is empty or ambiguous")
    return paths


def _working_fixture_paths() -> tuple[str, ...]:
    root = ROOT / FIXTURE_ROOT
    try:
        paths = tuple(
            path.relative_to(ROOT).as_posix()
            for path in sorted(root.rglob("*"))
            if path.is_file() and not path.is_symlink()
        )
    except OSError as error:
        raise EvidenceVerificationError("FIXTURE_BINDING", "working fixture inventory is unavailable") from error
    return paths


def _command_text(arguments: Sequence[str], label: str) -> str:
    try:
        completed = subprocess.run(
            arguments,
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise EvidenceVerificationError("ENVIRONMENT_BINDING", f"{label} is unavailable") from error
    _require(completed.returncode == 0, "ENVIRONMENT_BINDING", f"{label} is unavailable")
    lines = [" ".join(line.split()) for line in (completed.stdout or completed.stderr).splitlines() if line.strip()]
    _require(lines, "ENVIRONMENT_BINDING", f"{label} is empty")
    return " ".join(lines[:2])


def environment_facts() -> dict[str, str]:
    return {
        "platform": f"{platform.system()} {platform.release()} {platform.machine()}",
        "python": _command_text(("python3", "--version"), "Python version"),
        "swift": _command_text(("swift", "--version"), "Swift version"),
        "xcode": _command_text(("xcodebuild", "-version"), "Xcode version"),
    }


@contextlib.contextmanager
def _clean_worktree(revision: str) -> Iterator[Path]:
    parent = Path(tempfile.mkdtemp(prefix="reroom-phase-02-1-worktree-parent-"))
    worktree = parent / "source"
    try:
        completed = subprocess.run(
            ("git", "worktree", "add", "--detach", "--quiet", str(worktree), revision),
            cwd=ROOT,
            check=False,
            capture_output=True,
            timeout=120,
        )
        _require(completed.returncode == 0, "GIT_STATE", "clean exact-revision worktree could not be created")
        yield worktree
    finally:
        if worktree.exists():
            subprocess.run(
                ("git", "worktree", "remove", "--force", str(worktree)),
                cwd=ROOT,
                check=False,
                capture_output=True,
                timeout=120,
            )
        shutil.rmtree(parent, ignore_errors=True)


def _run_command(spec: CommandSpec, root: Path) -> dict[str, Any]:
    environment = dict(os.environ)
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    environment["NSUnbufferedIO"] = "YES"
    try:
        with tempfile.TemporaryFile() as output:
            completed = subprocess.run(
                spec.argv,
                cwd=root,
                env=environment,
                check=False,
                stdout=output,
                stderr=subprocess.STDOUT,
                timeout=1_800,
            )
            output.seek(0)
            raw = output.read()
    except subprocess.TimeoutExpired as error:
        raise EvidenceVerificationError("COMMAND_FAILED", f"{spec.check_id} timed out") from error
    except OSError as error:
        raise EvidenceVerificationError("COMMAND_FAILED", f"{spec.check_id} could not execute") from error
    return {
        "check_id": spec.check_id,
        "argv": list(spec.argv),
        "exit_code": completed.returncode,
        "output": _bounded_output(raw),
    }


def _run_all_commands(revision: str, worktree: Path) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for spec in command_specs(revision):
        print(f"phase-02.1 exact-source: RUN {spec.check_id}", file=sys.stderr, flush=True)
        result = _run_command(spec, worktree)
        if result["exit_code"] != 0:
            raise EvidenceVerificationError("COMMAND_FAILED", f"{spec.check_id} failed")
        results.append(result)
    return results


def _write_atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if temporary.exists():
            temporary.unlink()


def generate_full(output: Path) -> dict[str, Any]:
    revision = _current_revision()
    _require_commit(revision)
    fixture_paths = _fixture_paths(revision)
    _require(
        fixture_paths == _working_fixture_paths(),
        "FIXTURE_BINDING",
        "working fixture member set differs from the immutable revision",
    )
    revision_reader = _revision_reader(revision)
    for path in (*BEHAVIOR_SOURCE_PATHS, *SCHEMA_PATHS, *fixture_paths):
        _require(
            _working_reader(path) == revision_reader(path),
            "DIRTY_BEHAVIOR_SOURCE" if path in BEHAVIOR_SOURCE_PATHS else "SOURCE_BINDING",
            f"bound working file differs from the immutable revision: {path}",
        )
    environment = environment_facts()
    with _clean_worktree(revision) as worktree:
        results = _run_all_commands(revision, worktree)
    record = build_candidate_record(
        revision=f"git:{revision}",
        command_results=results,
        environment=environment,
        revision_reader=revision_reader,
        fixture_paths=fixture_paths,
    )
    _write_atomic(output, serialize_record(record))
    return record


def verify_evidence_path(path: Path) -> None:
    try:
        data = path.read_bytes()
    except OSError as error:
        raise EvidenceVerificationError("MALFORMED_RECORD", "evidence file is unavailable") from error
    record = decode_record(data)
    environment = environment_facts()
    revision_value = record.get("implementation", {}).get("revision")
    match = _REVISION.fullmatch(revision_value) if isinstance(revision_value, str) else None
    _require(match is not None, "REVISION_IMMUTABLE", "implementation revision is mutable or malformed")
    revision = match.group(1)
    _require_commit(revision)
    fixture_paths = _fixture_paths(revision)
    _require(
        fixture_paths == _working_fixture_paths(),
        "FIXTURE_BINDING",
        "working fixture member set differs from the immutable revision",
    )
    revision_reader = _revision_reader(revision)
    _verify_static_record(record, environment)
    _verify_file_bindings(record, revision_reader, _working_reader, fixture_paths)
    _verify_command_inventory(record, revision)
    with _clean_worktree(revision) as worktree:
        verify_candidate_record(
            record,
            revision_reader=revision_reader,
            working_reader=_working_reader,
            fixture_paths=fixture_paths,
            command_runner=lambda spec: _run_command(spec, worktree),
            environment=environment,
        )


_SECRET_PATTERNS = (
    ("private-key", re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----")),
    ("openai-key", re.compile(rb"sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{32,}")),
    ("github-token", re.compile(rb"gh[pousr]_[A-Za-z0-9]{36,}")),
    ("aws-access-key", re.compile(rb"AKIA[0-9A-Z]{16}")),
    ("slack-token", re.compile(rb"xox[baprs]-[A-Za-z0-9-]{24,}")),
)


def tracked_secret_scan(root: Path = ROOT) -> None:
    output = _git(("ls-files", "-z"), root=root)
    paths = [item.decode("utf-8") for item in output.split(b"\0") if item]
    for relative in paths:
        path = root / relative
        if not path.is_file() or path.is_symlink():
            continue
        try:
            data = path.read_bytes()
        except OSError as error:
            raise EvidenceVerificationError("SECRET_SCAN", f"tracked file is unreadable: {relative}") from error
        for label, pattern in _SECRET_PATTERNS:
            if pattern.search(data):
                raise EvidenceVerificationError("SECRET_SCAN", f"{label} pattern found in {relative}")
    print(f"tracked secret scan: PASS ({len(paths)} tracked files)")


def _parse_args(arguments: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--full", action="store_true")
    mode.add_argument("--verify-evidence", type=Path)
    mode.add_argument("--tracked-secret-scan", action="store_true")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    return parser.parse_args(arguments)


def main(arguments: Sequence[str] | None = None) -> int:
    args = _parse_args(arguments)
    try:
        if args.tracked_secret_scan:
            tracked_secret_scan()
            return 0
        if args.full:
            record = generate_full(args.output)
            print(
                "phase-02.1 trust-boundary generation: PASS "
                f"({record['implementation']['revision']}, {len(REQUIRED_CHECK_IDS)} checks)"
            )
            return 0
        verify_evidence_path(args.verify_evidence)
    except EvidenceVerificationError as error:
        print(f"phase-02.1 trust-boundary: FAIL [{error.code}] {error}", file=sys.stderr)
        return 1
    print("phase-02.1 trust-boundary verification: PASS (automated review candidate only)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
