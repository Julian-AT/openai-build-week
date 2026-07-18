#!/usr/bin/env python3
"""Fail-closed Phase 8 sprint hardening composition and evidence helpers.

This module deliberately distinguishes a passing automated sprint slice from
formal release, device, browser, human, security, and licensing acceptance.
"""

from __future__ import annotations

import copy
import hashlib
import importlib.machinery
import importlib.util
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path
from typing import Any, Callable, Mapping, NoReturn, Sequence


ROOT = Path(__file__).resolve().parents[2]
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
REVISION_RE = re.compile(r"^git:[0-9a-f]{40}$")

UPSTREAMS: tuple[dict[str, str], ...] = (
    {
        "phase_id": "phase-02",
        "summary": ".planning/phases/02-atomic-capture-and-exact-replay/02-07-SUMMARY.md",
        "verifier": "scripts/verify-phase-02-capture-replay",
        "evidence": "evidence/capture/phase-02/automated-preflight.json",
        "verification": ".planning/phases/02-atomic-capture-and-exact-replay/02-VERIFICATION.md",
    },
    {
        "phase_id": "phase-03",
        "summary": ".planning/phases/03-typed-place-commit-and-offline-restore/03-07-SUMMARY.md",
        "verifier": "scripts/verify-phase-03-transactions",
        "evidence": "evidence/transactions/phase-03/automated-preflight.json",
        "verification": ".planning/phases/03-typed-place-commit-and-offline-restore/03-VERIFICATION.md",
    },
    {
        "phase_id": "phase-04",
        "summary": ".planning/phases/04-target-grounding-and-compositor-gate/04-04-SUMMARY.md",
        "verifier": "scripts/verify-phase-04-targeting",
        "evidence": "evidence/targeting/phase-04/automated-preflight.json",
        "verification": ".planning/phases/04-target-grounding-and-compositor-gate/04-VERIFICATION.md",
    },
    {
        "phase_id": "phase-05",
        "summary": ".planning/phases/05-curated-replacement-vertical/05-04-SUMMARY.md",
        "verifier": "scripts/verify-phase-05-replacement",
        "evidence": "evidence/replacement/phase-05/automated-preflight.json",
        "verification": ".planning/phases/05-curated-replacement-vertical/05-VERIFICATION.md",
    },
    {
        "phase_id": "phase-06",
        "summary": ".planning/phases/06-controlled-multi-surface-removal/06-04-SUMMARY.md",
        "verifier": "scripts/verify-phase-06-removal",
        "evidence": "evidence/removal/phase-06/automated-preflight.json",
        "verification": ".planning/phases/06-controlled-multi-surface-removal/06-VERIFICATION.md",
    },
    {
        "phase_id": "phase-07",
        "summary": ".planning/phases/07-separate-mode-b0-web-fallback/07-03-SUMMARY.md",
        "verifier": "scripts/verify-phase-07-b0",
        "evidence": "evidence/web/phase-07/automated-preflight.json",
        "verification": ".planning/phases/07-separate-mode-b0-web-fallback/07-VERIFICATION.md",
    },
)

LOCK_INPUTS = (
    "ios/Packages/ReRoomContracts/Package.resolved",
    "tools/javascript/package-lock.json",
    "web/package-lock.json",
    "tools/python/requirements.lock",
)
ASSET_INPUTS = (
    "ios/ReRoomDeviceProof/ReRoomDeviceProof/Resources/Phase3Proxy/PROVENANCE.md",
    "ios/ReRoomDeviceProof/ReRoomDeviceProof/Resources/Phase3Proxy/asset-manifest.json",
    "ios/ReRoomDeviceProof/ReRoomDeviceProof/Resources/Phase3Proxy/proxy-chair.usda",
    "ios/ReRoomDeviceProof/ReRoomDeviceProof/Resources/Phase6Reveal/PROVENANCE.md",
    "ios/ReRoomDeviceProof/ReRoomDeviceProof/Resources/Phase6Reveal/demo-reveal-fixture.json",
)

BOM_KEYS = {
    "schema_version", "evidence_kind", "implementation_revision", "recorded_at_utc",
    "authority_inputs", "members", "blockers", "shipping_status", "requirements",
    "gates", "limitations", "evidence_sha256",
}
MEMBER_KEYS = {
    "member_id", "kind", "name", "exact_version_or_digest", "source",
    "terms_reference", "attribution_reference", "shipping_surface", "decision",
}
PREFLIGHT_KEYS = {
    "schema_version", "evidence_kind", "implementation_revision", "recorded_at_utc",
    "classification", "automated_sprint_slice", "readiness", "checks", "source_bindings",
    "bom", "requirements", "formal_gates", "claims", "limitations", "privacy",
    "evidence_sha256",
}


class HardeningRejected(ValueError):
    def __init__(self, code: str, artifact_class: str | None = None):
        self.code = code
        self.artifact_class = artifact_class
        super().__init__(code if artifact_class is None else f"{code}:{artifact_class}")


def reject(code: str, artifact_class: str | None = None) -> NoReturn:
    raise HardeningRejected(code, artifact_class)


def canonical_bytes(value: object) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def document_sha256(value: Mapping[str, object]) -> str:
    unsigned = copy.deepcopy(dict(value))
    unsigned.pop("evidence_sha256", None)
    return hashlib.sha256(canonical_bytes(unsigned)).hexdigest()


def _exact_dict(value: object, keys: set[str], code: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        reject(code)
    return value


def _verification_status(path: Path) -> str | None:
    match = re.search(r"(?m)^status:\s*([a-z_]+)\s*$", path.read_text(encoding="utf-8"))
    return match.group(1) if match else None


def audit_readiness(
    root: Path,
    invoke: Callable[[str, Path], None],
) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for item in UPSTREAMS:
        status = "READY"
        diagnostic = "UPSTREAM_AUTHORITY_VALIDATED"
        paths = [root / item[key] for key in ("summary", "verifier", "evidence", "verification")]
        if any(not path.is_file() or path.is_symlink() for path in paths):
            status, diagnostic = "BLOCKED_BY_UPSTREAM", "UPSTREAM_SURFACE_MISSING"
        elif not os.access(root / item["verifier"], os.X_OK):
            status, diagnostic = "BLOCKED_BY_UPSTREAM", "UPSTREAM_VERIFIER_NOT_EXECUTABLE"
        else:
            verification_status = _verification_status(root / item["verification"])
            if verification_status not in {"passed", "human_needed"}:
                status, diagnostic = "FAILED", "UPSTREAM_VERIFICATION_NOT_ACCEPTABLE"
            else:
                try:
                    invoke(item["phase_id"], root)
                except Exception:
                    status, diagnostic = "FAILED", "UPSTREAM_AUTHORITY_REJECTED"
        rows.append({"phase_id": item["phase_id"], "status": status, "diagnostic": diagnostic})
    return rows


def _load_script(path: Path, name: str) -> Any:
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    specification = importlib.util.spec_from_loader(name, loader)
    if specification is None:
        reject("E08_UPSTREAM_AUTHORITY")
    module = importlib.util.module_from_spec(specification)
    loader.exec_module(module)
    return module


def _validate_historical_bindings(
    root: Path, report: Mapping[str, object], paths: Mapping[str, str],
) -> None:
    revision_value = report.get("implementation_revision")
    bindings = report.get("source_bindings")
    if not isinstance(revision_value, str) or not REVISION_RE.fullmatch(revision_value) or not isinstance(bindings, dict):
        reject("E08_UPSTREAM_BINDING")
    revision = revision_value.removeprefix("git:")
    if set(bindings) != set(paths):
        reject("E08_UPSTREAM_BINDING")
    for key, relative in paths.items():
        result = subprocess.run(
            ["git", "show", f"{revision}:{relative}"], cwd=root,
            check=False, capture_output=True, timeout=20,
        )
        if result.returncode != 0 or hashlib.sha256(result.stdout).hexdigest() != bindings[key]:
            reject("E08_UPSTREAM_BINDING")


def _validate_current_bindings(
    root: Path, report: Mapping[str, object], paths: Mapping[str, str],
    *, superseded_keys: set[str] = set(),
) -> None:
    bindings = report.get("source_bindings")
    if not isinstance(bindings, dict) or set(bindings) != set(paths):
        reject("E08_UPSTREAM_BINDING")
    for key, relative in paths.items():
        if key in superseded_keys:
            continue
        if sha256_file(root / relative) != bindings[key]:
            reject("E08_UPSTREAM_BINDING")
    if superseded_keys:
        phase06 = json.loads((root / "evidence/removal/phase-06/automated-preflight.json").read_text(encoding="utf-8"))
        later = phase06.get("source_bindings")
        if not isinstance(later, dict):
            reject("E08_UPSTREAM_BINDING")
        for key in superseded_keys:
            if key not in later or sha256_file(root / paths[key]) != later[key]:
                reject("E08_UPSTREAM_BINDING")


def validate_upstream_authority(phase_id: str, root: Path = ROOT) -> None:
    item = next((value for value in UPSTREAMS if value["phase_id"] == phase_id), None)
    if item is None:
        reject("E08_UPSTREAM_ID")
    report = json.loads((root / item["evidence"]).read_text(encoding="utf-8"))
    if phase_id == "phase-02":
        from tools.verify import verify_phase_02_gate
        verify_phase_02_gate.validate_automated_preflight(report)
    elif phase_id in {"phase-03", "phase-04", "phase-05", "phase-06"}:
        module = _load_script(root / item["verifier"], "phase08_" + phase_id.replace("-", "_"))
        if phase_id == "phase-03":
            module.validate_evidence(report)
            _validate_current_bindings(root, report, {
                "comparator_sha256": module.COMPARATOR_RELATIVE_PATH,
                "orchestrator_sha256": module.ORCHESTRATOR_RELATIVE_PATH,
                "result_schema_sha256": module.RESULT_SCHEMA_RELATIVE_PATH,
            })
        elif phase_id == "phase-04":
            module.validate_evidence(report)
            _validate_current_bindings(
                root, report, module.SOURCE_BINDING_PATHS,
                superseded_keys={"room_edit_model_sha256", "room_edit_view_sha256", "model_tests_sha256", "ui_tests_sha256"},
            )
        else:
            module._validate_report(report, require_self_digest=True)
            _validate_current_bindings(
                root, report, module.SOURCE_BINDING_PATHS,
                superseded_keys={"room_edit_model_sha256", "room_edit_view_sha256", "model_tests_sha256", "ui_tests_sha256"} if phase_id == "phase-05" else set(),
            )
    elif phase_id == "phase-07":
        from tools.verify import verify_phase_07_b0
        verify_phase_07_b0.validate_source(root)
        verify_phase_07_b0.validate_evidence(report, root=root)


_CREDENTIAL_PATTERNS = (
    re.compile(b"s" + b"k-" + b"[A-Za-z0-9_-]{20,}"),
    re.compile(b"AK" + b"IA[0-9A-Z]{16}"),
    re.compile(b"gh" + b"[ps]_[A-Za-z0-9]{30,}"),
    re.compile(b"xox" + b"[aboprs]-[A-Za-z0-9-]{10,}"),
    re.compile(b"BEGIN " + b"(?:RSA |EC |OPENSSH )?PRIVATE KEY"),
)


def scan_bytes(value: bytes, artifact_class: str) -> None:
    if any(pattern.search(value) for pattern in _CREDENTIAL_PATTERNS):
        reject("E08_CREDENTIAL_SIGNATURE", artifact_class)


def scan_files(root: Path, relative_paths: Sequence[str], artifact_class: str) -> dict[str, str]:
    bindings: dict[str, str] = {}
    for relative in sorted(set(relative_paths)):
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts:
            reject("E08_SCAN_SCOPE")
        absolute = root / path
        if not absolute.is_file() or absolute.is_symlink():
            reject("E08_SCAN_SCOPE")
        content = absolute.read_bytes()
        scan_bytes(content, artifact_class)
        bindings[path.as_posix()] = hashlib.sha256(content).hexdigest()
    return bindings


def fixture_bom_member() -> dict[str, str]:
    return {
        "member_id": "asset:fixture", "kind": "asset", "name": "fixture",
        "exact_version_or_digest": "sha256:" + "1" * 64, "source": "fixture/asset",
        "terms_reference": "ROOT_LICENSE_MISSING", "attribution_reference": "fixture/provenance",
        "shipping_surface": "ios_demo", "decision": "BLOCKED",
    }


def build_bom(
    *, implementation_revision: str, recorded_at_utc: str,
    members: Sequence[Mapping[str, str]], authority_inputs: Sequence[str] = (),
) -> dict[str, object]:
    return {
        "schema_version": "1.0.0", "evidence_kind": "phase_08_exact_sprint_bom",
        "implementation_revision": implementation_revision, "recorded_at_utc": recorded_at_utc,
        "authority_inputs": sorted(authority_inputs),
        "members": sorted((dict(member) for member in members), key=lambda item: item["member_id"]),
        "blockers": ["PROXY_USE_REDISTRIBUTION_DECISION_MISSING", "ROOT_LICENSE_MISSING"],
        "shipping_status": "BLOCKED", "requirements": {"OPS-LICENSE-001": "PENDING"},
        "gates": {"GATE-011": "PENDING"},
        "limitations": [
            "The repository has no root product license.",
            "Repository-owned proxy use and redistribution approval is not recorded.",
            "This inventory is an automated sprint artifact, not formal license acceptance.",
        ],
    }


def seal_bom(value: dict[str, object]) -> dict[str, object]:
    value["evidence_sha256"] = document_sha256(value)
    return value


def validate_bom(value: object, *, expected_member_ids: set[str] | None = None) -> None:
    report = _exact_dict(value, BOM_KEYS, "E08_BOM_SHAPE")
    if report["schema_version"] != "1.0.0" or report["evidence_kind"] != "phase_08_exact_sprint_bom":
        reject("E08_BOM_SHAPE")
    if not REVISION_RE.fullmatch(report["implementation_revision"]):
        reject("E08_REVISION")
    if report["shipping_status"] != "BLOCKED" or report["requirements"] != {"OPS-LICENSE-001": "PENDING"}:
        reject("E08_LICENSE_PROMOTION")
    if report["gates"] != {"GATE-011": "PENDING"}:
        reject("E08_GATE_PROMOTION")
    if report["blockers"] != ["PROXY_USE_REDISTRIBUTION_DECISION_MISSING", "ROOT_LICENSE_MISSING"]:
        reject("E08_LICENSE_CLOSURE")
    members = report["members"]
    if not isinstance(members, list) or not members:
        reject("E08_BOM_MEMBERS")
    ids: list[str] = []
    for member_value in members:
        member = _exact_dict(member_value, MEMBER_KEYS, "E08_BOM_MEMBER")
        if member["decision"] != "BLOCKED" or not isinstance(member["member_id"], str):
            reject("E08_BOM_MEMBER")
        ids.append(member["member_id"])
    if ids != sorted(ids) or len(ids) != len(set(ids)):
        reject("E08_BOM_MEMBERS")
    if expected_member_ids is not None and set(ids) != expected_member_ids:
        reject("E08_BOM_CLOSURE")
    _reject_private(value)
    if report["evidence_sha256"] != document_sha256(report):
        reject("E08_SELF_DIGEST")


def fixture_readiness_row() -> dict[str, str]:
    return {"phase_id": "phase-fixture", "status": "READY", "diagnostic": "UPSTREAM_AUTHORITY_VALIDATED"}


def fixture_check() -> dict[str, str]:
    return {"check_id": "fixture", "status": "PASS", "evidence_class": "SOURCE_BOUND_AUTOMATED"}


def build_preflight(
    *, implementation_revision: str, recorded_at_utc: str,
    readiness: Sequence[Mapping[str, str]], checks: Sequence[Mapping[str, str]],
    source_bindings: Mapping[str, str], bom_sha256: str,
) -> dict[str, object]:
    return {
        "schema_version": "1.0.0", "evidence_kind": "phase_08_hardening_automated_preflight",
        "implementation_revision": implementation_revision, "recorded_at_utc": recorded_at_utc,
        "classification": "AUTOMATED_PREFLIGHT", "automated_sprint_slice": "PASS",
        "readiness": [dict(row) for row in readiness], "checks": [dict(row) for row in checks],
        "source_bindings": dict(sorted(source_bindings.items())),
        "bom": {"path": "evidence/hardening/phase-08/sprint-bom.json", "sha256": bom_sha256, "shipping_status": "BLOCKED"},
        "requirements": {
            "NFR-RESILIENCE-001": "PENDING", "OPS-LICENSE-001": "PENDING",
            "SEC-AGENT-001": "PENDING", "SEC-CREDENTIAL-001": "PENDING",
        },
        "formal_gates": {"GATE-003": "PENDING", "GATE-006": "PENDING", "GATE-008": "PENDING", "GATE-011": "PENDING"},
        "claims": {
            "device_evidence": "NOT_CLAIMED", "browser_evidence": "NOT_CLAIMED",
            "human_evidence": "NOT_CLAIMED", "submission_readiness": "NOT_CLAIMED",
        },
        "limitations": [
            "Retained source-bound upstream evidence was validated; expensive Xcode and browser reruns were not performed.",
            "Automated sprint PASS does not complete any canonical requirement or formal gate.",
            "The exact sprint BOM is blocked by missing root license and proxy redistribution decisions.",
        ],
        "privacy": {"raw_room_data": False, "credentials": False, "user_identifiers": False, "machine_paths": False},
    }


def seal_preflight(value: dict[str, object]) -> dict[str, object]:
    value["evidence_sha256"] = document_sha256(value)
    return value


def validate_preflight(value: object) -> None:
    report = _exact_dict(value, PREFLIGHT_KEYS, "E08_PREFLIGHT_SHAPE")
    if report["schema_version"] != "1.0.0" or report["classification"] != "AUTOMATED_PREFLIGHT":
        reject("E08_PREFLIGHT_SHAPE")
    if report["automated_sprint_slice"] != "PASS" or not REVISION_RE.fullmatch(report["implementation_revision"]):
        reject("E08_PREFLIGHT_RESULT")
    expected_requirements = {
        "NFR-RESILIENCE-001": "PENDING", "OPS-LICENSE-001": "PENDING",
        "SEC-AGENT-001": "PENDING", "SEC-CREDENTIAL-001": "PENDING",
    }
    if report["requirements"] != expected_requirements:
        reject("E08_REQUIREMENT_PROMOTION")
    if report["formal_gates"] != {"GATE-003": "PENDING", "GATE-006": "PENDING", "GATE-008": "PENDING", "GATE-011": "PENDING"}:
        reject("E08_GATE_PROMOTION")
    expected_claims = {
        "device_evidence": "NOT_CLAIMED", "browser_evidence": "NOT_CLAIMED",
        "human_evidence": "NOT_CLAIMED", "submission_readiness": "NOT_CLAIMED",
    }
    if report["claims"] != expected_claims:
        reject("E08_CLAIM_PROMOTION")
    if report["bom"] != {
        "path": "evidence/hardening/phase-08/sprint-bom.json",
        "sha256": report["bom"].get("sha256") if isinstance(report["bom"], dict) else None,
        "shipping_status": "BLOCKED",
    } or not SHA256_RE.fullmatch(report["bom"]["sha256"]):
        reject("E08_BOM_BINDING")
    readiness = report["readiness"]
    if not isinstance(readiness, list) or not readiness or any(row.get("status") != "READY" for row in readiness if isinstance(row, dict)):
        reject("E08_READINESS")
    checks = report["checks"]
    if not isinstance(checks, list) or not checks or any(row.get("status") != "PASS" for row in checks if isinstance(row, dict)):
        reject("E08_CHECK")
    bindings = report["source_bindings"]
    if not isinstance(bindings, dict) or not bindings or any(not isinstance(k, str) or not SHA256_RE.fullmatch(v) for k, v in bindings.items()):
        reject("E08_SOURCE_BINDING")
    if report["privacy"] != {"raw_room_data": False, "credentials": False, "user_identifiers": False, "machine_paths": False}:
        reject("E08_PRIVACY")
    _reject_private(value)
    if report["evidence_sha256"] != document_sha256(report):
        reject("E08_SELF_DIGEST")


def _reject_private(value: object) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if str(key).lower() in {"credential", "secret", "user_identifier", "device_identifier", "room_data", "raw_output"}:
                reject("E08_PRIVATE_FIELD")
            _reject_private(child)
    elif isinstance(value, list):
        for child in value:
            _reject_private(child)
    elif isinstance(value, str):
        if value.startswith(("/Users/", "/home/", "/tmp/", "file://")):
            reject("E08_MACHINE_PATH")
        scan_bytes(value.encode(), "evidence")


def publish_pair(
    bom_path: Path, report_path: Path, bom: dict[str, object], report: dict[str, object],
    *, expected_member_ids: set[str] | None = None,
) -> None:
    validate_bom(bom, expected_member_ids=expected_member_ids)
    if report.get("bom", {}).get("sha256") != hashlib.sha256(canonical_bytes(bom)).hexdigest():
        reject("E08_BOM_BINDING")
    validate_preflight(report)
    bom_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_paths: list[Path] = []
    try:
        for target, value in ((bom_path, bom), (report_path, report)):
            descriptor, name = tempfile.mkstemp(prefix=".phase08-", dir=target.parent)
            temporary = Path(name)
            temporary_paths.append(temporary)
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(canonical_bytes(value))
                stream.flush()
                os.fsync(stream.fileno())
        temporary_paths[0].replace(bom_path)
        temporary_paths[1].replace(report_path)
    finally:
        for path in temporary_paths:
            path.unlink(missing_ok=True)


def git_revision_and_time(root: Path = ROOT) -> tuple[str, str]:
    revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, check=True, text=True, capture_output=True).stdout.strip()
    timestamp = subprocess.run(["git", "show", "-s", "--format=%cI", "HEAD"], cwd=root, check=True, text=True, capture_output=True).stdout.strip()
    return "git:" + revision, timestamp.replace("+00:00", "Z")


def tracked_shipping_files(root: Path = ROOT) -> list[str]:
    output = subprocess.run(["git", "ls-files", "-z"], cwd=root, check=True, capture_output=True).stdout
    allowed = ("ios/Packages/", "ios/ReRoomDeviceProof/ReRoomDeviceProof/", "web/src/", "tools/javascript/src/", "tools/python/src/")
    excluded = ("/Tests/", "/test/", "/.swiftpm/", ".xcodeproj/")
    return [path for path in output.decode().split("\0") if path and path.startswith(allowed) and not any(part in path for part in excluded)]


def _python_requirements(path: Path) -> list[tuple[str, str]]:
    return re.findall(r"(?m)^([A-Za-z0-9_.-]+)==([^\s\\]+)", path.read_text(encoding="utf-8"))


def exact_bom_members(root: Path = ROOT) -> list[dict[str, str]]:
    members: list[dict[str, str]] = []
    swift = json.loads((root / LOCK_INPUTS[0]).read_text(encoding="utf-8"))
    for pin in swift["pins"]:
        state = pin["state"]
        members.append({
            "member_id": f"swift:{pin['identity']}@{state['version']}", "kind": "swift_package",
            "name": pin["identity"], "exact_version_or_digest": f"{state['version']}+git:{state['revision']}",
            "source": pin["location"], "terms_reference": "evidence/dependencies/phase-01-package-audit.json",
            "attribution_reference": "evidence/dependencies/phase-01-package-audit.json",
            "shipping_surface": "ios", "decision": "BLOCKED",
        })
    for surface, relative in (("contract_tools", LOCK_INPUTS[1]), ("web_b0", LOCK_INPUTS[2])):
        lock = json.loads((root / relative).read_text(encoding="utf-8"))
        for package_path, package in lock.get("packages", {}).items():
            if not package_path or "version" not in package:
                continue
            name = package.get("name") or package_path.rsplit("node_modules/", 1)[-1]
            version = str(package["version"])
            members.append({
                "member_id": f"npm:{surface}:{name}@{version}", "kind": "npm_package", "name": name,
                "exact_version_or_digest": version, "source": relative,
                "terms_reference": relative, "attribution_reference": "evidence/dependencies/phase-01-package-audit.json",
                "shipping_surface": surface, "decision": "BLOCKED",
            })
    for name, version in _python_requirements(root / LOCK_INPUTS[3]):
        members.append({
            "member_id": f"pypi:{name}@{version}", "kind": "python_package", "name": name,
            "exact_version_or_digest": version, "source": LOCK_INPUTS[3],
            "terms_reference": "evidence/dependencies/phase-01-package-audit.json",
            "attribution_reference": "evidence/dependencies/phase-01-package-audit.json",
            "shipping_surface": "contract_tools", "decision": "BLOCKED",
        })
    for relative in ASSET_INPUTS:
        members.append({
            "member_id": "asset:" + relative, "kind": "repository_asset", "name": Path(relative).name,
            "exact_version_or_digest": "sha256:" + sha256_file(root / relative), "source": relative,
            "terms_reference": "ROOT_LICENSE_MISSING", "attribution_reference": relative if relative.endswith("PROVENANCE.md") else str(Path(relative).parent / "PROVENANCE.md"),
            "shipping_surface": "ios_demo", "decision": "BLOCKED",
        })
    return sorted(members, key=lambda item: item["member_id"])
