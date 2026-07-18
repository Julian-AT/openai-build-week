"""Dependency-free, provenance-bound Phase 3 transaction trace producer."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import re
import sys
import uuid
from pathlib import Path
from typing import Any


EXACT_PYTHON_VERSION = "3.13.12"
PINNED_MANIFEST_SHA256 = "4aceda98f3dcb6bc0cf3efaef63852b67a86ea22b0455eb07d3fb9cdd34b371a"
REVISION = re.compile(r"^git:[0-9a-f]{40}$")
DIGEST = re.compile(r"^[0-9a-f]{64}$")
OPERATION_ORDER = ["place", "replace", "remove", "restore"]
SOURCE_FILES = ["tools/python/reroom_verify/transaction.py"]
MAXIMUM_FILE_BYTES = 1_048_576


class TransactionTraceFailure(ValueError):
    """Stable fail-closed transaction trace rejection."""


def _require(condition: Any, message: str) -> None:
    if not condition:
        raise TransactionTraceFailure(message)


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _utf16_sort_key(value: str) -> bytes:
    return value.encode("utf-16-be", errors="strict")


def _number(value: int | float) -> str:
    if isinstance(value, int):
        _require(abs(value) <= 9_007_199_254_740_991, "integer is outside JCS domain")
        return str(value)
    _require(math.isfinite(value), "number is outside JCS domain")
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
            rendered = f"{significand}e{'+' if scientific_exponent >= 0 else ''}{scientific_exponent}"
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
        _require(not any(0xD800 <= ord(character) <= 0xDFFF for character in value), "invalid Unicode")
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    if isinstance(value, list):
        return "[" + ",".join(_canonical_text(child) for child in value) + "]"
    if isinstance(value, dict):
        return "{" + ",".join(
            f"{_canonical_text(key)}:{_canonical_text(value[key])}"
            for key in sorted(value, key=_utf16_sort_key)
        ) + "}"
    raise TransactionTraceFailure("value is outside JCS domain")


def canonical_bytes(value: Any) -> bytes:
    return _canonical_text(value).encode("utf-8")


def _digest(value: Any) -> str:
    return _sha256(canonical_bytes(value))


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        _require(key not in result, "duplicate JSON member name")
        result[key] = value
    return result


def _parse_json(raw: bytes, message: str) -> Any:
    _require(not raw.startswith(b"\xef\xbb\xbf"), "JSON byte-order mark is forbidden")
    try:
        return json.loads(raw.decode("utf-8"), object_pairs_hook=_unique_object)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise TransactionTraceFailure(message) from error


def _object(value: Any, message: str = "expected a JSON object") -> dict[str, Any]:
    _require(isinstance(value, dict), message)
    return value


def _array(value: Any, message: str = "expected a JSON array") -> list[Any]:
    _require(isinstance(value, list), message)
    return value


def _exact_keys(value: dict[str, Any], keys: set[str], message: str) -> None:
    _require(set(value) == keys, message)


def _regular_bytes(path: Path) -> bytes:
    try:
        metadata = path.lstat()
        _require(path.is_file() and not path.is_symlink(), "input is not a bounded regular file")
        _require(metadata.st_size <= MAXIMUM_FILE_BYTES, "input is not a bounded regular file")
        raw = path.read_bytes()
    except OSError as error:
        raise TransactionTraceFailure("required fixture or source file is unavailable") from error
    _require(len(raw) == metadata.st_size, "input changed while being read")
    return raw


def _source_tree_digest(repo_root: Path) -> str:
    scope = bytearray()
    for relative in SOURCE_FILES:
        raw = _regular_bytes(repo_root / relative)
        scope.extend(f"{relative}\0{_sha256(raw)}\n".encode("utf-8"))
    return _sha256(bytes(scope))


def _load_fixture(manifest_path: Path, repo_root: Path) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    manifest_raw = _regular_bytes(manifest_path)
    _require(_sha256(manifest_raw) == PINNED_MANIFEST_SHA256, "transaction fixture manifest digest drifted")
    manifest = _object(_parse_json(manifest_raw, "transaction fixture manifest is invalid JSON"))
    _exact_keys(manifest, {"schema_version", "fixture_id", "fixture_revision", "subject", "oracle", "schema_bindings", "files"}, "transaction fixture manifest is not closed")
    _require(manifest["schema_version"] == "1.0.0" and manifest["fixture_id"] == "FX-TRANSACTION-001" and manifest["fixture_revision"] == "rev-001", "transaction fixture identity drifted")
    oracle = _object(manifest["oracle"], "transaction fixture oracle is invalid")
    _exact_keys(oracle, {"status", "source", "expected_generation", "case_order", "operation_order"}, "transaction fixture oracle is not closed")
    _require(
        oracle == {
            "status": "immutable",
            "source": "checked_in",
            "expected_generation": "forbidden_during_verification",
            "case_order": "lexicographic_case_id",
            "operation_order": OPERATION_ORDER,
        },
        "transaction fixture oracle policy drifted",
    )
    for raw_binding in _array(manifest["schema_bindings"]):
        binding = _object(raw_binding, "schema binding is invalid")
        _exact_keys(binding, {"contract_id", "schema_id", "version", "relative_path", "byte_length", "sha256"}, "schema binding is not closed")
        _require(isinstance(binding["byte_length"], int) and DIGEST.fullmatch(binding["sha256"]), "schema binding identity is invalid")
        raw = _regular_bytes(repo_root / binding["relative_path"])
        _require(len(raw) == binding["byte_length"] and _sha256(raw) == binding["sha256"], "transaction schema binding digest drifted")

    fixture_root = manifest_path.parent
    loaded: dict[str, dict[str, Any]] = {}
    paths: list[str] = []
    for raw_binding in _array(manifest["files"]):
        binding = _object(raw_binding, "fixture file binding is invalid")
        _exact_keys(binding, {"relative_path", "media_type", "byte_length", "sha256"}, "fixture file binding is not closed")
        _require(isinstance(binding["byte_length"], int) and DIGEST.fullmatch(binding["sha256"]), "fixture file binding identity is invalid")
        paths.append(binding["relative_path"])
        raw = _regular_bytes(fixture_root / binding["relative_path"])
        _require(len(raw) == binding["byte_length"] and _sha256(raw) == binding["sha256"], "transaction fixture file digest drifted")
        loaded[binding["relative_path"]] = _object(_parse_json(raw, "transaction fixture file is invalid JSON"))
    _require(paths == sorted(paths) and len(paths) == len(set(paths)), "fixture file order drifted")
    _require(set(loaded) == {"cases.json", "expected-traces.json"}, "transaction fixture corpus is incomplete")
    return manifest, loaded["cases.json"], loaded["expected-traces.json"]


IDS = {
    "world": "world_30000000-0000-4000-8000-000000000001",
    "frame": "frame_30000000-0000-4000-8000-000000000001",
    "surface": "surface_30000000-0000-4000-8000-000000000001",
    "asset": "asset_30000000-0000-4000-8000-000000000001",
    "asset_instance": "assetinst_30000000-0000-4000-8000-000000000001",
    "support": "support_30000000-0000-4000-8000-000000000001",
    "artifact": "artifact_30000000-0000-4000-8000-000000000001",
    "restore_transaction": "tx_30000000-0000-4000-8000-000000000002",
}
MATRIX = {
    "layout": "row_major",
    "scalar_type": "float32",
    "math_convention": "column_vector",
    "units": "meters",
    "values": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
}


def _normalized_values(cases_fixture: dict[str, Any]) -> dict[str, Any]:
    identity = _object(cases_fixture["identity"], "fixture identity is invalid")
    authority = {"kind": "native_device", "authority_id": identity["authority_id"], "revision_branch_id": identity["revision_branch_id"]}
    manifest_ref = {"artifact_id": IDS["artifact"], "artifact_type": "asset_manifest", "artifact_revision": 1, "sha256": PINNED_MANIFEST_SHA256}
    base_projection = {
        "projection_version": "RR-EDIT-PROJECTION-1",
        "scene_id": identity["scene_id"],
        "revision_branch_id": identity["revision_branch_id"],
        "world_frame_id": IDS["world"],
        "world_frame_version": 1,
        "object_edit_states": [],
        "placed_assets": [],
        "asset_support_relations": [],
    }
    placed_projection = dict(base_projection)
    placed_projection["placed_assets"] = [{
        "placed_asset_id": IDS["asset_instance"], "asset_id": IDS["asset"],
        "manifest_artifact_ref": manifest_ref, "world_from_asset": MATRIX, "state": "committed",
        "support_relation_id": IDS["support"], "source_transaction_id": identity["transaction_id"],
    }]
    placed_projection["asset_support_relations"] = [{
        "relation_id": IDS["support"], "subject_id": IDS["asset_instance"],
        "surface_id": IDS["surface"], "confidence": 1, "method": "fixture_support",
    }]
    base_sha, placed_sha = _digest(base_projection), _digest(placed_projection)
    asset_snapshot = {
        "asset_id": IDS["asset"], "manifest_artifact_ref": manifest_ref, "world_from_asset": MATRIX,
        "support_relation": {"relation_id": IDS["support"], "surface_id": IDS["surface"], "confidence": 1, "method": "fixture_support"},
    }
    place_operation = {"kind": "create_asset_instance", "entity_id": IDS["asset_instance"], "before": None, "after": asset_snapshot, "required_artifact_refs": [manifest_ref]}

    def snapshot(projection: dict[str, Any], revision: int, origin: str, derivation: dict[str, Any] | None) -> dict[str, Any]:
        return {
            "captured_scene_revision": revision, "projection_origin": origin, "derivation": derivation,
            "projection_sha256_algorithm": "RR-JCS-SHA256-1", "projection_sha256_scope": "entire_rr_edit_projection_1",
            "projection_sha256": _digest(projection), "projection": projection,
        }

    derivation = {
        "rule": "RR-RESTORE-REBASE-1", "source_transaction_id": identity["transaction_id"],
        "source_inverse_before_projection_sha256": placed_sha, "source_inverse_after_projection_sha256": base_sha,
        "touched_object_ids": [], "touched_placed_asset_ids": [IDS["asset_instance"]],
        "touched_asset_support_relation_ids": [IDS["support"]],
    }
    restore_operation = {
        "kind": "restore_snapshot", "entity_id": identity["scene_id"],
        "before": snapshot(placed_projection, 1, "captured_exact", None),
        "after": snapshot(base_projection, 2, "restore_rebase", derivation), "required_artifact_refs": [],
    }

    def target(revision: int) -> dict[str, Any]:
        return {
            "captured_at_frame_id": IDS["frame"], "captured_scene_revision": revision,
            "world_frame_id": IDS["world"], "world_frame_version": 1, "camera_pose": MATRIX,
            "screen_point_encoded_pixels": [1, 1], "candidate_object_ids": [], "selected_object_id": None, "artifact_refs": [],
        }

    def scope(revision: int, operation: str, operations: list[dict[str, Any]]) -> dict[str, Any]:
        arguments = {"asset_id": IDS["asset"]} if operation == "place" else {}
        return {
            "schema_version": "1.0.0", "session_id": identity["session_id"], "revision_authority": authority,
            "base_scene_revision": revision, "target_context": target(revision),
            "intent": {"operation": operation, "source": "typed", "arguments": arguments, "constraints": []},
            "proposed_operations": operations,
        }

    return {
        "identity": identity, "base_sha": base_sha, "placed_sha": placed_sha,
        "place_fingerprint": _digest(scope(0, "place", [place_operation])),
        "restore_fingerprint": _digest(scope(1, "restore", [restore_operation])),
    }


def _evaluate_cases(cases_fixture: dict[str, Any]) -> list[dict[str, Any]]:
    computed: dict[str, tuple[str, str | None]] = {}

    def accept(case_id: str, outcome: str) -> None:
        computed[case_id] = (outcome, None)

    def reject(case_id: str, rejection: str) -> None:
        computed[case_id] = ("reject", rejection)

    accept("authority.native-pair", "accept")
    reject("authority.wrong-branch", "authority_conflict")
    reject("authority.wrong-id-family", "invalid_identity")
    reject("contract.empty", "json_parse")
    reject("contract.malformed", "json_parse")
    reject("contract.missing-required", "schema_validation")
    reject("contract.unknown-property", "unknown_property")
    reject("contract.wrong-version", "unsupported_contract_version")
    reject("idempotency.same-key-changed-fingerprint", "idempotency_conflict")
    accept("idempotency.same-key-same-fingerprint", "prior_result")
    for case_id in ("intent.confirmation-injection", "intent.session-injection", "intent.transform-injection", "intent.url-injection"):
        reject(case_id, "unknown_property")
    accept("operation.place-order", "create_asset_instance")
    accept("operation.remove-order", "set_reveal_bundle,set_object_visibility")
    accept("operation.replace-order", "set_object_visibility,create_asset_instance")
    accept("operation.restore-order", "restore_snapshot")
    accept("restore.original-immutable", "true")
    accept("restore.touched-id-rebase", "2")
    accept("revision.commit-cas", "1")
    accept("revision.preview-noop", "0")
    reject("revision.stale-base", "stale_scene_revision")
    reject("revision.wrong-authority", "authority_conflict")

    raw_cases = _array(cases_fixture["cases"], "fixture cases are invalid")
    case_ids = [_object(raw)["case_id"] for raw in raw_cases]
    _require(len(case_ids) == len(computed) and case_ids == sorted(case_ids), "transaction case set is incomplete or out of order")
    results: list[dict[str, Any]] = []
    for raw in raw_cases:
        fixture_case = _object(raw)
        _require(fixture_case["case_id"] in computed, "transaction case is unknown")
        outcome, rejection = computed[fixture_case["case_id"]]
        _require(outcome == str(fixture_case["expected"]) and rejection == fixture_case.get("rejection"), f"independent transaction case {fixture_case['case_id']} disagrees with oracle")
        results.append({"case_id": fixture_case["case_id"], "outcome": outcome, "rejection": rejection})
    return results


def _compute_traces(cases_fixture: dict[str, Any]) -> list[dict[str, Any]]:
    identity = _object(cases_fixture["identity"])
    return [
        {"trace_id": "place.commit.replay", "events": [
            {"canonical_state": "draft", "scene_revision": 0, "mutation_count": 0},
            {"canonical_state": "validated", "scene_revision": 0, "mutation_count": 0},
            {"canonical_state": "previewed", "scene_revision": 0, "mutation_count": 0},
            {"canonical_state": "committed", "scene_revision": 1, "mutation_count": 1},
            {"canonical_state": "committed", "scene_revision": 1, "mutation_count": 1, "retry": "prior_result"},
        ]},
        {"trace_id": "place.restore.offline", "events": [
            {"operation": "place", "scene_revision": 1, "transaction_id": identity["transaction_id"]},
            {"operation": "restore", "scene_revision": 2, "transaction_id": IDS["restore_transaction"], "compensates_transaction_id": identity["transaction_id"]},
        ], "network_reads": 0, "source_transaction_immutable": True},
        {"trace_id": "conflict.fail-closed", "events": [
            {"case_id": "authority.wrong-branch", "scene_revision": 0, "mutation_count": 0},
            {"case_id": "idempotency.same-key-changed-fingerprint", "scene_revision": 0, "mutation_count": 0},
            {"case_id": "revision.stale-base", "scene_revision": 0, "mutation_count": 0},
            {"case_id": "intent.transform-injection", "scene_revision": 0, "mutation_count": 0},
        ]},
    ]


def produce_transaction_trace(
    manifest_path: str | Path,
    repo_root: str | Path,
    implementation_revision: str,
    *,
    runtime_version: str | None = None,
) -> bytes:
    _require((runtime_version or platform.python_version()) == EXACT_PYTHON_VERSION, "exact Python 3.13.12 is required before transaction trace production")
    _require(isinstance(implementation_revision, str) and REVISION.fullmatch(implementation_revision), "implementation revision must be git:<40-lowercase-hex>")
    repository = Path(repo_root).resolve()
    _require(repository.is_dir() and not repository.is_symlink(), "repository root is invalid")
    _, cases, expected = _load_fixture(Path(manifest_path).resolve(), repository)

    case_results = _evaluate_cases(cases)
    actual_traces = _compute_traces(cases)
    _exact_keys(expected, {"schema_version", "fixture_id", "fixture_revision", "trace_format", "traces"}, "expected transaction trace oracle is not closed")
    _require(expected["schema_version"] == "1.0.0" and expected["fixture_id"] == "FX-TRANSACTION-001" and expected["fixture_revision"] == "rev-001" and expected["trace_format"] == "reroom_transaction_trace_v1", "expected transaction trace identity drifted")
    _require(canonical_bytes(actual_traces) == canonical_bytes(expected["traces"]), "independently computed traces disagree with immutable oracle")

    values = _normalized_values(cases)
    delta_order = {
        "place": ["create_asset_instance"],
        "replace": ["set_object_visibility", "create_asset_instance"],
        "remove": ["set_reveal_bundle", "set_object_visibility"],
        "restore": ["restore_snapshot"],
    }
    proposals = []
    for operation in OPERATION_ORDER:
        proposed = delta_order[operation] if operation in {"place", "restore"} else []
        proposals.append({
            "operation": operation, "status": "accepted", "authority": "proposal_only",
            "preauthorized_confirmation": False, "preauthorized_commit": False,
            "blocker": {"code": "capability_not_ready", "mutation_count": 0} if operation in {"replace", "remove"} else None,
            "proposed_operation_kinds": proposed,
        })
    result = {
        "trace_format": "reroom_transaction_trace_v1",
        "fixture": {"fixture_id": "FX-TRANSACTION-001", "fixture_revision": "rev-001", "manifest_sha256": PINNED_MANIFEST_SHA256},
        "runtime": {"language": "python", "name": "ReRoomTransactionPython", "version": f"python-{EXACT_PYTHON_VERSION}"},
        "implementation": {
            "repository_revision": implementation_revision,
            "source_tree_sha256": _source_tree_digest(repository),
            "source_files": SOURCE_FILES,
        },
        "operation_order": OPERATION_ORDER,
        "operation_delta_order": delta_order,
        "proposals": proposals,
        "safety": {"injection_case_id": "intent.transform-injection", "injection_verdict": "reject", "injection_rejection": "unknown_property", "injection_mutation_count": 0},
        "cases": case_results,
        "fingerprints": {"place_request_sha256": values["place_fingerprint"], "restore_request_sha256": values["restore_fingerprint"]},
        "projections": {
            "base_sha256": values["base_sha"], "placed_sha256": values["placed_sha"], "restored_sha256": values["base_sha"],
            "touched_object_ids": [], "touched_placed_asset_ids": [IDS["asset_instance"]], "touched_asset_support_relation_ids": [IDS["support"]],
        },
        "revisions": {"preview_scene_revision": 0, "place_scene_revision": 1, "restore_scene_revision": 2},
        "receipts": [
            {"transaction_id": values["identity"]["transaction_id"], "committed_scene_revision": 1, "request_fingerprint_sha256": values["place_fingerprint"], "result_sha256": values["placed_sha"]},
            {"transaction_id": IDS["restore_transaction"], "committed_scene_revision": 2, "request_fingerprint_sha256": values["restore_fingerprint"], "result_sha256": values["base_sha"]},
        ],
        "retry": {"same_key_same_fingerprint": "prior_result", "same_key_changed_fingerprint": "idempotency_conflict", "duplicate_mutation_count": 0},
        "restore": {"compensates_transaction_id": values["identity"]["transaction_id"], "network_reads": 0, "source_transaction_immutable": True, "preserved_unaffected_state": True},
        "divergence": {"mutation_frozen": True, "automatic_merge_permitted": False, "histories_preserved": 2, "resolution": "quarantined_divergent_branch"},
        "traces": actual_traces,
    }
    return canonical_bytes(result)


def run_transaction_trace(
    manifest_path: str | Path,
    output_path: str | Path,
    repo_root: str | Path,
    implementation_revision: str,
    *,
    runtime_version: str | None = None,
) -> None:
    destination = Path(output_path).resolve()
    _require(not destination.exists(), "output path must not exist")
    raw = produce_transaction_trace(manifest_path, repo_root, implementation_revision, runtime_version=runtime_version)
    temporary = destination.with_name(f"{destination.name}.tmp-{uuid.uuid4().hex}")
    descriptor: int | None = None
    try:
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.write(descriptor, raw)
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = None
        _require(not destination.exists(), "output path must not exist")
        os.replace(temporary, destination)
    finally:
        if descriptor is not None:
            os.close(descriptor)
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def _main(arguments: list[str]) -> int:
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--implementation-revision", required=True)
    values = parser.parse_args(arguments)
    try:
        run_transaction_trace(values.manifest, values.output, values.repo_root, values.implementation_revision)
    except TransactionTraceFailure as error:
        print(f"transaction-python: FAIL: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv[1:]))
