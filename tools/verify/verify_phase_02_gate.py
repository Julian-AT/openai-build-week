#!/usr/bin/env python3
"""Fail-closed Phase 02 deterministic preflight and GATE-001 verifier."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Iterable, Sequence

from jsonschema import Draft202012Validator

from tools.verify.verify_evidence import (
    VerificationFailure,
    assert_privacy_safe,
    read_json,
    verify_files,
)


ROOT = Path(__file__).resolve().parents[2]
OBSERVATION_SCHEMA_PATH = ROOT / "evidence/templates/gate-001-physical-observations.schema.json"
DEFAULT_PREFLIGHT_PATH = ROOT / "evidence/capture/phase-02/automated-preflight.json"
DEFAULT_REPORT_PATH = ROOT / "evidence/capture/phase-02/gate-001-report.json"
DEFAULT_CHECKLIST_PATH = ROOT / "evidence/capture/phase-02/gate-001-checklist.json"

CANONICAL_TERMINATION_STATES = (
    "selected",
    "image_and_metadata_durable",
    "journaled",
    "network_eligible",
    "server_acknowledged",
)
PHYSICAL_FIXTURE_IDS = ("FX-RRCAP-010S", "FX-RRCAP-060S")
PHYSICAL_DURATIONS = (10, 60)

QUICK_CHECK_IDS = (
    "contract_package",
    "lifecycle_crash_matrix",
    "recovery_exact_replay",
    "queue_stress_reordering",
    "consent_denial",
)
FULL_CHECK_IDS = QUICK_CHECK_IDS + (
    "native_simulator_flow",
    "release_surface",
    "three_runtime_agreement",
)

_SHA256 = re.compile(r"^[0-9a-f]{64}$")


class GateVerificationError(ValueError):
    """The evidence is malformed, stale, private, mixed, or unauthorized."""


class GatePending(GateVerificationError):
    """Required real physical evidence or human authority has not been supplied."""


class GateRed(GateVerificationError):
    """A valid RED gate record exists and therefore remains non-success."""


@dataclass(frozen=True)
class CommandSpec:
    check_id: str
    commands: tuple[tuple[str, ...], ...]


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _schema_validator() -> Draft202012Validator:
    try:
        schema = json.loads(OBSERVATION_SCHEMA_PATH.read_text(encoding="utf-8"))
        Draft202012Validator.check_schema(schema)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise GateVerificationError("physical observation schema is unavailable") from error
    return Draft202012Validator(schema)


def _schema_validate(value: Any) -> None:
    errors = sorted(_schema_validator().iter_errors(value), key=lambda item: list(item.path))
    if errors:
        location = ".".join(str(part) for part in errors[0].path) or "$"
        raise GateVerificationError(f"physical observations fail schema at {location}")


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise GateVerificationError(message)


def _fixture_map(value: dict[str, Any]) -> dict[str, dict[str, Any]]:
    refs = value["fixture_refs"]
    return {item["fixture_id"]: item for item in refs}


def validate_physical_observations(value: Any) -> None:
    """Validate the closed physical record and all non-schema threshold relations."""
    _schema_validate(value)
    try:
        assert_privacy_safe(value)
    except VerificationFailure as error:
        raise GateVerificationError(str(error)) from error

    _require(value["decision_actor"] == "human", "physical evidence requires a human actor")
    _require(
        value["evidence_origin"] == "physical_base_device",
        "simulator or synthetic evidence cannot satisfy GATE-001",
    )
    _require(value["value_classification"] == "MEASURED", "physical evidence must be MEASURED")
    _require(value["environment"]["device_model"].startswith("iPhone 17"), "base iPhone 17 is required")
    _require(value["environment"]["runtime_tier"] == "base-iphone-17", "wrong physical runtime tier")
    _require(value["environment"]["signing_result"] == "pass", "signed build was not verified")
    environment_sha = sha256_bytes(canonical_json_bytes(value["environment"]))
    _require(value["environment_sha256"] == environment_sha, "environment digest is stale")

    fixtures = _fixture_map(value)
    _require(tuple(fixtures) == PHYSICAL_FIXTURE_IDS, "physical fixture binding is incomplete or reordered")
    denial = value["consent_denial_observation"]
    _require(denial["attempted"] is True, "consent denial was not attempted")
    _require(denial["local_capture_created"] is False, "denied consent created a local capture")
    _require(denial["upload_reference_count"] == 0, "denied consent created an upload reference")

    observations = value["termination_observations"]
    states = tuple(item["termination_state"] for item in observations)
    _require(states == CANONICAL_TERMINATION_STATES, "canonical termination states are incomplete or reordered")
    _require(len(set(states)) == len(states), "canonical termination states are duplicated")

    for observation in observations:
        state = observation["termination_state"]
        _require(observation["build_revision"] == value["build_revision"], f"{state}: build revision mismatch")
        _require(observation["evaluator_id"] == value["evaluator_id"], f"{state}: evaluator mismatch")
        _require(observation["environment_sha256"] == environment_sha, f"{state}: environment digest mismatch")
        runs = observation["runs"]
        _require(
            tuple(run["fixture_id"] for run in runs) == PHYSICAL_FIXTURE_IDS,
            f"{state}: physical 10s/60s runs are incomplete or reordered",
        )
        _require(
            tuple(run["target_duration_seconds"] for run in runs) == PHYSICAL_DURATIONS,
            f"{state}: physical target durations are invalid",
        )
        for run in runs:
            label = f"{state}/{run['fixture_id']}"
            target_milliseconds = run["target_duration_seconds"] * 1000
            _require(
                run["observed_duration_milliseconds"] >= target_milliseconds,
                f"{label}: target duration was not reached",
            )
            _require(run["build_revision"] == value["build_revision"], f"{label}: build revision mismatch")
            _require(run["evaluator_id"] == value["evaluator_id"], f"{label}: evaluator mismatch")
            _require(run["environment_sha256"] == environment_sha, f"{label}: environment digest mismatch")
            _require(run["consent_state"] == "granted", f"{label}: consent was not granted")
            _require(
                run["local_capture_state"] == "recovered_hash_valid_prefix",
                f"{label}: local capture did not recover a hash-valid prefix",
            )
            _require(
                run["upload_state"] == "paused_or_blackholed",
                f"{label}: upload-pause or blackhole observation is absent",
            )
            _require(run["packet_image_binding_valid"] is True, f"{label}: packet/image binding failed")
            _require(
                run["non_journaled_upload_reference_count"] == 0,
                f"{label}: non-journaled upload reference observed",
            )
            _require(
                run["earlier_record_corruption_count"] == 0,
                f"{label}: earlier-record corruption observed",
            )
            _require(run["recovered_prefix_exact"] is True, f"{label}: recovered prefix is not exact")
            _require(
                run["actual_recovered_global_sequence"] == run["expected_recovered_global_sequence"],
                f"{label}: recovered sequence differs from expected prefix",
            )
            queue = run["queue_observation"]
            _require(queue["maximum_depth"] <= queue["capacity"], f"{label}: queue exceeded capacity")
            _require(queue["pressure_applied"] is True, f"{label}: queue pressure was not applied")
            _require(queue["network_blackholed"] is True, f"{label}: network was not blackholed")
            _require(queue["upload_paused_first"] is True, f"{label}: upload was not paused first")
            replays = run["replays"]
            _require(len({item["replay_id"] for item in replays}) == 2, f"{label}: replays are not independent")
            _require(all(item["evaluator_id"] == value["evaluator_id"] for item in replays), f"{label}: replay evaluator mismatch")
            _require(all(item["matches_expected"] is True for item in replays), f"{label}: replay mismatch")
            for digest_field in (
                "journal_digest_sha256",
                "projection_digest_sha256",
                "accepted_order_digest_sha256",
            ):
                _require(
                    len({item[digest_field] for item in replays}) == 1,
                    f"{label}: two replays disagree on {digest_field}",
                )

    acknowledgement = value["fallback_and_kill_acknowledgement"]
    _require(all(item is True for item in acknowledgement.values()), "fallback or kill rule was not acknowledged")


def declared_check_ids(mode: str) -> tuple[str, ...]:
    if mode == "quick":
        return QUICK_CHECK_IDS
    if mode == "full":
        return FULL_CHECK_IDS
    raise GateVerificationError("deterministic check mode must be quick or full")


def sanitize_check_results(
    declared: Sequence[str], raw_results: Iterable[dict[str, Any]]
) -> list[dict[str, str]]:
    """Reconstruct the public result shape; arbitrary runner fields never flow through."""
    values = list(raw_results)
    _require(len(values) == len(declared), "a declared deterministic check result is missing")
    sanitized: list[dict[str, str]] = []
    for expected, value in zip(declared, values, strict=True):
        _require(isinstance(value, dict), "deterministic check result is not an object")
        _require(
            set(value) == {"check_id", "exit_code", "output"},
            "deterministic check result contains an unknown or private field",
        )
        _require(value["check_id"] == expected, "deterministic check identity is missing or reordered")
        _require(type(value["exit_code"]) is int, "deterministic check exit code is invalid")
        _require(isinstance(value["output"], str), "deterministic check output is invalid")
        _require(value["exit_code"] == 0, f"deterministic check failed: {expected}")
        sanitized.append(
            {
                "check_id": expected,
                "status": "PASS",
                "output_sha256": sha256_bytes(value["output"].encode("utf-8")),
            }
        )
    return sanitized


def _validate_preflight(value: Any) -> None:
    _require(isinstance(value, dict), "automated preflight root is invalid")
    allowed = {
        "schema_version",
        "gate_id",
        "gate_state",
        "decision_actor",
        "recorded_at_utc",
        "implementation_revision",
        "fixture_refs",
        "environment",
        "value_classification",
        "checks",
        "synthetic_metrics",
        "preflight_sha256",
    }
    _require(set(value) == allowed, "automated preflight contains an unknown or private field")
    _require(value["schema_version"] == "1.0.0", "automated preflight version is unsupported")
    _require(value["gate_id"] == "GATE-001", "automated preflight gate identity is invalid")
    _require(value["gate_state"] in {"RUNNING", "RED"}, "automation cannot publish this gate state")
    _require(value["decision_actor"] == "automation", "automated preflight actor is invalid")
    _require(value["value_classification"] == "HYPOTHESIS", "synthetic preflight must remain HYPOTHESIS")
    _require(re.fullmatch(r"git:[0-9a-f]{40}", value["implementation_revision"]) is not None, "implementation revision is invalid")
    fixture_ids = tuple(item.get("fixture_id") for item in value["fixture_refs"])
    _require(
        fixture_ids == ("FX-PREFLIGHT-CAPTURE-SHORT", "FX-PREFLIGHT-CAPTURE-LONG"),
        "automated preflight must use distinct synthetic fixture identities",
    )
    checks = value["checks"]
    _require(tuple(item.get("check_id") for item in checks) == FULL_CHECK_IDS, "full preflight checks are incomplete")
    _require(all(item.get("status") == "PASS" for item in checks), "full preflight contains a failed check")
    _require(
        all(set(item) == {"check_id", "status", "output_sha256"} and _SHA256.fullmatch(item["output_sha256"]) for item in checks),
        "full preflight check shape is invalid",
    )
    _require(isinstance(value["synthetic_metrics"], list) and value["synthetic_metrics"], "synthetic metrics are missing")
    _require(
        all(item.get("value_classification") in {"HYPOTHESIS", "TARGET"} for item in value["synthetic_metrics"]),
        "synthetic metrics cannot be labeled MEASURED",
    )
    payload = dict(value)
    recorded = payload.pop("preflight_sha256")
    _require(recorded == sha256_bytes(canonical_json_bytes(payload)), "automated preflight self-digest is stale")
    try:
        assert_privacy_safe(value)
    except VerificationFailure as error:
        raise GateVerificationError(str(error)) from error


def _read(path: Path, label: str) -> tuple[bytes, Any]:
    try:
        return read_json(path)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, VerificationFailure) as error:
        raise GateVerificationError(f"{label} is unavailable or malformed") from error


def _report_has_artifact(report: dict[str, Any], digest: str) -> bool:
    return any(
        item.get("artifact_role") == "supporting_evidence" and item.get("sha256") == digest
        for item in report.get("evidence_artifacts", [])
    )


def verify_gate_paths(
    preflight_path: Path,
    report_path: Path,
    checklist_path: Path | None,
    observations_path: Path | None,
) -> None:
    """Succeed only for fresh automated proof plus complete human physical GREEN."""
    preflight_bytes, preflight = _read(preflight_path, "automated preflight")
    _validate_preflight(preflight)
    preflight_sha = sha256_bytes(preflight_bytes)
    _, report = _read(report_path, "GATE-001 report")
    _require(isinstance(report, dict), "GATE-001 report root is invalid")
    _require(report.get("gate_id") == "GATE-001", "GATE-001 report identity is invalid")
    _require(report.get("implementation_revision") == preflight["implementation_revision"], "report/preflight revision mismatch")
    _require(_report_has_artifact(report, preflight_sha), "report does not bind the automated preflight bytes")

    state = report.get("gate_state")
    if state in {"UNRUN", "RUNNING"}:
        try:
            verify_files(report_path, None)
        except VerificationFailure as error:
            raise GateVerificationError(str(error)) from error
        raise GatePending("GATE-001 pending: physical observations and human attestation are required")
    if state == "RED":
        try:
            verify_files(report_path, None)
        except VerificationFailure as error:
            raise GateVerificationError(str(error)) from error
        _require(report.get("automated_report_sha256") == preflight_sha, "RED report preflight digest is stale")
        raise GateRed("GATE-001 RED: live integration remains blocked")
    _require(state == "GREEN", "GATE-001 waiver or unknown state is not accepted by this gate")
    _require(checklist_path is not None, "human GREEN requires a checklist")
    _require(observations_path is not None, "human GREEN requires runtime physical observations")

    observation_bytes, observation_value = _read(observations_path, "physical observations")
    validate_physical_observations(observation_value)
    observation_sha = sha256_bytes(observation_bytes)
    _require(report.get("decision_actor") == "human", "GREEN requires human authority")
    _require(report.get("automated_report_sha256") == preflight_sha, "GREEN report preflight digest is stale")
    _require(_report_has_artifact(report, observation_sha), "GREEN report does not bind physical observation bytes")
    _require(report.get("fixture_refs") == observation_value["fixture_refs"], "report/observation fixture binding mismatch")
    _require(report.get("environment") == observation_value["environment"], "report/observation environment mismatch")
    _require(report.get("implementation_revision") == observation_value["implementation_revision"], "report/observation revision mismatch")
    try:
        verify_files(report_path, checklist_path)
    except VerificationFailure as error:
        raise GateVerificationError(str(error)) from error


def command_specs(mode: str) -> tuple[CommandSpec, ...]:
    requested = declared_check_ids(mode)
    package = "ios/Packages/ReRoomContracts"
    definitions = {
        "contract_package": (("python3", "-m", "unittest", "tools.verify.tests.test_phase_02_fixtures", "-v"),),
        "lifecycle_crash_matrix": (
            ("swift", "test", "--package-path", package, "--filter", "CaptureLifecycleTests"),
            ("swift", "test", "--package-path", package, "--filter", "CaptureCrashMatrixTests"),
        ),
        "recovery_exact_replay": (
            ("swift", "test", "--package-path", package, "--filter", "CaptureRecoveryTests"),
            ("swift", "test", "--package-path", package, "--filter", "ReplayCoreTests"),
            ("scripts/run-phase-02-replay-agreement", "--verify-evidence"),
        ),
        "queue_stress_reordering": (
            ("swift", "test", "--package-path", package, "--filter", "BoundedQueueTests"),
            ("swift", "test", "--package-path", package, "--filter", "FrameSelectionTests"),
        ),
        "consent_denial": (("swift", "test", "--package-path", package, "--filter", "CaptureAdmissionTests"),),
        "native_simulator_flow": (
            (
                "xcodebuild",
                "test",
                "-project",
                "ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj",
                "-scheme",
                "ReRoomDeviceProof",
                "-configuration",
                "Debug",
                "-sdk",
                "iphonesimulator",
                "-destination",
                "platform=iOS Simulator,name=iPhone 17 Pro",
                "-only-testing:ReRoomDeviceProofTests/CaptureSessionAdapterTests",
                "-only-testing:ReRoomDeviceProofUITests/DiagnosticSurfaceTests",
            ),
        ),
        "release_surface": (("scripts/verify-reroom-release-surface",),),
        "three_runtime_agreement": (("scripts/run-three-runtime-agreement",),),
    }
    return tuple(CommandSpec(check_id, definitions[check_id]) for check_id in requested)


def _run_spec(spec: CommandSpec, *, root: Path = ROOT) -> dict[str, Any]:
    output: list[str] = []
    for command in spec.commands:
        try:
            with tempfile.TemporaryDirectory(prefix="reroom-phase-02-pycache-") as cache:
                environment = dict(os.environ, PYTHONPYCACHEPREFIX=cache)
                completed = subprocess.run(
                    command,
                    cwd=root,
                    env=environment,
                    check=False,
                    capture_output=True,
                    text=True,
                    timeout=900,
                )
        except (OSError, subprocess.SubprocessError) as error:
            return {"check_id": spec.check_id, "exit_code": 1, "output": f"execution failed: {type(error).__name__}"}
        output.extend((completed.stdout, completed.stderr))
        if completed.returncode != 0:
            return {"check_id": spec.check_id, "exit_code": completed.returncode, "output": "".join(output)}
    return {"check_id": spec.check_id, "exit_code": 0, "output": "".join(output)}


def run_deterministic_checks(
    mode: str,
    runner: Callable[[CommandSpec], dict[str, Any]] | None = None,
) -> list[dict[str, str]]:
    specs = command_specs(mode)
    execute = runner or _run_spec
    raw = [execute(spec) for spec in specs]
    return sanitize_check_results(tuple(spec.check_id for spec in specs), raw)


def _parse_args(arguments: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("quick", "full", "gate"))
    parser.add_argument("--preflight", type=Path, default=DEFAULT_PREFLIGHT_PATH)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT_PATH)
    parser.add_argument("--checklist", type=Path, default=DEFAULT_CHECKLIST_PATH)
    return parser.parse_args(arguments)


def main(arguments: Sequence[str] | None = None) -> int:
    args = _parse_args(arguments)
    try:
        if args.mode in {"quick", "full"}:
            results = run_deterministic_checks(args.mode)
            print(f"phase-02 {args.mode}: PASS ({len(results)} declared checks)")
            return 0
        observation_text = os.environ.get("REROOM_GATE_001_OBSERVATIONS_PATH")
        observation_path = Path(observation_text) if observation_text else None
        checklist_path = args.checklist if args.checklist.exists() else None
        verify_gate_paths(args.preflight, args.report, checklist_path, observation_path)
    except GatePending as error:
        print(str(error), file=sys.stderr)
        return 2
    except GateRed as error:
        print(str(error), file=sys.stderr)
        return 3
    except GateVerificationError as error:
        print(f"phase-02 verification: FAIL ({error})", file=sys.stderr)
        return 1
    print("GATE-001: GREEN (human-bound physical evidence verified)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
