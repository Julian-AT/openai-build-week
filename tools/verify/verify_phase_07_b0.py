#!/usr/bin/env python3
"""Fail-closed verifier and evidence producer for the Phase 7 B0 sprint slice."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import platform
import re
import sys
from pathlib import Path
from typing import Any, Mapping, NoReturn


ROOT = Path(__file__).resolve().parents[2]
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
REVISION_RE = re.compile(r"^git:[0-9a-f]{40}$")

CHECK_IDS = (
    "phase_02_exact_replay",
    "web_projection_timeline",
    "web_typecheck",
    "web_production_build",
    "source_closure",
    "local_http_smoke",
)

TOOLCHAIN = {
    "node": "v22.22.3",
    "npm": "10.9.8",
    "next": "16.2.9",
    "react": "19.2.7",
    "react_dom": "19.2.7",
    "typescript": "6.0.2",
    "python": platform.python_version(),
}

FIXTURE = {
    "fixture_id": "FX-CAPTURE-001",
    "fixture_revision": "rev-001",
    "manifest_sha256": "3b4519d2730e158df73e938f7b841664c6ce5f7d65ed2650c90ca8e89c7a7610",
    "archive_id": "archive.finalized-one-frame",
    "archive_name": "finalized-one-frame.rrcap",
    "archive_manifest_sha256": "2a6454e6014eb294bee94be36569ce94c6a49adaa3c77e064a2b03756df99c09",
    "report_id": "archive.finalized-one-frame.replay-report.json",
    "report_sha256": "5a15914545789d20e0255b8ab2bbff55cbd1d9374b54816638ed0d64400acb2b",
}

CLAIMS = {
    "automated_sprint_slice": "PASS",
    "local_http_smoke": "PASS",
    "browser_smoke": "PENDING",
    "FR-WEB-001": "PENDING",
    "SEC-RETENTION-001": "PENDING",
    "GATE-008": "PENDING",
}

DEFERRED = [
    "General .rrcap upload/import and adversarial archive UI.",
    "MP4/MOV ordinary-video decode, timeline, codec support, and geometry-unavailable behavior.",
    "Session creation/listing, server TTL, deletion queue, audit log, share links, share invalidation, authentication, authorization, and cloud storage.",
    "Typed B0 proposals, explicit replay forks, gateway authority, live phone connectivity, WebSockets, and acknowledged-commit fault campaigns.",
    "Sparse plane/point/mesh/reveal/asset visualization beyond metadata for artifacts actually present in the selected verified fixture.",
    "Learned providers, dense geometry, LingBot/B1, GPU/runtime tiers, production deployment, and multi-user behavior.",
    "Full GATE-008 two-run and browser/fault evidence, complete FR-WEB-001, and complete SEC-RETENTION-001 acceptance.",
]

LIMITATIONS = [
    "Local HTTP rendering is not browser interaction evidence.",
    "Only the fixed golden capture is covered.",
    "No server retention or sharing lifecycle was exercised.",
    "No deployment, device, provider, or cloud system was exercised.",
]

EXPECTED_WEB_DEPENDENCIES = {
    "next": "16.2.9",
    "react": "19.2.7",
    "react-dom": "19.2.7",
}
EXPECTED_WEB_DEV_DEPENDENCIES = {
    "@types/node": "22.19.7",
    "@types/react": "19.2.17",
    "@types/react-dom": "19.2.3",
    "typescript": "6.0.2",
}

TOP_LEVEL_KEYS = {
    "schema_version",
    "evidence_kind",
    "implementation_revision",
    "source_tree_sha256",
    "toolchain",
    "fixture",
    "checks",
    "claims",
    "deferred",
    "limitations",
    "provider_call_paths",
    "browser_artifact",
    "evidence_sha256",
}

SOURCE_FILE_ROOTS = (
    "web/src",
    "web/test",
    "tools/javascript/src",
    "tools/javascript/test",
    "fixtures/capture/1.0.0/rev-001",
)
SOURCE_FIXED_FILES = (
    "web/package.json",
    "web/package-lock.json",
    "web/next.config.ts",
    "web/tsconfig.json",
    "web/next-env.d.ts",
    "tools/javascript/package.json",
    "tools/javascript/package-lock.json",
    "tools/verify/verify_phase_07_b0.py",
    "tools/verify/tests/test_phase_07_b0_gate.py",
)
OPTIONAL_SOURCE_FILES = ("scripts/verify-phase-07-b0",)


class EvidenceRejected(ValueError):
    """A sanitized, stable rejection classification."""

    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def reject(code: str) -> NoReturn:
    raise EvidenceRejected(code)


def _canonical_bytes(value: object) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _exact_keys(value: object, expected: set[str], code: str = "E07_SHAPE") -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != expected:
        reject(code)
    return value


def _closed_source_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for relative in SOURCE_FIXED_FILES:
        path = root / relative
        if not path.is_file() or path.is_symlink():
            reject("E07_SOURCE_CLOSURE")
        files.append(path)
    for relative in OPTIONAL_SOURCE_FILES:
        path = root / relative
        if path.exists():
            if not path.is_file() or path.is_symlink():
                reject("E07_SOURCE_CLOSURE")
            files.append(path)
    for relative in SOURCE_FILE_ROOTS:
        directory = root / relative
        if not directory.is_dir() or directory.is_symlink():
            reject("E07_SOURCE_CLOSURE")
        for path in directory.rglob("*"):
            if path.is_symlink():
                reject("E07_SOURCE_CLOSURE")
            if path.is_file() and "__pycache__" not in path.parts:
                files.append(path)
    return sorted(set(files), key=lambda path: path.relative_to(root).as_posix())


def source_tree_sha256(root: Path = ROOT) -> str:
    manifest = [
        {
            "file": path.relative_to(root).as_posix(),
            "sha256": _sha256_file(path),
        }
        for path in _closed_source_files(root)
    ]
    return _sha256_bytes(_canonical_bytes(manifest))


def evidence_sha256(value: Mapping[str, object]) -> str:
    unsigned = copy.deepcopy(dict(value))
    unsigned.pop("evidence_sha256", None)
    return _sha256_bytes(_canonical_bytes(unsigned))


def seal_evidence(value: dict[str, object]) -> dict[str, object]:
    value["evidence_sha256"] = evidence_sha256(value)
    return value


def build_evidence(
    *,
    root: Path,
    implementation_revision: str,
    check_output_digests: Mapping[str, str],
) -> dict[str, object]:
    checks = [
        {
            "check_id": check_id,
            "status": "PASS",
            "output_sha256": check_output_digests[check_id],
        }
        for check_id in CHECK_IDS
    ]
    value: dict[str, object] = {
        "schema_version": "1.0.0",
        "evidence_kind": "phase_07_b0_automated_preflight",
        "implementation_revision": implementation_revision,
        "source_tree_sha256": source_tree_sha256(root),
        "toolchain": dict(TOOLCHAIN),
        "fixture": dict(FIXTURE),
        "checks": checks,
        "claims": dict(CLAIMS),
        "deferred": list(DEFERRED),
        "limitations": list(LIMITATIONS),
        "provider_call_paths": 0,
        "browser_artifact": None,
    }
    return seal_evidence(value)


UNSAFE_KEYS = {
    "raw",
    "body",
    "html",
    "response",
    "temporary_path",
    "temp_path",
    "process_id",
    "pid",
    "port",
    "stack",
    "stack_trace",
    "credential",
    "credentials",
    "secret",
    "user_identifier",
    "device_identifier",
    "room_imagery",
    "payload",
}
UNSAFE_KEY_SUFFIXES = ("_raw", "_body", "_html", "_response", "_payload", "_stack", "_credentials", "_secret")
UNSAFE_STRING_PATTERNS = (
    re.compile(r"/tmp(?:/|\b)", re.IGNORECASE),
    re.compile(r"file://", re.IGNORECASE),
    re.compile(r"https?://", re.IGNORECASE),
    re.compile(r"-----BEGIN [A-Z ]+-----"),
    re.compile(r"(?:password|credential|secret|access[_ -]?token)\s*[:=]", re.IGNORECASE),
    re.compile(r"(?:response body|raw page|stack trace|process id|device identifier|user identifier)", re.IGNORECASE),
)


def _scan_unsafe(value: object) -> None:
    if isinstance(value, dict):
        for key, member in value.items():
            lowered = str(key).lower()
            if lowered in UNSAFE_KEYS or lowered.endswith(UNSAFE_KEY_SUFFIXES):
                reject("E07_UNSAFE")
            _scan_unsafe(member)
    elif isinstance(value, list):
        for member in value:
            _scan_unsafe(member)
    elif isinstance(value, str):
        if len(value) > 1024 or any(pattern.search(value) for pattern in UNSAFE_STRING_PATTERNS):
            reject("E07_UNSAFE")


def _validate_shape(value: object) -> dict[str, Any]:
    evidence = _exact_keys(value, TOP_LEVEL_KEYS)
    _exact_keys(evidence["toolchain"], set(TOOLCHAIN))
    _exact_keys(evidence["fixture"], set(FIXTURE))
    _exact_keys(evidence["claims"], set(CLAIMS))
    if not isinstance(evidence["checks"], list):
        reject("E07_SHAPE")
    for check in evidence["checks"]:
        _exact_keys(check, {"check_id", "status", "output_sha256"})
    if not isinstance(evidence["deferred"], list) or not isinstance(evidence["limitations"], list):
        reject("E07_SHAPE")
    return evidence


def _read_json(path: Path, code: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        reject(code)
    if not isinstance(value, dict):
        reject(code)
    return value


def _validate_dependencies(root: Path) -> None:
    package = _read_json(root / "web/package.json", "E07_DEPENDENCY")
    if package.get("engines") != {"node": "22.22.3"} or package.get("packageManager") != "npm@10.9.8":
        reject("E07_DEPENDENCY")
    if package.get("dependencies") != EXPECTED_WEB_DEPENDENCIES:
        reject("E07_DEPENDENCY")
    if package.get("devDependencies") != EXPECTED_WEB_DEV_DEPENDENCIES:
        reject("E07_DEPENDENCY")

    lock = _read_json(root / "web/package-lock.json", "E07_DEPENDENCY")
    if lock.get("lockfileVersion") != 3:
        reject("E07_DEPENDENCY")
    packages = lock.get("packages")
    if not isinstance(packages, dict) or not isinstance(packages.get(""), dict):
        reject("E07_DEPENDENCY")
    root_package = packages[""]
    if root_package.get("dependencies") != EXPECTED_WEB_DEPENDENCIES:
        reject("E07_DEPENDENCY")
    if root_package.get("devDependencies") != EXPECTED_WEB_DEV_DEPENDENCIES:
        reject("E07_DEPENDENCY")


LIVE_OR_PERSISTENT_PATTERNS = (
    re.compile(r"\bfetch\s*\("),
    re.compile(r"\b(?:XMLHttpRequest|WebSocket|EventSource)\b"),
    re.compile(r"\b(?:localStorage|sessionStorage|indexedDB|serviceWorker|showOpenFilePicker)\b"),
    re.compile(r"\bnode:(?:http|https|net|dgram)\b"),
    re.compile(r"\bhttps?://"),
    re.compile(r"<input\b[^>]*\btype\s*=\s*[\"']file[\"']", re.IGNORECASE | re.DOTALL),
    re.compile(r"\b(?:formAction|action)\s*=\s*\{"),
)
PROCESS_PATTERN = re.compile(r"\b(?:node:child_process|child_process|execFile|execSync|spawn|spawnSync|process\.)\b")
ACTION_BUTTON_PATTERN = re.compile(r"<button\b[^>]*>(.*?)</button>", re.IGNORECASE | re.DOTALL)
DEFERRED_ACTION_WORDS = re.compile(r"\b(?:upload|share|sign[ -]?in|log[ -]?in|authenticate|delete session|connect phone|ordinary video|typed proposal|provider)\b", re.IGNORECASE)


def _validate_source_scope(root: Path) -> None:
    source_root = root / "web/src"
    loader_relative = "web/src/lib/replay/load-golden-capture.server.ts"
    for path in sorted(source_root.rglob("*")):
        if path.is_symlink():
            reject("E07_SOURCE_SCOPE")
        if not path.is_file():
            continue
        relative = path.relative_to(root).as_posix()
        if path.name in {"route.ts", "route.tsx", "route.js", "route.mjs"}:
            reject("E07_SOURCE_SCOPE")
        try:
            source = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            reject("E07_SOURCE_SCOPE")
        if any(pattern.search(source) for pattern in LIVE_OR_PERSISTENT_PATTERNS):
            reject("E07_SOURCE_SCOPE")
        for button in ACTION_BUTTON_PATTERN.findall(source):
            visible = re.sub(r"<[^>]+>", " ", button)
            if DEFERRED_ACTION_WORDS.search(visible):
                reject("E07_SOURCE_SCOPE")
        if relative != loader_relative and PROCESS_PATTERN.search(source):
            reject("E07_SOURCE_SCOPE")

    loader = (root / loader_relative).read_text(encoding="utf-8")
    required_loader_tokens = (
        "node:child_process",
        "execFile",
        "tools/javascript/src/replay.ts",
        "shell: false",
    )
    if any(token not in loader for token in required_loader_tokens):
        reject("E07_SOURCE_SCOPE")
    if re.search(r"\b(?:exec|spawn|spawnSync|execSync)\s*\(", loader):
        reject("E07_SOURCE_SCOPE")


def validate_source(root: Path = ROOT) -> None:
    _closed_source_files(root)
    _validate_dependencies(root)
    _validate_source_scope(root)


def validate_evidence(value: object, *, root: Path = ROOT) -> None:
    _scan_unsafe(value)
    evidence = _validate_shape(value)

    if evidence["schema_version"] != "1.0.0" or evidence["evidence_kind"] != "phase_07_b0_automated_preflight":
        reject("E07_IDENTITY")
    if not isinstance(evidence["implementation_revision"], str) or not REVISION_RE.fullmatch(evidence["implementation_revision"]):
        reject("E07_IDENTITY")
    if evidence["toolchain"] != TOOLCHAIN or evidence["fixture"] != FIXTURE:
        reject("E07_IDENTITY")

    checks = evidence["checks"]
    if [check.get("check_id") for check in checks] != list(CHECK_IDS):
        reject("E07_CHECK_SET")
    for check in checks:
        if check.get("status") != "PASS":
            reject("E07_CHECK_STATUS")
        digest = check.get("output_sha256")
        if not isinstance(digest, str) or not SHA256_RE.fullmatch(digest):
            reject("E07_CHECK_STATUS")

    claims = evidence["claims"]
    if claims.get("browser_smoke") != "PENDING":
        reject("E07_BROWSER_ARTIFACT")
    if claims != CLAIMS:
        reject("E07_CLAIM")
    if evidence["browser_artifact"] is not None:
        reject("E07_BROWSER_ARTIFACT")
    if evidence["provider_call_paths"] != 0:
        reject("E07_CLAIM")
    if evidence["deferred"] != DEFERRED or evidence["limitations"] != LIMITATIONS:
        reject("E07_CLAIM")

    validate_source(root)
    expected_source_digest = source_tree_sha256(root)
    if evidence["source_tree_sha256"] != expected_source_digest:
        reject("E07_SOURCE_DIGEST")
    supplied_digest = evidence["evidence_sha256"]
    if not isinstance(supplied_digest, str) or not SHA256_RE.fullmatch(supplied_digest):
        reject("E07_EVIDENCE_DIGEST")
    if supplied_digest != evidence_sha256(evidence):
        reject("E07_EVIDENCE_DIGEST")


HTTP_REQUIRED_TOKENS = (
    "MODE B0 — RECORDED REPLAY",
    "PROVIDER-INDEPENDENT",
    "LOCAL DEMO FIXTURE",
    "GATE-008 PENDING",
    "FX-CAPTURE-001",
    "rev-001",
    "finalized-one-frame.rrcap",
    "Event 1 of 7: session_started",
    "session_started",
    "event_00000002-0000-4000-8000-000000000001",
    "1000002000",
    "local_only_until_share",
    "No browser or server session is created.",
    "not present in this capture",
)


def verify_http_response(path: Path) -> None:
    try:
        body = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        reject("E07_HTTP_SMOKE")
    if any(token not in body for token in HTTP_REQUIRED_TOKENS):
        reject("E07_HTTP_SMOKE")
    if body.count("not present in this capture") < 2:
        reject("E07_HTTP_SMOKE")
    if "Archive verification failed" in body:
        reject("E07_HTTP_SMOKE")


def _load_check_digests(results_dir: Path) -> dict[str, str]:
    digests: dict[str, str] = {}
    for check_id in CHECK_IDS:
        path = results_dir / f"{check_id}.pass"
        try:
            contents = path.read_bytes()
        except OSError:
            reject("E07_CHECK_SET")
        if contents != f"{check_id}: PASS\n".encode("utf-8"):
            reject("E07_CHECK_STATUS")
        digests[check_id] = _sha256_bytes(contents)
    return digests


def _write_atomic(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".new")
    try:
        temporary.write_bytes(_canonical_bytes(value))
        temporary.replace(path)
    except OSError:
        reject("E07_PUBLICATION")


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify the closed Phase 7 B0 evidence boundary")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--verify-source", action="store_true")
    mode.add_argument("--verify-evidence", type=Path)
    mode.add_argument("--verify-http", type=Path)
    mode.add_argument("--generate", action="store_true")
    parser.add_argument("--results-dir", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--implementation-revision")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv[1:] if argv is None else argv)
    try:
        if args.verify_source:
            validate_source(ROOT)
            print("source_closure: PASS")
        elif args.verify_evidence is not None:
            value = _read_json(args.verify_evidence, "E07_EVIDENCE_PARSE")
            validate_evidence(value, root=ROOT)
            print("phase_07_b0_evidence: PASS")
        elif args.verify_http is not None:
            verify_http_response(args.verify_http)
            print("local_http_smoke: PASS")
        else:
            if args.results_dir is None or args.output is None or args.implementation_revision is None:
                reject("E07_GENERATION_ARGS")
            check_digests = _load_check_digests(args.results_dir)
            value = build_evidence(
                root=ROOT,
                implementation_revision=args.implementation_revision,
                check_output_digests=check_digests,
            )
            validate_evidence(value, root=ROOT)
            _write_atomic(args.output, value)
            print("phase_07_b0_generation: PASS")
    except EvidenceRejected as error:
        print(error.code, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
