#!/usr/bin/env python3
"""Validate the ReRoom documentation-only PRE-GSD repository."""

from __future__ import annotations

import copy
import json
import math
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath
from typing import Any
from urllib.parse import unquote, urlparse


ROOT = Path(__file__).resolve().parents[1]

GOVERNING_PROMPT = "prompts/ReRoom_SOL_ULTRA_Pre-GSD_Master_Prompt.md"
GOVERNING_PROMPT_SHA256 = "9DFF9D9E3A717510E089A60C92E69311FFC13D29A7462EBFD22975EF6B8DE4D1"

ARCHIVE_HASHES = {
    "docs/archive/source/ReRoom_Master_Technical_Plan_v3.2.md": "3BB8774DDD9C15120B5610D8F5510D4E84FB3F15AEA0A671FF2CC282A69C0FAB",
    "docs/archive/source/ReRoom_PRD_v1.0.md": "313F8338931E2254CAB26EECC5008B2F1626AFA0ED5B224895149D0AA4FA39ED",
}

CANONICAL = [
    "docs/canonical/README.md",
    "docs/canonical/MASTER_TECHNICAL_SPEC.md",
    "docs/canonical/PRD.md",
    "docs/canonical/DEVELOPMENT_STRATEGY.md",
    "docs/canonical/TEST_AND_EVALUATION_PLAN.md",
    "docs/canonical/RISK_AND_KILL_GATES.md",
    "docs/canonical/RESEARCH_LEDGER.md",
    "docs/canonical/GLOSSARY_AND_ID_REGISTRY.md",
]

CONTRACTS = [
    "docs/contracts/README.md",
    "docs/contracts/frame-packet.schema.json",
    "docs/contracts/rrcap-manifest.schema.json",
    "docs/contracts/scene-state.schema.json",
    "docs/contracts/edit-artifacts.schema.json",
    "docs/contracts/transaction.schema.json",
]

AUDITS = [
    "docs/audit/ARCHITECTURE_AUDIT.md",
    "docs/audit/BEST_SOLUTION_DECISION_MATRIX.md",
    "docs/audit/SOURCE_VERIFICATION.md",
    "docs/audit/DECISION_CHANGELOG.md",
    "docs/audit/ASSUMPTION_REGISTER.md",
    "docs/audit/OPEN_DECISIONS.md",
]

GSD_FILES = [
    "docs/gsd/ONBOARDING_AND_CONTINUATION.md",
    "docs/gsd/ingest-manifest.yml",
    "docs/gsd/profiles/quality-fast.config.json",
    "docs/gsd/profiles/quality.config.json",
]

ROOT_FILES = [
    "README.md",
    "AGENTS.md",
    ".gitattributes",
    ".gitignore",
    ".env.example",
    "skills-lock.json",
    ".codex/config.toml",
    "docs/archive/README.md",
    "scripts/verify_pre_gsd_readiness.py",
    "scripts/verify-pre-gsd-readiness.sh",
    "scripts/apply_gsd_profile.py",
    "scripts/check_no_secrets.py",
    GOVERNING_PROMPT,
]

ALLOWED_ROOT_FILES = {
    "README.md",
    "AGENTS.md",
    ".gitattributes",
    ".gitignore",
    ".env.example",
    "skills-lock.json",
}
ALLOWED_ROOT_DIRS = {".agents", ".codex", ".git", "docs", "prompts", "scripts"}
ALLOWED_CODEX_FILES = {".codex/config.toml"}
ALLOWED_PROMPT_FILES = {GOVERNING_PROMPT}
ALLOWED_SCRIPT_FILES = {
    "scripts/verify_pre_gsd_readiness.py",
    "scripts/verify-pre-gsd-readiness.sh",
    "scripts/apply_gsd_profile.py",
    "scripts/check_no_secrets.py",
}
ALLOWED_DOC_DIRS = {
    "docs",
    "docs/adr",
    "docs/archive",
    "docs/archive/source",
    "docs/audit",
    "docs/canonical",
    "docs/codex",
    "docs/contracts",
    "docs/gsd",
    "docs/gsd/profiles",
}
ALLOWED_DOC_SUFFIXES = {".md", ".json", ".yml", ".toml"}

EXPECTED_MANIFEST: dict[str, tuple[str, int]] = {
    "docs/canonical/README.md": ("DOC", -10),
    "docs/adr/ADR-001-product-modes-and-p0-scope.md": ("ADR", 0),
    "docs/adr/ADR-002-native-iphone-and-web-split.md": ("ADR", 0),
    "docs/adr/ADR-003-arkit-authority-and-coordinates.md": ("ADR", 0),
    "docs/adr/ADR-004-atomic-capture-and-record-first-replay.md": ("ADR", 0),
    "docs/adr/ADR-006-fast-and-dense-geometry-tracks.md": ("ADR", 0),
    "docs/adr/ADR-008-scene-identity-and-readiness.md": ("ADR", 0),
    "docs/adr/ADR-010-asset-contract.md": ("ADR", 0),
    "docs/adr/ADR-011-agent-and-deterministic-boundary.md": ("ADR", 0),
    "docs/adr/ADR-012-transaction-and-offline-restore.md": ("ADR", 0),
    "docs/adr/ADR-013-mode-b0-guarantee.md": ("ADR", 0),
    "docs/adr/ADR-014-service-topology-and-hardware-tiers.md": ("ADR", 0),
    "docs/adr/ADR-005-realitykit-first-compositor.md": ("ADR", 10),
    "docs/adr/ADR-007-segmentation-and-depth-providers.md": ("ADR", 10),
    "docs/adr/ADR-009-multi-surface-reveal.md": ("ADR", 10),
    "docs/canonical/MASTER_TECHNICAL_SPEC.md": ("SPEC", 20),
    "docs/contracts/README.md": ("SPEC", 20),
    "docs/contracts/frame-packet.schema.json": ("SPEC", 20),
    "docs/contracts/rrcap-manifest.schema.json": ("SPEC", 20),
    "docs/contracts/scene-state.schema.json": ("SPEC", 20),
    "docs/contracts/transaction.schema.json": ("SPEC", 20),
    "docs/contracts/edit-artifacts.schema.json": ("SPEC", 20),
    "docs/canonical/PRD.md": ("PRD", 30),
    "docs/canonical/DEVELOPMENT_STRATEGY.md": ("DOC", 40),
    "docs/canonical/TEST_AND_EVALUATION_PLAN.md": ("DOC", 40),
    "docs/canonical/RISK_AND_KILL_GATES.md": ("DOC", 40),
    "docs/canonical/RESEARCH_LEDGER.md": ("DOC", 40),
    "docs/canonical/GLOSSARY_AND_ID_REGISTRY.md": ("DOC", 40),
}

EXPECTED_SCHEMA_IDS = {
    "edit-artifacts.schema.json": "urn:reroom:schema:edit-artifacts:1",
    "frame-packet.schema.json": "urn:reroom:schema:frame-packet:1",
    "rrcap-manifest.schema.json": "urn:reroom:schema:rrcap-manifest:1",
    "scene-state.schema.json": "urn:reroom:schema:scene-state:1",
    "transaction.schema.json": "urn:reroom:schema:transaction:1",
}

EXPECTED_SKILLS: dict[str, tuple[int, str, str, bool, str, str | None, str]] = {
    "agent-browser": (1, "bb6b4c5aae49ff88addb31312437f94242a3e5aae950503ab4f332e28186c261", "d90860bd424c0888e5ae5e9a52bb1cd96b0ca51725f9e209b7e52b1545509d33", False, "vercel-labs/agent-browser", None, "ecc7641aea05f85ca3b11e7759d32aaf52fe05946ab4b63739c7bf78a41237a2"),
    "find-skills": (1, "deddc03b4b5f50755b97fcdb737a786676992ef7e9be614d2cd2c71e0320bebf", "de65c847e3929b71a535f055183e3adc7a3454361ae4f4f9c7bb21d8e0aeb68e", False, "vercel-labs/skills", None, "781bd6d3f9b19f8c9af6b53d8d0e4876d0183841b565db34ca7092ffa412d111"),
    "improve-codebase-architecture": (3, "4b4cb798c3863d5b6f5c0b4604af1ecb5beb6df82553c972898a91ba38bcf289", "b43ea86ec00eef865aa2ce1ddea630ca0a13fae7790298e082c35772b51b759e", False, "mattpocock/skills", None, "569299a60c8e93880f3b3c1eca55578f58f7e1a4155876edb4cb814da3d6b3ea"),
    "shadcn": (15, "a45cddd4511f8262df05b20506f4d52be8210a9ee05a13d9e36d4ee321bab593", "679eca9603c19c3ae81e13dabe400de0de4889d6bc184b35f69b545abafb9c7c", False, "shadcn/ui", None, "4f78ff7cd3a4f637b6fe30dbbab4a80a19dd63fa62d9352bed461ccfdbcbbf43"),
    "swift-concurrency": (17, "d3cb40aef411f1cfeae4bdd6bc9925a8ad55fdc70804e6d3ffdee188499deb64", "1dac74c169e426fcc61fb3ebb9c94526438eb7ed2c2b94d4c9e53ea06a2e508e", True, "AvdLee/Swift-Concurrency-Agent-Skill", "2.1.1", "7861d2fca2adbdad4b92df7a76702b289ac23b4e9b3cdeeb017e425bbede9782"),
    "swift-testing-expert": (12, "d039eb55cfbaa379d308ff42c1e459dea355edb869ec0a4d6f488759d2156aec", "7527c21fdb97ed949e302a1213c644017c70294383f48ce49f249667eeeff45d", True, "AvdLee/Swift-Testing-Agent-Skill", "1.2.0", "6d3a23709448c916ffd7cdfca82930918e42456ced3996ef9eb0b9867e0cfa4f"),
    "swiftui-expert-skill": (41, "e74c27b66f5ff5da524ede219348e7f9ddb7602ca9288cc5e3972e8e05e3ba29", "77468736fd8af123619e9d10d00bf602406f5eecd0707968d986ad7978e8687f", True, "AvdLee/SwiftUI-Agent-Skill", "4.0.0", "6d7649505e14bc3242eb04d078978cd81dc30fb808250698968b45897df696ea"),
    "vercel-react-best-practices": (76, "71ed7794962fa6e803ee83030517b5b93a9f70fbfeb431ec4535c5480a8d8355", "1eac6c4db59291404dff537eb9607e125fd31ebdc17a5fbc0631e0ec0c5d1b05", False, "vercel-labs/agent-skills", None, "ca7b0c0c6e5f2750043f7f0cd72d16ac4e2abc48f9b5500d047a4b77a2506212"),
}
EXPECTED_SKILL_PATHS = {
    "agent-browser": "skills/agent-browser/SKILL.md",
    "find-skills": "skills/find-skills/SKILL.md",
    "improve-codebase-architecture": "skills/engineering/improve-codebase-architecture/SKILL.md",
    "shadcn": "skills/shadcn/SKILL.md",
    "swift-concurrency": "swift-concurrency/SKILL.md",
    "swift-testing-expert": "swift-testing-expert/SKILL.md",
    "swiftui-expert-skill": "swiftui-expert-skill/SKILL.md",
    "vercel-react-best-practices": "skills/react-best-practices/SKILL.md",
}


@dataclass(frozen=True)
class ProfileRule:
    """Pinned GSD v1.6.1 type/enum rule for one supported profile leaf."""

    kind: str
    values: frozenset[Any] | None = None
    minimum: float | None = None


BOOL = ProfileRule("boolean")
GRANULARITY = ProfileRule("string", frozenset({"coarse", "standard", "fine"}))
MODEL_TIER = ProfileRule("string", frozenset({"opus", "sonnet", "haiku", "inherit"}))

PROFILE_REGISTRY: dict[str, ProfileRule] = {
    "mode": ProfileRule("string", frozenset({"interactive", "yolo"})),
    "runtime": ProfileRule("string"),
    "model_profile": ProfileRule("string", frozenset({"quality", "balanced", "budget", "adaptive", "inherit"})),
    "models.planning": MODEL_TIER,
    "models.discuss": MODEL_TIER,
    "models.research": MODEL_TIER,
    "models.execution": MODEL_TIER,
    "models.verification": MODEL_TIER,
    "models.completion": MODEL_TIER,
    "granularity": GRANULARITY,
    "granularities.planning": GRANULARITY,
    "granularities.discuss": GRANULARITY,
    "granularities.research": GRANULARITY,
    "granularities.execution": GRANULARITY,
    "granularities.verification": GRANULARITY,
    "granularities.completion": GRANULARITY,
    "parallelization": BOOL,
    "workflow.research": BOOL,
    "workflow.plan_check": BOOL,
    "workflow.verifier": BOOL,
    "workflow.auto_advance": BOOL,
    "workflow.nyquist_validation": BOOL,
    "workflow.post_planning_gaps": BOOL,
    "workflow.node_repair": BOOL,
    "workflow.node_repair_budget": ProfileRule("number", minimum=0),
    "workflow.human_verify_mode": ProfileRule("string", frozenset({"end-of-phase", "mid-flight"})),
    "workflow.research_before_questions": BOOL,
    "workflow.discuss_mode": ProfileRule("string", frozenset({"discuss", "assumptions"})),
    "workflow.max_discuss_passes": ProfileRule("number", minimum=1),
    "workflow.skip_discuss": BOOL,
    "workflow.use_worktrees": BOOL,
    "workflow.code_review": BOOL,
    "workflow.code_review_depth": ProfileRule("string", frozenset({"quick", "standard", "deep"})),
    "workflow.plan_review_convergence": BOOL,
    "workflow.ui_phase": BOOL,
    "workflow.ui_review": BOOL,
    "workflow.ui_safety_gate": BOOL,
    "workflow.context_coverage_gate": BOOL,
    "workflow.context_guard_mode": ProfileRule("string", frozenset({"auto", "warn", "off"})),
    "workflow.security_enforcement": BOOL,
    "workflow.security_asvs_level": ProfileRule("number", frozenset({1, 2, 3})),
    "workflow.security_block_on": ProfileRule("string", frozenset({"critical", "high", "medium", "low", "none"})),
    "plan_review.source_grounding": BOOL,
    "plan_review.source_grounding_authority": ProfileRule("string", frozenset({"grep", "intel"})),
    "hooks.context_warnings": BOOL,
}

CRITICAL_PROFILE_VALUES: dict[str, dict[str, Any]] = {
    "quality-fast.config.json": {
        "mode": "interactive",
        "runtime": "codex",
        "model_profile": "balanced",
        "models.execution": "sonnet",
        "models.completion": "sonnet",
        "models.planning": "opus",
        "models.research": "opus",
        "models.verification": "opus",
        "granularity": "standard",
        "granularities.planning": "fine",
        "granularities.execution": "standard",
        "granularities.verification": "standard",
        "parallelization": True,
        "workflow.research": True,
        "workflow.plan_check": True,
        "workflow.verifier": True,
        "workflow.auto_advance": False,
        "workflow.nyquist_validation": True,
        "workflow.post_planning_gaps": True,
        "workflow.node_repair": True,
        "workflow.node_repair_budget": 2,
        "workflow.human_verify_mode": "end-of-phase",
        "workflow.research_before_questions": False,
        "workflow.max_discuss_passes": 2,
        "workflow.use_worktrees": False,
        "workflow.code_review": True,
        "workflow.code_review_depth": "standard",
        "workflow.ui_phase": True,
        "workflow.ui_review": True,
        "workflow.ui_safety_gate": True,
        "workflow.context_coverage_gate": True,
        "workflow.context_guard_mode": "warn",
        "workflow.security_enforcement": True,
        "workflow.security_asvs_level": 1,
        "workflow.security_block_on": "high",
        "plan_review.source_grounding": True,
        "plan_review.source_grounding_authority": "grep",
        "hooks.context_warnings": True,
    },
    "maximum-assurance.config.json": {
        "mode": "interactive",
        "runtime": "codex",
        "model_profile": "quality",
        "models.planning": "opus",
        "models.discuss": "opus",
        "models.research": "opus",
        "models.execution": "opus",
        "models.verification": "opus",
        "models.completion": "opus",
        "granularity": "fine",
        "granularities.planning": "fine",
        "granularities.execution": "standard",
        "granularities.verification": "fine",
        "parallelization": False,
        "workflow.research": True,
        "workflow.plan_check": True,
        "workflow.verifier": True,
        "workflow.auto_advance": False,
        "workflow.nyquist_validation": True,
        "workflow.post_planning_gaps": True,
        "workflow.node_repair": True,
        "workflow.node_repair_budget": 2,
        "workflow.human_verify_mode": "mid-flight",
        "workflow.research_before_questions": True,
        "workflow.max_discuss_passes": 3,
        "workflow.use_worktrees": False,
        "workflow.code_review": True,
        "workflow.code_review_depth": "deep",
        "workflow.plan_review_convergence": True,
        "workflow.ui_phase": True,
        "workflow.ui_review": True,
        "workflow.ui_safety_gate": True,
        "workflow.context_coverage_gate": True,
        "workflow.context_guard_mode": "auto",
        "workflow.security_enforcement": True,
        "workflow.security_asvs_level": 2,
        "workflow.security_block_on": "medium",
        "plan_review.source_grounding": True,
        "plan_review.source_grounding_authority": "grep",
        "hooks.context_warnings": True,
    },
}


@dataclass
class Report:
    results: list[tuple[str, str, str]] = field(default_factory=list)

    def pass_(self, name: str, detail: str = "") -> None:
        self.results.append(("PASS", name, detail))

    def warn(self, name: str, detail: str) -> None:
        self.results.append(("WARNING", name, detail))

    def fail(self, name: str, detail: str) -> None:
        self.results.append(("FAIL", name, detail))

    def emit(self) -> int:
        for status, name, detail in self.results:
            suffix = f": {detail}" if detail else ""
            print(f"{status} [{name}]{suffix}")
        counts = {status: sum(1 for result in self.results if result[0] == status) for status in ("PASS", "WARNING", "FAIL")}
        print(f"SUMMARY PASS={counts['PASS']} WARNING={counts['WARNING']} FAIL={counts['FAIL']}")
        return 1 if counts["FAIL"] else 0


def rel(path: str) -> Path:
    return ROOT / path


def missing(paths: list[str]) -> list[str]:
    return [path for path in paths if not rel(path).is_file()]


def sha256(path: Path) -> str:
    import hashlib

    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def _reject_json_constant(value: str) -> None:
    raise ValueError(f"non-standard JSON numeric constant {value!r}")


def _unique_json_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON object key {key!r}")
        result[key] = value
    return result


def load_json(path: Path) -> Any:
    """Load strict JSON: reject duplicate keys and NaN/Infinity extensions."""
    return json.loads(
        path.read_text(encoding="utf-8"),
        object_pairs_hook=_unique_json_object,
        parse_constant=_reject_json_constant,
    )


def is_link_like(path: Path) -> bool:
    """Return true for symlinks and, on supporting Python versions, junctions."""
    if path.is_symlink():
        return True
    is_junction = getattr(path, "is_junction", None)
    return bool(is_junction and is_junction())


def path_within_root(path: Path, *, strict: bool) -> tuple[bool, str]:
    """Resolve a path and prove that it and every component stay in ROOT."""
    try:
        resolved = path.resolve(strict=strict)
        resolved.relative_to(ROOT.resolve(strict=True))
    except (FileNotFoundError, OSError, RuntimeError, ValueError) as exc:
        return False, str(exc)

    current = path
    while current != ROOT and current != current.parent:
        if is_link_like(current):
            return False, f"link/junction component is not permitted: {current}"
        current = current.parent
    return True, ""


def validate_posix_repo_path(value: str) -> str | None:
    """Validate a canonical, relative, forward-slash repository path."""
    if not value or "\\" in value or any(ord(character) < 32 for character in value):
        return "path is empty or contains a backslash/control character"
    if ":" in value:
        return "drive-qualified paths, URLs, and alternate data streams are forbidden"
    pure = PurePosixPath(value)
    if pure.is_absolute():
        return "absolute paths are forbidden"
    if any(part in {"", ".", ".."} for part in value.split("/")):
        return "empty, dot, and parent segments are forbidden"
    if pure.as_posix() != value:
        return "path is not in canonical POSIX form"
    return None


def parse_manifest(path: Path) -> list[dict[str, Any]]:
    """Parse the deliberately narrow released GSD manifest subset."""
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "docs:":
        raise ValueError("top-level `docs:` list is required")
    entries: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    for number, raw in enumerate(lines[1:], 2):
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        match_item = re.fullmatch(r"\s{2}-\s+path:\s+(.+)", line)
        if match_item:
            if current:
                entries.append(current)
            value = match_item.group(1).strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in {"\"", "'"}:
                value = value[1:-1]
            path_error = validate_posix_repo_path(value)
            if path_error:
                raise ValueError(f"unsafe manifest path at line {number}: {path_error}: {value!r}")
            current = {"path": value}
            continue
        match_field = re.fullmatch(r"\s{4}(type|precedence):\s+(.+)", line)
        if match_field and current is not None:
            key, value = match_field.groups()
            if key in current:
                raise ValueError(f"duplicate {key!r} at line {number}")
            value = value.strip().strip("\"'")
            if key == "precedence":
                try:
                    current[key] = int(value)
                except ValueError as exc:
                    raise ValueError(f"precedence at line {number} must be an integer") from exc
            else:
                current[key] = value
            continue
        raise ValueError(f"unsupported YAML at line {number}: {raw}")
    if current:
        entries.append(current)
    if not entries:
        raise ValueError("manifest docs list is empty")
    for entry in entries:
        if set(entry) != {"path", "type", "precedence"}:
            raise ValueError(f"invalid entry {entry}")
        if entry["type"] not in {"ADR", "PRD", "SPEC", "DOC"}:
            raise ValueError(f"unsupported type {entry['type']}")
        if type(entry["precedence"]) is not int:
            raise ValueError("precedence must be an integer")
    return entries


def flatten_values(value: Any, prefix: str = "") -> dict[str, Any]:
    """Return dotted leaf configuration paths and their values."""
    leaves: dict[str, Any] = {}
    if isinstance(value, dict):
        if not value and prefix:
            leaves[prefix] = value
        for key, child in value.items():
            dotted = f"{prefix}.{key}" if prefix else key
            leaves.update(flatten_values(child, dotted))
    else:
        leaves[prefix] = value
    return leaves


def profile_value_error(rule: ProfileRule, value: Any) -> str | None:
    if rule.kind == "boolean":
        valid_type = type(value) is bool
    elif rule.kind == "string":
        valid_type = type(value) is str
    elif rule.kind == "number":
        valid_type = type(value) in {int, float} and math.isfinite(value)
    else:
        return f"validator has unsupported rule kind {rule.kind!r}"
    if not valid_type:
        return f"expected {rule.kind}, got {type(value).__name__}"
    if rule.values is not None and value not in rule.values:
        return f"value {value!r} is outside {sorted(rule.values, key=str)!r}"
    if rule.minimum is not None and value < rule.minimum:
        return f"value {value!r} is below minimum {rule.minimum}"
    return None


def extract_p0_requirements(text: str) -> list[tuple[str, str]]:
    matches = list(re.finditer(r"^###\s+((?:FR|NFR|SEC|OPS)-[A-Z0-9-]+)\s+—", text, re.MULTILINE))
    sections: list[tuple[str, str]] = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        section = text[match.start():end]
        if re.search(r"\*\*Priority:\*\*\s*P0", section):
            sections.append((match.group(1), section))
    return sections


def iter_nodes(value: Any, location: str = "$"):
    """Yield every JSON node with a stable diagnostic location."""
    yield location, value
    if isinstance(value, dict):
        for key, child in value.items():
            yield from iter_nodes(child, f"{location}/{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from iter_nodes(child, f"{location}/{index}")


def resolve_local_ref(document: Any, reference: str) -> Any:
    """Resolve an RFC 6901 JSON Pointer fragment against one schema document."""
    if reference == "#":
        return document
    if not reference.startswith("#/"):
        raise ValueError(f"not a local JSON Pointer: {reference!r}")
    current = document
    fragment = unquote(reference[2:])
    for raw_token in fragment.split("/"):
        if re.search(r"~(?![01])", raw_token):
            raise ValueError(f"invalid JSON Pointer escape in {reference!r}")
        token = raw_token.replace("~1", "/").replace("~0", "~")
        if isinstance(current, dict) and token in current:
            current = current[token]
        elif isinstance(current, list) and token.isdigit() and int(token) < len(current):
            current = current[int(token)]
        else:
            raise ValueError(f"unresolved JSON Pointer {reference!r} at token {token!r}")
    return current


def schema_structure_errors(name: str, schema: Any) -> list[str]:
    """Perform dependency-free Draft 2020-12 structural validation."""
    errors: list[str] = []
    if not isinstance(schema, dict):
        return [f"{name}: schema root must be an object"]
    if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        errors.append(f"{name}: $schema must select Draft 2020-12")
    if not isinstance(schema.get("$id"), str) or not schema["$id"]:
        errors.append(f"{name}: non-empty $id is required")
    if not isinstance(schema.get("$defs"), dict) or not schema["$defs"]:
        errors.append(f"{name}: non-empty $defs object is required")

    valid_types = {"null", "boolean", "object", "array", "number", "string", "integer"}
    for location, node in iter_nodes(schema):
        if not isinstance(node, dict):
            continue
        if location.rsplit("/", 1)[-1] in {"properties", "patternProperties", "$defs", "dependentSchemas"}:
            # These nodes map names to schemas; a property literally named "type"
            # is not the JSON Schema `type` keyword at the mapping level.
            continue
        if "$ref" in node:
            reference = node["$ref"]
            if not isinstance(reference, str):
                errors.append(f"{name}:{location}: $ref must be a string")
            elif not reference.startswith("#"):
                errors.append(f"{name}:{location}: contract schemas must use self-contained local refs: {reference!r}")
            else:
                try:
                    resolve_local_ref(schema, reference)
                except ValueError as exc:
                    errors.append(f"{name}:{location}: {exc}")
        if "pattern" in node:
            pattern = node["pattern"]
            if not isinstance(pattern, str):
                errors.append(f"{name}:{location}: pattern must be a string")
            else:
                try:
                    re.compile(pattern)
                except re.error as exc:
                    errors.append(f"{name}:{location}: pattern does not compile: {exc}")
        for keyword in ("properties", "patternProperties", "$defs", "dependentSchemas"):
            if keyword in node and not isinstance(node[keyword], dict):
                errors.append(f"{name}:{location}: {keyword} must be an object")
        if "additionalProperties" in node and not isinstance(node["additionalProperties"], (bool, dict)):
            errors.append(f"{name}:{location}: additionalProperties must be boolean or schema object")
        if "required" in node:
            required = node["required"]
            if not isinstance(required, list) or not all(isinstance(item, str) for item in required):
                errors.append(f"{name}:{location}: required must be an array of strings")
            elif len(required) != len(set(required)):
                errors.append(f"{name}:{location}: required contains duplicates")
        if "enum" in node:
            enum = node["enum"]
            if not isinstance(enum, list) or not enum:
                errors.append(f"{name}:{location}: enum must be a non-empty array")
            else:
                serialized = [json.dumps(item, sort_keys=True, separators=(",", ":")) for item in enum]
                if len(serialized) != len(set(serialized)):
                    errors.append(f"{name}:{location}: enum contains duplicate values")
        if "type" in node:
            schema_type = node["type"]
            types = [schema_type] if isinstance(schema_type, str) else schema_type
            if not isinstance(types, list) or not types or not all(item in valid_types for item in types):
                errors.append(f"{name}:{location}: invalid type declaration {schema_type!r}")
            elif len(types) != len(set(types)):
                errors.append(f"{name}:{location}: type declaration contains duplicates")
        for keyword in ("oneOf", "allOf", "anyOf"):
            if keyword in node and (not isinstance(node[keyword], list) or not node[keyword]):
                errors.append(f"{name}:{location}: {keyword} must be a non-empty array")
        for keyword in ("minItems", "maxItems", "minProperties", "maxProperties", "minLength", "maxLength"):
            if keyword in node and (type(node[keyword]) is not int or node[keyword] < 0):
                errors.append(f"{name}:{location}: {keyword} must be a non-negative integer")
        for minimum, maximum in (("minItems", "maxItems"), ("minProperties", "maxProperties"), ("minLength", "maxLength")):
            if minimum in node and maximum in node and node[minimum] > node[maximum]:
                errors.append(f"{name}:{location}: {minimum} exceeds {maximum}")
    return errors


def pattern_accepts(pattern: str, value: str) -> bool:
    return re.search(pattern, value) is not None


def schema_probe_valid(instance: Any, schema: Any, root_schema: dict[str, Any]) -> bool:
    """Evaluate the dependency-free JSON Schema subset used by invariant probes."""
    if isinstance(schema, bool):
        return schema
    if not isinstance(schema, dict):
        return False
    if "$ref" in schema:
        try:
            target = resolve_local_ref(root_schema, schema["$ref"])
        except (KeyError, TypeError, ValueError):
            return False
        if not schema_probe_valid(instance, target, root_schema):
            return False

    def json_equal(left: Any, right: Any) -> bool:
        if isinstance(left, bool) or isinstance(right, bool):
            return type(left) is type(right) and left == right
        return left == right

    def matches_type(type_name: str) -> bool:
        return {
            "null": instance is None,
            "boolean": type(instance) is bool,
            "object": isinstance(instance, dict),
            "array": isinstance(instance, list),
            "number": type(instance) in {int, float} and math.isfinite(instance),
            "integer": type(instance) is int,
            "string": isinstance(instance, str),
        }.get(type_name, False)

    if "type" in schema:
        declared = schema["type"]
        types = [declared] if isinstance(declared, str) else declared
        if not isinstance(types, list) or not any(matches_type(item) for item in types):
            return False
    if "const" in schema and not json_equal(instance, schema["const"]):
        return False
    if "enum" in schema and not any(json_equal(instance, allowed) for allowed in schema["enum"]):
        return False
    if "allOf" in schema and not all(schema_probe_valid(instance, child, root_schema) for child in schema["allOf"]):
        return False
    if "anyOf" in schema and not any(schema_probe_valid(instance, child, root_schema) for child in schema["anyOf"]):
        return False
    if "oneOf" in schema and sum(schema_probe_valid(instance, child, root_schema) for child in schema["oneOf"]) != 1:
        return False
    if "not" in schema and schema_probe_valid(instance, schema["not"], root_schema):
        return False
    if "if" in schema and schema_probe_valid(instance, schema["if"], root_schema):
        if "then" in schema and not schema_probe_valid(instance, schema["then"], root_schema):
            return False
    elif "else" in schema and not schema_probe_valid(instance, schema["else"], root_schema):
        return False

    if isinstance(instance, dict):
        required = schema.get("required", [])
        if any(key not in instance for key in required):
            return False
        properties = schema.get("properties", {})
        for key, child_schema in properties.items():
            if key in instance and not schema_probe_valid(instance[key], child_schema, root_schema):
                return False
        if schema.get("additionalProperties") is False and any(key not in properties for key in instance):
            return False
        if "minProperties" in schema and len(instance) < schema["minProperties"]:
            return False
        if "maxProperties" in schema and len(instance) > schema["maxProperties"]:
            return False
    if isinstance(instance, list):
        if "minItems" in schema and len(instance) < schema["minItems"]:
            return False
        if "maxItems" in schema and len(instance) > schema["maxItems"]:
            return False
        if "items" in schema and not all(schema_probe_valid(item, schema["items"], root_schema) for item in instance):
            return False
        if "prefixItems" in schema:
            prefix_items = schema["prefixItems"]
            if not isinstance(prefix_items, list):
                return False
            for index, child_schema in enumerate(prefix_items):
                if index < len(instance) and not schema_probe_valid(instance[index], child_schema, root_schema):
                    return False
        if "contains" in schema:
            matches = sum(schema_probe_valid(item, schema["contains"], root_schema) for item in instance)
            if matches < schema.get("minContains", 1):
                return False
            if "maxContains" in schema and matches > schema["maxContains"]:
                return False
        if schema.get("uniqueItems") is True:
            serialized = [json.dumps(item, sort_keys=True, separators=(",", ":")) for item in instance]
            if len(serialized) != len(set(serialized)):
                return False
    if isinstance(instance, str):
        if "minLength" in schema and len(instance) < schema["minLength"]:
            return False
        if "maxLength" in schema and len(instance) > schema["maxLength"]:
            return False
        if "pattern" in schema and not pattern_accepts(schema["pattern"], instance):
            return False
    if type(instance) in {int, float} and not isinstance(instance, bool):
        if "minimum" in schema and instance < schema["minimum"]:
            return False
        if "maximum" in schema and instance > schema["maximum"]:
            return False
        if "exclusiveMinimum" in schema and instance <= schema["exclusiveMinimum"]:
            return False
        if "exclusiveMaximum" in schema and instance >= schema["exclusiveMaximum"]:
            return False
    return True


def _property_path_ref_errors(schema_name: str, schema: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    for location, node in iter_nodes(schema):
        if not isinstance(node, dict) or not isinstance(node.get("properties"), dict):
            continue
        for field_name, field_schema in node["properties"].items():
            if field_name == "relative_path" or field_name.endswith("_path"):
                if not isinstance(field_schema, dict) or field_schema.get("$ref") != "#/$defs/archiveRelativePath":
                    errors.append(f"{schema_name}:{location}/{field_name}: archive path must reference archiveRelativePath")
    return errors


def contract_invariant_errors(schemas: dict[str, dict[str, Any]]) -> list[str]:
    """Prove load-bearing negative path, ID, replay, and transaction invariants."""
    errors: list[str] = []
    path_schema_names = {
        "edit-artifacts.schema.json",
        "frame-packet.schema.json",
        "rrcap-manifest.schema.json",
    }
    safe_paths = ("frames/frame_0001.jpg", "artifacts/a-b_1.json")
    unsafe_paths = ("", "../secret", "a/../secret", "/absolute", "C:/absolute", "C:\\absolute", "a\\b", "./file", "a//b", ".hidden")
    for schema_name in path_schema_names:
        schema = schemas.get(schema_name, {})
        path_rule = schema.get("$defs", {}).get("archiveRelativePath", {})
        pattern = path_rule.get("pattern")
        if not isinstance(pattern, str):
            errors.append(f"{schema_name}: archiveRelativePath pattern is missing")
            continue
        for sample in safe_paths:
            if not pattern_accepts(pattern, sample):
                errors.append(f"{schema_name}: safe archive path rejected: {sample!r}")
        for sample in unsafe_paths:
            if pattern_accepts(pattern, sample):
                errors.append(f"{schema_name}: unsafe archive path accepted: {sample!r}")
        errors.extend(_property_path_ref_errors(schema_name, schema))

    uuid_suffix_v4 = "123e4567-e89b-42d3-a456-426614174000"
    uuid_suffix_v7 = "01890f47-6d3a-7d31-8f3a-123456789abc"
    invalid_suffixes = (
        "123e4567-e89b-12d3-a456-426614174000",
        "123e4567-e89b-42d3-7456-426614174000",
        "123E4567-E89B-42D3-A456-426614174000",
    )
    prefixes = (
        "artifact", "asset", "assetinst", "branch", "device", "event", "frame", "frameidem",
        "gateway", "object", "preview", "scene", "session", "submap", "support", "surface", "tx",
        "txidem", "undo", "world", "actor", "envelope", "layer", "user",
    )
    uuid_pattern_count = 0
    for schema_name, schema in schemas.items():
        for location, node in iter_nodes(schema):
            if not isinstance(node, dict) or not isinstance(node.get("pattern"), str):
                continue
            pattern = node["pattern"]
            if "[0-9a-f]{8}" not in pattern:
                continue
            uuid_pattern_count += 1
            if "[47][0-9a-f]{3}" not in pattern or "[89ab][0-9a-f]{3}" not in pattern:
                errors.append(f"{schema_name}:{location}: ID pattern is not RFC 9562 v4/v7 constrained")
                continue
            matching_prefix = next((prefix for prefix in prefixes if pattern_accepts(pattern, f"{prefix}_{uuid_suffix_v4}")), None)
            if matching_prefix is None:
                errors.append(f"{schema_name}:{location}: ID pattern accepts no known canonical prefix")
                continue
            if not pattern_accepts(pattern, f"{matching_prefix}_{uuid_suffix_v7}"):
                errors.append(f"{schema_name}:{location}: ID pattern rejects a valid v7 UUID")
            for invalid in invalid_suffixes:
                if pattern_accepts(pattern, f"{matching_prefix}_{invalid}"):
                    errors.append(f"{schema_name}:{location}: ID pattern accepts invalid UUID {invalid!r}")
    if uuid_pattern_count < 20:
        errors.append(f"only {uuid_pattern_count} RFC 9562 identifier patterns were exercised")

    sample_uuid = "123e4567-e89b-42d3-a456-426614174000"

    def identifier(prefix: str) -> str:
        return f"{prefix}_{sample_uuid}"

    other_uuid = "123e4567-e89b-42d3-a456-426614174001"

    def other_identifier(prefix: str) -> str:
        return f"{prefix}_{other_uuid}"

    third_uuid = "123e4567-e89b-42d3-a456-426614174002"

    def third_identifier(prefix: str) -> str:
        return f"{prefix}_{third_uuid}"

    identity_matrix = {
        "layout": "row_major",
        "scalar_type": "float32",
        "math_convention": "column_vector",
        "units": "meters",
        "values": [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0],
    }

    frame_schema = schemas.get("frame-packet.schema.json", {})
    durability = frame_schema.get("$defs", {}).get("durability", {})
    if durability.get("additionalProperties") is not False:
        errors.append("frame-packet.schema.json: durability object must be closed")
    durability_required = {"state", "image_and_metadata_durable", "journal_sequence", "network_eligible"}
    if not durability_required.issubset(set(durability.get("required", []))):
        errors.append(f"frame-packet.schema.json: durability fields missing {sorted(durability_required-set(durability.get('required', [])))}")
    if durability.get("properties", {}).get("state", {}).get("const") != "network_eligible":
        errors.append("frame-packet.schema.json: persisted packet snapshot must be at the network_eligible lifecycle state")
    if durability.get("properties", {}).get("image_and_metadata_durable", {}).get("const") is not True:
        errors.append("frame-packet.schema.json: durability must require image+metadata before eligibility")
    if durability.get("properties", {}).get("network_eligible", {}).get("const") is not True:
        errors.append("frame-packet.schema.json: durability must explicitly require network eligibility")

    durability_baseline = {
        "state": "network_eligible",
        "image_and_metadata_durable": True,
        "journal_sequence": 0,
        "network_eligible": True,
    }
    durability_cases = (
        ("network-eligible durable baseline accepted", durability_baseline, True),
        ("state cannot precede network eligibility", {**durability_baseline, "state": "journaled"}, False),
        ("network eligibility cannot disagree with state", {**durability_baseline, "network_eligible": False}, False),
        ("image and metadata durability cannot be false", {**durability_baseline, "image_and_metadata_durable": False}, False),
        ("journal sequence cannot be omitted", {key: value for key, value in durability_baseline.items() if key != "journal_sequence"}, False),
        ("journal sequence cannot be negative", {**durability_baseline, "journal_sequence": -1}, False),
    )
    for label, instance, expected_valid in durability_cases:
        if schema_probe_valid(instance, durability, frame_schema) is not expected_valid:
            errors.append(f"frame-packet.schema.json: durability probe failed: {label}")

    tracking = frame_schema.get("$defs", {}).get("tracking", {})
    tracking_cases = (
        ("normal requires no limitation reason", {"state": "normal", "reason": "none"}, True),
        ("limited accepts initializing", {"state": "limited", "reason": "initializing"}, True),
        ("limited accepts excessive motion", {"state": "limited", "reason": "excessive_motion"}, True),
        ("limited accepts insufficient features", {"state": "limited", "reason": "insufficient_features"}, True),
        ("limited accepts relocalizing", {"state": "limited", "reason": "relocalizing"}, True),
        ("limited accepts unknown", {"state": "limited", "reason": "unknown"}, True),
        ("not available accepts camera unavailable", {"state": "not_available", "reason": "camera_unavailable"}, True),
        ("not available accepts unknown", {"state": "not_available", "reason": "unknown"}, True),
        ("normal rejects a limitation reason", {"state": "normal", "reason": "initializing"}, False),
        ("limited rejects none", {"state": "limited", "reason": "none"}, False),
        ("limited rejects camera unavailable", {"state": "limited", "reason": "camera_unavailable"}, False),
        ("not available rejects none", {"state": "not_available", "reason": "none"}, False),
        ("not available rejects a limited-only reason", {"state": "not_available", "reason": "relocalizing"}, False),
        ("tracking rejects an unknown field", {"state": "normal", "reason": "none", "confidence": 1.0}, False),
    )
    for label, instance, expected_valid in tracking_cases:
        if schema_probe_valid(instance, tracking, frame_schema) is not expected_valid:
            errors.append(f"frame-packet.schema.json: tracking state/reason probe failed: {label}")

    rrcap = schemas.get("rrcap-manifest.schema.json", {})
    if "journal" not in rrcap.get("required", []):
        errors.append("rrcap-manifest.schema.json: global journal is not required")
    journal = rrcap.get("properties", {}).get("journal", {})
    if journal.get("items", {}).get("$ref") != "#/$defs/journalEntry" or journal.get("minItems", 0) < 1:
        errors.append("rrcap-manifest.schema.json: journal must be a non-empty journalEntry sequence")
    journal_variants = rrcap.get("$defs", {}).get("journalEntry", {}).get("oneOf", [])
    journal_types = {variant.get("properties", {}).get("entry_type", {}).get("const") for variant in journal_variants}
    if journal_types != {"frame", "event"} or any(variant.get("additionalProperties") is not False for variant in journal_variants):
        errors.append("rrcap-manifest.schema.json: journal entries must be closed frame/event variants")
    replay = rrcap.get("$defs", {}).get("replay", {}).get("properties", {})
    expected_replay = {
        "ordering_authority": "global_journal_sequence",
        "input_digest_algorithm": "RR-JCS-SHA256-1",
        "input_digest_scope": "jcs_array_of_journal_sequence_entry_type_reference_id_content_sha256",
    }
    for field_name, expected in expected_replay.items():
        if replay.get(field_name, {}).get("const") != expected:
            errors.append(f"rrcap-manifest.schema.json: replay {field_name} is not pinned to {expected!r}")
    finalization = rrcap.get("$defs", {}).get("finalization", {}).get("properties", {})
    expected_finalization = {
        "manifest_sha256_algorithm": "RR-JCS-SHA256-1",
        "manifest_sha256_scope": "entire_manifest_with_finalization_manifest_sha256_member_omitted",
    }
    for field_name, expected in expected_finalization.items():
        if finalization.get(field_name, {}).get("const") != expected:
            errors.append(f"rrcap-manifest.schema.json: finalization {field_name} is not pinned to {expected!r}")
    event_types = set(rrcap.get("$defs", {}).get("event", {}).get("properties", {}).get("type", {}).get("enum", []))
    lifecycle = {
        "frame_selected",
        "frame_image_and_metadata_durable",
        "frame_journaled",
        "frame_network_eligible",
        "frame_server_acknowledged",
    }
    if not lifecycle.issubset(event_types):
        errors.append(f"rrcap-manifest.schema.json: capture lifecycle events missing {sorted(lifecycle - event_types)}")

    ordinary_video_schema = rrcap.get("$defs", {}).get("ordinaryVideo", {})
    ordinary_video = {
        "file_path": "video/import.mp4",
        "sha256": "7" * 64,
        "container": "mp4",
        "video_codec": "h264_video",
        "timeline_timebase": "1/600",
        "calibration_state": "uncalibrated_no_world_authority",
        "replay_guarantee": "decode_and_timeline_only",
        "learned_geometry_state": "unavailable",
    }
    ordinary_video_cases = (
        ("ordinary video baseline accepted", ordinary_video, True),
        ("ordinary video cannot claim calibrated world authority", {**ordinary_video, "calibration_state": "calibrated"}, False),
        ("ordinary video cannot claim deterministic spatial replay", {**ordinary_video, "replay_guarantee": "deterministic_spatial_replay"}, False),
        ("ordinary video cannot carry a world frame", {**ordinary_video, "world_frame_id": identifier("world")}, False),
        ("ordinary video cannot carry an ARKit pose", {**ordinary_video, "camera_pose": copy.deepcopy(identity_matrix)}, False),
        ("ordinary video cannot carry fabricated intrinsics", {**ordinary_video, "intrinsics": [1.0] * 9}, False),
        ("ordinary video cannot carry fabricated metric scale", {**ordinary_video, "metric_scale_m": 1.0}, False),
    )
    for label, instance, expected_valid in ordinary_video_cases:
        if schema_probe_valid(instance, ordinary_video_schema, rrcap) is not expected_valid:
            errors.append(f"rrcap-manifest.schema.json: ordinary-video probe failed: {label}")

    privacy_schema = rrcap.get("$defs", {}).get("privacy", {})
    privacy_baseline = {
        "capture_consent_recorded": True,
        "contains_room_imagery": True,
        "retention_policy": "local_only_until_share",
        "deletion_state": "none",
        "share_access_state": "not_shared",
    }
    privacy_cases = (
        ("consented local-only baseline accepted", privacy_baseline, True),
        ("capture without consent rejected", {**privacy_baseline, "capture_consent_recorded": False}, False),
        ("room imagery declaration cannot be false", {**privacy_baseline, "contains_room_imagery": False}, False),
        ("TTL requires an expiry", {**privacy_baseline, "retention_policy": "session_ttl"}, False),
        ("TTL rejects a null expiry", {**privacy_baseline, "retention_policy": "session_ttl", "retention_expires_at": None}, False),
        ("TTL accepts an explicit expiry", {**privacy_baseline, "retention_policy": "session_ttl", "retention_expires_at": "2026-07-14T13:00:00Z"}, True),
        ("deletion request requires a timestamp", {**privacy_baseline, "deletion_state": "requested"}, False),
        (
            "deletion request cannot leave sharing active",
            {**privacy_baseline, "deletion_state": "requested", "deletion_requested_at": "2026-07-14T12:00:00Z", "share_access_state": "active"},
            False,
        ),
        (
            "deletion request accepts revoked access and timestamp",
            {**privacy_baseline, "deletion_state": "requested", "deletion_requested_at": "2026-07-14T12:00:00Z", "share_access_state": "revoked"},
            True,
        ),
    )
    for label, instance, expected_valid in privacy_cases:
        if schema_probe_valid(instance, privacy_schema, rrcap) is not expected_valid:
            errors.append(f"rrcap-manifest.schema.json: privacy lifecycle probe failed: {label}")

    def structured_probe_sha256(value: Any) -> str:
        import hashlib

        canonical_probe_bytes = json.dumps(
            value, ensure_ascii=False, separators=(",", ":"), sort_keys=True
        ).encode("utf-8")
        return hashlib.sha256(canonical_probe_bytes).hexdigest()

    def event_record(
        event_id: str,
        event_sequence: int,
        journal_sequence: int,
        monotonic_timestamp_ns: str,
    ) -> dict[str, Any]:
        event_without_digest = {
            "event_id": event_id,
            "event_sequence": event_sequence,
            "durable_journal_sequence": journal_sequence,
            "monotonic_timestamp_ns": monotonic_timestamp_ns,
            "type": "ordinary_video_imported",
            "payload_sha256": "7" * 64,
            "payload_path": "video/import.mp4",
            "record_sha256_algorithm": "RR-JCS-SHA256-1",
            "record_sha256_scope": "entire_event_record_with_record_sha256_member_omitted",
        }
        return {
            **event_without_digest,
            "record_sha256": structured_probe_sha256(event_without_digest),
        }

    def replay_input_digest(journal_entries: list[dict[str, Any]]) -> str:
        tuples = [
            [
                entry["journal_sequence"],
                entry["entry_type"],
                entry["reference_id"],
                entry["content_sha256"],
            ]
            for entry in journal_entries
        ]
        return structured_probe_sha256(tuples)

    imported_event = event_record(identifier("event"), 0, 0, "1")
    ordinary_journal = [
        {
            "journal_sequence": 0,
            "monotonic_timestamp_ns": "1",
            "entry_type": "event",
            "reference_id": identifier("event"),
            "content_sha256": imported_event["record_sha256"],
        }
    ]

    ordinary_manifest = {
        "format_version": "1.0.0",
        "capture_kind": "ordinary_video_import",
        "session_id": identifier("session"),
        "source": {
            "device_model": "import",
            "os_version": "1",
            "app_version": "1",
            "build_id": "probe",
            "recorded_at_utc": "2026-07-14T12:00:00Z",
        },
        "files": [
            {
                "relative_path": "video/import.mp4",
                "media_type": "video/mp4",
                "codec": "h264_video",
                "byte_length": 1,
                "sha256": "7" * 64,
                "role": "ordinary_video",
            },
            {
                "relative_path": "events/ordinary-video-imported.json",
                "media_type": "application/json",
                "codec": "json_jcs_1",
                "byte_length": 1,
                "sha256": imported_event["record_sha256"],
                "role": "event_log",
            },
        ],
        "journal": ordinary_journal,
        "accepted_frame_order": [],
        "keyframes": [],
        "events": [imported_event],
        "replay": {
            "ordering_authority": "global_journal_sequence",
            "input_digest_algorithm": "RR-JCS-SHA256-1",
            "input_digest_scope": "jcs_array_of_journal_sequence_entry_type_reference_id_content_sha256",
            "input_digest": replay_input_digest(ordinary_journal),
            "neural_determinism": "tolerance_based_when_provider_pinned",
            "provider_lock": [],
        },
        "privacy": copy.deepcopy(privacy_baseline),
        "finalization": {
            "state": "finalized",
            "manifest_sha256_algorithm": "RR-JCS-SHA256-1",
            "manifest_sha256_scope": "entire_manifest_with_finalization_manifest_sha256_member_omitted",
            "manifest_sha256": "a" * 64,
            "last_durable_journal_sequence": 0,
        },
        "ordinary_video": copy.deepcopy(ordinary_video),
    }

    def rrcap_semantically_valid(manifest: dict[str, Any]) -> bool:
        if not schema_probe_valid(manifest, rrcap, rrcap):
            return False
        journal_entries = manifest.get("journal")
        if not isinstance(journal_entries, list) or not journal_entries:
            return False
        if [entry.get("journal_sequence") for entry in journal_entries] != list(range(len(journal_entries))):
            return False

        frame_entries = [entry for entry in journal_entries if entry.get("entry_type") == "frame"]
        accepted_frames = manifest.get("accepted_frame_order")
        if not isinstance(accepted_frames, list) or len(accepted_frames) != len(frame_entries):
            return False
        for sequence, (journal_entry, frame) in enumerate(zip(frame_entries, accepted_frames)):
            if (
                frame.get("sequence") != sequence
                or frame.get("frame_id") != journal_entry.get("reference_id")
                or frame.get("durable_journal_sequence") != journal_entry.get("journal_sequence")
                or frame.get("packet_sha256") != journal_entry.get("content_sha256")
            ):
                return False

        event_entries = [entry for entry in journal_entries if entry.get("entry_type") == "event"]
        events = manifest.get("events")
        if not isinstance(events, list) or len(events) != len(event_entries):
            return False
        for sequence, (journal_entry, event) in enumerate(zip(event_entries, events)):
            event_without_digest = {
                key: value for key, value in event.items() if key != "record_sha256"
            }
            expected_record_digest = structured_probe_sha256(event_without_digest)
            if (
                event.get("event_sequence") != sequence
                or event.get("event_id") != journal_entry.get("reference_id")
                or event.get("durable_journal_sequence") != journal_entry.get("journal_sequence")
                or event.get("monotonic_timestamp_ns") != journal_entry.get("monotonic_timestamp_ns")
                or event.get("record_sha256") != expected_record_digest
                or journal_entry.get("content_sha256") != expected_record_digest
            ):
                return False

        finalization = manifest.get("finalization", {})
        if finalization.get("last_durable_journal_sequence") != journal_entries[-1].get("journal_sequence"):
            return False
        replay = manifest.get("replay", {})
        if replay.get("input_digest") != replay_input_digest(journal_entries):
            return False
        return True

    if not rrcap_semantically_valid(ordinary_manifest):
        errors.append("rrcap-manifest.schema.json: ordinary-video import baseline probe is invalid")
    ordinary_with_coordinates = copy.deepcopy(ordinary_manifest)
    ordinary_with_coordinates["coordinate_convention"] = {
        "convention": "RR-COORD-1",
        "world_frame_id": identifier("world"),
        "initial_world_frame_version": 1,
    }
    if schema_probe_valid(ordinary_with_coordinates, rrcap, rrcap):
        errors.append("rrcap-manifest.schema.json: ordinary-video import accepts fabricated RR-COORD-1 world authority")
    ordinary_with_arkit = copy.deepcopy(ordinary_manifest)
    ordinary_with_arkit["capture_settings"] = {
        "camera_format": "probe",
        "frame_selection_policy": "probe",
        "queue_capacity": 1,
        "high_resolution_keyframe_policy": "probe",
        "arkit_configuration": {
            "world_tracking": True,
            "plane_detection": ["horizontal"],
            "lidar_required": False,
        },
    }
    if schema_probe_valid(ordinary_with_arkit, rrcap, rrcap):
        errors.append("rrcap-manifest.schema.json: ordinary-video import accepts ARKit capture settings")
    ordinary_with_frames = copy.deepcopy(ordinary_manifest)
    ordinary_with_frames["accepted_frame_order"] = [{}]
    if schema_probe_valid(ordinary_with_frames, rrcap, rrcap):
        errors.append("rrcap-manifest.schema.json: ordinary-video import accepts fabricated accepted frames")

    missing_event_projection = copy.deepcopy(ordinary_manifest)
    missing_event_projection["events"] = []
    if rrcap_semantically_valid(missing_event_projection):
        errors.append("rrcap-manifest.schema.json: journal event can be missing from the events projection")
    extra_event_projection = copy.deepcopy(ordinary_manifest)
    extra_event_projection["events"].append(copy.deepcopy(imported_event))
    if rrcap_semantically_valid(extra_event_projection):
        errors.append("rrcap-manifest.schema.json: events projection accepts an extra event")
    wrong_event_reference = copy.deepcopy(ordinary_manifest)
    wrong_event_reference["journal"][0]["reference_id"] = other_identifier("event")
    wrong_event_reference["replay"]["input_digest"] = replay_input_digest(wrong_event_reference["journal"])
    if rrcap_semantically_valid(wrong_event_reference):
        errors.append("rrcap-manifest.schema.json: event projection accepts a wrong journal reference ID")
    wrong_event_hash = copy.deepcopy(ordinary_manifest)
    wrong_event_hash["journal"][0]["content_sha256"] = "0" * 64
    wrong_event_hash["replay"]["input_digest"] = replay_input_digest(wrong_event_hash["journal"])
    if rrcap_semantically_valid(wrong_event_hash):
        errors.append("rrcap-manifest.schema.json: event projection accepts a wrong journal record hash")
    wrong_event_sequence = copy.deepcopy(ordinary_manifest)
    wrong_event_sequence["events"][0]["event_sequence"] = 1
    if rrcap_semantically_valid(wrong_event_sequence):
        errors.append("rrcap-manifest.schema.json: event projection accepts a non-contiguous event sequence")

    second_event = event_record(other_identifier("event"), 1, 1, "2")
    two_event_manifest = copy.deepcopy(ordinary_manifest)
    two_event_manifest["journal"].append(
        {
            "journal_sequence": 1,
            "monotonic_timestamp_ns": "2",
            "entry_type": "event",
            "reference_id": other_identifier("event"),
            "content_sha256": second_event["record_sha256"],
        }
    )
    two_event_manifest["events"].append(second_event)
    two_event_manifest["replay"]["input_digest"] = replay_input_digest(two_event_manifest["journal"])
    two_event_manifest["finalization"]["last_durable_journal_sequence"] = 1
    if not rrcap_semantically_valid(two_event_manifest):
        errors.append("rrcap-manifest.schema.json: two-event journal baseline is invalid")
    reordered_events = copy.deepcopy(two_event_manifest)
    reordered_events["events"].reverse()
    if rrcap_semantically_valid(reordered_events):
        errors.append("rrcap-manifest.schema.json: events projection accepts reordered events")
    reordered_journal = copy.deepcopy(two_event_manifest)
    reordered_journal["journal"].reverse()
    reordered_journal["replay"]["input_digest"] = replay_input_digest(reordered_journal["journal"])
    if rrcap_semantically_valid(reordered_journal):
        errors.append("rrcap-manifest.schema.json: global journal accepts non-contiguous array order")

    native_manifest = copy.deepcopy(ordinary_manifest)
    native_manifest["capture_kind"] = "native_arkit"
    del native_manifest["ordinary_video"]
    native_manifest["coordinate_convention"] = {
        "convention": "RR-COORD-1",
        "world_frame_id": identifier("world"),
        "initial_world_frame_version": 1,
    }
    native_manifest["capture_settings"] = copy.deepcopy(ordinary_with_arkit["capture_settings"])
    frame_hashes = ("a" * 64, "b" * 64)
    frame_ids = (identifier("frame"), other_identifier("frame"))
    native_manifest["files"] = []
    native_manifest["journal"] = []
    native_manifest["accepted_frame_order"] = []
    native_manifest["events"] = []
    for sequence, (frame_id, frame_hash) in enumerate(zip(frame_ids, frame_hashes)):
        packet_path = f"frames/frame-{sequence}.json"
        native_manifest["files"].append(
            {
                "relative_path": packet_path,
                "media_type": "application/json",
                "codec": "json_jcs_1",
                "byte_length": 1,
                "sha256": frame_hash,
                "role": "frame_metadata",
            }
        )
        native_manifest["journal"].append(
            {
                "journal_sequence": sequence,
                "monotonic_timestamp_ns": str(sequence + 1),
                "entry_type": "frame",
                "reference_id": frame_id,
                "content_sha256": frame_hash,
            }
        )
        native_manifest["accepted_frame_order"].append(
            {
                "sequence": sequence,
                "frame_id": frame_id,
                "packet_path": packet_path,
                "packet_sha256": frame_hash,
                "durable_journal_sequence": sequence,
            }
        )
    native_manifest["replay"]["input_digest"] = replay_input_digest(native_manifest["journal"])
    native_manifest["finalization"]["last_durable_journal_sequence"] = 1
    if not rrcap_semantically_valid(native_manifest):
        errors.append("rrcap-manifest.schema.json: two-frame native journal baseline is invalid")
    for label, field_name, bad_value in (
        ("frame ID", "frame_id", other_identifier("frame")),
        ("frame digest", "packet_sha256", "0" * 64),
        ("durable journal sequence", "durable_journal_sequence", 1),
        ("per-type frame sequence", "sequence", 1),
    ):
        invalid_frame_projection = copy.deepcopy(native_manifest)
        invalid_frame_projection["accepted_frame_order"][0][field_name] = bad_value
        if rrcap_semantically_valid(invalid_frame_projection):
            errors.append(f"rrcap-manifest.schema.json: frame projection accepts wrong {label}")
    missing_frame_projection = copy.deepcopy(native_manifest)
    missing_frame_projection["accepted_frame_order"].pop()
    if rrcap_semantically_valid(missing_frame_projection):
        errors.append("rrcap-manifest.schema.json: accepted-frame projection can omit a journal frame")
    extra_frame_projection = copy.deepcopy(native_manifest)
    extra_frame_projection["accepted_frame_order"].append(
        copy.deepcopy(extra_frame_projection["accepted_frame_order"][-1])
    )
    if rrcap_semantically_valid(extra_frame_projection):
        errors.append("rrcap-manifest.schema.json: accepted-frame projection accepts an extra frame")
    reordered_frames = copy.deepcopy(native_manifest)
    reordered_frames["accepted_frame_order"].reverse()
    if rrcap_semantically_valid(reordered_frames):
        errors.append("rrcap-manifest.schema.json: accepted-frame projection accepts reordered frames")
    wrong_final_sequence = copy.deepcopy(native_manifest)
    wrong_final_sequence["finalization"]["last_durable_journal_sequence"] = 0
    if rrcap_semantically_valid(wrong_final_sequence):
        errors.append("rrcap-manifest.schema.json: finalization accepts a non-final durable journal sequence")
    wrong_replay_digest = copy.deepcopy(native_manifest)
    wrong_replay_digest["replay"]["input_digest"] = "0" * 64
    if rrcap_semantically_valid(wrong_replay_digest):
        errors.append("rrcap-manifest.schema.json: replay accepts a digest not derived from ordered journal tuples")

    codec_registry = {
        "json_jcs_1", "jsonl_utf8_1", "jpeg", "png", "hevc_intra", "hevc_video", "h264_video",
        "glb2", "usdz", "ply_binary_little_endian_1_0", "npy_1_0", "ktx2_2_0",
    }
    rrcap_codecs = set(rrcap.get("$defs", {}).get("file", {}).get("properties", {}).get("codec", {}).get("enum", []))
    frame_codecs = set(frame_schema.get("$defs", {}).get("image", {}).get("properties", {}).get("codec", {}).get("enum", []))
    edit_codecs = set(schemas.get("edit-artifacts.schema.json", {}).get("$defs", {}).get("payload", {}).get("properties", {}).get("codec", {}).get("enum", []))
    if rrcap_codecs != codec_registry:
        errors.append(f"rrcap-manifest.schema.json: closed codec registry mismatch {sorted(rrcap_codecs)}")
    if frame_codecs != {"jpeg", "hevc_intra", "png"}:
        errors.append(f"frame-packet.schema.json: frame codec subset mismatch {sorted(frame_codecs)}")
    expected_edit_codecs = {"glb2", "ply_binary_little_endian_1_0", "npy_1_0", "json_jcs_1", "png", "jpeg", "ktx2_2_0", "usdz"}
    if edit_codecs != expected_edit_codecs or not edit_codecs.issubset(codec_registry):
        errors.append(f"edit-artifacts.schema.json: artifact codec subset mismatch {sorted(edit_codecs)}")

    edit_artifacts = schemas.get("edit-artifacts.schema.json", {})
    edit_defs = edit_artifacts.get("$defs", {})

    def payload(codec: str, stem: str = "payload") -> dict[str, Any]:
        return {
            "relative_path": f"artifacts/{stem}.bin",
            "codec": codec,
            "media_type": "application/octet-stream",
            "byte_length": 1,
            "sha256": "b" * 64,
        }

    def artifact_base(artifact_type: str, readiness: str = "ready") -> dict[str, Any]:
        return {
            "schema_version": "1.0.0",
            "artifact_id": identifier("artifact"),
            "artifact_type": artifact_type,
            "artifact_revision": 1,
            "origin_revision_branch_id": identifier("branch"),
            "activation_revision_branch_id": identifier("branch"),
            "producing_authority_id": identifier("device"),
            "scene_revision": 0,
            "world_frame_id": identifier("world"),
            "world_frame_version": 2,
            "readiness": readiness,
            "provider": {
                "name": "probe",
                "version": "1",
                "configuration_sha256": "c" * 64,
                "provenance": "deterministic_local",
            },
            "created_at_utc": "2026-07-14T12:00:00Z",
            "content_sha256_algorithm": "RR-JCS-SHA256-1",
            "content_sha256_scope": "entire_artifact_record_with_content_sha256_member_omitted",
            "content_sha256": "d" * 64,
        }

    world_mesh_encoding = {
        "kind": "mesh_vertices_in_artifact_world_frame",
        "coordinate_convention": "RR-COORD-1",
        "vertex_coordinate_space": "artifact_world_frame",
        "units": "meters",
    }
    world_mesh_schema = edit_defs.get("worldMeshEncoding", {})
    world_mesh_cases = (
        ("world-mesh baseline accepted", world_mesh_encoding, True),
        ("world-mesh convention is required", {key: value for key, value in world_mesh_encoding.items() if key != "coordinate_convention"}, False),
        ("world-mesh convention is RR-COORD-1", {**world_mesh_encoding, "coordinate_convention": "OpenGL"}, False),
        ("world-mesh vertices are in artifact world space", {**world_mesh_encoding, "vertex_coordinate_space": "asset_local"}, False),
        ("world-mesh units are meters", {**world_mesh_encoding, "units": "centimeters"}, False),
        ("world-mesh cannot add an implicit node transform", {**world_mesh_encoding, "node_transform": copy.deepcopy(identity_matrix)}, False),
    )
    for label, instance, expected_valid in world_mesh_cases:
        if schema_probe_valid(instance, world_mesh_schema, edit_artifacts) is not expected_valid:
            errors.append(f"edit-artifacts.schema.json: world-mesh encoding probe failed: {label}")

    voxel_grid_encoding = {
        "kind": "sparse_voxel_grid_v1",
        "coordinate_convention": "RR-COORD-1",
        "world_from_volume": copy.deepcopy(identity_matrix),
        "voxel_size_xyz_m": [0.01, 0.01, 0.01],
        "dimensions_xyz": [10, 20, 30],
        "array_shape_order": "z_y_x",
        "memory_order": "c_contiguous",
        "dtype": "uint8",
        "empty_value": 0,
        "occupied_value": 1,
        "voxel_center_convention": "index_plus_half_times_voxel_size",
    }
    voxel_schema = edit_defs.get("voxelGridEncoding", {})
    voxel_cases = (
        ("voxel-grid baseline accepted", voxel_grid_encoding, True),
        ("voxel grid requires a world transform", {key: value for key, value in voxel_grid_encoding.items() if key != "world_from_volume"}, False),
        ("voxel grid uses RR-COORD-1", {**voxel_grid_encoding, "coordinate_convention": "camera_local"}, False),
        ("voxel size has exactly xyz components", {**voxel_grid_encoding, "voxel_size_xyz_m": [0.01, 0.01]}, False),
        ("voxel size components are positive", {**voxel_grid_encoding, "voxel_size_xyz_m": [0.01, 0.0, 0.01]}, False),
        ("voxel dimensions have exactly xyz components", {**voxel_grid_encoding, "dimensions_xyz": [10, 20]}, False),
        ("voxel dimensions are positive", {**voxel_grid_encoding, "dimensions_xyz": [10, 0, 30]}, False),
        ("voxel dimensions are bounded", {**voxel_grid_encoding, "dimensions_xyz": [10, 20, 16385]}, False),
        ("voxel NPY shape order is z-y-x", {**voxel_grid_encoding, "array_shape_order": "x_y_z"}, False),
        ("voxel memory order is C contiguous", {**voxel_grid_encoding, "memory_order": "fortran_contiguous"}, False),
        ("voxel dtype is uint8", {**voxel_grid_encoding, "dtype": "float32"}, False),
        ("voxel empty value is zero", {**voxel_grid_encoding, "empty_value": 255}, False),
        ("voxel occupied value is one", {**voxel_grid_encoding, "occupied_value": 255}, False),
        ("voxel centers use index-plus-half", {**voxel_grid_encoding, "voxel_center_convention": "integer_corner"}, False),
    )
    for label, instance, expected_valid in voxel_cases:
        if schema_probe_valid(instance, voxel_schema, edit_artifacts) is not expected_valid:
            errors.append(f"edit-artifacts.schema.json: voxel-grid encoding probe failed: {label}")

    planar_mapping = {
        "kind": "planar_polygon_uv_v1",
        "coordinate_convention": "RR-COORD-1",
        "world_from_surface": copy.deepcopy(identity_matrix),
        "surface_plane": "local_xy_z_zero_meters",
        "polygon_rule": "convex_counter_clockwise_positive_z_triangle_fan_vertex_0",
        "texture_uv_convention": "normalized_top_left_u_right_v_down",
        "vertices": [
            {"surface_xy_m": [0.0, 0.0], "texture_uv": [0.0, 1.0]},
            {"surface_xy_m": [1.0, 0.0], "texture_uv": [1.0, 1.0]},
            {"surface_xy_m": [0.0, 1.0], "texture_uv": [0.0, 0.0]},
        ],
    }
    planar_schema = edit_defs.get("planarRevealMapping", {})
    planar_cases = (
        ("planar reveal mapping baseline accepted", planar_mapping, True),
        ("planar reveal mapping requires a transform", {key: value for key, value in planar_mapping.items() if key != "world_from_surface"}, False),
        ("planar reveal mapping uses RR-COORD-1", {**planar_mapping, "coordinate_convention": "texture_space"}, False),
        ("planar reveal mapping is on local z zero", {**planar_mapping, "surface_plane": "local_xz_y_zero"}, False),
        ("planar reveal polygon rule is closed", {**planar_mapping, "polygon_rule": "arbitrary_mesh"}, False),
        ("planar reveal UV convention is closed", {**planar_mapping, "texture_uv_convention": "bottom_left"}, False),
        ("planar reveal requires at least three vertices", {**planar_mapping, "vertices": planar_mapping["vertices"][:2]}, False),
        (
            "planar reveal UVs remain normalized",
            {
                **planar_mapping,
                "vertices": [
                    *planar_mapping["vertices"][:2],
                    {"surface_xy_m": [0.0, 1.0], "texture_uv": [0.0, 1.01]},
                ],
            },
            False,
        ),
    )
    for label, instance, expected_valid in planar_cases:
        if schema_probe_valid(instance, planar_schema, edit_artifacts) is not expected_valid:
            errors.append(f"edit-artifacts.schema.json: planar-reveal mapping probe failed: {label}")

    visual_mask = {
        **artifact_base("mask_volume"),
        "object_id": identifier("object"),
        "representation": "visual_hull_mesh",
        "payload": payload("glb2", "mask-mesh"),
        "spatial_encoding": copy.deepcopy(world_mesh_encoding),
        "source_frame_ids": [identifier("frame")],
        "conservative_margin_m": 0.01,
    }
    voxel_mask = {
        **artifact_base("mask_volume"),
        "object_id": identifier("object"),
        "representation": "sparse_voxel_occupancy",
        "payload": payload("npy_1_0", "mask-voxel"),
        "spatial_encoding": copy.deepcopy(voxel_grid_encoding),
        "source_frame_ids": [identifier("frame")],
        "conservative_margin_m": 0.01,
    }
    mask_schema = edit_defs.get("maskVolume", {})
    for label, instance, expected_valid in (
        ("visual-hull mask baseline accepted", visual_mask, True),
        ("voxel mask baseline accepted", voxel_mask, True),
        ("visual-hull mask rejects NPY", {**visual_mask, "payload": payload("npy_1_0")}, False),
        ("visual-hull mask rejects voxel encoding", {**visual_mask, "spatial_encoding": copy.deepcopy(voxel_grid_encoding)}, False),
        ("voxel mask rejects GLB", {**voxel_mask, "payload": payload("glb2")}, False),
        ("voxel mask rejects mesh encoding", {**voxel_mask, "spatial_encoding": copy.deepcopy(world_mesh_encoding)}, False),
        ("mask requires spatial encoding", {key: value for key, value in visual_mask.items() if key != "spatial_encoding"}, False),
    ):
        if schema_probe_valid(instance, mask_schema, edit_artifacts) is not expected_valid:
            errors.append(f"edit-artifacts.schema.json: mask-volume probe failed: {label}")

    surface_mesh = {
        **artifact_base("surface_mesh"),
        "owner_id": identifier("surface"),
        "payload": payload("ply_binary_little_endian_1_0", "surface"),
        "spatial_encoding": copy.deepcopy(world_mesh_encoding),
        "metric_scale_verified": True,
    }
    occluder_chunk = {
        **artifact_base("occluder_chunk"),
        "canonical_owner_ids": [identifier("object")],
        "payload": payload("glb2", "occluder"),
        "spatial_encoding": copy.deepcopy(world_mesh_encoding),
        "coverage_envelope_id": identifier("envelope"),
    }
    for label, definition_name, instance in (
        ("surface-mesh", "surfaceMesh", surface_mesh),
        ("occluder-chunk", "occluderChunk", occluder_chunk),
    ):
        definition = edit_defs.get(definition_name, {})
        if not schema_probe_valid(instance, definition, edit_artifacts):
            errors.append(f"edit-artifacts.schema.json: {label} spatial baseline probe is invalid")
        missing_spatial = {key: value for key, value in instance.items() if key != "spatial_encoding"}
        if schema_probe_valid(missing_spatial, definition, edit_artifacts):
            errors.append(f"edit-artifacts.schema.json: {label} accepts missing spatial encoding")
        wrong_codec = {**instance, "payload": payload("png", f"{label}-bad")}
        if schema_probe_valid(wrong_codec, definition, edit_artifacts):
            errors.append(f"edit-artifacts.schema.json: {label} accepts an image payload codec")

    reveal_layer = {
        "layer_id": identifier("layer"),
        "surface_id": identifier("surface"),
        "provenance": "observed_atlas",
        "payload": payload("png", "reveal"),
        "mapping": copy.deepcopy(planar_mapping),
        "observed_coverage": 0.99,
        "confidence": 0.99,
    }
    reveal_layer_schema = edit_defs.get("revealLayer", {})
    if not schema_probe_valid(reveal_layer, reveal_layer_schema, edit_artifacts):
        errors.append("edit-artifacts.schema.json: reveal-layer mapping baseline probe is invalid")
    missing_mapping = {key: value for key, value in reveal_layer.items() if key != "mapping"}
    if schema_probe_valid(missing_mapping, reveal_layer_schema, edit_artifacts):
        errors.append("edit-artifacts.schema.json: reveal layer accepts missing surface-to-texture mapping")
    wrong_reveal_codec = {**reveal_layer, "payload": payload("glb2", "reveal-bad")}
    if schema_probe_valid(wrong_reveal_codec, reveal_layer_schema, edit_artifacts):
        errors.append("edit-artifacts.schema.json: reveal layer accepts a mesh payload codec")

    reveal_bundle = {
        **artifact_base("reveal_bundle"),
        "object_id": identifier("object"),
        "layers": [copy.deepcopy(reveal_layer)],
        "supported_view_envelope": {
            "envelope_id": identifier("envelope"),
            "sampled_camera_poses": [copy.deepcopy(identity_matrix)],
            "containment_rule": "nearest_pose_translation_rotation_bounds",
            "max_translation_m": 0.5,
            "max_rotation_deg": 30.0,
        },
        "foreground_occluder_artifact_ids": [],
        "quality": {
            "gate_id": "GATE-006",
            "gate_revision": "1.0.0",
            "fixture_id": "probe",
            "metric_version": "1",
            "evidence_record_sha256": "e" * 64,
            "coverage_p10": 0.95,
            "coverage_median": 0.98,
            "largest_uncovered_component_fraction": 0.01,
            "synthesized_fraction": 0.1,
            "foreground_overwrite_fraction": 0.0,
            "severe_foreground_overwrite": False,
            "seam_severity": "minor",
            "severe_surface_order_artifact": False,
            "human_visual_votes_pass": 4,
            "human_visual_votes_total": 5,
        },
    }

    asset_manifest = {
        **artifact_base("asset_manifest"),
        "asset_id": identifier("asset"),
        "display_name": "Probe asset",
        "canonical_dimensions_m": [1.0, 2.0, 1.0],
        "visual_bounds_m": {"minimum": [-0.5, 0.0, -0.5], "maximum": [0.5, 2.0, 0.5]},
        "origin_convention": "floor_center_y_up",
        "forward_axis": "minus_z",
        "source": {
            "source_url": "https://example.invalid/asset",
            "source_revision": "1",
            "source_sha256": "f" * 64,
            "author": "Probe",
        },
        "license": {
            "spdx_or_terms": "CC0-1.0",
            "terms_revision": "1",
            "source_url": "https://example.invalid/license",
            "use_approved": True,
            "redistribution_allowed": True,
            "attribution_required": True,
            "attribution": "Probe author",
            "approval_evidence_sha256": "1" * 64,
        },
        "texture_budget": {
            "max_dimension_px": 2048,
            "max_total_bytes": 1_000_000,
            "allowed_formats": ["png"],
        },
        "delivery": {
            "state": "bundled_local",
            "network_required_at_edit_time": False,
            "native_verified": True,
            "web_verified": True,
        },
        "usdz": payload("usdz", "asset-usdz"),
        "glb": payload("glb2", "asset-glb"),
        "collision": payload("glb2", "asset-collision"),
        "lods": [payload("glb2", "asset-lod")],
        "validation_evidence_sha256": "2" * 64,
    }

    world_correction = {
        **artifact_base("world_frame_correction"),
        "from_world_frame_version": 1,
        "to_world_frame_version": 2,
        "transform_status": "validated",
        "to_from_from_transform": copy.deepcopy(identity_matrix),
        "reason": "relocalization",
    }

    def edit_artifact_semantically_valid(instance: dict[str, Any]) -> bool:
        if not schema_probe_valid(instance, edit_artifacts, edit_artifacts):
            return False
        artifact_type = instance.get("artifact_type")
        if artifact_type == "reveal_bundle":
            quality = instance.get("quality", {})
            p10 = quality.get("coverage_p10")
            median = quality.get("coverage_median")
            if not isinstance(p10, (int, float)) or isinstance(p10, bool):
                return False
            if not isinstance(median, (int, float)) or isinstance(median, bool) or p10 > median:
                return False
        elif artifact_type == "asset_manifest":
            bounds = instance.get("visual_bounds_m", {})
            minimum = bounds.get("minimum")
            maximum = bounds.get("maximum")
            if not isinstance(minimum, list) or not isinstance(maximum, list) or len(minimum) != 3 or len(maximum) != 3:
                return False
            if any(lower >= upper for lower, upper in zip(minimum, maximum)):
                return False
        elif artifact_type == "world_frame_correction":
            source_version = instance.get("from_world_frame_version")
            destination_version = instance.get("to_world_frame_version")
            world_version = instance.get("world_frame_version")
            if not all(type(value) is int for value in (source_version, destination_version, world_version)):
                return False
            if source_version >= destination_version or destination_version != world_version:
                return False
        return True

    if not edit_artifact_semantically_valid(reveal_bundle):
        errors.append("edit-artifacts.schema.json: ready reveal-bundle baseline probe is invalid")
    for quality_field, bad_value in (
        ("coverage_p10", 0.949),
        ("coverage_median", 0.979),
        ("largest_uncovered_component_fraction", 0.011),
        ("severe_foreground_overwrite", True),
        ("seam_severity", "severe"),
        ("severe_surface_order_artifact", True),
        ("human_visual_votes_pass", 3),
    ):
        below_gate = copy.deepcopy(reveal_bundle)
        below_gate["quality"][quality_field] = bad_value
        if edit_artifact_semantically_valid(below_gate):
            errors.append(f"edit-artifacts.schema.json: ready reveal bundle accepts gate failure {quality_field}")
    reversed_distribution = copy.deepcopy(reveal_bundle)
    reversed_distribution["quality"]["coverage_p10"] = 0.99
    reversed_distribution["quality"]["coverage_median"] = 0.98
    if edit_artifact_semantically_valid(reversed_distribution):
        errors.append("edit-artifacts.schema.json: reveal quality accepts coverage_p10 greater than coverage_median")

    asset_schema = edit_defs.get("assetManifest", {})
    if not edit_artifact_semantically_valid(asset_manifest):
        errors.append("edit-artifacts.schema.json: ready asset-manifest baseline probe is invalid")
    asset_cases = (
        ("ready asset rejects unapproved redistribution", ("license", "redistribution_allowed"), False),
        ("required attribution cannot be empty", ("license", "attribution"), ""),
        ("USDZ payload requires usdz codec", ("usdz", "codec"), "glb2"),
        ("GLB payload requires glb2 codec", ("glb", "codec"), "usdz"),
        ("collision payload rejects image codec", ("collision", "codec"), "png"),
        ("LOD payload rejects image codec", ("lods", 0, "codec"), "png"),
    )
    for label, field_path, bad_value in asset_cases:
        invalid_asset = copy.deepcopy(asset_manifest)
        target: Any = invalid_asset
        for segment in field_path[:-1]:
            target = target[segment]
        target[field_path[-1]] = bad_value
        if schema_probe_valid(invalid_asset, asset_schema, edit_artifacts):
            errors.append(f"edit-artifacts.schema.json: asset probe failed: {label}")
    unnecessary_attribution = copy.deepcopy(asset_manifest)
    unnecessary_attribution["license"]["attribution_required"] = False
    if schema_probe_valid(unnecessary_attribution, asset_schema, edit_artifacts):
        errors.append("edit-artifacts.schema.json: attribution text is accepted when attribution is not required")
    invalid_bounds = copy.deepcopy(asset_manifest)
    invalid_bounds["visual_bounds_m"]["minimum"][0] = invalid_bounds["visual_bounds_m"]["maximum"][0]
    if edit_artifact_semantically_valid(invalid_bounds):
        errors.append("edit-artifacts.schema.json: asset visual bounds accept an axis with minimum >= maximum")

    if not edit_artifact_semantically_valid(world_correction):
        errors.append("edit-artifacts.schema.json: world-frame correction baseline probe is invalid")
    reversed_correction = copy.deepcopy(world_correction)
    reversed_correction["from_world_frame_version"] = 2
    if edit_artifact_semantically_valid(reversed_correction):
        errors.append("edit-artifacts.schema.json: world-frame correction accepts from >= to")
    mismatched_correction = copy.deepcopy(world_correction)
    mismatched_correction["to_world_frame_version"] = 3
    if edit_artifact_semantically_valid(mismatched_correction):
        errors.append("edit-artifacts.schema.json: correction destination can disagree with base world-frame version")

    scene_state = schemas.get("scene-state.schema.json", {})
    scene_defs = scene_state.get("$defs", {})
    readiness_reason_codes = {
        "tracking_not_normal", "target_ambiguous", "target_lost", "support_missing",
        "collision_check_failed", "room_boundary_unknown", "walkway_unknown", "artifact_missing",
        "artifact_not_ready", "reveal_quality_failed", "outside_view_envelope",
        "asset_integrity_failed", "asset_license_failed", "local_durability_failed", "authority_conflict",
        "no_eligible_restore", "provider_unavailable", "unsupported_target_category", "world_frame_mismatch",
    }
    observed_reason_codes = set(
        scene_defs.get("readinessReason", {}).get("properties", {}).get("code", {}).get("enum", [])
    )
    if observed_reason_codes != readiness_reason_codes:
        errors.append(
            "scene-state.schema.json: readiness reason registry mismatch "
            f"missing={sorted(readiness_reason_codes-observed_reason_codes)} "
            f"extra={sorted(observed_reason_codes-readiness_reason_codes)}"
        )
    capability_names = ("select", "place", "replace", "remove", "restore")
    scene_object = {
        "object_id": identifier("object"),
        "label": "chair",
        "label_confidence": 0.9,
        "lifecycle": "tracked",
        "readiness": {capability: "ready" for capability in capability_names},
        "readiness_reasons": {capability: [] for capability in capability_names},
        "artifact_refs": [],
        "edit_state": {"visible": True, "active_reveal": None},
        "created_scene_revision": 0,
        "last_observed_frame_id": identifier("frame"),
    }
    object_schema = scene_defs.get("object", {})
    if not schema_probe_valid(scene_object, object_schema, scene_state):
        errors.append("scene-state.schema.json: all-ready object baseline probe is invalid")
    for capability in capability_names:
        ready_with_blocker = copy.deepcopy(scene_object)
        ready_with_blocker["readiness_reasons"][capability] = [
            {"code": "artifact_not_ready", "message": "probe blocker"}
        ]
        if schema_probe_valid(ready_with_blocker, object_schema, scene_state):
            errors.append(f"scene-state.schema.json: ready {capability} accepts a blocker")
        for nonready_state in ("unavailable", "warming", "degraded", "failed"):
            nonready_without_blocker = copy.deepcopy(scene_object)
            nonready_without_blocker["readiness"][capability] = nonready_state
            if schema_probe_valid(nonready_without_blocker, object_schema, scene_state):
                errors.append(
                    f"scene-state.schema.json: {nonready_state} {capability} accepts an empty blocker list"
                )
            nonready_with_blocker = copy.deepcopy(nonready_without_blocker)
            nonready_with_blocker["readiness_reasons"][capability] = [
                {"code": "artifact_not_ready", "message": "probe blocker"}
            ]
            if not schema_probe_valid(nonready_with_blocker, object_schema, scene_state):
                errors.append(
                    f"scene-state.schema.json: {nonready_state} {capability} rejects an explicit blocker"
                )
    unknown_blocker = copy.deepcopy(scene_object)
    unknown_blocker["readiness"]["replace"] = "failed"
    unknown_blocker["readiness_reasons"]["replace"] = [
        {"code": "model_says_no", "message": "unregistered reason"}
    ]
    if schema_probe_valid(unknown_blocker, object_schema, scene_state):
        errors.append("scene-state.schema.json: readiness accepts an unregistered blocker code")
    active_reveal = {
        "artifact_id": identifier("artifact"),
        "artifact_type": "reveal_bundle",
        "artifact_revision": 1,
        "sha256": "3" * 64,
    }
    hidden_with_reveal = copy.deepcopy(scene_object)
    hidden_with_reveal["edit_state"] = {"visible": False, "active_reveal": active_reveal}
    if not schema_probe_valid(hidden_with_reveal, object_schema, scene_state):
        errors.append("scene-state.schema.json: hidden object with active reveal baseline is invalid")
    visible_with_reveal = copy.deepcopy(hidden_with_reveal)
    visible_with_reveal["edit_state"]["visible"] = True
    if schema_probe_valid(visible_with_reveal, object_schema, scene_state):
        errors.append("scene-state.schema.json: visible object accepts an active reveal")

    transaction = schemas.get("transaction.schema.json", {})
    tx_defs = transaction.get("$defs", {})
    tx_required = set(transaction.get("required", []))
    fingerprint_required = {
        "request_fingerprint_algorithm", "request_fingerprint_scope", "request_fingerprint_sha256", "revision_authority",
    }
    if not fingerprint_required.issubset(tx_required):
        errors.append(f"transaction.schema.json: required fingerprint/authority fields missing {sorted(fingerprint_required - tx_required)}")
    tx_properties = transaction.get("properties", {})
    if transaction.get("additionalProperties") is not False:
        errors.append("transaction.schema.json: top-level transaction must reject arbitrary properties")
    if tx_properties.get("request_fingerprint_algorithm", {}).get("const") != "RR-JCS-SHA256-1":
        errors.append("transaction.schema.json: request fingerprint algorithm is not pinned")
    if tx_properties.get("request_fingerprint_scope", {}).get("const") != "schema_version_session_id_revision_authority_base_scene_revision_target_context_intent_proposed_operations":
        errors.append("transaction.schema.json: request fingerprint field scope is not exact")
    if tx_properties.get("proposed_operations", {}).get("minItems", 0) < 1:
        errors.append("transaction.schema.json: proposed_operations must be non-empty")

    intent = tx_defs.get("intent", {})
    public_operations = {"place", "replace", "remove", "restore"}
    if intent.get("additionalProperties") is not False:
        errors.append("transaction.schema.json: intent must reject arbitrary fields")
    if set(intent.get("properties", {}).get("operation", {}).get("enum", [])) != public_operations:
        errors.append("transaction.schema.json: intent operation set is not exactly place/replace/remove/restore")
    try:
        intent_variants = intent["allOf"][0]["oneOf"]
    except (KeyError, IndexError, TypeError):
        intent_variants = []
    intent_map = {
        variant.get("properties", {}).get("operation", {}).get("const"): variant.get("properties", {}).get("arguments", {}).get("$ref")
        for variant in intent_variants
    }
    expected_intent_map = {
        "place": "#/$defs/assetIntentArguments",
        "replace": "#/$defs/assetIntentArguments",
        "remove": "#/$defs/emptyIntentArguments",
        "restore": "#/$defs/emptyIntentArguments",
    }
    if intent_map != expected_intent_map:
        errors.append(f"transaction.schema.json: operation-specific intent arguments are not closed/discriminated: {intent_map}")
    for definition in ("assetIntentArguments", "emptyIntentArguments"):
        if tx_defs.get(definition, {}).get("additionalProperties") is not False:
            errors.append(f"transaction.schema.json: {definition} must reject arbitrary fields")

    sample_asset_id = "asset_123e4567-e89b-42d3-a456-426614174000"
    intent_cases = (
        ("place accepts typed asset args", {"operation": "place", "source": "typed", "arguments": {"asset_id": sample_asset_id}, "constraints": []}, True),
        ("remove accepts empty args", {"operation": "remove", "source": "tap", "arguments": {}, "constraints": []}, True),
        ("unknown public operation rejected", {"operation": "delete", "source": "typed", "arguments": {}, "constraints": []}, False),
        ("place rejects empty args", {"operation": "place", "source": "typed", "arguments": {}, "constraints": []}, False),
        ("remove rejects asset args", {"operation": "remove", "source": "tap", "arguments": {"asset_id": sample_asset_id}, "constraints": []}, False),
        ("intent rejects arbitrary target field", {"operation": "remove", "source": "tap", "arguments": {}, "constraints": [], "target_id": "object"}, False),
    )
    for label, instance, expected_valid in intent_cases:
        if schema_probe_valid(instance, intent, transaction) is not expected_valid:
            errors.append(f"transaction.schema.json: intent probe failed: {label}")

    internal = tx_defs.get("operation", {}).get("oneOf", [])
    expected_internal = {
        "create_asset_instance", "set_asset_transform", "set_object_visibility", "set_reveal_bundle", "restore_snapshot",
    }
    internal_kinds = {variant.get("properties", {}).get("kind", {}).get("const") for variant in internal}
    if internal_kinds != expected_internal:
        errors.append(f"transaction.schema.json: internal operation variants changed: {sorted(internal_kinds, key=str)}")
    required_operation_fields = {"kind", "entity_id", "before", "after"}
    for variant in internal:
        kind = variant.get("properties", {}).get("kind", {}).get("const", "unknown")
        if variant.get("additionalProperties") is not False:
            errors.append(f"transaction.schema.json: internal operation {kind} is not closed")
        if not required_operation_fields.issubset(set(variant.get("required", []))):
            errors.append(f"transaction.schema.json: internal operation {kind} lacks typed before/after/entity fields")

    visibility_operation = {
        "kind": "set_object_visibility",
        "entity_id": "object_123e4567-e89b-42d3-a456-426614174000",
        "before": {"visible": True},
        "after": {"visible": False},
    }
    operation_cases = (
        ("typed visibility operation accepted", visibility_operation, True),
        ("unknown internal operation rejected", {**visibility_operation, "kind": "delete_entity"}, False),
        ("wrong entity identity rejected", {**visibility_operation, "entity_id": sample_asset_id}, False),
        ("arbitrary operation field rejected", {**visibility_operation, "target_index": 0}, False),
        ("untyped before snapshot rejected", {**visibility_operation, "before": True}, False),
    )
    operation_schema = tx_defs.get("operation", {})
    for label, instance, expected_valid in operation_cases:
        if schema_probe_valid(instance, operation_schema, transaction) is not expected_valid:
            errors.append(f"transaction.schema.json: internal-operation probe failed: {label}")

    authorities = tx_defs.get("revisionAuthority", {}).get("oneOf", [])
    authority_kinds = {variant.get("properties", {}).get("kind", {}).get("const") for variant in authorities}
    if authority_kinds != {"native_device", "replay_gateway"} or any(variant.get("additionalProperties") is not False for variant in authorities):
        errors.append("transaction.schema.json: revision authority must be closed native_device/replay_gateway variants")

    lifecycle_rules = transaction.get("allOf", [])
    committed = next((rule for rule in lifecycle_rules if rule.get("if", {}).get("properties", {}).get("canonical_state", {}).get("const") == "committed"), None)
    if not committed:
        errors.append("transaction.schema.json: committed lifecycle conditional is missing")
    else:
        then = committed.get("then", {})
        required = set(then.get("required", []))
        expected = {"preview", "commit", "inverse_operations", "local_undo_token"}
        if not expected.issubset(required):
            errors.append(f"transaction.schema.json: committed state can omit {sorted(expected - required)}")
        then_properties = then.get("properties", {})
        validation_state = then_properties.get("validation", {}).get("properties", {}).get("state", {}).get("const")
        if validation_state != "passed":
            errors.append("transaction.schema.json: committed state does not require passed validation")
        if then_properties.get("inverse_operations", {}).get("minItems", 0) < 1:
            errors.append("transaction.schema.json: committed state can omit a compensating inverse")
        if then_properties.get("local_undo_token", {}).get("type") != "string":
            errors.append("transaction.schema.json: committed state can use a null undo token")
    restore = next((rule for rule in lifecycle_rules if rule.get("if", {}).get("properties", {}).get("intent", {}).get("properties", {}).get("operation", {}).get("const") == "restore"), None)
    if not restore or "compensates_transaction_id" not in restore.get("then", {}).get("required", []):
        errors.append("transaction.schema.json: restore can omit compensates_transaction_id")
    previewed = next((rule for rule in lifecycle_rules if rule.get("if", {}).get("properties", {}).get("canonical_state", {}).get("const") == "previewed"), None)
    if not previewed or "preview" not in previewed.get("then", {}).get("required", []):
        errors.append("transaction.schema.json: previewed state can omit preview evidence")
    passed_states = next((rule for rule in lifecycle_rules if set(rule.get("if", {}).get("properties", {}).get("canonical_state", {}).get("enum", [])) == {"validated", "previewed", "committed"}), None)
    passed_const = (passed_states or {}).get("then", {}).get("properties", {}).get("validation", {}).get("properties", {}).get("state", {}).get("const")
    if passed_const != "passed":
        errors.append("transaction.schema.json: validated/previewed/committed states can carry failed validation")

    validation_properties = tx_defs.get("validation", {}).get("properties", {})
    if validation_properties.get("input_sha256_algorithm", {}).get("const") != "RR-JCS-SHA256-1":
        errors.append("transaction.schema.json: validation input digest algorithm is not pinned")
    validation_schema = tx_defs.get("validation", {})
    expected_check_ids = {
        "scene_revision", "target_exists", "capability_ready", "support", "collision_proxy",
        "room_boundary_proxy", "walkway_proxy", "asset_license", "artifact_integrity",
        "view_envelope", "snapshot_integrity", "compensation_eligibility",
    }
    observed_check_ids = set(
        validation_properties.get("checks", {}).get("items", {}).get("properties", {}).get("check_id", {}).get("enum", [])
    )
    if observed_check_ids != expected_check_ids:
        errors.append(
            f"transaction.schema.json: validation check ID registry mismatch missing={sorted(expected_check_ids-observed_check_ids)} "
            f"extra={sorted(observed_check_ids-expected_check_ids)}"
        )

    def validation_probe(state: str, results: list[str]) -> dict[str, Any]:
        return {
            "state": state,
            "checks": [
                {
                    "check_id": "scene_revision",
                    "result": result,
                    "measured": None,
                    "threshold": None,
                }
                for result in results
            ],
            "validator_version": "probe-1",
            "input_sha256_algorithm": "RR-JCS-SHA256-1",
            "input_sha256_scope": "request_fingerprint_object_plus_validation_checks_without_validation_results",
            "input_sha256": "0" * 64,
        }

    validation_cases = (
        ("not_run permits zero checks", validation_probe("not_run", []), True),
        ("not_run rejects completed checks", validation_probe("not_run", ["pass"]), False),
        ("passed rejects zero checks", validation_probe("passed", []), False),
        ("passed accepts pass", validation_probe("passed", ["pass"]), True),
        ("passed accepts not_applicable", validation_probe("passed", ["not_applicable"]), True),
        ("passed rejects fail", validation_probe("passed", ["fail"]), False),
        ("failed rejects zero checks", validation_probe("failed", []), False),
        ("failed rejects all-pass checks", validation_probe("failed", ["pass"]), False),
        ("failed accepts a failing check", validation_probe("failed", ["fail"]), True),
    )
    for label, instance, expected_valid in validation_cases:
        actual_valid = schema_probe_valid(instance, validation_schema, transaction)
        if actual_valid is not expected_valid:
            errors.append(f"transaction.schema.json: validation-state probe failed: {label}")

    def artifact_reference(artifact_type: str) -> dict[str, Any]:
        return {
            "artifact_id": identifier("artifact"),
            "artifact_type": artifact_type,
            "artifact_revision": 1,
            "sha256": "1" * 64,
        }

    asset_snapshot = {
        "asset_id": identifier("asset"),
        "manifest_artifact_ref": artifact_reference("asset_manifest"),
        "world_from_asset": copy.deepcopy(identity_matrix),
        "support_relation": {
            "relation_id": identifier("support"),
            "surface_id": identifier("surface"),
            "confidence": 0.99,
            "method": "proxy_contact",
        },
    }
    create_asset_operation = {
        "kind": "create_asset_instance",
        "entity_id": identifier("assetinst"),
        "before": None,
        "after": asset_snapshot,
        "required_artifact_refs": [artifact_reference("asset_manifest")],
    }
    reveal_snapshot = {
        "artifact_id": identifier("artifact"),
        "artifact_type": "reveal_bundle",
        "artifact_revision": 1,
        "sha256": "1" * 64,
    }
    reveal_operation = {
        "kind": "set_reveal_bundle",
        "entity_id": identifier("object"),
        "before": None,
        "after": reveal_snapshot,
        "required_artifact_refs": [artifact_reference("reveal_bundle")],
    }

    projection_matrix = {
        **copy.deepcopy(identity_matrix),
        "values": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
    }

    def projection_content(
        *,
        visible: bool,
        active_reveal: dict[str, Any] | None,
        with_asset: bool,
        include_new_object: bool = False,
        source_transaction_id: str | None = None,
    ) -> dict[str, Any]:
        placed_assets: list[dict[str, Any]] = []
        support_relations: list[dict[str, Any]] = []
        if with_asset:
            placed_assets.append(
                {
                    "placed_asset_id": identifier("assetinst"),
                    "asset_id": identifier("asset"),
                    "manifest_artifact_ref": artifact_reference("asset_manifest"),
                    "world_from_asset": copy.deepcopy(projection_matrix),
                    "state": "committed",
                    "support_relation_id": identifier("support"),
                    "source_transaction_id": source_transaction_id or identifier("tx"),
                }
            )
            support_relations.append(
                {
                    "relation_id": identifier("support"),
                    "subject_id": identifier("assetinst"),
                    "surface_id": identifier("surface"),
                    "confidence": 0.99,
                    "method": "proxy_contact",
                }
            )
        object_edit_states = [
            {
                "object_id": identifier("object"),
                "visible": visible,
                "active_reveal": copy.deepcopy(active_reveal),
            }
        ]
        if include_new_object:
            object_edit_states.append(
                {
                    "object_id": other_identifier("object"),
                    "visible": True,
                    "active_reveal": None,
                }
            )
        return {
            "projection_version": "RR-EDIT-PROJECTION-1",
            "scene_id": identifier("scene"),
            "revision_branch_id": identifier("branch"),
            "world_frame_id": identifier("world"),
            "world_frame_version": 1,
            "object_edit_states": object_edit_states,
            "placed_assets": placed_assets,
            "asset_support_relations": support_relations,
        }

    def projection_snapshot(
        captured_scene_revision: int,
        projection: dict[str, Any],
        *,
        projection_origin: str = "captured_exact",
        derivation: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        import hashlib

        canonical_probe_bytes = json.dumps(
            projection, ensure_ascii=False, separators=(",", ":"), sort_keys=True
        ).encode("utf-8")
        return {
            "captured_scene_revision": captured_scene_revision,
            "projection_origin": projection_origin,
            "derivation": copy.deepcopy(derivation),
            "projection_sha256_algorithm": "RR-JCS-SHA256-1",
            "projection_sha256_scope": "entire_rr_edit_projection_1",
            "projection_sha256": hashlib.sha256(canonical_probe_bytes).hexdigest(),
            "projection": copy.deepcopy(projection),
        }

    source_remove_before = projection_snapshot(
        1,
        projection_content(
            visible=False, active_reveal=reveal_snapshot, with_asset=False
        ),
    )
    source_remove_after = projection_snapshot(
        0, projection_content(visible=True, active_reveal=None, with_asset=False)
    )
    source_place_before = projection_snapshot(
        1,
        projection_content(
            visible=True,
            active_reveal=None,
            with_asset=True,
            source_transaction_id=third_identifier("tx"),
        ),
    )
    source_place_after = projection_snapshot(
        0, projection_content(visible=True, active_reveal=None, with_asset=False)
    )
    probe_source_inverse_records = {
        other_identifier("tx"): {
            "before": source_remove_before,
            "after": source_remove_after,
            "ordered_touched": {
                "touched_object_ids": [identifier("object")],
                "touched_placed_asset_ids": [],
                "touched_asset_support_relation_ids": [],
            },
        },
        third_identifier("tx"): {
            "before": source_place_before,
            "after": source_place_after,
            "ordered_touched": {
                "touched_object_ids": [],
                "touched_placed_asset_ids": [identifier("assetinst")],
                "touched_asset_support_relation_ids": [identifier("support")],
            },
        },
    }

    def restore_operation(
        before: dict[str, Any], after: dict[str, Any]
    ) -> dict[str, Any]:
        required_artifact_refs: list[dict[str, Any]] = []
        projection = after.get("projection", {})
        for object_state in projection.get("object_edit_states", []):
            active_reveal = object_state.get("active_reveal")
            if isinstance(active_reveal, dict):
                required_artifact_refs.append(copy.deepcopy(active_reveal))
        for placed_asset in projection.get("placed_assets", []):
            required_artifact_refs.append(copy.deepcopy(placed_asset["manifest_artifact_ref"]))
        return {
            "kind": "restore_snapshot",
            "entity_id": identifier("scene"),
            "before": copy.deepcopy(before),
            "after": copy.deepcopy(after),
            "required_artifact_refs": required_artifact_refs,
        }

    def committed_transaction(
        operation: str,
        check_ids: set[str],
        *,
        replace_with_reveal: bool = False,
        restore_source: str = "remove",
    ) -> dict[str, Any]:
        base_revision = 2 if operation == "restore" else 0
        committed_revision = base_revision + 1
        pre_projection = projection_content(visible=True, active_reveal=None, with_asset=False)
        restore_source_transaction_id: str | None = None
        if operation == "place":
            proposed = [copy.deepcopy(create_asset_operation)]
            post_projection = projection_content(visible=True, active_reveal=None, with_asset=True)
        elif operation == "replace":
            proposed = [copy.deepcopy(visibility_operation), copy.deepcopy(create_asset_operation)]
            if replace_with_reveal:
                proposed.insert(0, copy.deepcopy(reveal_operation))
            post_projection = projection_content(
                visible=False,
                active_reveal=reveal_snapshot if replace_with_reveal else None,
                with_asset=True,
            )
        elif operation == "remove":
            proposed = [copy.deepcopy(reveal_operation), copy.deepcopy(visibility_operation)]
            post_projection = projection_content(
                visible=False, active_reveal=reveal_snapshot, with_asset=False
            )
        elif operation == "restore":
            if restore_source == "remove":
                restore_source_transaction_id = other_identifier("tx")
                current_projection = projection_content(
                    visible=False,
                    active_reveal=reveal_snapshot,
                    with_asset=False,
                    include_new_object=True,
                )
                historical_projection = projection_content(
                    visible=True,
                    active_reveal=None,
                    with_asset=False,
                    include_new_object=True,
                )
            elif restore_source == "place":
                restore_source_transaction_id = third_identifier("tx")
                current_projection = projection_content(
                    visible=True,
                    active_reveal=None,
                    with_asset=True,
                    include_new_object=True,
                    source_transaction_id=restore_source_transaction_id,
                )
                historical_projection = projection_content(
                    visible=True,
                    active_reveal=None,
                    with_asset=False,
                    include_new_object=True,
                )
            else:
                raise ValueError(f"unsupported restore source {restore_source}")
            source_inverse = probe_source_inverse_records[restore_source_transaction_id]
            ordered_touched = source_inverse["ordered_touched"]
            derivation = {
                "rule": "RR-RESTORE-REBASE-1",
                "source_transaction_id": restore_source_transaction_id,
                "source_inverse_before_projection_sha256": source_inverse["before"]["projection_sha256"],
                "source_inverse_after_projection_sha256": source_inverse["after"]["projection_sha256"],
                **copy.deepcopy(ordered_touched),
            }
            proposed = [
                restore_operation(
                    projection_snapshot(base_revision, current_projection),
                    projection_snapshot(
                        base_revision,
                        historical_projection,
                        projection_origin="restore_rebase",
                        derivation=derivation,
                    ),
                )
            ]
            post_projection = historical_projection
        else:
            raise ValueError(f"unsupported probe operation {operation}")
        if operation == "restore":
            inverse = restore_operation(
                projection_snapshot(committed_revision, post_projection),
                projection_snapshot(base_revision, current_projection),
            )
        else:
            inverse = restore_operation(
                projection_snapshot(committed_revision, post_projection),
                projection_snapshot(base_revision, pre_projection),
            )
        intent_arguments = {"asset_id": identifier("asset")} if operation in {"place", "replace"} else {}
        selected_object_id = identifier("object") if operation in {"replace", "remove"} else None
        preview_id = identifier("preview")
        operation_validation = validation_probe("passed", ["pass"] * len(check_ids))
        for check, check_id in zip(operation_validation["checks"], sorted(check_ids)):
            check["check_id"] = check_id
        result = {
            "schema_version": "1.0.0",
            "transaction_id": identifier("tx"),
            "idempotency_key": identifier("txidem"),
            "request_fingerprint_algorithm": "RR-JCS-SHA256-1",
            "request_fingerprint_scope": "schema_version_session_id_revision_authority_base_scene_revision_target_context_intent_proposed_operations",
            "request_fingerprint_sha256": "5" * 64,
            "session_id": identifier("session"),
            "revision_authority": {
                "kind": "native_device",
                "authority_id": identifier("device"),
                "revision_branch_id": identifier("branch"),
            },
            "base_scene_revision": base_revision,
            "target_context": {
                "captured_at_frame_id": identifier("frame"),
                "captured_scene_revision": base_revision,
                "world_frame_id": identifier("world"),
                "world_frame_version": 1,
                "camera_pose": copy.deepcopy(identity_matrix),
                "screen_point_encoded_pixels": [100.5, 200.5],
                "candidate_object_ids": [identifier("object")] if selected_object_id else [],
                "selected_object_id": selected_object_id,
                "artifact_refs": [],
            },
            "intent": {
                "operation": operation,
                "source": "typed",
                "arguments": intent_arguments,
                "constraints": [],
            },
            "proposed_operations": proposed,
            "validation": operation_validation,
            "preview": {
                "preview_id": preview_id,
                "base_scene_revision": base_revision,
                "expires_at_utc": "2026-07-14T12:05:00Z",
                "artifact_refs": [],
            },
            "commit": {
                "authority_id": identifier("device"),
                "revision_branch_id": identifier("branch"),
                "compare_and_swap_base_revision": base_revision,
                "committed_scene_revision": committed_revision,
                "confirmation": {
                    "kind": "explicit_user_confirmation",
                    "actor_id": identifier("user"),
                    "source": "native_ui",
                    "preview_id": preview_id,
                    "confirmation_event_id": identifier("event"),
                    "confirmed_at_utc": "2026-07-14T12:00:00Z",
                },
                "committed_at_utc": "2026-07-14T12:00:01Z",
                "local_durable_before_visible_ack": True,
                "result_sha256_algorithm": "RR-JCS-SHA256-1",
                "result_sha256_scope": "commit_object_with_result_sha256_member_omitted",
                "result_sha256": "6" * 64,
            },
            "inverse_operations": [inverse],
            "local_undo_token": identifier("undo"),
            "canonical_state": "committed",
            "sync_state": "pending_sync",
            "created_at_utc": "2026-07-14T11:59:59Z",
        }
        if operation == "restore":
            result["compensates_transaction_id"] = restore_source_transaction_id
        return result

    def projection_semantically_valid(projection: dict[str, Any]) -> bool:
        def sorted_unique(records: Any, identity_key: str) -> bool:
            if not isinstance(records, list):
                return False
            identities = [record.get(identity_key) for record in records if isinstance(record, dict)]
            return (
                len(identities) == len(records)
                and all(isinstance(identity, str) for identity in identities)
                and identities == sorted(identities)
                and len(identities) == len(set(identities))
            )

        object_states = projection.get("object_edit_states")
        placed_assets = projection.get("placed_assets")
        support_relations = projection.get("asset_support_relations")
        if not sorted_unique(object_states, "object_id"):
            return False
        if not sorted_unique(placed_assets, "placed_asset_id"):
            return False
        if not sorted_unique(support_relations, "relation_id"):
            return False
        relation_by_id = {relation["relation_id"]: relation for relation in support_relations}
        placed_by_id = {asset["placed_asset_id"]: asset for asset in placed_assets}
        if set(relation_by_id) != {
            asset.get("support_relation_id") for asset in placed_assets if isinstance(asset, dict)
        }:
            return False
        for placed_asset in placed_assets:
            relation = relation_by_id.get(placed_asset.get("support_relation_id"))
            if relation is None or relation.get("subject_id") != placed_asset.get("placed_asset_id"):
                return False
        if any(relation.get("subject_id") not in placed_by_id for relation in support_relations):
            return False
        return True

    def projection_snapshot_semantically_valid(snapshot: Any) -> bool:
        import hashlib

        if not isinstance(snapshot, dict):
            return False
        projection = snapshot.get("projection")
        if not isinstance(projection, dict) or not projection_semantically_valid(projection):
            return False
        origin = snapshot.get("projection_origin")
        derivation = snapshot.get("derivation")
        if origin == "captured_exact":
            if derivation is not None:
                return False
        elif origin == "restore_rebase":
            if not isinstance(derivation, dict):
                return False
            touched_fields = (
                "touched_object_ids",
                "touched_placed_asset_ids",
                "touched_asset_support_relation_ids",
            )
            for field_name in touched_fields:
                identities = derivation.get(field_name)
                if (
                    not isinstance(identities, list)
                    or identities != sorted(identities)
                    or len(identities) != len(set(identities))
                ):
                    return False
        else:
            return False
        canonical_probe_bytes = json.dumps(
            projection, ensure_ascii=False, separators=(",", ":"), sort_keys=True
        ).encode("utf-8")
        return (
            snapshot.get("projection_sha256_algorithm") == "RR-JCS-SHA256-1"
            and snapshot.get("projection_sha256_scope") == "entire_rr_edit_projection_1"
            and snapshot.get("projection_sha256") == hashlib.sha256(canonical_probe_bytes).hexdigest()
        )

    def transaction_semantically_valid(instance: dict[str, Any]) -> bool:
        """Apply deterministic cross-field rules that Draft 2020-12 cannot compare."""
        if not schema_probe_valid(instance, transaction, transaction):
            return False
        base_revision = instance.get("base_scene_revision")
        preview = instance.get("preview")
        commit = instance.get("commit")
        authority = instance.get("revision_authority")
        if isinstance(preview, dict) and preview.get("base_scene_revision") != base_revision:
            return False
        if isinstance(commit, dict):
            if not isinstance(authority, dict):
                return False
            if commit.get("authority_id") != authority.get("authority_id"):
                return False
            if commit.get("revision_branch_id") != authority.get("revision_branch_id"):
                return False
            if commit.get("compare_and_swap_base_revision") != base_revision:
                return False
            if type(base_revision) is not int or commit.get("committed_scene_revision") != base_revision + 1:
                return False
            confirmation = commit.get("confirmation")
            if not isinstance(confirmation, dict) or not isinstance(preview, dict):
                return False
            if confirmation.get("preview_id") != preview.get("preview_id"):
                return False
        target_context = instance.get("target_context", {})
        if target_context.get("captured_scene_revision") != base_revision:
            return False
        selected_object_id = target_context.get("selected_object_id")
        if selected_object_id is not None and selected_object_id not in target_context.get("candidate_object_ids", []):
            return False
        validation_checks = instance.get("validation", {}).get("checks", [])
        check_ids = [check.get("check_id") for check in validation_checks if isinstance(check, dict)]
        if len(check_ids) != len(validation_checks) or len(check_ids) != len(set(check_ids)):
            return False
        intent_asset_id = instance.get("intent", {}).get("arguments", {}).get("asset_id")
        for operation in instance.get("proposed_operations", []):
            if not isinstance(operation, dict):
                return False
            kind = operation.get("kind")
            if kind == "set_object_visibility":
                if operation.get("before") != {"visible": True} or operation.get("after") != {"visible": False}:
                    return False
                if selected_object_id is not None and operation.get("entity_id") != selected_object_id:
                    return False
            elif kind == "set_reveal_bundle":
                if not isinstance(operation.get("after"), dict):
                    return False
                if selected_object_id is not None and operation.get("entity_id") != selected_object_id:
                    return False
                reveal_references = [
                    reference
                    for reference in operation.get("required_artifact_refs", [])
                    if isinstance(reference, dict) and reference.get("artifact_type") == "reveal_bundle"
                ]
                if len(reveal_references) != 1 or any(
                    operation["after"].get(field_name) != reveal_references[0].get(field_name)
                    for field_name in ("artifact_id", "artifact_type", "artifact_revision", "sha256")
                ):
                    return False
            elif kind == "create_asset_instance":
                required_refs = operation.get("required_artifact_refs", [])
                manifest_references = [
                    reference
                    for reference in required_refs
                    if isinstance(reference, dict) and reference.get("artifact_type") == "asset_manifest"
                ]
                if len(manifest_references) != 1:
                    return False
                after = operation.get("after")
                if not isinstance(after, dict) or not isinstance(after.get("support_relation"), dict):
                    return False
                if after.get("manifest_artifact_ref") != manifest_references[0]:
                    return False
                if intent_asset_id is not None and after.get("asset_id") != intent_asset_id:
                    return False
        inverse_operations = instance.get("inverse_operations", [])
        restore_operations = [
            operation
            for operation in [*instance.get("proposed_operations", []), *inverse_operations]
            if isinstance(operation, dict) and operation.get("kind") == "restore_snapshot"
        ]
        for restore in restore_operations:
            if restore.get("entity_id") != identifier("scene"):
                return False
            after_projection = restore.get("after", {}).get("projection", {})
            required_refs = restore.get("required_artifact_refs")
            if not isinstance(required_refs, list):
                return False
            if len({reference.get("artifact_id") for reference in required_refs if isinstance(reference, dict)}) != len(required_refs):
                return False
            reference_by_id = {
                reference.get("artifact_id"): reference
                for reference in required_refs
                if isinstance(reference, dict)
            }
            expected_reference_ids: set[str] = set()
            for object_state in after_projection.get("object_edit_states", []):
                active_reveal = object_state.get("active_reveal")
                if isinstance(active_reveal, dict):
                    expected_reference_ids.add(active_reveal.get("artifact_id"))
                    if reference_by_id.get(active_reveal.get("artifact_id")) != active_reveal:
                        return False
            for placed_asset in after_projection.get("placed_assets", []):
                manifest_reference = placed_asset.get("manifest_artifact_ref")
                if not isinstance(manifest_reference, dict):
                    return False
                manifest_id = manifest_reference.get("artifact_id")
                expected_reference_ids.add(manifest_id)
                if reference_by_id.get(manifest_id) != manifest_reference:
                    return False
            if set(reference_by_id) != expected_reference_ids:
                return False
            for snapshot in (restore.get("before"), restore.get("after")):
                if not projection_snapshot_semantically_valid(snapshot):
                    return False
                projection = snapshot["projection"]
                if projection.get("scene_id") != restore.get("entity_id"):
                    return False
                if projection.get("revision_branch_id") != authority.get("revision_branch_id"):
                    return False
                if projection.get("world_frame_id") != target_context.get("world_frame_id"):
                    return False
                if projection.get("world_frame_version") != target_context.get("world_frame_version"):
                    return False
        if isinstance(commit, dict) and inverse_operations:
            inverse = inverse_operations[0]
            if inverse.get("kind") != "restore_snapshot":
                return False
            if inverse.get("before", {}).get("captured_scene_revision") != commit.get("committed_scene_revision"):
                return False
        intent_operation = instance.get("intent", {}).get("operation")
        proposed_operations = instance.get("proposed_operations", [])
        if intent_operation == "restore":
            proposed_restore = proposed_operations[0]
            inverse_restore = inverse_operations[0]
            if proposed_restore.get("before", {}).get("captured_scene_revision") != base_revision:
                return False
            if proposed_restore.get("after", {}).get("captured_scene_revision") != base_revision:
                return False
            if proposed_restore.get("before", {}).get("projection_origin") != "captured_exact":
                return False
            if proposed_restore.get("after", {}).get("projection_origin") != "restore_rebase":
                return False
            if any(
                snapshot.get("projection_origin") != "captured_exact"
                for snapshot in (inverse_restore.get("before", {}), inverse_restore.get("after", {}))
            ):
                return False
            derivation = proposed_restore.get("after", {}).get("derivation")
            if not isinstance(derivation, dict) or derivation.get("rule") != "RR-RESTORE-REBASE-1":
                return False
            source_transaction_id = derivation.get("source_transaction_id")
            if source_transaction_id != instance.get("compensates_transaction_id"):
                return False
            source_inverse = probe_source_inverse_records.get(source_transaction_id)
            if not isinstance(source_inverse, dict):
                return False
            if (
                derivation.get("source_inverse_before_projection_sha256")
                != source_inverse["before"].get("projection_sha256")
                or derivation.get("source_inverse_after_projection_sha256")
                != source_inverse["after"].get("projection_sha256")
            ):
                return False

            array_specs = (
                ("object_edit_states", "object_id", "touched_object_ids"),
                ("placed_assets", "placed_asset_id", "touched_placed_asset_ids"),
                (
                    "asset_support_relations",
                    "relation_id",
                    "touched_asset_support_relation_ids",
                ),
            )
            source_before_projection = source_inverse["before"]["projection"]
            source_after_projection = source_inverse["after"]["projection"]
            expected_after_projection = copy.deepcopy(proposed_restore["before"]["projection"])
            for array_name, identity_field, touched_field in array_specs:
                before_records = {
                    record[identity_field]: record
                    for record in source_before_projection[array_name]
                }
                after_records = {
                    record[identity_field]: record
                    for record in source_after_projection[array_name]
                }
                expected_touched_ids = sorted(
                    identity
                    for identity in set(before_records) | set(after_records)
                    if before_records.get(identity) != after_records.get(identity)
                )
                ordered_operation_touched_ids = source_inverse["ordered_touched"].get(touched_field)
                if (
                    derivation.get(touched_field) != expected_touched_ids
                    or derivation.get(touched_field) != ordered_operation_touched_ids
                ):
                    return False
                current_records = {
                    record[identity_field]: copy.deepcopy(record)
                    for record in expected_after_projection[array_name]
                }
                if any(
                    current_records.get(identity) != before_records.get(identity)
                    for identity in expected_touched_ids
                ):
                    return False
                for identity in expected_touched_ids:
                    if identity in after_records:
                        current_records[identity] = copy.deepcopy(after_records[identity])
                    else:
                        current_records.pop(identity, None)
                expected_after_projection[array_name] = [
                    current_records[identity] for identity in sorted(current_records)
                ]
            if proposed_restore.get("after", {}).get("projection") != expected_after_projection:
                return False
            if inverse_restore.get("before", {}).get("projection") != proposed_restore.get("after", {}).get("projection"):
                return False
            if inverse_restore.get("after", {}).get("projection") != proposed_restore.get("before", {}).get("projection"):
                return False
            if inverse_restore.get("after", {}).get("captured_scene_revision") != base_revision:
                return False
        elif inverse_operations:
            inverse = inverse_operations[0]
            if inverse.get("after", {}).get("captured_scene_revision") != base_revision:
                return False
            if intent_operation in {"place", "replace"}:
                create = next(
                    (operation for operation in proposed_operations if operation.get("kind") == "create_asset_instance"),
                    None,
                )
                if not isinstance(create, dict):
                    return False
                projection = inverse.get("before", {}).get("projection", {})
                placed_asset = next(
                    (
                        asset
                        for asset in projection.get("placed_assets", [])
                        if asset.get("placed_asset_id") == create.get("entity_id")
                    ),
                    None,
                )
                if not isinstance(placed_asset, dict):
                    return False
                support = create.get("after", {}).get("support_relation", {})
                expected_relation = next(
                    (
                        relation
                        for relation in projection.get("asset_support_relations", [])
                        if relation.get("relation_id") == support.get("relation_id")
                    ),
                    None,
                )
                if (
                    placed_asset.get("support_relation_id") != support.get("relation_id")
                    or placed_asset.get("source_transaction_id") != instance.get("transaction_id")
                    or placed_asset.get("manifest_artifact_ref")
                    != create.get("after", {}).get("manifest_artifact_ref")
                    or not isinstance(expected_relation, dict)
                    or expected_relation.get("subject_id") != create.get("entity_id")
                    or expected_relation.get("surface_id") != support.get("surface_id")
                ):
                    return False
        return True

    required_checks_by_operation = {
        "place": {"scene_revision", "artifact_integrity", "support", "collision_proxy", "asset_license"},
        "replace": {"scene_revision", "artifact_integrity", "target_exists", "capability_ready", "support", "collision_proxy", "asset_license"},
        "remove": {"scene_revision", "artifact_integrity", "target_exists", "capability_ready", "view_envelope"},
        "restore": {"scene_revision", "artifact_integrity", "snapshot_integrity", "compensation_eligibility"},
    }
    for operation, required_check_ids in required_checks_by_operation.items():
        baseline = committed_transaction(operation, required_check_ids)
        if not schema_probe_valid(baseline, transaction, transaction):
            errors.append(f"transaction.schema.json: committed {operation} baseline probe is invalid")
            continue
        for missing_check_id in sorted(required_check_ids):
            incomplete = committed_transaction(operation, required_check_ids - {missing_check_id})
            if schema_probe_valid(incomplete, transaction, transaction):
                errors.append(f"transaction.schema.json: committed {operation} accepts missing passed {missing_check_id}")
            nonpassing = committed_transaction(operation, required_check_ids)
            for check in nonpassing["validation"]["checks"]:
                if check["check_id"] == missing_check_id:
                    check["result"] = "not_applicable"
            if schema_probe_valid(nonpassing, transaction, transaction):
                errors.append(f"transaction.schema.json: committed {operation} accepts non-pass {missing_check_id}")

    sparse_place = committed_transaction("place", {"scene_revision"})
    if schema_probe_valid(sparse_place, transaction, transaction):
        errors.append("transaction.schema.json: committed place accepts scene_revision without artifact/support/collision/license checks")
    revealed_replace_checks = required_checks_by_operation["replace"] | {"view_envelope"}
    revealed_replace = committed_transaction("replace", revealed_replace_checks, replace_with_reveal=True)
    if not schema_probe_valid(revealed_replace, transaction, transaction):
        errors.append("transaction.schema.json: revealed replace baseline probe is invalid")
    missing_view = committed_transaction("replace", required_checks_by_operation["replace"], replace_with_reveal=True)
    if schema_probe_valid(missing_view, transaction, transaction):
        errors.append("transaction.schema.json: revealed replace accepts missing passed view_envelope")

    for operation, required_check_ids in required_checks_by_operation.items():
        if not transaction_semantically_valid(committed_transaction(operation, required_check_ids)):
            errors.append(f"transaction.schema.json: committed {operation} fails deterministic cross-field validation")

    wrong_asset_reference = committed_transaction("place", required_checks_by_operation["place"])
    wrong_asset_reference["proposed_operations"][0]["required_artifact_refs"][0]["artifact_type"] = "reveal_bundle"
    if transaction_semantically_valid(wrong_asset_reference):
        errors.append("transaction.schema.json: create operation accepts no asset_manifest reference")
    missing_asset_reference = committed_transaction("place", required_checks_by_operation["place"])
    missing_asset_reference["proposed_operations"][0]["required_artifact_refs"] = []
    if transaction_semantically_valid(missing_asset_reference):
        errors.append("transaction.schema.json: create operation accepts an empty artifact reference set")
    missing_support = committed_transaction("place", required_checks_by_operation["place"])
    del missing_support["proposed_operations"][0]["after"]["support_relation"]
    if transaction_semantically_valid(missing_support):
        errors.append("transaction.schema.json: create operation accepts a missing atomic support relation")
    wrong_manifest_id = committed_transaction("place", required_checks_by_operation["place"])
    wrong_manifest_id["proposed_operations"][0]["after"]["manifest_artifact_ref"]["artifact_id"] = other_identifier("artifact")
    if transaction_semantically_valid(wrong_manifest_id):
        errors.append("transaction.schema.json: create snapshot manifest ID can disagree with its artifact reference")
    wrong_manifest_revision = committed_transaction("place", required_checks_by_operation["place"])
    wrong_manifest_revision["proposed_operations"][0]["after"]["manifest_artifact_ref"]["artifact_revision"] = 2
    if transaction_semantically_valid(wrong_manifest_revision):
        errors.append("transaction.schema.json: create snapshot manifest revision can disagree with its artifact reference")
    wrong_manifest_digest = committed_transaction("place", required_checks_by_operation["place"])
    wrong_manifest_digest["proposed_operations"][0]["after"]["manifest_artifact_ref"]["sha256"] = "2" * 64
    if transaction_semantically_valid(wrong_manifest_digest):
        errors.append("transaction.schema.json: create snapshot manifest digest can disagree with its artifact reference")
    wrong_reveal_digest = committed_transaction("remove", required_checks_by_operation["remove"])
    wrong_reveal_digest["proposed_operations"][0]["after"]["sha256"] = "2" * 64
    if transaction_semantically_valid(wrong_reveal_digest):
        errors.append("transaction.schema.json: reveal snapshot digest can disagree with its artifact reference")

    visibility_not_hidden = committed_transaction("replace", required_checks_by_operation["replace"])
    visibility_not_hidden["proposed_operations"][0]["after"]["visible"] = True
    if transaction_semantically_valid(visibility_not_hidden):
        errors.append("transaction.schema.json: replace accepts visibility transition true -> true")
    visibility_not_initially_visible = committed_transaction("remove", required_checks_by_operation["remove"])
    visibility_not_initially_visible["proposed_operations"][1]["before"]["visible"] = False
    if transaction_semantically_valid(visibility_not_initially_visible):
        errors.append("transaction.schema.json: remove accepts visibility transition false -> false")
    null_reveal = committed_transaction("remove", required_checks_by_operation["remove"])
    null_reveal["proposed_operations"][0]["after"] = None
    if transaction_semantically_valid(null_reveal):
        errors.append("transaction.schema.json: forward remove accepts a null reveal after-state")

    reordered_replace = committed_transaction("replace", required_checks_by_operation["replace"])
    reordered_replace["proposed_operations"].reverse()
    if transaction_semantically_valid(reordered_replace):
        errors.append("transaction.schema.json: replace accepts create-before-hide reducer order")
    reordered_remove = committed_transaction("remove", required_checks_by_operation["remove"])
    reordered_remove["proposed_operations"].reverse()
    if transaction_semantically_valid(reordered_remove):
        errors.append("transaction.schema.json: remove accepts hide-before-reveal reducer order")
    reordered_revealed_replace = committed_transaction(
        "replace", revealed_replace_checks, replace_with_reveal=True
    )
    reordered_revealed_replace["proposed_operations"][0], reordered_revealed_replace["proposed_operations"][1] = (
        reordered_revealed_replace["proposed_operations"][1],
        reordered_revealed_replace["proposed_operations"][0],
    )
    if transaction_semantically_valid(reordered_revealed_replace):
        errors.append("transaction.schema.json: revealed replace accepts hide-before-reveal reducer order")

    binding_mutations: tuple[tuple[str, tuple[str, ...], Any], ...] = (
        ("confirmation preview", ("commit", "confirmation", "preview_id"), other_identifier("preview")),
        ("commit authority", ("commit", "authority_id"), other_identifier("device")),
        ("commit revision branch", ("commit", "revision_branch_id"), other_identifier("branch")),
        ("preview base revision", ("preview", "base_scene_revision"), 1),
        ("CAS base revision", ("commit", "compare_and_swap_base_revision"), 1),
        ("single-increment committed revision", ("commit", "committed_scene_revision"), 2),
    )
    for label, field_path, bad_value in binding_mutations:
        invalid_binding = committed_transaction("place", required_checks_by_operation["place"])
        target: Any = invalid_binding
        for segment in field_path[:-1]:
            target = target[segment]
        target[field_path[-1]] = bad_value
        if transaction_semantically_valid(invalid_binding):
            errors.append(f"transaction.schema.json: deterministic binding accepts mismatched {label}")

    stale_target_context = committed_transaction("place", required_checks_by_operation["place"])
    stale_target_context["target_context"]["captured_scene_revision"] = 1
    if transaction_semantically_valid(stale_target_context):
        errors.append("transaction.schema.json: target_context revision can disagree with transaction base")
    selected_outside_candidates = committed_transaction("remove", required_checks_by_operation["remove"])
    selected_outside_candidates["target_context"]["candidate_object_ids"] = []
    if transaction_semantically_valid(selected_outside_candidates):
        errors.append("transaction.schema.json: selected object need not belong to candidate_object_ids")
    mismatched_intent_asset = committed_transaction("place", required_checks_by_operation["place"])
    mismatched_intent_asset["proposed_operations"][0]["after"]["asset_id"] = other_identifier("asset")
    if transaction_semantically_valid(mismatched_intent_asset):
        errors.append("transaction.schema.json: created asset can disagree with exact intent asset_id")
    duplicate_validation_check = committed_transaction("place", required_checks_by_operation["place"])
    duplicate_validation_check["validation"]["checks"].append(
        copy.deepcopy(duplicate_validation_check["validation"]["checks"][0])
    )
    if transaction_semantically_valid(duplicate_validation_check):
        errors.append("transaction.schema.json: validation checks accept duplicate check_id values")

    target_mismatch = committed_transaction("remove", required_checks_by_operation["remove"])
    target_mismatch["proposed_operations"][0]["entity_id"] = other_identifier("object")
    if transaction_semantically_valid(target_mismatch):
        errors.append("transaction.schema.json: reveal reducer can target a different object than target_context")

    projection_schema = tx_defs.get("editProjection", {})
    ordered_projection = projection_content(visible=True, active_reveal=None, with_asset=True)
    ordered_projection["object_edit_states"].append(
        {
            "object_id": other_identifier("object"),
            "visible": True,
            "active_reveal": None,
        }
    )
    second_placed_asset = copy.deepcopy(ordered_projection["placed_assets"][0])
    second_placed_asset.update(
        {
            "placed_asset_id": other_identifier("assetinst"),
            "asset_id": other_identifier("asset"),
            "manifest_artifact_ref": {
                **copy.deepcopy(second_placed_asset["manifest_artifact_ref"]),
                "artifact_id": other_identifier("artifact"),
            },
            "support_relation_id": other_identifier("support"),
        }
    )
    ordered_projection["placed_assets"].append(second_placed_asset)
    second_support_relation = copy.deepcopy(ordered_projection["asset_support_relations"][0])
    second_support_relation.update(
        {
            "relation_id": other_identifier("support"),
            "subject_id": other_identifier("assetinst"),
            "surface_id": other_identifier("surface"),
        }
    )
    ordered_projection["asset_support_relations"].append(second_support_relation)
    if not (
        schema_probe_valid(ordered_projection, projection_schema, transaction)
        and projection_semantically_valid(ordered_projection)
    ):
        errors.append("transaction.schema.json: ordered RR-EDIT-PROJECTION-1 baseline is invalid")
    projection_arrays = (
        ("object_edit_states", "object_id"),
        ("placed_assets", "placed_asset_id"),
        ("asset_support_relations", "relation_id"),
    )
    for array_name, identity_field in projection_arrays:
        reversed_projection = copy.deepcopy(ordered_projection)
        reversed_projection[array_name].reverse()
        if (
            schema_probe_valid(reversed_projection, projection_schema, transaction)
            and projection_semantically_valid(reversed_projection)
        ):
            errors.append(
                f"transaction.schema.json: edit projection accepts reverse stable-ID order in {array_name}"
            )
        duplicate_identity = copy.deepcopy(ordered_projection)
        duplicate_identity[array_name][1][identity_field] = duplicate_identity[array_name][0][identity_field]
        if array_name == "object_edit_states":
            duplicate_identity[array_name][1]["visible"] = False
        elif array_name == "placed_assets":
            duplicate_identity[array_name][1]["state"] = "hidden"
        else:
            duplicate_identity[array_name][1]["confidence"] = 0.98
        if (
            schema_probe_valid(duplicate_identity, projection_schema, transaction)
            and projection_semantically_valid(duplicate_identity)
        ):
            errors.append(
                f"transaction.schema.json: edit projection accepts duplicate {identity_field} with different content"
            )
    dangling_support = copy.deepcopy(ordered_projection)
    dangling_support["placed_assets"][0]["support_relation_id"] = other_identifier("support")
    if projection_semantically_valid(dangling_support):
        errors.append("transaction.schema.json: edit projection accepts a dangling asset support_relation_id")
    wrong_support_subject = copy.deepcopy(ordered_projection)
    wrong_support_subject["asset_support_relations"][0]["subject_id"] = other_identifier("assetinst")
    if projection_semantically_valid(wrong_support_subject):
        errors.append("transaction.schema.json: edit projection accepts a support relation for the wrong asset")
    extra_support = copy.deepcopy(ordered_projection)
    extra_support["asset_support_relations"].append(
        {
            **copy.deepcopy(extra_support["asset_support_relations"][0]),
            "relation_id": other_identifier("support"),
        }
    )
    if projection_semantically_valid(extra_support):
        errors.append("transaction.schema.json: edit projection accepts an extra asset support row")

    restore_baseline = committed_transaction("restore", required_checks_by_operation["restore"])
    restore_proposed = restore_baseline["proposed_operations"][0]
    restored_object_before = next(
        state
        for state in restore_proposed["before"]["projection"]["object_edit_states"]
        if state["object_id"] == other_identifier("object")
    )
    restored_object_after = next(
        state
        for state in restore_proposed["after"]["projection"]["object_edit_states"]
        if state["object_id"] == other_identifier("object")
    )
    if restored_object_after != restored_object_before:
        errors.append("transaction.schema.json: restore-rebase baseline does not preserve a newly tracked object")

    def resnapshot_like(snapshot: dict[str, Any], projection: dict[str, Any]) -> dict[str, Any]:
        return projection_snapshot(
            snapshot["captured_scene_revision"],
            projection,
            projection_origin=snapshot["projection_origin"],
            derivation=snapshot["derivation"],
        )

    dropped_new_object = copy.deepcopy(restore_baseline)
    dropped_after_projection = dropped_new_object["proposed_operations"][0]["after"]["projection"]
    dropped_after_projection["object_edit_states"] = [
        state
        for state in dropped_after_projection["object_edit_states"]
        if state["object_id"] != other_identifier("object")
    ]
    dropped_new_object["proposed_operations"][0]["after"] = resnapshot_like(
        dropped_new_object["proposed_operations"][0]["after"], dropped_after_projection
    )
    dropped_new_object["inverse_operations"][0]["before"] = projection_snapshot(
        3, dropped_after_projection
    )
    if transaction_semantically_valid(dropped_new_object):
        errors.append("transaction.schema.json: restore-rebase can drop a newly tracked object")

    overwritten_new_object = copy.deepcopy(restore_baseline)
    overwritten_projection = overwritten_new_object["proposed_operations"][0]["after"]["projection"]
    next(
        state
        for state in overwritten_projection["object_edit_states"]
        if state["object_id"] == other_identifier("object")
    )["visible"] = False
    overwritten_new_object["proposed_operations"][0]["after"] = resnapshot_like(
        overwritten_new_object["proposed_operations"][0]["after"], overwritten_projection
    )
    overwritten_new_object["inverse_operations"][0]["before"] = projection_snapshot(
        3, overwritten_projection
    )
    if transaction_semantically_valid(overwritten_new_object):
        errors.append("transaction.schema.json: restore-rebase can overwrite an untouched new object")

    touched_entity_drift = copy.deepcopy(restore_baseline)
    drifted_current_projection = touched_entity_drift["proposed_operations"][0]["before"]["projection"]
    drifted_original = next(
        state
        for state in drifted_current_projection["object_edit_states"]
        if state["object_id"] == identifier("object")
    )
    drifted_original["active_reveal"] = None
    drifted_current_snapshot = projection_snapshot(2, drifted_current_projection)
    touched_entity_drift["proposed_operations"][0]["before"] = drifted_current_snapshot
    touched_entity_drift["inverse_operations"][0] = restore_operation(
        touched_entity_drift["inverse_operations"][0]["before"], drifted_current_snapshot
    )
    if transaction_semantically_valid(touched_entity_drift):
        errors.append("transaction.schema.json: restore-rebase accepts unexpected drift on a touched object")

    invalid_source = copy.deepcopy(restore_baseline)
    invalid_source["proposed_operations"][0]["after"]["derivation"]["source_transaction_id"] = third_identifier("tx")
    if transaction_semantically_valid(invalid_source):
        errors.append("transaction.schema.json: restore-rebase derivation can name a transaction other than compensates_transaction_id")
    invalid_source_hash = copy.deepcopy(restore_baseline)
    invalid_source_hash["proposed_operations"][0]["after"]["derivation"]["source_inverse_before_projection_sha256"] = "0" * 64
    if transaction_semantically_valid(invalid_source_hash):
        errors.append("transaction.schema.json: restore-rebase accepts a wrong persisted source-inverse digest")
    missing_touched_object = copy.deepcopy(restore_baseline)
    missing_touched_object["proposed_operations"][0]["after"]["derivation"]["touched_object_ids"] = []
    if transaction_semantically_valid(missing_touched_object):
        errors.append("transaction.schema.json: restore-rebase accepts a missing touched object ID")
    extra_touched_object = copy.deepcopy(restore_baseline)
    extra_touched_object["proposed_operations"][0]["after"]["derivation"]["touched_object_ids"] = [
        identifier("object"), other_identifier("object")
    ]
    if transaction_semantically_valid(extra_touched_object):
        errors.append("transaction.schema.json: restore-rebase accepts an untouched object ID")
    reversed_touched_objects = copy.deepcopy(extra_touched_object)
    reversed_touched_objects["proposed_operations"][0]["after"]["derivation"]["touched_object_ids"].reverse()
    if transaction_semantically_valid(reversed_touched_objects):
        errors.append("transaction.schema.json: restore-rebase accepts reverse touched-ID order")
    duplicate_touched_object = copy.deepcopy(restore_baseline)
    duplicate_touched_object["proposed_operations"][0]["after"]["derivation"]["touched_object_ids"] = [
        identifier("object"), identifier("object")
    ]
    if transaction_semantically_valid(duplicate_touched_object):
        errors.append("transaction.schema.json: restore-rebase accepts duplicate touched IDs")

    place_source_restore = committed_transaction(
        "restore", required_checks_by_operation["restore"], restore_source="place"
    )
    if not transaction_semantically_valid(place_source_restore):
        errors.append("transaction.schema.json: place-source restore-rebase baseline is invalid")
    missing_touched_support = copy.deepcopy(place_source_restore)
    missing_touched_support["proposed_operations"][0]["after"]["derivation"]["touched_asset_support_relation_ids"] = []
    if transaction_semantically_valid(missing_touched_support):
        errors.append("transaction.schema.json: restore-rebase accepts a missing created support relation ID")
    wrong_touched_asset = copy.deepcopy(place_source_restore)
    wrong_touched_asset["proposed_operations"][0]["after"]["derivation"]["touched_placed_asset_ids"] = [
        other_identifier("assetinst")
    ]
    if transaction_semantically_valid(wrong_touched_asset):
        errors.append("transaction.schema.json: restore-rebase touched asset IDs can disagree with source operations")

    captured_with_derivation = copy.deepcopy(restore_baseline)
    captured_with_derivation["proposed_operations"][0]["before"]["derivation"] = copy.deepcopy(
        captured_with_derivation["proposed_operations"][0]["after"]["derivation"]
    )
    if transaction_semantically_valid(captured_with_derivation):
        errors.append("transaction.schema.json: captured_exact snapshot accepts rebase derivation metadata")
    rebase_without_derivation = copy.deepcopy(restore_baseline)
    rebase_without_derivation["proposed_operations"][0]["after"]["derivation"] = None
    if transaction_semantically_valid(rebase_without_derivation):
        errors.append("transaction.schema.json: restore_rebase snapshot accepts null derivation")
    wrong_proposed_origin = copy.deepcopy(restore_baseline)
    wrong_proposed_origin["proposed_operations"][0]["after"]["projection_origin"] = "captured_exact"
    wrong_proposed_origin["proposed_operations"][0]["after"]["derivation"] = None
    if transaction_semantically_valid(wrong_proposed_origin):
        errors.append("transaction.schema.json: restore proposal after-state accepts captured_exact origin")
    rebase_inverse = copy.deepcopy(restore_baseline)
    rebase_inverse["inverse_operations"][0]["before"]["projection_origin"] = "restore_rebase"
    rebase_inverse["inverse_operations"][0]["before"]["derivation"] = copy.deepcopy(
        restore_baseline["proposed_operations"][0]["after"]["derivation"]
    )
    if transaction_semantically_valid(rebase_inverse):
        errors.append("transaction.schema.json: committed inverse accepts restore_rebase origin")

    missing_restore_reference = copy.deepcopy(restore_baseline)
    missing_restore_reference["inverse_operations"][0]["required_artifact_refs"] = []
    if transaction_semantically_valid(missing_restore_reference):
        errors.append("transaction.schema.json: restore inverse accepts a missing reveal artifact reference")
    extra_restore_reference = copy.deepcopy(restore_baseline)
    extra_restore_reference["proposed_operations"][0]["required_artifact_refs"] = [
        artifact_reference("asset_manifest")
    ]
    if transaction_semantically_valid(extra_restore_reference):
        errors.append("transaction.schema.json: restore proposal accepts an extra artifact reference")
    wrong_restore_manifest_digest = copy.deepcopy(place_source_restore)
    wrong_restore_manifest_digest["inverse_operations"][0]["required_artifact_refs"][0]["sha256"] = "2" * 64
    if transaction_semantically_valid(wrong_restore_manifest_digest):
        errors.append("transaction.schema.json: restore inverse manifest reference can disagree with projection")

    stale_before_revision = copy.deepcopy(restore_baseline)
    stale_before_revision["proposed_operations"][0]["before"]["captured_scene_revision"] = 0
    if transaction_semantically_valid(stale_before_revision):
        errors.append("transaction.schema.json: restore accepts a before projection not bound to current base")
    wrong_before_digest = copy.deepcopy(restore_baseline)
    wrong_before_digest["proposed_operations"][0]["before"]["projection_sha256"] = "0" * 64
    if transaction_semantically_valid(wrong_before_digest):
        errors.append("transaction.schema.json: restore accepts a before projection digest mismatch")
    wrong_projection_branch = copy.deepcopy(restore_baseline)
    wrong_projection_branch["proposed_operations"][0]["before"]["projection"]["revision_branch_id"] = other_identifier("branch")
    wrong_projection_branch["proposed_operations"][0]["before"] = projection_snapshot(
        2, wrong_projection_branch["proposed_operations"][0]["before"]["projection"]
    )
    if transaction_semantically_valid(wrong_projection_branch):
        errors.append("transaction.schema.json: restore accepts a before projection from another branch")
    stale_inverse_envelope = copy.deepcopy(restore_baseline)
    stale_inverse_envelope["inverse_operations"][0]["before"]["captured_scene_revision"] = 1
    if transaction_semantically_valid(stale_inverse_envelope):
        errors.append("transaction.schema.json: restore inverse can reuse an old envelope revision")
    unswapped_inverse = copy.deepcopy(restore_baseline)
    changed_projection = copy.deepcopy(
        unswapped_inverse["inverse_operations"][0]["before"]["projection"]
    )
    changed_projection["object_edit_states"][0]["visible"] = False
    unswapped_inverse["inverse_operations"][0]["before"] = projection_snapshot(3, changed_projection)
    if transaction_semantically_valid(unswapped_inverse):
        errors.append("transaction.schema.json: restore inverse accepts content not rebound from restored projection")
    rewound_restore_envelope = copy.deepcopy(restore_baseline)
    rewound_restore_envelope["commit"]["committed_scene_revision"] = 1
    if transaction_semantically_valid(rewound_restore_envelope):
        errors.append("transaction.schema.json: restore can rewind/reuse the historical scene revision")

    serialized_transaction_schema = json.dumps(transaction, sort_keys=True)
    if "entire_con_003_scene_state_document" in serialized_transaction_schema or "sceneSnapshot" in tx_defs:
        errors.append("transaction.schema.json: obsolete whole-SceneState restore snapshot contract remains")
    projection_snapshot_schema = tx_defs.get("editProjectionSnapshot", {})
    if (
        projection_snapshot_schema.get("properties", {})
        .get("projection_sha256_scope", {})
        .get("const")
        != "entire_rr_edit_projection_1"
    ):
        errors.append("transaction.schema.json: RR-EDIT-PROJECTION-1 digest scope is not exact")

    commit_definition = tx_defs.get("commit", {})
    commit_properties = commit_definition.get("properties", {})
    commit_required = set(commit_definition.get("required", []))
    commit_digest_fields = {"result_sha256_algorithm", "result_sha256_scope", "result_sha256"}
    if not commit_digest_fields.issubset(commit_required):
        errors.append(f"transaction.schema.json: commit digest fields missing {sorted(commit_digest_fields-commit_required)}")
    if commit_properties.get("result_sha256_algorithm", {}).get("const") != "RR-JCS-SHA256-1":
        errors.append("transaction.schema.json: commit result digest algorithm is not pinned")
    if commit_properties.get("result_sha256_scope", {}).get("const") != "commit_object_with_result_sha256_member_omitted":
        errors.append("transaction.schema.json: commit result digest scope is not exact")
    if commit_properties.get("local_durable_before_visible_ack", {}).get("const") is not True:
        errors.append("transaction.schema.json: commit can acknowledge before local durability")
    return errors


def check_paths(report: Report) -> None:
    prompt_path = rel(GOVERNING_PROMPT)
    if not prompt_path.is_file():
        report.fail("governing prompt integrity", f"missing {GOVERNING_PROMPT}")
    else:
        actual_prompt_hash = sha256(prompt_path)
        if actual_prompt_hash != GOVERNING_PROMPT_SHA256:
            report.fail("governing prompt integrity", f"SHA-256 {actual_prompt_hash}, expected {GOVERNING_PROMPT_SHA256}")
        else:
            report.pass_("governing prompt integrity", f"{GOVERNING_PROMPT} SHA-256 matches")

    archive_missing = missing(list(ARCHIVE_HASHES) + ["docs/archive/README.md"])
    if archive_missing:
        report.fail("source archival", f"missing {archive_missing}")
    else:
        archive_readme = rel("docs/archive/README.md").read_text(encoding="utf-8")
        mismatches = []
        for path, expected in ARCHIVE_HASHES.items():
            actual = sha256(rel(path))
            if actual != expected or archive_readme.count(expected) < 2:
                mismatches.append(f"{path}: {actual}")
        if mismatches:
            report.fail("source archival", "; ".join(mismatches))
        else:
            report.pass_("source archival", "byte hashes match before/after records")

    roots_present = [name for name in ("ReRoom_Master_Technical_Plan_v3.2.md", "ReRoom_PRD_v1.0.md") if rel(name).exists()]
    if roots_present:
        report.fail("archive authority", f"root sources still present: {roots_present}")
    else:
        report.pass_("archive authority", "historical inputs no longer compete at root")

    required_missing = missing(CANONICAL + CONTRACTS + AUDITS + GSD_FILES + ROOT_FILES)
    if required_missing:
        report.fail("required outputs", f"missing {required_missing}")
    else:
        report.pass_("required outputs", "canonical, audit, GSD, Codex, contract, and script set complete")


def check_machine_files(report: Report) -> tuple[list[dict[str, Any]], set[str]]:
    json_files = sorted(path for path in ROOT.rglob("*.json") if ".git" not in path.relative_to(ROOT).parts)
    schema_ids: list[str] = []
    parsed: dict[Path, Any] = {}
    schemas: dict[str, dict[str, Any]] = {}
    errors: list[str] = []
    for path in json_files:
        try:
            parsed[path] = load_json(path)
            if path.name.endswith(".schema.json"):
                if not isinstance(parsed[path], dict):
                    errors.append(f"{path.relative_to(ROOT)} schema root is not an object")
                    continue
                schemas[path.name] = parsed[path]
                errors.extend(schema_structure_errors(path.name, parsed[path]))
                schema_id = parsed[path].get("$id")
                if not schema_id:
                    errors.append(f"{path.relative_to(ROOT)} missing $id")
                else:
                    schema_ids.append(schema_id)
                expected_id = EXPECTED_SCHEMA_IDS.get(path.name)
                if expected_id is None:
                    errors.append(f"unexpected contract schema {path.relative_to(ROOT)}")
                elif schema_id != expected_id:
                    errors.append(f"{path.relative_to(ROOT)} has $id {schema_id!r}, expected {expected_id!r}")
        except (OSError, json.JSONDecodeError, ValueError) as exc:
            errors.append(f"{path.relative_to(ROOT)}: {exc}")
    missing_schemas = sorted(set(EXPECTED_SCHEMA_IDS) - set(schemas))
    if missing_schemas:
        errors.append(f"missing contract schemas {missing_schemas}")
    errors.extend(contract_invariant_errors(schemas))
    if errors or len(schema_ids) != len(set(schema_ids)):
        if len(schema_ids) != len(set(schema_ids)):
            errors.append("duplicate JSON Schema $id")
        report.fail("JSON/schema validation", "; ".join(errors))
    else:
        report.pass_(
            "JSON/schema validation",
            f"{len(json_files)} strict JSON files; {len(schema_ids)} Draft 2020-12 schemas; local refs/regex/required arrays and negative path/UUID/replay/transaction invariants pass",
        )

    toml_files = sorted(path for path in ROOT.rglob("*.toml") if ".git" not in path.relative_to(ROOT).parts)
    try:
        import tomllib
    except ImportError:
        report.warn("TOML validation", "tomllib unavailable in this Python runtime")
    else:
        toml_errors = []
        for path in toml_files:
            try:
                with path.open("rb") as handle:
                    tomllib.load(handle)
            except (OSError, tomllib.TOMLDecodeError) as exc:
                toml_errors.append(f"{path.relative_to(ROOT)}: {exc}")
        if toml_errors:
            report.fail("TOML validation", "; ".join(toml_errors))
        else:
            report.pass_("TOML validation", f"{len(toml_files)} TOML files parse")

    try:
        entries = parse_manifest(rel("docs/gsd/ingest-manifest.yml"))
    except (OSError, ValueError) as exc:
        report.fail("YAML/manifest syntax", str(exc))
        entries = []
    else:
        report.pass_("YAML/manifest syntax", f"{len(entries)} entries, released narrow schema")
    return entries, set(schema_ids)


def check_manifest(report: Report, entries: list[dict[str, Any]]) -> None:
    if not entries:
        return
    paths = [entry["path"] for entry in entries]
    duplicates = sorted({path for path in paths if paths.count(path) > 1})
    path_errors: list[str] = []
    resolved_seen: dict[str, str] = {}
    resolved_duplicates: list[str] = []
    tier_errors: list[str] = []
    for entry in entries:
        path = entry["path"]
        path_error = validate_posix_repo_path(path)
        if path_error:
            path_errors.append(f"{path}: {path_error}")
            continue
        candidate = rel(path)
        safe, detail = path_within_root(candidate, strict=True)
        if not safe or not candidate.is_file():
            path_errors.append(f"{path}: {detail or 'not a regular file'}")
            continue
        resolved_key = os.path.normcase(str(candidate.resolve(strict=True)))
        if resolved_key in resolved_seen:
            resolved_duplicates.append(f"{resolved_seen[resolved_key]} == {path}")
        else:
            resolved_seen[resolved_key] = path

        expected = EXPECTED_MANIFEST.get(path)
        actual = (entry.get("type"), entry.get("precedence"))
        if expected is None:
            tier_errors.append(f"{path}: unexpected entry {actual}")
        elif actual != expected:
            tier_errors.append(f"{path}: {actual}, expected {expected}")
        if path.startswith("docs/adr/"):
            status_match = re.search(r"^Status:\s*(Accepted|Provisional|Rejected|Superseded)\s*$", candidate.read_text(encoding="utf-8"), re.MULTILINE)
            expected_status = "Provisional" if expected and expected[1] == 10 else "Accepted"
            if not status_match or status_match.group(1) != expected_status:
                tier_errors.append(f"{path}: status {status_match.group(1) if status_match else 'missing'}, expected {expected_status}")

    missing_expected = sorted(set(EXPECTED_MANIFEST) - set(paths))
    extra_unexpected = sorted(set(paths) - set(EXPECTED_MANIFEST))
    excluded = [path for path in paths if path.startswith(("docs/archive/", "docs/audit/", "docs/gsd/", "docs/codex/")) or path in {"README.md", "AGENTS.md"}]
    precedence_values = [entry["precedence"] for entry in entries]
    ordering_error = precedence_values != sorted(precedence_values)
    highest_authority_error = not (
        entries[0]["path"] == "docs/canonical/README.md"
        and entries[0]["type"] == "DOC"
        and entries[0]["precedence"] == -10
        and sum(entry["precedence"] == -10 for entry in entries) == 1
        and all(entry["precedence"] > -10 for entry in entries[1:])
    )
    authority_text = rel("docs/canonical/README.md").read_text(encoding="utf-8")
    authority_section_match = re.search(r"^## Intended GSD ingest set\s*$([\s\S]*?)(?=^##\s|\Z)", authority_text, re.MULTILINE)
    authority_section = authority_section_match.group(1) if authority_section_match else ""
    authority_text_errors: list[str] = []
    forbidden_authority_phrases = ("not ingested", "deliberately not ingested", "through the accepted adrs")
    for phrase in forbidden_authority_phrases:
        if phrase in authority_section.lower():
            authority_text_errors.append(f"obsolete phrase {phrase!r}")
    required_authority_patterns = {
        "index is ingested": r"\b(?:this|canonical) index\b.{0,80}\b(?:is|remains)\b.{0,40}\bingested\b",
        "sole highest-authority": r"\bsole\b.{0,50}\bhighest-authority\b",
        "DOC/-10 tier": r"\bDOC\b.{0,30}`-10`",
        "accepted ADR/0 tier": r"Accepted ADRs?.{0,30}`0`",
        "provisional ADR/10 tier": r"provisional ADRs?.{0,30}`10`",
        "specification/20 tier": r"specifications?/contracts?.{0,30}`20`",
        "PRD/30 tier": r"\bPRD\b.{0,20}`30`",
        "supporting/40 tier": r"supporting canonical documents?.{0,30}`40`",
    }
    for label, pattern in required_authority_patterns.items():
        if not re.search(pattern, authority_section, re.IGNORECASE | re.DOTALL):
            authority_text_errors.append(f"missing {label}")
    if path_errors or duplicates or resolved_duplicates or excluded or missing_expected or extra_unexpected or tier_errors or ordering_error or highest_authority_error or authority_text_errors or len(entries) != 28:
        report.fail(
            "ingest-manifest integrity",
            f"path_errors={path_errors}, duplicates={duplicates}, resolved_duplicates={resolved_duplicates}, excluded={excluded}, "
            f"expected_missing={missing_expected}, unexpected={extra_unexpected}, tiers={tier_errors}, "
            f"ordered={not ordering_error}, sole_highest_lock={not highest_authority_error}, "
            f"authority_text={authority_text_errors}, count={len(entries)}",
        )
    else:
        report.pass_(
            "ingest-manifest integrity",
            "28 exact safe in-root documents; canonical lock index is sole DOC/-10 authority; ADR/status and remaining tier precedence match; archives/audits/setup excluded",
        )


def check_boundary(report: Report) -> None:
    repository_paths = [path for path in ROOT.rglob("*") if path.relative_to(ROOT).parts[0] != ".git"]
    planning = [path for path in repository_paths if path.name == ".planning" and (path.is_dir() or is_link_like(path))]
    if planning:
        report.fail("no .planning", f"found {[str(path.relative_to(ROOT)) for path in planning]}")
    else:
        report.pass_("no .planning", "no generated planning state")

    violations: list[str] = []
    allowed_dirs = (ALLOWED_ROOT_DIRS - {".git"}) | ALLOWED_DOC_DIRS
    try:
        skill_lock = load_json(rel("skills-lock.json"))
        locked_skill_names = set(skill_lock.get("skills", {}))
    except (OSError, json.JSONDecodeError, ValueError, AttributeError):
        locked_skill_names = set()
    for path in repository_paths:
        relative = path.relative_to(ROOT)
        relative_posix = relative.as_posix()
        if is_link_like(path):
            violations.append(f"link/junction forbidden: {relative_posix}")
            continue
        safe, detail = path_within_root(path, strict=True)
        if not safe:
            violations.append(f"outside/unresolvable: {relative_posix}: {detail}")
            continue
        if path.is_dir():
            if relative.parts[0] == ".agents":
                is_skill_directory = (
                    relative_posix in {".agents", ".agents/skills"}
                    or (
                        len(relative.parts) >= 3
                        and relative.parts[1] == "skills"
                        and relative.parts[2] in locked_skill_names
                    )
                )
                if not is_skill_directory:
                    violations.append(f"unexpected skill directory: {relative_posix}")
                continue
            if relative_posix not in allowed_dirs:
                violations.append(f"unexpected directory: {relative_posix}")
            continue
        if not path.is_file():
            violations.append(f"non-regular entry: {relative_posix}")
            continue

        parent = relative.parent.as_posix()
        if parent == ".":
            permitted = relative_posix in ALLOWED_ROOT_FILES
        elif relative.parts[0] == ".agents":
            permitted = (
                len(relative.parts) >= 4
                and relative.parts[1] == "skills"
                and relative.parts[2] in locked_skill_names
            )
        elif relative.parts[0] == ".codex":
            permitted = relative_posix in ALLOWED_CODEX_FILES
        elif relative.parts[0] == "prompts":
            permitted = relative_posix in ALLOWED_PROMPT_FILES
        elif relative.parts[0] == "scripts":
            permitted = relative_posix in ALLOWED_SCRIPT_FILES
        elif relative.parts[0] == "docs":
            permitted = parent in ALLOWED_DOC_DIRS and path.suffix.lower() in ALLOWED_DOC_SUFFIXES
        else:
            permitted = False
        if not permitted:
            violations.append(f"unexpected file: {relative_posix}")

    root_entries = {path.name for path in ROOT.iterdir()}
    expected_root_entries = ALLOWED_ROOT_FILES | ALLOWED_ROOT_DIRS
    unexpected_root = sorted(root_entries - expected_root_entries)
    missing_root = sorted(expected_root_entries - root_entries)
    if unexpected_root:
        violations.append(f"unexpected root entries: {unexpected_root}")
    if missing_root:
        violations.append(f"missing root entries: {missing_root}")
    if violations:
        report.fail("no product code", f"PRE-GSD repository allowlist violations: {violations}")
    else:
        report.pass_(
            "no product code",
            "strict root/locked-skill/.codex/prompt/script allowlist and expected documentation trees/extensions only; no links, outside paths, or implementation files",
        )


def check_requirements(report: Report) -> None:
    text = rel("docs/canonical/PRD.md").read_text(encoding="utf-8")
    sections = extract_p0_requirements(text)
    defined_ids = set(re.findall(r"^###\s+((?:FR|NFR|SEC|OPS|STR)-[A-Z0-9-]+)\s+—", text, re.MULTILINE))
    required_fields = (
        "**Priority:**",
        "**Statement:**",
        "**Rationale:**",
        "**Acceptance criteria:**",
        "**Dependencies:**",
        "**Fallback:**",
        "**Relevant ADRs:**",
        "**Contract/spec references:**",
        "**Recommended slice:**",
    )
    failures = [req_id for req_id, section in sections if any(field not in section for field in required_fields)]
    ids = [req_id for req_id, _ in sections]
    authority_files = list((ROOT / "docs/canonical").glob("*.md")) + list((ROOT / "docs/adr").glob("*.md")) + [rel("docs/contracts/README.md")]
    referenced_ids: set[str] = set()
    for path in authority_files:
        referenced_ids.update(re.findall(r"\b(?:FR|NFR|SEC|OPS|STR)-[A-Z0-9-]+\b", path.read_text(encoding="utf-8")))
    undefined = sorted(referenced_ids - defined_ids)
    if not sections or failures or len(ids) != len(set(ids)) or undefined:
        report.fail("requirement quality", f"P0 count={len(sections)}, incomplete={failures}, duplicate IDs={len(ids) != len(set(ids))}, undefined authoritative references={undefined}")
    else:
        report.pass_("requirement quality", f"{len(sections)} unique independently structured P0 requirements; all authoritative references resolve")


def h2_sections(text: str) -> dict[str, str]:
    matches = list(re.finditer(r"^##\s+(.+?)\s*$", text, re.MULTILINE))
    result: dict[str, str] = {}
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        result[match.group(1).strip()] = text[match.end():end].strip()
    return result


def benchmark_plan_errors(path: Path, text: str, risk_text: str) -> list[str]:
    """Parse every provisional gate into fixture/variants/metrics/threshold/timebox controls."""
    errors: list[str] = []
    sections = h2_sections(text)
    benchmark_name = next((name for name in sections if name.lower().startswith("benchmark")), None)
    fallback_name = next((name for name in sections if name.lower() == "fallback"), None)
    if not benchmark_name:
        return [f"{path.name}: provisional benchmark section missing"]
    if not fallback_name or not sections[fallback_name]:
        errors.append(f"{path.name}: non-empty fallback section missing")
    benchmark = sections[benchmark_name]
    gate_matches = list(re.finditer(r"`(GATE-\d{3})`\s*(?:\N{EM DASH}|-)\s*", benchmark))
    if not gate_matches:
        return errors + [f"{path.name}: no parsed GATE-NNN benchmark record"]
    observed_gates: set[str] = set()
    labels = "Fixture|Variants|Metrics|Pass|Timebox|Deadline"

    def labeled(block: str, label: str) -> str | None:
        match = re.search(rf"\b{label}:\s*(.+?)(?=\s+(?:{labels}):|$)", block, re.IGNORECASE | re.DOTALL)
        return match.group(1).strip() if match else None

    for index, gate_match in enumerate(gate_matches):
        gate_id = gate_match.group(1)
        block_end = gate_matches[index + 1].start() if index + 1 < len(gate_matches) else len(benchmark)
        block = benchmark[gate_match.end():block_end].strip()
        if gate_id in observed_gates:
            errors.append(f"{path.name}: duplicate benchmark record {gate_id}")
        observed_gates.add(gate_id)
        if not re.search(rf"\b{re.escape(gate_id)}\b", risk_text):
            errors.append(f"{path.name}: {gate_id} is absent from RISK_AND_KILL_GATES.md")
        parsed = {label.lower(): labeled(block, label) for label in ("Fixture", "Variants", "Metrics")}
        for field_name, value in parsed.items():
            if not value:
                errors.append(f"{path.name}: {gate_id} missing parsed {field_name}")

        pass_threshold = labeled(block, "Pass")
        if not pass_threshold:
            threshold_match = re.search(
                r"\bqualifies?\b.+?\bonly with\b(.+?)(?=\s+Timebox:|\s+Deadline:|$)",
                block,
                re.IGNORECASE | re.DOTALL,
            )
            pass_threshold = threshold_match.group(1).strip() if threshold_match else None
        if not pass_threshold or not re.search(r"\d|at least|at most|zero|\bno\b|within", pass_threshold, re.IGNORECASE):
            errors.append(f"{path.name}: {gate_id} missing a measurable threshold")

        explicit_timebox = labeled(block, "Timebox")
        implicit_timebox = re.search(r"\b(?:one|two|three|four|\d+)(?:-|\s+)(?:hour|day|slice)s?\s+timebox\b", block, re.IGNORECASE)
        if not explicit_timebox and not implicit_timebox:
            errors.append(f"{path.name}: {gate_id} missing a bounded timebox")

        deadline = labeled(block, "Deadline")
        deadline_phrase = re.search(r"\b(?:before|completed before|in the first)\b", block, re.IGNORECASE)
        if not deadline and not deadline_phrase:
            errors.append(f"{path.name}: {gate_id} missing an execution deadline")

        if not re.search(r"\b(?:fallback|failure|missed|tie|kills?|blocks?|selects?)\b", block, re.IGNORECASE):
            errors.append(f"{path.name}: {gate_id} missing an explicit failure selection/kill action")
    return errors


def check_adrs(report: Report) -> None:
    adr_files = sorted((ROOT / "docs/adr").glob("ADR-*.md"))
    expected = {f"ADR-{index:03d}" for index in range(1, 15)}
    observed: set[str] = set()
    failures: list[str] = []
    required_headings = ["## Context", "## Project constraints", "## Alternatives considered", "## Decision", "## Evidence", "## Consequences", "## Risks", "## Fallback", "## Requirements and contracts affected"]
    risk_text = rel("docs/canonical/RISK_AND_KILL_GATES.md").read_text(encoding="utf-8")
    provisional_count = 0
    for path in adr_files:
        text = path.read_text(encoding="utf-8")
        match = re.search(r"^#\s+(ADR-\d{3})", text, re.MULTILINE)
        if match:
            observed.add(match.group(1))
        else:
            failures.append(f"{path.name}: ID")
        if not re.search(r"^Status:\s*(Accepted|Provisional|Rejected|Superseded)", text, re.MULTILINE):
            failures.append(f"{path.name}: status")
        for heading in required_headings:
            if heading not in text:
                failures.append(f"{path.name}: {heading}")
        if "Status: Provisional" in text:
            provisional_count += 1
            failures.extend(benchmark_plan_errors(path, text, risk_text))
    if observed != expected or failures:
        report.fail("ADR coverage", f"missing={sorted(expected-observed)}, extra={sorted(observed-expected)}, issues={failures}")
    elif provisional_count != 3:
        report.fail("ADR coverage", f"expected 3 provisional ADRs, found {provisional_count}")
    else:
        report.pass_("ADR coverage", "14 load-bearing ADRs; 3 provisional ADRs have parsed fixture/variants/metrics/threshold/timebox/deadline/fallback gate records")


def check_research(report: Report) -> None:
    path = rel("docs/canonical/RESEARCH_LEDGER.md")
    if not path.exists():
        report.fail("source verification", "research ledger missing")
        return
    text = path.read_text(encoding="utf-8")
    claim_matches = list(re.finditer(r"^###\s+(CLM-\d{3})\s+\N{EM DASH}\s+(.+?)\s*$", text, re.MULTILINE))
    claim_ids = [match.group(1) for match in claim_matches]
    defined_claims = set(claim_ids)
    required_fields = {
        "Claim",
        "Status",
        "Decision or requirement affected",
        "Source title",
        "Source URL",
        "Source type",
        "Publication/release date",
        "Retrieval date",
        "Exact version/tag/revision",
        "Evidence summary",
        "Confidence",
        "Known limitations or ambiguity",
    }
    valid_statuses = {"VERIFIED", "PLAUSIBLE", "REQUIRES_BENCHMARK", "CONTRADICTED", "UNVERIFIED"}
    issues: list[str] = []
    observed_statuses: set[str] = set()
    for index, match in enumerate(claim_matches):
        end = claim_matches[index + 1].start() if index + 1 < len(claim_matches) else len(text)
        section = text[match.end():end]
        field_pairs = re.findall(r"^- \*\*([^*]+):\*\*\s*(.*)$", section, re.MULTILINE)
        field_names = [name for name, _ in field_pairs]
        duplicates = sorted({name for name in field_names if field_names.count(name) > 1})
        fields = dict(field_pairs)
        missing_fields = sorted(required_fields - set(fields))
        unexpected_fields = sorted(set(fields) - required_fields)
        if duplicates or missing_fields or unexpected_fields:
            issues.append(f"{match.group(1)} fields missing={missing_fields} duplicate={duplicates} unexpected={unexpected_fields}")
            continue
        empty_fields = sorted(name for name, value in fields.items() if not value.strip())
        if empty_fields:
            issues.append(f"{match.group(1)} empty fields={empty_fields}")
        status_match = re.fullmatch(r"`([A-Z_]+)`\.?", fields["Status"].strip())
        status = status_match.group(1) if status_match else fields["Status"].strip("` .")
        observed_statuses.add(status)
        if status not in valid_statuses:
            issues.append(f"{match.group(1)} invalid status {status!r}")
        retrieval = fields["Retrieval date"].strip().rstrip(".")
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", retrieval):
            issues.append(f"{match.group(1)} invalid retrieval date {retrieval!r}")
        url_values = [value.strip().rstrip(".") for value in fields["Source URL"].split(";") if value.strip()]
        if not url_values:
            issues.append(f"{match.group(1)} has no source URL")
        for source_url in url_values:
            parsed_url = urlparse(source_url)
            if parsed_url.scheme != "https" or not parsed_url.netloc or parsed_url.username or parsed_url.password:
                issues.append(f"{match.group(1)} invalid source URL {source_url!r}")
        for reference in re.findall(r"\[[^\]]+\]\(([^)]+)\)", fields["Decision or requirement affected"]):
            if urlparse(reference).scheme:
                continue
            target = path.parent / reference
            safe, detail = path_within_root(target, strict=True)
            if not safe or not target.is_file():
                issues.append(f"{match.group(1)} unresolved local reference {reference!r}: {detail}")

    expected_ids = {f"CLM-{index:03d}" for index in range(1, len(claim_matches) + 1)}
    if len(claim_ids) != len(defined_claims):
        issues.append("duplicate CLM heading IDs")
    if defined_claims != expected_ids:
        issues.append(f"non-contiguous CLM IDs missing={sorted(expected_ids-defined_claims)} extra={sorted(defined_claims-expected_ids)}")

    referenced_claims: set[str] = set()
    for reference_path in ROOT.joinpath("docs").rglob("*"):
        if not reference_path.is_file() or reference_path == path or "archive" in reference_path.relative_to(ROOT).parts:
            continue
        if reference_path.suffix.lower() not in ALLOWED_DOC_SUFFIXES:
            continue
        referenced_claims.update(re.findall(r"\bCLM-\d{3}\b", reference_path.read_text(encoding="utf-8")))
    undefined_references = sorted(referenced_claims - defined_claims)
    if undefined_references:
        issues.append(f"undefined CLM references={undefined_references}")

    markers = ["Apple", "RealityKit", "Next.js", "OpenAI", "GSD", "Firecrawl", "SAM", "Depth Anything", "Open3D", "license", "Build Week"]
    absent = [marker for marker in markers if marker.lower() not in text.lower()]
    status_absent = sorted({"VERIFIED", "REQUIRES_BENCHMARK", "CONTRADICTED"} - observed_statuses)
    if len(claim_matches) < 20 or absent or status_absent or issues:
        report.fail("source verification", f"claims={len(claim_matches)}, missing topics={absent}, missing statuses={status_absent}, issues={issues}")
    else:
        report.pass_(
            "source verification",
            f"{len(claim_matches)} complete, unique, contiguous CLM records; statuses/URLs/local links and all cross-document CLM references validate",
        )


def check_project_skills(report: Report) -> None:
    import hashlib

    issues: list[str] = []
    try:
        lock = load_json(rel("skills-lock.json"))
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        report.fail("project skill integrity", str(exc))
        return
    if not isinstance(lock, dict) or lock.get("version") != 1:
        issues.append("skills-lock.json must be a version-1 object")
    entries = lock.get("skills") if isinstance(lock, dict) else None
    if not isinstance(entries, dict):
        issues.append("skills-lock.json skills must be an object")
        entries = {}

    expected_names = set(EXPECTED_SKILLS)
    locked_names = set(entries)
    skill_root = rel(".agents/skills")
    actual_names = (
        {path.name for path in skill_root.iterdir() if path.is_dir()}
        if skill_root.is_dir()
        else set()
    )
    if locked_names != expected_names:
        issues.append(
            f"lock names missing={sorted(expected_names-locked_names)} extra={sorted(locked_names-expected_names)}"
        )
    if actual_names != expected_names:
        issues.append(
            f"skill roots missing={sorted(expected_names-actual_names)} extra={sorted(actual_names-expected_names)}"
        )

    attributes = rel(".gitattributes").read_text(encoding="utf-8")
    if ".agents/skills/** text eol=lf" not in attributes:
        issues.append(".gitattributes does not enforce LF for project skills")
    guide = rel("docs/gsd/ONBOARDING_AND_CONTINUATION.md").read_text(
        encoding="utf-8"
    )
    text_suffixes = {
        ".md", ".py", ".json", ".yaml", ".yml", ".toml", ".txt",
        ".js", ".cjs", ".mjs", ".ts", ".tsx", ".jsx", ".css", ".html",
    }
    executable_suffixes = {".bat", ".cmd", ".com", ".exe", ".js", ".mjs", ".cjs", ".ps1", ".py", ".sh"}

    for name, expected in EXPECTED_SKILLS.items():
        file_count, skill_sha, tree_sha, notice_required, source, ref_name, computed_hash = expected
        entry = entries.get(name)
        expected_entry = {
            "source": source,
            "sourceType": "github",
            "skillPath": EXPECTED_SKILL_PATHS[name],
            "computedHash": computed_hash,
        }
        if ref_name is not None:
            expected_entry["ref"] = ref_name
        if not isinstance(entry, dict):
            issues.append(f"{name}: missing lock entry")
            continue
        if entry != expected_entry:
            issues.append(f"{name}: lock metadata differs from reviewed entry")

        root = skill_root / name
        if not root.is_dir() or is_link_like(root):
            issues.append(f"{name}: missing, non-directory, or link-like skill root")
            continue
        files = sorted(
            (path for path in root.rglob("*") if path.is_file()),
            key=lambda path: (
                path.relative_to(root).as_posix().casefold(),
                path.relative_to(root).as_posix(),
            ),
        )
        linked = [
            path.relative_to(root).as_posix()
            for path in root.rglob("*")
            if is_link_like(path)
        ]
        if linked:
            issues.append(f"{name}: link-like entries={linked}")
        records: list[bytes] = []
        actual_skill_sha = ""
        executables: list[str] = []
        for path in files:
            relative_path = path.relative_to(root).as_posix()
            raw = path.read_bytes()
            if path.suffix.lower() in text_suffixes or path.name in {
                "LICENSE", "SKILL.md", "AGENTS.md", "README.md"
            }:
                raw = raw.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
            file_sha = hashlib.sha256(raw).hexdigest()
            records.append(f"{relative_path}\0{file_sha}\n".encode("utf-8"))
            if relative_path == "SKILL.md":
                actual_skill_sha = file_sha
            if path.suffix.lower() in executable_suffixes:
                executables.append(relative_path)
        actual_tree_sha = hashlib.sha256(b"".join(records)).hexdigest()
        if len(files) != file_count or actual_skill_sha != skill_sha or actual_tree_sha != tree_sha:
            issues.append(
                f"{name}: files/SKILL/tree={len(files)}/{actual_skill_sha}/{actual_tree_sha}, "
                f"expected {file_count}/{skill_sha}/{tree_sha}"
            )
        if notice_required and not (root / "LICENSE").is_file():
            issues.append(f"{name}: audited license notice missing")
        if name != "swiftui-expert-skill" and executables:
            issues.append(f"{name}: unexpected executable-bearing files={executables}")
        skill_path = root / "SKILL.md"
        if skill_path.is_file():
            skill_text = skill_path.read_text(encoding="utf-8")
            frontmatter = re.match(r"\A---\n(.*?)\n---(?:\n|\Z)", skill_text, re.DOTALL)
            skill_name = re.search(r"^name:\s*(.+?)\s*$", frontmatter.group(1), re.MULTILINE) if frontmatter else None
            description = re.search(r"^description:\s*\S", frontmatter.group(1), re.MULTILINE) if frontmatter else None
            declared_name = skill_name.group(1).strip().strip(chr(34)).strip(chr(39)) if skill_name else ""
            if declared_name != name or not description:
                issues.append(f"{name}: invalid name/description frontmatter")
        if skill_sha not in guide or tree_sha not in guide:
            issues.append(f"{name}: guide omits the pinned SKILL/tree hashes")

    if issues:
        report.fail("project skill integrity", "; ".join(issues))
    else:
        report.pass_(
            "project skill integrity",
            "8 explicitly locked skill roots match file counts, frontmatter, LF-normalized tree hashes, notices, and executable policy",
        )


def check_current_profiles(report: Report) -> None:
    expected_hashes = {
        "quality-fast.config.json": "043107e1e67c42118f30451c305312991887c043f2eaaec0473fa05446110321",
        "quality.config.json": "4ade86239f171e0eab8780d527fd9b7520c482827438643d45cafac60cbd9269",
    }
    profile_paths = [
        rel("docs/gsd/profiles/quality-fast.config.json"),
        rel("docs/gsd/profiles/quality.config.json"),
    ]
    issues: list[str] = []
    profiles: dict[str, dict[str, Any]] = {}
    for path in profile_paths:
        try:
            raw = path.read_bytes()
            profile = json.loads(raw.decode("utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            issues.append(f"{path.name}: {exc}")
            continue
        if not isinstance(profile, dict):
            issues.append(f"{path.name}: root must be an object")
            continue
        profiles[path.name] = profile
        actual_hash = sha256(path).lower()
        if actual_hash != expected_hashes[path.name]:
            issues.append(
                f"{path.name}: SHA-256 {actual_hash}, expected {expected_hashes[path.name]}"
            )
        if b"\r" in raw:
            issues.append(f"{path.name}: profile bytes must use LF line endings")

    required_empty_maps = ("models", "model_overrides", "model_profile_overrides")
    required_workflow_true = (
        "research", "plan_check", "verifier", "nyquist_validation",
        "post_planning_gaps", "pattern_mapper", "ai_integration_phase",
        "ui_phase", "ui_safety_gate", "ui_review", "tdd_mode", "code_review",
        "security_enforcement", "schema_push_detection", "plan_drift_precheck",
        "schema_drift_gate", "context_coverage_gate", "node_repair", "mvp_mode",
    )
    expected_profile_values = {
        "quality-fast.config.json": {
            "model_profile": "balanced", "granularity": "standard",
            "parallelization": True, "code_review_depth": "standard",
            "security_block_on": "high", "research_before_questions": False,
            "max_discuss_passes": 2, "human_verify_mode": "end-of-phase",
            "plan_chunked": False, "plan_review_convergence": False,
            "context_guard_mode": "warn",
        },
        "quality.config.json": {
            "model_profile": "quality", "granularity": "fine",
            "parallelization": False, "code_review_depth": "deep",
            "security_block_on": "medium", "research_before_questions": True,
            "max_discuss_passes": 3, "human_verify_mode": "mid-flight",
            "plan_chunked": True, "plan_review_convergence": True,
            "context_guard_mode": "auto",
        },
    }
    key_sets: list[set[str]] = []
    for name, profile in profiles.items():
        key_sets.append(set(flatten_values(profile)))
        for key in required_empty_maps:
            if profile.get(key) != {}:
                issues.append(f"{name}: {key} must be an empty replacement map")
        if profile.get("effort", {}).get("agent_overrides") != {}:
            issues.append(f"{name}: effort.agent_overrides must be an empty replacement map")
        if profile.get("mode") != "interactive" or profile.get("runtime") != "codex":
            issues.append(f"{name}: mode/runtime must be interactive/codex")
        if profile.get("commit_docs") is not True or profile.get("planning", {}).get("commit_docs") is not True:
            issues.append(f"{name}: both durable planning commit flags must be true")
        workflow = profile.get("workflow", {})
        for key in required_workflow_true:
            if workflow.get(key) is not True:
                issues.append(f"{name}: workflow.{key} must be true")
        if workflow.get("auto_advance") is not False or workflow.get("use_worktrees") is not False:
            issues.append(f"{name}: auto advance and worktrees must be false")
        if profile.get("plan_review", {}).get("source_grounding") is not True:
            issues.append(f"{name}: source-grounded plan review must be true")
        if any(key in profile for key in ("model_policy", "dynamic_routing", "fast_mode")):
            issues.append(f"{name}: stale routing controls remain")
        expected = expected_profile_values[name]
        for key, value in expected.items():
            actual = profile.get(key) if key in profile else workflow.get(key)
            if actual != value or type(actual) is not type(value):
                issues.append(f"{name}: {key}={actual!r}, expected {value!r}")
    if len(key_sets) == 2 and key_sets[0] != key_sets[1]:
        issues.append(
            f"profile leaf-key mismatch only-fast={sorted(key_sets[0]-key_sets[1])} only-quality={sorted(key_sets[1]-key_sets[0])}"
        )

    guide = rel("docs/gsd/ONBOARDING_AND_CONTINUATION.md").read_text(encoding="utf-8")
    applier = rel("scripts/apply_gsd_profile.py").read_text(encoding="utf-8")
    for name, expected_hash in expected_hashes.items():
        if expected_hash not in guide or expected_hash not in applier:
            issues.append(f"{name}: byte pin missing from guide or applier")
    for marker in (
        'PROFILE_NAMES = ("quality-fast", "quality")',
        "REPLACE_TOP_LEVEL_MAPS", "STALE_TOP_LEVEL_KEYS", "ensure_no_workstream",
        "write_exact_backup", "expected_active", "find_credential_like_values",
    ):
        if marker not in applier:
            issues.append(f"profile applier missing safety marker {marker!r}")

    if issues:
        report.fail("GSD profile validation", "; ".join(issues))
    else:
        report.pass_(
            "GSD profile validation",
            "pinned quality-fast/quality bytes, identical leaf sets, replacement maps, routing cleanup, interactive gates, and applier safety contract pass",
        )


def check_profiles(report: Report) -> None:
    profile_paths = [rel("docs/gsd/profiles/quality-fast.config.json"), rel("docs/gsd/profiles/maximum-assurance.config.json")]
    matrix_path = rel("docs/gsd/GSD_CONFIG_KEY_MATRIX.md")
    try:
        profiles = [load_json(path) for path in profile_paths]
        matrix = matrix_path.read_text(encoding="utf-8")
        lock = load_json(rel("docs/gsd/GSD_VERSION_LOCK.json"))
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        report.fail("GSD version/config validation", str(exc))
        return
    issues: list[str] = []
    if len(PROFILE_REGISTRY) != 45:
        issues.append(f"validator registry has {len(PROFILE_REGISTRY)} leaves, expected 45")

    flattened_profiles: dict[str, dict[str, Any]] = {}
    for path, profile in zip(profile_paths, profiles):
        if not isinstance(profile, dict):
            issues.append(f"{path.name}: profile root must be an object")
            continue
        leaves = flatten_values(profile)
        flattened_profiles[path.name] = leaves
        unknown = sorted(set(leaves) - set(PROFILE_REGISTRY))
        if unknown:
            issues.append(f"{path.name}: unsupported leaf keys {unknown}")
        for key in sorted(set(leaves) & set(PROFILE_REGISTRY)):
            value_error = profile_value_error(PROFILE_REGISTRY[key], leaves[key])
            if value_error:
                issues.append(f"{path.name}:{key}: {value_error}")
        expected_keys = set(PROFILE_REGISTRY)
        if path.name == "quality-fast.config.json":
            expected_keys.remove("workflow.plan_review_convergence")
        missing_keys = sorted(expected_keys - set(leaves))
        extra_known = sorted((set(leaves) & set(PROFILE_REGISTRY)) - expected_keys)
        if missing_keys or extra_known:
            issues.append(f"{path.name}: missing intended keys={missing_keys}, unexpected intended keys={extra_known}")
        for key, expected_value in CRITICAL_PROFILE_VALUES[path.name].items():
            if key not in leaves:
                issues.append(f"{path.name}: critical key {key} is absent")
            elif leaves[key] != expected_value or type(leaves[key]) is not type(expected_value):
                issues.append(f"{path.name}: critical {key}={leaves[key]!r}, expected {expected_value!r}")

    all_keys = set().union(*(set(values) for values in flattened_profiles.values())) if flattened_profiles else set()
    if all_keys != set(PROFILE_REGISTRY):
        issues.append(f"profile union differs from pinned registry: missing={sorted(set(PROFILE_REGISTRY)-all_keys)}, extra={sorted(all_keys-set(PROFILE_REGISTRY))}")

    supported_matrix = matrix.split("## Explicitly excluded settings", 1)[0]
    matrix_keys = re.findall(r"^\|\s*`([^`]+)`\s*\|", supported_matrix, re.MULTILINE)
    duplicate_matrix_keys = sorted({key for key in matrix_keys if matrix_keys.count(key) > 1})
    if set(matrix_keys) != set(PROFILE_REGISTRY) or duplicate_matrix_keys:
        issues.append(
            f"key matrix mismatch missing={sorted(set(PROFILE_REGISTRY)-set(matrix_keys))}, "
            f"extra={sorted(set(matrix_keys)-set(PROFILE_REGISTRY))}, duplicates={duplicate_matrix_keys}"
        )

    expected_lock = {
        "package": "@opengsd/gsd-core",
        "version": "1.6.1",
        "git_tag": "v1.6.1",
        "commit": "1c352d1ea37b010e99b8353905eb5def4f784100",
        "node_requirement": ">=22.0.0",
        "npm_requirement": ">=10.0.0",
        "codex_minimum": "0.130.0",
        "codex_recommended": ">=0.137.0",
        "install_command": "npx --yes @opengsd/gsd-core@1.6.1 --codex --local --profile=full",
        "first_ingest_command": "$gsd-ingest-docs --mode new --manifest docs/gsd/ingest-manifest.yml",
    }
    if not isinstance(lock, dict):
        issues.append("GSD_VERSION_LOCK.json root must be an object")
    else:
        for key, expected_value in expected_lock.items():
            if lock.get(key) != expected_value:
                issues.append(f"version lock {key}={lock.get(key)!r}, expected {expected_value!r}")

    if issues:
        report.fail("GSD version/config validation", "; ".join(issues))
    else:
        report.pass_(
            "GSD version/config validation",
            "pinned 1.6.1 runtime lock; exact 45-leaf type/enum registry, matrix, profile key sets, and critical quality-fast/maximum-assurance intent pass",
        )


def check_consistency(report: Report) -> None:
    canonical_text = "\n".join(path.read_text(encoding="utf-8") for path in (ROOT / "docs/canonical").glob("*.md"))
    failures = []
    for marker in ("exactly four", "place", "replace", "remove", "restore", "Mode B0", "Mode B1", "RR-COORD-1", "pending_sync", "compensating"):
        if marker.lower() not in canonical_text.lower():
            failures.append(marker)
    if re.search(r"\b(five developers|Developer [A-E]|Owner:)\b", canonical_text, re.IGNORECASE):
        failures.append("obsolete person/five-developer plan")
    if not all(name in canonical_text for name in ("frame-packet.schema.json", "rrcap-manifest.schema.json", "scene-state.schema.json", "edit-artifacts.schema.json", "transaction.schema.json")):
        failures.append("schema references")
    for line in canonical_text.splitlines():
        lowered = line.lower()
        if "mode b1" in lowered and ("p0 critical path" in lowered or "p0 dependency" in lowered):
            if not any(guard in lowered for guard in ("not", "no ", "never", "outside", "stretch", "defer", "isolat")):
                failures.append("B1 appears on P0 path")
                break
    if failures:
        report.fail("architecture consistency", ", ".join(failures))
    else:
        report.pass_("architecture consistency", "scope, terminology, identities, readiness, replay, transactions, and schema references aligned")


def check_runbook_and_action(report: Report) -> None:
    guide = rel("docs/gsd/ONBOARDING_AND_CONTINUATION.md").read_text(encoding="utf-8")
    readme = rel("README.md").read_text(encoding="utf-8")
    expected_install = "npx --yes @opengsd/gsd-core@1.6.1 --codex --local --profile=full"
    expected_first = "$gsd-ingest-docs --mode new --manifest docs/gsd/ingest-manifest.yml"
    required_markers = (
        expected_install,
        expected_first,
        "prepared, not run",
        ".planning/config.json",
        "quality-fast",
        "quality",
        "Do not precede or follow it with `$gsd-new-project`",
        "fully restart Codex",
    )
    missing_markers = [marker for marker in required_markers if marker.lower() not in guide.lower()]
    readme_ok = (
        "PRE-GSD READY" in readme
        and expected_first in readme
        and re.search(r"has\s+(?:\*\*)?not", readme, re.IGNORECASE)
    )
    if missing_markers or not readme_ok:
        report.fail(
            "manual onboarding contract",
            f"guide missing={missing_markers}, README stage/action valid={bool(readme_ok)}",
        )
    else:
        report.pass_(
            "manual onboarding contract",
            "single pinned guide covers install, docs-first ingest, profile materialization, restart, continuation, and no-run boundary",
        )
    return

    runbook = rel("docs/gsd/GSD_MANUAL_ONBOARDING_RUNBOOK.md").read_text(encoding="utf-8")
    readme = rel("README.md").read_text(encoding="utf-8")
    expected_install = "npx --yes @opengsd/gsd-core@1.6.1 --codex --local --profile=full"
    expected_first = "$gsd-ingest-docs --mode new --manifest docs/gsd/ingest-manifest.yml"
    missing_markers = [value for value in (expected_install, expected_first, "not run", ".planning/config.json", "maximum-assurance") if value.lower() not in runbook.lower()]
    if missing_markers:
        report.fail("manual onboarding contract", f"runbook missing {missing_markers}")
    elif "PRE-GSD READY" not in readme or expected_first not in readme or not re.search(r"has\s+(?:\*\*)?not", readme, re.IGNORECASE):
        report.fail("manual onboarding contract", "README lacks stage/no-run/exact next action")
    else:
        report.pass_("manual onboarding contract", "pinned manual install, exact first ingest, profile/rollback guidance, and no-run statement present")


def check_codex_firecrawl(report: Report) -> None:
    config = rel(".codex/config.toml").read_text(encoding="utf-8")
    setup = rel("docs/gsd/ONBOARDING_AND_CONTINUATION.md").read_text(encoding="utf-8")
    required = ["workspace-write", "network_access = true", "firecrawl-mcp@3.22.3", 'env_vars = ["FIRECRAWL_API_KEY"]', "required = false", "max_threads = 3", "max_depth = 1"]
    absent = [marker for marker in required if marker not in config]
    if (
        absent
        or "untrusted" not in setup.lower()
        or "credit-efficient" not in setup.lower()
        or "never write it" not in setup.lower()
    ):
        report.fail("Codex/Firecrawl setup", f"missing config/setup markers {absent}")
    else:
        report.pass_("Codex/Firecrawl setup", "pinned optional read/research MCP, bounded agents/timeouts, trust and injection guidance")


def check_secrets(report: Report) -> None:
    command = [sys.executable, str(rel("scripts/check_no_secrets.py")), str(ROOT)]
    completed = subprocess.run(command, text=True, capture_output=True, check=False)
    if completed.returncode:
        report.fail("secrets scan", (completed.stdout + completed.stderr).strip())
    else:
        report.pass_("secrets scan", completed.stdout.strip())


def main() -> int:
    report = Report()
    check_paths(report)
    entries, _ = check_machine_files(report)
    check_manifest(report, entries)
    check_boundary(report)
    check_requirements(report)
    check_adrs(report)
    check_research(report)
    check_project_skills(report)
    check_current_profiles(report)
    check_consistency(report)
    check_runbook_and_action(report)
    check_codex_firecrawl(report)
    check_secrets(report)
    return report.emit()


if __name__ == "__main__":
    raise SystemExit(main())
