#!/usr/bin/env python3
"""Independent Phase 8 evidence-classification and documentation verifier."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Mapping, NoReturn, Sequence


ROOT = Path(__file__).resolve().parents[2]
RUNBOOK_PATH = "docs/demo/PHASE_08_DEMO_RUNBOOK.md"
HANDOFF_PATH = "docs/demo/BUILD_WEEK_SUBMISSION_HANDOFF.md"
INDEX_PATH = "evidence/hardening/phase-08/evidence-index.json"
GATES_PATH = "evidence/hardening/phase-08/pending-gates.json"
PERMITTED_CLAIM = "ReRoom demo candidate: automated integration checks passed; representative device/browser smoke recorded where linked; deferred P0 gates remain pending."
RULES_RETRIEVAL_DATE = "2026-07-18"

SHA_RE = re.compile(r"^[0-9a-f]{64}$")
REV_RE = re.compile(r"^git:[0-9a-f]{40}$")
EVIDENCE_CLASSES = {"automated_check", "device_smoke", "browser_smoke", "human_observation", "external_submission"}
EVIDENCE_STATES = {"VERIFIED", "PENDING", "BLOCKED"}
FORMAL_STATES = {"GREEN", "RUNNING", "RED", "UNRUN", "WAIVED_BY_HUMAN", "NO_REPORT"}
SPRINT_DISPOSITIONS = {"retained_green", "running", "fallback_active", "deferred_pending", "blocked"}
TRACE_STATES = {"evidence_present", "partial", "pending", "blocked"}

INDEX_KEYS = {
    "schema_version", "evidence_kind", "implementation_revision", "recorded_at_utc",
    "strongest_permitted_claim", "entries", "limitations", "evidence_sha256",
}
ENTRY_KEYS = {
    "evidence_id", "implementation_revision", "location", "sha256", "requirement_ids",
    "gate_ids", "procedure", "classification", "state", "provenance",
}
GATES_KEYS = {
    "schema_version", "evidence_kind", "implementation_revision", "recorded_at_utc",
    "strongest_permitted_claim", "gates", "requirements", "limitations", "evidence_sha256",
}
GATE_ROW_KEYS = {"gate_id", "formal_state", "formal_report", "sprint_disposition", "evidence_ids"}
FORMAL_REPORT_KEYS = {"path", "sha256"}
REQUIREMENT_KEYS = {"requirement_id", "trace_state", "resume_procedure"}

REQUIREMENTS = (
    "NFR-LATENCY-001", "NFR-RESILIENCE-001", "OPS-GOLDEN-001", "OPS-LICENSE-001",
    "OPS-SUBMISSION-001", "SEC-AGENT-001", "SEC-CREDENTIAL-001",
)
GATE_IDS = tuple(f"GATE-{number:03d}" for number in range(1, 15))

DEFERRED_RESUME_ORDER = (
    "1. Finish the missing Phase 5–7 implementation/evidence plans and rerun their authoritative verifiers.",
    "2. Resume `$gsd-verify-work 2` for the full `GATE-001` signed-device termination matrix.",
    "3. Run formal `GATE-003`, `GATE-006`, `GATE-008`, `GATE-009`, and `GATE-011` campaigns against the frozen implementation.",
    "4. Benchmark `GATE-004`, `GATE-007`, and `GATE-012` only if replacing the activated manual/no-dense/local fallbacks.",
    "5. Complete the canonical latency/resilience distributions and security/license closure, then run `OPS-GOLDEN-001` 5/5.",
    "6. Audit the milestone and assemble signed release/submission evidence before making a full P0 claim.",
)


class EvidenceRejected(ValueError):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def reject(code: str) -> NoReturn:
    raise EvidenceRejected(code)


def canonical_bytes(value: object) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode()


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def document_sha256(value: Mapping[str, object]) -> str:
    unsigned = copy.deepcopy(dict(value))
    unsigned.pop("evidence_sha256", None)
    return hashlib.sha256(canonical_bytes(unsigned)).hexdigest()


def _exact(value: object, keys: set[str], code: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        reject(code)
    return value


def fixture_automated_entry(digest: str) -> dict[str, object]:
    return {
        "evidence_id": "EVID-P08-FIXTURE-AUTOMATED", "implementation_revision": "git:" + "a" * 40,
        "location": "evidence/example.json", "sha256": digest,
        "requirement_ids": ["SEC-CREDENTIAL-001"], "gate_ids": ["GATE-010"],
        "procedure": "fixture automated verifier", "classification": "automated_check",
        "state": "VERIFIED", "provenance": "phase_automated_report",
    }


def fixture_pending_external_entry() -> dict[str, object]:
    return {
        "evidence_id": "EVID-P08-FIXTURE-DEVICE-PENDING", "implementation_revision": "git:" + "a" * 40,
        "location": "opaque:device-smoke-not-retained", "sha256": None,
        "requirement_ids": ["OPS-GOLDEN-001"], "gate_ids": ["GATE-003"],
        "procedure": "Run signed-device rehearsal and retain an opaque artifact digest.",
        "classification": "device_smoke", "state": "PENDING", "provenance": "procedure_only",
    }


def build_index(
    *, implementation_revision: str, recorded_at_utc: str,
    entries: Sequence[Mapping[str, object]],
) -> dict[str, object]:
    return {
        "schema_version": "1.0.0", "evidence_kind": "phase_08_sanitized_evidence_index",
        "implementation_revision": implementation_revision, "recorded_at_utc": recorded_at_utc,
        "strongest_permitted_claim": PERMITTED_CLAIM,
        "entries": sorted((dict(entry) for entry in entries), key=lambda item: str(item["evidence_id"])),
        "limitations": [
            "Automated integration and local HTTP evidence do not constitute device or browser smoke.",
            "Physical, human, golden, license, and submission work remains separately pending or blocked.",
        ],
    }


def seal_index(value: dict[str, object]) -> dict[str, object]:
    value["evidence_sha256"] = document_sha256(value)
    return value


def validate_index(value: object, *, root: Path = ROOT, require_complete: bool = False) -> None:
    report = _exact(value, INDEX_KEYS, "E08I_INDEX_SHAPE")
    if report["schema_version"] != "1.0.0" or report["evidence_kind"] != "phase_08_sanitized_evidence_index":
        reject("E08I_INDEX_SHAPE")
    if not REV_RE.fullmatch(report["implementation_revision"]) or report["strongest_permitted_claim"] != PERMITTED_CLAIM:
        reject("E08I_INDEX_IDENTITY")
    entries = report["entries"]
    if not isinstance(entries, list) or not entries:
        reject("E08I_ENTRY_SET")
    ids: list[str] = []
    for raw in entries:
        entry = _exact(raw, ENTRY_KEYS, "E08I_ENTRY_SHAPE")
        evidence_id = entry["evidence_id"]
        if not isinstance(evidence_id, str) or not re.fullmatch(r"EVID-P08-[A-Z0-9-]+", evidence_id):
            reject("E08I_ENTRY_ID")
        ids.append(evidence_id)
        if not REV_RE.fullmatch(entry["implementation_revision"]):
            reject("E08I_ENTRY_REVISION")
        if entry["classification"] not in EVIDENCE_CLASSES or entry["state"] not in EVIDENCE_STATES:
            reject("E08I_ENTRY_ENUM")
        if not isinstance(entry["requirement_ids"], list) or not isinstance(entry["gate_ids"], list):
            reject("E08I_ENTRY_TRACE")
        if entry["provenance"] in {"phase_automated_report", "phase_08_bom"} and entry["classification"] != "automated_check":
            reject("E08I_CLASS_PROMOTION")
        location = entry["location"]
        if not isinstance(location, str):
            reject("E08I_LOCATION")
        if location.startswith("opaque:"):
            if entry["state"] == "VERIFIED" or entry["sha256"] is not None or entry["provenance"] != "procedure_only":
                reject("E08I_EXTERNAL_PROVENANCE")
        else:
            path = Path(location)
            if path.is_absolute() or ".." in path.parts:
                reject("E08I_LOCATION")
            absolute = root / path
            if not absolute.is_file() or absolute.is_symlink() or not SHA_RE.fullmatch(entry["sha256"] or ""):
                reject("E08I_TRACKED_ARTIFACT")
            if file_sha256(absolute) != entry["sha256"]:
                reject("E08I_DIGEST_DRIFT")
            if entry["state"] != "VERIFIED":
                reject("E08I_TRACKED_STATE")
            if entry["classification"] != "automated_check" and entry["provenance"] != "canonical_gate_report":
                reject("E08I_EXTERNAL_PROVENANCE")
    if ids != sorted(ids) or len(ids) != len(set(ids)):
        reject("E08I_ENTRY_SET")
    if require_complete:
        classifications = {(entry["classification"], entry["state"]) for entry in entries}
        required = {
            ("automated_check", "VERIFIED"), ("device_smoke", "PENDING"),
            ("browser_smoke", "PENDING"), ("human_observation", "PENDING"),
            ("external_submission", "PENDING"),
        }
        if not required.issubset(classifications):
            reject("E08I_CLASS_CLOSURE")
    _reject_unsafe(value)
    if report["evidence_sha256"] != document_sha256(report):
        reject("E08I_SELF_DIGEST")


def fixture_gate_rows() -> list[dict[str, object]]:
    return [{
        "gate_id": "GATE-003", "formal_state": "NO_REPORT", "formal_report": None,
        "sprint_disposition": "deferred_pending", "evidence_ids": ["EVID-P08-FIXTURE-DEVICE-PENDING"],
    }]


def build_gate_report(
    *, implementation_revision: str, recorded_at_utc: str,
    gate_rows: Sequence[Mapping[str, object]], requirement_rows: Sequence[Mapping[str, str]] | None = None,
) -> dict[str, object]:
    if requirement_rows is None:
        requirement_rows = [{
            "requirement_id": requirement_id,
            "trace_state": "blocked" if requirement_id == "OPS-LICENSE-001" else "pending",
            "resume_procedure": "Follow the Phase 8 deferred resume order and retain canonical evidence.",
        } for requirement_id in REQUIREMENTS]
    return {
        "schema_version": "1.0.0", "evidence_kind": "phase_08_formal_and_sprint_status",
        "implementation_revision": implementation_revision, "recorded_at_utc": recorded_at_utc,
        "strongest_permitted_claim": PERMITTED_CLAIM,
        "gates": sorted((dict(row) for row in gate_rows), key=lambda row: str(row["gate_id"])),
        "requirements": sorted((dict(row) for row in requirement_rows), key=lambda row: str(row["requirement_id"])),
        "limitations": [
            "Formal state comes only from retained canonical gate reports.",
            "Sprint disposition and requirement trace state are not completion metadata.",
            "GATE-011 and shipping remain blocked by the missing root license and proxy redistribution decision.",
        ],
    }


def seal_gates(value: dict[str, object]) -> dict[str, object]:
    value["evidence_sha256"] = document_sha256(value)
    return value


def validate_gate_report(value: object, *, root: Path = ROOT, require_complete: bool = False) -> None:
    report = _exact(value, GATES_KEYS, "E08I_GATES_SHAPE")
    if report["schema_version"] != "1.0.0" or report["evidence_kind"] != "phase_08_formal_and_sprint_status":
        reject("E08I_GATES_SHAPE")
    if not REV_RE.fullmatch(report["implementation_revision"]) or report["strongest_permitted_claim"] != PERMITTED_CLAIM:
        reject("E08I_GATES_IDENTITY")
    gate_ids: list[str] = []
    for raw in report["gates"]:
        row = _exact(raw, GATE_ROW_KEYS, "E08I_GATE_ROW")
        if row["gate_id"] not in GATE_IDS or row["formal_state"] not in FORMAL_STATES or row["sprint_disposition"] not in SPRINT_DISPOSITIONS:
            reject("E08I_GATE_ENUM")
        gate_ids.append(row["gate_id"])
        formal = row["formal_report"]
        if row["formal_state"] == "NO_REPORT":
            if formal is not None:
                reject("E08I_GATE_AUTHORITY")
        else:
            formal = _exact(formal, FORMAL_REPORT_KEYS, "E08I_GATE_AUTHORITY")
            path = Path(formal["path"])
            if path.is_absolute() or ".." in path.parts or not (root / path).is_file():
                reject("E08I_GATE_AUTHORITY")
            if file_sha256(root / path) != formal["sha256"]:
                reject("E08I_GATE_AUTHORITY")
            canonical = json.loads((root / path).read_text(encoding="utf-8"))
            if canonical.get("gate_id") != row["gate_id"] or canonical.get("gate_state") != row["formal_state"]:
                reject("E08I_GATE_AUTHORITY")
        if row["formal_state"] == "GREEN" and row["sprint_disposition"] != "retained_green":
            reject("E08I_GATE_PROMOTION")
        if row["formal_state"] == "NO_REPORT" and row["sprint_disposition"] == "retained_green":
            reject("E08I_GATE_PROMOTION")
    if gate_ids != sorted(gate_ids) or len(gate_ids) != len(set(gate_ids)):
        reject("E08I_GATE_SET")
    if require_complete and tuple(gate_ids) != GATE_IDS:
        reject("E08I_GATE_SET")
    requirement_ids: list[str] = []
    for raw in report["requirements"]:
        row = _exact(raw, REQUIREMENT_KEYS, "E08I_REQUIREMENT_ROW")
        if row["requirement_id"] not in REQUIREMENTS or row["trace_state"] not in TRACE_STATES:
            reject("E08I_REQUIREMENT_ENUM")
        requirement_ids.append(row["requirement_id"])
    if requirement_ids != sorted(requirement_ids) or len(requirement_ids) != len(set(requirement_ids)):
        reject("E08I_REQUIREMENT_SET")
    if require_complete and tuple(requirement_ids) != REQUIREMENTS:
        reject("E08I_REQUIREMENT_SET")
    _reject_unsafe(value)
    if report["evidence_sha256"] != document_sha256(report):
        reject("E08I_SELF_DIGEST")


def _reject_unsafe(value: object) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if str(key).lower() in {"completed", "credential", "secret", "raw_log", "raw_room_media", "device_identifier", "user_identifier", "signing_material"}:
                reject("E08I_PRIVATE_OR_COMPLETION_FIELD")
            _reject_unsafe(child)
    elif isinstance(value, list):
        for child in value:
            _reject_unsafe(child)
    elif isinstance(value, str):
        lowered = value.lower()
        if value.startswith(("/Users/", "/home/", "/tmp/", "file://")):
            reject("E08I_MACHINE_PATH")
        if re.search(r"sk-[A-Za-z0-9_-]{20,}", value) or "private key" in lowered:
            reject("E08I_CREDENTIAL")
        forbidden = ("p0 complete", "release ready", "real-time", "licensed for shipping", "all gates green")
        if any(token in lowered for token in forbidden):
            reject("E08I_UNSUPPORTED_CLAIM")


def fixture_docs() -> tuple[str, str]:
    runbook = "\n".join((
        "# Phase 8 Demo Runbook", PERMITTED_CLAIM,
        "scripts/verify-phase-08-hardening --verify-evidence",
        "scripts/verify-phase-08-evidence full",
        "scripts/verify-phase-08-evidence --verify-evidence",
        "Operations: place, replace, remove, restore. Mode B0 replay is local HTTP evidence.",
        "Evidence classes: automated_check, device_smoke, browser_smoke, human_observation, external_submission.",
        "OPS-GOLDEN-001 remains PENDING until 5/5 after blocking gates are green.",
        "Device smoke PENDING. Browser smoke PENDING. License shipping BLOCKED. Submission PENDING.",
        "## Deferred Resume Order", *DEFERRED_RESUME_ORDER, "",
    ))
    handoff = "\n".join((
        "# Build Week Submission Handoff", PERMITTED_CLAIM,
        "Official challenge: https://openai.devpost.com/",
        "Official rules: https://openai.devpost.com/rules",
        "Retrieved: 2026-07-18",
        "Human must recheck both official pages immediately before submission.",
        "Deadline observed: July 21, 2026 at 5:00 PM Pacific Time.",
        "Public YouTube demo must be under three minutes with audio explaining Codex and GPT-5.6.",
        "Include repository URL, category, project description, setup/testing guidance, and representative `/feedback` Session ID.",
        "- [ ] Human: recheck and sign off official rules",
        "- [ ] Human: approve public media",
        "- [ ] Human: upload public demo video",
        "- [ ] Human: choose representative /feedback Session ID",
        "- [ ] Human: set repository visibility or judge access",
        "- [ ] Human: submit final Devpost entry",
        "OPS-GOLDEN-001 remains PENDING until 5/5. Device/browser/license/submission remain pending or blocked.",
        "## Deferred Resume Order", *DEFERRED_RESUME_ORDER, "",
    ))
    return runbook, handoff


def validate_docs_text(runbook: str, handoff: str) -> None:
    runbook_required = (
        PERMITTED_CLAIM,
        "scripts/verify-phase-08-hardening --verify-evidence",
        "scripts/verify-phase-08-evidence full",
        "scripts/verify-phase-08-evidence --verify-evidence",
        "place", "replace", "remove", "restore", "Mode B0",
        "automated_check", "device_smoke", "browser_smoke", "human_observation", "external_submission",
        "OPS-GOLDEN-001 remains PENDING until 5/5", "Device smoke PENDING", "Browser smoke PENDING",
        "License shipping BLOCKED", "Submission PENDING", *DEFERRED_RESUME_ORDER,
    )
    handoff_required = (
        PERMITTED_CLAIM, "https://openai.devpost.com/", "https://openai.devpost.com/rules",
        f"Retrieved: {RULES_RETRIEVAL_DATE}", "immediately before submission",
        "under three minutes", "audio", "Codex", "GPT-5.6", "repository", "category",
        "project description", "/feedback", "Session ID",
        "- [ ] Human: recheck and sign off official rules",
        "- [ ] Human: approve public media",
        "- [ ] Human: upload public demo video",
        "- [ ] Human: choose representative /feedback Session ID",
        "- [ ] Human: submit final Devpost entry", *DEFERRED_RESUME_ORDER,
    )
    if any(token not in runbook for token in runbook_required) or any(token not in handoff for token in handoff_required):
        reject("E08I_DOCS_COMPLETENESS")
    if re.search(r"- \[[xX]\]", handoff):
        reject("E08I_HUMAN_ACTION_COMPLETE")
    _reject_unsafe(runbook)
    _reject_unsafe(handoff)


def validate_docs(root: Path, runbook_relative: str, handoff_relative: str) -> None:
    if runbook_relative != RUNBOOK_PATH or handoff_relative != HANDOFF_PATH:
        reject("E08I_DOCS_PATH")
    runbook = root / runbook_relative
    handoff = root / handoff_relative
    if not runbook.is_file() or runbook.is_symlink() or not handoff.is_file() or handoff.is_symlink():
        reject("E08I_DOCS_PATH")
    validate_docs_text(runbook.read_text(encoding="utf-8"), handoff.read_text(encoding="utf-8"))


def publish_pair(index_path: Path, gates_path: Path, index: dict[str, object], gates: dict[str, object], *, root: Path = ROOT) -> None:
    validate_index(index, root=root, require_complete=True)
    validate_gate_report(gates, root=root, require_complete=True)
    index_path.parent.mkdir(parents=True, exist_ok=True)
    temporary: list[Path] = []
    try:
        for target, value in ((index_path, index), (gates_path, gates)):
            descriptor, name = tempfile.mkstemp(prefix=".phase08-evidence-", dir=target.parent)
            path = Path(name)
            temporary.append(path)
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(canonical_bytes(value)); stream.flush(); os.fsync(stream.fileno())
        temporary[0].replace(index_path)
        temporary[1].replace(gates_path)
    finally:
        for path in temporary:
            path.unlink(missing_ok=True)


def _cli() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--docs", nargs=2, metavar=("RUNBOOK", "HANDOFF"))
    parser.add_argument("--index", type=Path)
    parser.add_argument("--gates", type=Path)
    arguments = parser.parse_args()
    try:
        if arguments.index is None or arguments.gates is None:
            reject("E08I_CLI_INPUT")
        index = json.loads(arguments.index.read_text(encoding="utf-8"))
        gates = json.loads(arguments.gates.read_text(encoding="utf-8"))
        validate_index(index, root=ROOT, require_complete=True)
        validate_gate_report(gates, root=ROOT, require_complete=True)
        if arguments.docs:
            validate_docs(ROOT, arguments.docs[0], arguments.docs[1])
        print(json.dumps({"status": "PASS", "requirements_completed": [], "submission": "PENDING"}, sort_keys=True))
        return 0
    except (EvidenceRejected, OSError, ValueError, json.JSONDecodeError):
        print(json.dumps({"status": "FAILED", "code": "E08I_VALIDATION"}, sort_keys=True), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(_cli())
