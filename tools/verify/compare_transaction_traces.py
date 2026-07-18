#!/usr/bin/env python3
"""Fail-closed fixture verifier and exact three-runtime transaction comparator."""

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


MAXIMUM_RESULT_BYTES = 262_144
MAXIMUM_FIXTURE_BYTES = 65_536
MAXIMUM_DEPTH = 32
PINNED_MANIFEST_SHA256 = "4aceda98f3dcb6bc0cf3efaef63852b67a86ea22b0455eb07d3fb9cdd34b371a"
PINNED_CASES_SHA256 = "ab93381ddc9af5544501f2504c3d4a38f6b7d23d3115ee0fd78d99cc2286de62"
PINNED_TRACES_SHA256 = "cd32be368796d6666205024122a65b6443463e11430852217810aeed6786505d"
PINNED_RESULT_SCHEMA_SHA256 = "b82f11e94ad7300f19751ee0da62f92e38f7a5022b713abab2bfb86cc211dc1d"
PINNED_SCHEMA_BINDINGS = {
    "docs/contracts/scene-state.schema.json": "9c77d27762e20ff5fad24c438e8817a03c770b55be3fc82ea72097c4c273e440",
    "docs/contracts/transaction.schema.json": "2a4f6728978db0879b5dfb10f052f6d5280e5cf83ad5600f0cf959626c2399a2",
}
RUNTIME_IDENTITIES = {
    "swift": {"language": "swift", "name": "ReRoomTransactionSwift", "version": "swift-6.1"},
    "typescript": {"language": "typescript", "name": "ReRoomTransactionNode", "version": "node-v22.22.3"},
    "python": {"language": "python", "name": "ReRoomTransactionPython", "version": "python-3.13.12"},
}
EXPECTED_OPERATION_ORDER = ["place", "replace", "remove", "restore"]
EXPECTED_OPERATION_DELTAS = {
    "place": ["create_asset_instance"],
    "replace": ["set_object_visibility", "create_asset_instance"],
    "remove": ["set_reveal_bundle", "set_object_visibility"],
    "restore": ["restore_snapshot"],
}
EXPECTED_PROPOSALS = [
    {"authority": "proposal_only", "blocker": None, "operation": "place", "preauthorized_commit": False, "preauthorized_confirmation": False, "proposed_operation_kinds": ["create_asset_instance"], "status": "accepted"},
    {"authority": "proposal_only", "blocker": {"code": "capability_not_ready", "mutation_count": 0}, "operation": "replace", "preauthorized_commit": False, "preauthorized_confirmation": False, "proposed_operation_kinds": [], "status": "accepted"},
    {"authority": "proposal_only", "blocker": {"code": "capability_not_ready", "mutation_count": 0}, "operation": "remove", "preauthorized_commit": False, "preauthorized_confirmation": False, "proposed_operation_kinds": [], "status": "accepted"},
    {"authority": "proposal_only", "blocker": None, "operation": "restore", "preauthorized_commit": False, "preauthorized_confirmation": False, "proposed_operation_kinds": ["restore_snapshot"], "status": "accepted"},
]
EXPECTED_FAMILIES: dict[str, Any] = {
    "fingerprints": {
        "place_request_sha256": "90d76a310ab26393a687202458b5f5742c3a94cc112553760567b25f0947755c",
        "restore_request_sha256": "abd6d3eb1b2eed9d73f70e099587ab0c0d194b8aa0a1db0a76ae693523e37725",
    },
    "projections": {
        "base_sha256": "d95451be43ee9dae2a1ef79259f0efed979d17f98503e7ae0ad94b992e1e0e4a",
        "placed_sha256": "5bacfe7d2a46fbba6c4d833cf74f46d2835474954c54bd393f2aac42e0c6ce72",
        "restored_sha256": "d95451be43ee9dae2a1ef79259f0efed979d17f98503e7ae0ad94b992e1e0e4a",
        "touched_asset_support_relation_ids": ["support_30000000-0000-4000-8000-000000000001"],
        "touched_object_ids": [],
        "touched_placed_asset_ids": ["assetinst_30000000-0000-4000-8000-000000000001"],
    },
    "revisions": {"place_scene_revision": 1, "preview_scene_revision": 0, "restore_scene_revision": 2},
    "receipts": [
        {"committed_scene_revision": 1, "request_fingerprint_sha256": "90d76a310ab26393a687202458b5f5742c3a94cc112553760567b25f0947755c", "result_sha256": "5bacfe7d2a46fbba6c4d833cf74f46d2835474954c54bd393f2aac42e0c6ce72", "transaction_id": "tx_30000000-0000-4000-8000-000000000001"},
        {"committed_scene_revision": 2, "request_fingerprint_sha256": "abd6d3eb1b2eed9d73f70e099587ab0c0d194b8aa0a1db0a76ae693523e37725", "result_sha256": "d95451be43ee9dae2a1ef79259f0efed979d17f98503e7ae0ad94b992e1e0e4a", "transaction_id": "tx_30000000-0000-4000-8000-000000000002"},
    ],
    "retry": {"duplicate_mutation_count": 0, "same_key_changed_fingerprint": "idempotency_conflict", "same_key_same_fingerprint": "prior_result"},
    "restore": {"compensates_transaction_id": "tx_30000000-0000-4000-8000-000000000001", "network_reads": 0, "preserved_unaffected_state": True, "source_transaction_immutable": True},
    "divergence": {"automatic_merge_permitted": False, "histories_preserved": 2, "mutation_frozen": True, "resolution": "quarantined_divergent_branch"},
}
EXPECTED_SAFETY = {"injection_case_id": "intent.transform-injection", "injection_mutation_count": 0, "injection_rejection": "unknown_property", "injection_verdict": "reject"}
REVISION_PATTERN = re.compile(r"git:[0-9a-f]{40}\Z")


class TransactionComparisonError(RuntimeError):
    """A stable error that never embeds a path, payload, or private value."""


@dataclass(frozen=True)
class VerifiedTransactionFixture:
    manifest: dict[str, Any]
    manifest_sha256: str
    root: Path
    cases: tuple[dict[str, Any], ...]
    traces: tuple[dict[str, Any], ...]


@dataclass(frozen=True)
class TransactionComparison:
    runtimes: tuple[str, ...]
    case_count: int
    semantic_disagreements: int = 0
    provenance_disagreements: int = 0


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_bytes(value: Any) -> bytes:
    try:
        return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")
    except (TypeError, ValueError, UnicodeEncodeError) as error:
        raise TransactionComparisonError("canonical_json") from error


def _duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise TransactionComparisonError("json_duplicate_name")
        value[key] = item
    return value


def _check_depth(value: Any) -> None:
    stack = [(value, 1)]
    while stack:
        current, depth = stack.pop()
        if depth > MAXIMUM_DEPTH:
            raise TransactionComparisonError("json_depth_limit")
        if isinstance(current, str):
            if any(0xD800 <= ord(character) <= 0xDFFF for character in current):
                raise TransactionComparisonError("json_invalid_unicode")
        elif isinstance(current, dict):
            stack.extend((item, depth + 1) for item in current.values())
        elif isinstance(current, list):
            stack.extend((item, depth + 1) for item in current)


def _regular_bytes(path: Path, mismatch: str, maximum: int) -> bytes:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise TransactionComparisonError(f"{mismatch}:missing") from error
    if path.is_symlink() or not stat.S_ISREG(metadata.st_mode):
        raise TransactionComparisonError(f"{mismatch}:not_regular")
    if not 0 < metadata.st_size <= maximum:
        raise TransactionComparisonError(f"{mismatch}:size_limit")
    try:
        data = path.read_bytes()
    except OSError as error:
        raise TransactionComparisonError(f"{mismatch}:unreadable") from error
    if len(data) != metadata.st_size:
        raise TransactionComparisonError(f"{mismatch}:changed_during_read")
    return data


def _read_json(path: Path, mismatch: str, maximum: int) -> tuple[dict[str, Any], bytes]:
    raw = _regular_bytes(path, mismatch, maximum)
    try:
        value = json.loads(raw, object_pairs_hook=_duplicates)
    except TransactionComparisonError:
        raise
    except (UnicodeDecodeError, json.JSONDecodeError, RecursionError) as error:
        raise TransactionComparisonError(f"{mismatch}:malformed_json") from error
    if not isinstance(value, dict):
        raise TransactionComparisonError(f"{mismatch}:root_type")
    _check_depth(value)
    return value, raw


def _safe_file(root: Path, relative: str, mismatch: str) -> Path:
    if not isinstance(relative, str) or not relative or relative.startswith("/") or "\\" in relative or any(part in {"", ".", ".."} for part in relative.split("/")):
        raise TransactionComparisonError(f"{mismatch}:invalid_path")
    candidate = root
    for component in relative.split("/"):
        candidate /= component
        try:
            metadata = candidate.lstat()
        except OSError as error:
            raise TransactionComparisonError(f"{mismatch}:missing") from error
        if candidate.is_symlink():
            raise TransactionComparisonError(f"{mismatch}:symlink")
    if not stat.S_ISREG(metadata.st_mode):
        raise TransactionComparisonError(f"{mismatch}:wrong_type")
    return candidate


def _validate_schema(value: dict[str, Any], schema_path: Path, runtime: str) -> None:
    schema, raw = _read_json(schema_path, "result_schema_file", MAXIMUM_FIXTURE_BYTES)
    if _sha256(raw) != PINNED_RESULT_SCHEMA_SHA256:
        raise TransactionComparisonError("result_schema_sha256")
    errors = sorted(Draft202012Validator(schema).iter_errors(value), key=lambda item: tuple(str(part) for part in item.absolute_path))
    if errors:
        location = ".".join(str(part) for part in errors[0].absolute_path) or "root"
        raise TransactionComparisonError(f"result_schema:{runtime}:{location}")


def verify_transaction_fixture(manifest_path: Path | str, *, repo_root: Path | str | None = None) -> VerifiedTransactionFixture:
    repository = Path(repo_root).resolve() if repo_root is not None else Path(__file__).resolve().parents[2]
    path = Path(manifest_path).resolve()
    manifest, raw = _read_json(path, "fixture_manifest", MAXIMUM_FIXTURE_BYTES)
    if _sha256(raw) != PINNED_MANIFEST_SHA256:
        raise TransactionComparisonError("fixture_manifest_sha256")
    required = {"schema_version", "fixture_id", "fixture_revision", "subject", "oracle", "schema_bindings", "files"}
    if set(manifest) != required or manifest.get("fixture_id") != "FX-TRANSACTION-001" or manifest.get("fixture_revision") != "rev-001":
        raise TransactionComparisonError("fixture_manifest_identity")
    oracle = manifest.get("oracle")
    if oracle != {"status": "immutable", "source": "checked_in", "expected_generation": "forbidden_during_verification", "case_order": "lexicographic_case_id", "operation_order": EXPECTED_OPERATION_ORDER}:
        raise TransactionComparisonError("fixture_oracle_policy")
    if not isinstance(manifest.get("files"), list) or len(manifest["files"]) != 2:
        raise TransactionComparisonError("fixture_file_binding")
    bound_files: dict[str, dict[str, Any]] = {}
    for entry in manifest["files"]:
        if not isinstance(entry, dict) or set(entry) != {"relative_path", "media_type", "byte_length", "sha256"}:
            raise TransactionComparisonError("fixture_file_binding")
        relative = entry.get("relative_path")
        if relative in bound_files or relative not in {"cases.json", "expected-traces.json"}:
            raise TransactionComparisonError("fixture_file_binding")
        bound_files[relative] = entry
        target = _safe_file(path.parent, relative, "fixture_file")
        data = _regular_bytes(target, "fixture_file", MAXIMUM_FIXTURE_BYTES)
        if len(data) != entry.get("byte_length") or _sha256(data) != entry.get("sha256"):
            raise TransactionComparisonError("fixture_file_sha256")
    if bound_files["cases.json"].get("sha256") != PINNED_CASES_SHA256 or bound_files["expected-traces.json"].get("sha256") != PINNED_TRACES_SHA256:
        raise TransactionComparisonError("fixture_file_sha256")
    if not isinstance(manifest.get("schema_bindings"), list) or len(manifest["schema_bindings"]) != 2:
        raise TransactionComparisonError("fixture_schema_binding")
    seen_bindings: set[str] = set()
    for entry in manifest["schema_bindings"]:
        if not isinstance(entry, dict) or set(entry) != {"contract_id", "schema_id", "version", "relative_path", "byte_length", "sha256"}:
            raise TransactionComparisonError("fixture_schema_binding")
        relative = entry.get("relative_path")
        if relative in seen_bindings or PINNED_SCHEMA_BINDINGS.get(relative) != entry.get("sha256"):
            raise TransactionComparisonError("fixture_schema_binding")
        seen_bindings.add(relative)
        data = _regular_bytes(_safe_file(repository, relative, "fixture_schema"), "fixture_schema", MAXIMUM_FIXTURE_BYTES)
        if len(data) != entry.get("byte_length") or _sha256(data) != entry.get("sha256"):
            raise TransactionComparisonError("fixture_schema_sha256")
    cases_document, _ = _read_json(path.parent / "cases.json", "fixture_cases", MAXIMUM_FIXTURE_BYTES)
    traces_document, _ = _read_json(path.parent / "expected-traces.json", "fixture_traces", MAXIMUM_FIXTURE_BYTES)
    if set(cases_document) != {"schema_version", "fixture_id", "fixture_revision", "contract_bindings", "identity", "operation_inventory", "canonical_lifecycle", "terminal_lifecycle", "cases"}:
        raise TransactionComparisonError("fixture_cases_shape")
    cases = cases_document.get("cases")
    if not isinstance(cases, list) or len(cases) != 24 or any(not isinstance(item, dict) or set(item) not in ({"case_id", "expected"}, {"case_id", "expected", "rejection"}) for item in cases):
        raise TransactionComparisonError("fixture_case_set")
    case_ids = [item["case_id"] for item in cases]
    if case_ids != sorted(case_ids) or len(set(case_ids)) != 24:
        raise TransactionComparisonError("fixture_case_order")
    if set(traces_document) != {"schema_version", "fixture_id", "fixture_revision", "trace_format", "traces"} or traces_document.get("trace_format") != "reroom_transaction_trace_v1":
        raise TransactionComparisonError("fixture_trace_shape")
    traces = traces_document.get("traces")
    if not isinstance(traces, list) or len(traces) != 3:
        raise TransactionComparisonError("fixture_trace_set")
    return VerifiedTransactionFixture(manifest, PINNED_MANIFEST_SHA256, path.parent, tuple(cases), tuple(traces))


def _expected_sources(repository: Path, runtime: str) -> tuple[list[str], str]:
    if runtime == "typescript":
        files = ["tools/javascript/src/canonical-json.mjs", "tools/javascript/src/transaction.ts"]
    elif runtime == "python":
        files = ["tools/python/reroom_verify/transaction.py"]
    else:
        core = repository / "ios/Packages/ReRoomContracts/Sources/ReRoomTransactionCore"
        try:
            files = sorted(str(path.relative_to(repository)) for path in core.iterdir() if path.suffix == ".swift")
        except OSError as error:
            raise TransactionComparisonError("source_binding:swift") from error
        files.extend([
            "ios/Packages/ReRoomContracts/Sources/ReRoomTransactionTraceExporter/NormalizedTraceResult.swift",
            "ios/Packages/ReRoomContracts/Sources/ReRoomTransactionTraceExporter/main.swift",
        ])
        files.sort()
    records = bytearray()
    for relative in files:
        data = _regular_bytes(_safe_file(repository, relative, "source_file"), "source_file", 2_097_152)
        records.extend(relative.encode("utf-8"))
        records.extend(b"\0")
        records.extend(_sha256(data).encode("ascii"))
        records.extend(b"\n")
    return files, _sha256(bytes(records))


def _expected_cases(fixture: VerifiedTransactionFixture) -> list[dict[str, Any]]:
    return [{"case_id": item["case_id"], "outcome": item["expected"], "rejection": item.get("rejection")} for item in fixture.cases]


def compare_transaction_traces(
    manifest_path: Path | str,
    outputs: Mapping[str, Path | str],
    *,
    repo_root: Path | str | None = None,
    implementation_revision: str,
) -> TransactionComparison:
    repository = Path(repo_root).resolve() if repo_root is not None else Path(__file__).resolve().parents[2]
    if not REVISION_PATTERN.fullmatch(implementation_revision):
        raise TransactionComparisonError("implementation_revision")
    if tuple(outputs) != tuple(RUNTIME_IDENTITIES) or set(outputs) != set(RUNTIME_IDENTITIES):
        raise TransactionComparisonError("runtime_set")
    fixture = verify_transaction_fixture(manifest_path, repo_root=repository)
    schema_path = Path(__file__).with_name("transaction-trace-result.schema.json")
    expected_cases = _expected_cases(fixture)
    expected_traces = list(fixture.traces)
    normalized: list[bytes] = []
    for runtime in RUNTIME_IDENTITIES:
        value, raw = _read_json(Path(outputs[runtime]), f"result:{runtime}", MAXIMUM_RESULT_BYTES)
        if raw != canonical_bytes(value):
            raise TransactionComparisonError(f"result_canonical:{runtime}")
        _validate_schema(value, schema_path, runtime)
        if value.get("runtime") != RUNTIME_IDENTITIES[runtime]:
            raise TransactionComparisonError(f"runtime_identity:{runtime}")
        if value.get("implementation", {}).get("repository_revision") != implementation_revision:
            raise TransactionComparisonError(f"implementation_revision:{runtime}")
        if value.get("fixture") != {"fixture_id": "FX-TRANSACTION-001", "fixture_revision": "rev-001", "manifest_sha256": PINNED_MANIFEST_SHA256} or value.get("trace_format") != "reroom_transaction_trace_v1":
            raise TransactionComparisonError(f"fixture_identity:{runtime}")
        source_files, source_digest = _expected_sources(repository, runtime)
        implementation = value["implementation"]
        if implementation["source_files"] != source_files or implementation["source_tree_sha256"] != source_digest:
            raise TransactionComparisonError(f"source_binding:{runtime}")
        if value["operation_order"] != EXPECTED_OPERATION_ORDER or value["operation_delta_order"] != EXPECTED_OPERATION_DELTAS:
            raise TransactionComparisonError(f"operation_oracle:{runtime}")
        if value["proposals"] != EXPECTED_PROPOSALS:
            raise TransactionComparisonError(f"proposal_oracle:{runtime}")
        if value["safety"] != EXPECTED_SAFETY:
            raise TransactionComparisonError(f"injection_oracle:{runtime}")
        if len(value["cases"]) != len(expected_cases) or [item.get("case_id") for item in value["cases"]] != [item["case_id"] for item in expected_cases]:
            raise TransactionComparisonError(f"case_set:{runtime}")
        for actual, expected in zip(value["cases"], expected_cases, strict=True):
            if actual != expected:
                raise TransactionComparisonError(f"case_oracle:{runtime}:{expected['case_id']}")
        for family, expected in EXPECTED_FAMILIES.items():
            if value[family] != expected:
                raise TransactionComparisonError(f"{family}_oracle:{runtime}")
        if value["traces"] != expected_traces:
            raise TransactionComparisonError(f"traces_oracle:{runtime}")
        semantic = {key: value[key] for key in ("operation_order", "operation_delta_order", "proposals", "safety", "cases", *EXPECTED_FAMILIES, "traces")}
        normalized.append(canonical_bytes(semantic))
    if len(set(normalized)) != 1:
        raise TransactionComparisonError("semantic_disagreement")
    return TransactionComparison(tuple(RUNTIME_IDENTITIES), len(expected_cases))


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--implementation-revision", required=True)
    for runtime in RUNTIME_IDENTITIES:
        parser.add_argument(f"--{runtime}", required=True, type=Path)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parser().parse_args(argv)
    try:
        result = compare_transaction_traces(
            arguments.manifest,
            {runtime: getattr(arguments, runtime) for runtime in RUNTIME_IDENTITIES},
            repo_root=arguments.repo_root,
            implementation_revision=arguments.implementation_revision,
        )
    except TransactionComparisonError as error:
        print(f"transaction-comparison: FAIL ({error})", file=sys.stderr)
        return 1
    print(f"transaction-comparison: PASS ({result.case_count} cases, 3 runtimes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
