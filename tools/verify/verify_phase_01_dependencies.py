#!/usr/bin/env python3
"""Bounded, offline verification for the Phase 01 dependency approval gate."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import defaultdict, deque
from pathlib import Path
from typing import Any


ALLOWLIST = {
    "ajv",
    "ajv-formats",
    "canonicalize",
    "jsonschema",
    "rfc8785",
    "swift-json-schema",
}
FINAL_DECISIONS = {"approved", "rejected", "fallback_selected"}
HEX_40 = re.compile(r"^[0-9a-f]{40}$")
HEX_64 = re.compile(r"^[0-9a-f]{64}$")


class VerificationError(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise VerificationError(f"cannot read JSON {path}: {exc}") from exc
    require(isinstance(value, dict), f"{path} must contain a JSON object")
    return value


def normalized(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name).lower()


def reachable(roots: set[str], parents_by_child: dict[str, set[str]]) -> set[str]:
    children_by_parent: dict[str, set[str]] = defaultdict(set)
    for child, parents in parents_by_child.items():
        for parent in parents:
            children_by_parent[parent].add(child)
    seen = set(roots)
    queue = deque(sorted(roots))
    while queue:
        parent = queue.popleft()
        for child in sorted(children_by_parent.get(parent, set())):
            if child not in seen:
                seen.add(child)
                queue.append(child)
    return seen


def verify_audit(audit: dict[str, Any]) -> dict[str, dict[str, Any]]:
    candidates = audit.get("candidates")
    require(isinstance(candidates, dict), "audit.candidates must be an object")
    require(set(candidates) == ALLOWLIST, "audit candidate set must equal the six-name allowlist")
    policy = audit.get("candidate_policy", {})
    require(set(policy.get("allowlist", [])) == ALLOWLIST, "audit policy allowlist drift")
    require(policy.get("locks_or_installs_permitted") is True, "locks are not authorized by the audit")
    require(isinstance(policy.get("approval_provenance"), str), "missing human approval provenance")
    for name, candidate in candidates.items():
        decision = candidate.get("decision")
        require(decision in FINAL_DECISIONS, f"{name}: pending or unknown decision {decision!r}")
        provenance = candidate.get("decision_provenance")
        require(isinstance(provenance, dict), f"{name}: missing decision provenance")
        require(provenance.get("actor") == "human", f"{name}: decision is not human-provenanced")
        require(candidate.get("proposed_version"), f"{name}: missing exact proposed version")
        require(name.lower() != "sus", "SUS must never be a candidate or dependency")
        if decision == "approved":
            require(
                candidate.get("license", {}).get("compatibility") == "compatible_approved",
                f"{name}: approved candidate lacks compatible approved license",
            )
    transitive = audit.get("resolved_transitive_audit")
    require(isinstance(transitive, dict), "missing resolved transitive audit")
    for ecosystem in ("npm", "pypi", "swiftpm"):
        require(isinstance(transitive.get(ecosystem), dict), f"missing {ecosystem} transitive audit")
        require("sus" not in {normalized(n) for n in transitive[ecosystem]}, "SUS appears as dependency")
    return candidates


def verify_javascript(
    candidates: dict[str, dict[str, Any]], audit: dict[str, Any], package_path: Path, lock_path: Path
) -> tuple[int, int]:
    package = load_json(package_path)
    dependencies = package.get("dependencies", {})
    dev_dependencies = package.get("devDependencies", {})
    require(isinstance(dependencies, dict) and isinstance(dev_dependencies, dict), "npm dependency maps must be objects")
    require(not (set(dependencies) & set(dev_dependencies)), "duplicate npm direct dependency key")
    direct = {**dependencies, **dev_dependencies}
    expected = {
        name
        for name in ("ajv", "ajv-formats", "canonicalize")
        if candidates[name]["decision"] == "approved"
    }
    require(set(direct) == expected, f"npm direct set drift: expected {sorted(expected)}, got {sorted(direct)}")
    for name in expected:
        require(direct[name] == candidates[name]["proposed_version"], f"{name}: package.json version drift")

    lock = load_json(lock_path)
    require(lock.get("lockfileVersion") == 3, "npm lockfileVersion must be 3")
    packages = lock.get("packages")
    require(isinstance(packages, dict) and isinstance(packages.get(""), dict), "npm lock missing packages root")
    root = packages[""]
    root_direct = {**root.get("dependencies", {}), **root.get("devDependencies", {})}
    require(root_direct == direct, "package-lock root direct set/version drift")

    locked: dict[str, dict[str, Any]] = {}
    for location, entry in packages.items():
        if location == "":
            continue
        require("node_modules/" in location, f"unexpected npm lock location {location!r}")
        name = location.rsplit("node_modules/", 1)[1]
        require(name not in locked, f"duplicate npm resolved node for {name}")
        require(isinstance(entry, dict), f"npm lock entry {name} must be an object")
        locked[name] = entry

    transitive = audit["resolved_transitive_audit"]["npm"]
    require(set(locked) == expected | set(transitive), "npm resolved set contains missing or extraneous nodes")
    for name in expected:
        entry = locked[name]
        artifact = candidates[name]["artifact"]
        require(entry.get("version") == candidates[name]["proposed_version"], f"{name}: lock version drift")
        require(entry.get("resolved") == artifact["url"], f"{name}: lock source drift")
        require(entry.get("integrity") == artifact["integrity"], f"{name}: lock integrity drift")
        require(entry.get("license") == candidates[name]["license"]["spdx"], f"{name}: lock license drift")
    for name, approved in transitive.items():
        entry = locked.get(name, {})
        for field in ("version", "resolved", "integrity", "license"):
            require(entry.get(field) == approved.get(field), f"{name}: npm transitive {field} drift")

    parents_by_child: dict[str, set[str]] = defaultdict(set)
    for parent, entry in locked.items():
        for child in entry.get("dependencies", {}):
            require(child in locked, f"{parent}: dependency {child} is not resolved")
            parents_by_child[child].add(parent)
    for name, approved in transitive.items():
        require(parents_by_child[name] == set(approved["parents"]), f"{name}: npm provenance parent drift")
    reached = reachable(expected, parents_by_child)
    require(reached == set(locked), f"unreachable npm resolved nodes: {sorted(set(locked) - reached)}")
    return len(expected), len(transitive)


def parse_requirements_in(path: Path) -> dict[str, str]:
    direct: dict[str, str] = {}
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = re.fullmatch(r"([A-Za-z0-9_.-]+)==([^\s;]+)", line)
        require(match is not None, f"requirements.in:{number}: only exact name==version entries are allowed")
        name = normalized(match.group(1))
        require(name not in direct, f"requirements.in:{number}: duplicate direct requirement {name}")
        direct[name] = match.group(2)
    return direct


def parse_requirements_lock(path: Path) -> dict[str, dict[str, Any]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    starts: list[tuple[int, str, str]] = []
    for index, line in enumerate(lines):
        match = re.match(r"^([A-Za-z0-9_.-]+)==([^ \\]+)", line)
        if match:
            starts.append((index, normalized(match.group(1)), match.group(2)))
    require(starts, "requirements.lock has no pinned entries")
    result: dict[str, dict[str, Any]] = {}
    for position, (start, name, version) in enumerate(starts):
        end = starts[position + 1][0] if position + 1 < len(starts) else len(lines)
        block = lines[start:end]
        hashes = sorted(set(re.findall(r"--hash=sha256:([0-9a-f]{64})", "\n".join(block))))
        parents: set[str] = set()
        for line in block:
            match = re.match(r"\s*#\s+(?:via\s+)?([^#].*)$", line)
            if not match:
                continue
            value = match.group(1).strip()
            if value == "via" or value.startswith("-r "):
                continue
            if re.fullmatch(r"[A-Za-z0-9_.-]+", value):
                parents.add(normalized(value))
        require(name not in result, f"duplicate requirements.lock package {name}")
        require(hashes, f"{name}: requirements.lock entry lacks sha256 hashes")
        canonical = {"name": name, "version": version, "hashes": hashes, "parents": sorted(parents)}
        digest = hashlib.sha256(
            json.dumps(canonical, sort_keys=True, separators=(",", ":")).encode("utf-8")
        ).hexdigest()
        result[name] = {**canonical, "entry_digest_sha256": digest}
    return result


def verify_python(
    candidates: dict[str, dict[str, Any]], audit: dict[str, Any], requirements_path: Path, lock_path: Path
) -> tuple[int, int]:
    direct = parse_requirements_in(requirements_path)
    expected = {
        name
        for name in ("jsonschema", "rfc8785")
        if candidates[name]["decision"] == "approved"
    }
    require(set(direct) == expected, f"Python direct set drift: expected {sorted(expected)}, got {sorted(direct)}")
    for name in expected:
        require(direct[name] == candidates[name]["proposed_version"], f"{name}: requirements.in version drift")

    locked = parse_requirements_lock(lock_path)
    transitive = audit["resolved_transitive_audit"]["pypi"]
    require(set(locked) == expected | set(transitive), "Python lock contains missing or extraneous packages")
    for name in expected:
        entry = locked[name]
        expected_hashes = sorted(item["sha256"] for item in candidates[name]["artifacts"])
        require(entry["version"] == candidates[name]["proposed_version"], f"{name}: lock version drift")
        require(entry["hashes"] == expected_hashes, f"{name}: lock hash drift")
        require(not entry["parents"], f"{name}: direct Python root has unexpected provenance parents")
    parents_by_child: dict[str, set[str]] = {}
    for name, approved in transitive.items():
        entry = locked.get(name, {})
        require(entry.get("version") == approved.get("version"), f"{name}: Python transitive version drift")
        require(entry.get("parents") == sorted(approved.get("parents", [])), f"{name}: Python parent-chain drift")
        require(
            entry.get("entry_digest_sha256") == approved.get("lock_entry_digest_sha256"),
            f"{name}: Python transitive hash/version/provenance drift",
        )
        require(approved.get("license") in {"MIT", "Apache-2.0", "BSD-3-Clause"}, f"{name}: incompatible license")
        parents_by_child[name] = set(entry["parents"])
    for child, parents in parents_by_child.items():
        require(parents <= set(locked), f"{child}: unresolved provenance parent")
    reached = reachable(expected, parents_by_child)
    require(reached == set(locked), f"unreachable Python resolved packages: {sorted(set(locked) - reached)}")
    return len(expected), len(transitive)


def verify_swift(
    candidates: dict[str, dict[str, Any]], audit: dict[str, Any], package_path: Path, resolved_path: Path
) -> tuple[int, int]:
    candidate = candidates["swift-json-schema"]
    approved = candidate["decision"] == "approved"
    manifest = package_path.read_text(encoding="utf-8")
    declarations = re.findall(r"\.package\s*\(", manifest)
    if approved:
        require(len(declarations) == 1, "Package.swift must contain exactly one approved external package")
        match = re.search(
            r'\.package\s*\(\s*url:\s*"([^"]+)"\s*,\s*exact:\s*"([^"]+)"\s*\)',
            manifest,
            re.DOTALL,
        )
        require(match is not None, "Package.swift must use one exact URL/version requirement")
        expected_url = candidate["artifact"]["source_repository_url"]
        require(match.group(1) == expected_url, "Package.swift swift-json-schema URL drift")
        require(match.group(2) == candidate["proposed_version"], "Package.swift swift-json-schema exact version drift")
    else:
        require(not declarations, "rejected/fallback Swift package remains in Package.swift")

    if not resolved_path.exists():
        require(not approved, "approved Swift dependency has no Package.resolved")
        return 0, 0
    resolved = load_json(resolved_path)
    pins_list = resolved.get("pins", [])
    require(isinstance(pins_list, list), "Package.resolved pins must be an array")
    pins = {pin.get("identity"): pin for pin in pins_list if isinstance(pin, dict)}
    require(len(pins) == len(pins_list), "duplicate or malformed Swift pins")
    if not approved:
        require(not pins, "rejected/fallback Swift external pins remain")
        return 0, 0

    transitives = audit["resolved_transitive_audit"]["swiftpm"]
    require(set(pins) == {"swift-json-schema"} | set(transitives), "Swift pin set contains missing or extraneous packages")
    root = pins["swift-json-schema"]
    require(root.get("location") == candidate["artifact"]["source_repository_url"], "Swift root pin source drift")
    state = root.get("state", {})
    require(state.get("version") == candidate["proposed_version"], "Swift root pin version drift")
    require(state.get("revision") == candidate["proposed_revision"], "Swift root pin revision drift")
    require(HEX_40.fullmatch(state.get("revision", "")) is not None, "Swift root revision is not exact")
    parents_by_child: dict[str, set[str]] = {}
    for name, expected in transitives.items():
        pin = pins[name]
        require(pin.get("location") == expected["location"], f"{name}: Swift source drift")
        state = pin.get("state", {})
        require(state.get("version") == expected["version"], f"{name}: Swift version drift")
        require(state.get("revision") == expected["revision"], f"{name}: Swift revision drift")
        require(HEX_40.fullmatch(state.get("revision", "")) is not None, f"{name}: Swift revision is not exact")
        require(expected.get("license") in {"MIT", "Apache-2.0", "BSD-3-Clause"}, f"{name}: incompatible license")
        parents_by_child[name] = set(expected["parents"])
    reached = reachable({"swift-json-schema"}, parents_by_child)
    require(reached == set(pins), f"unreachable Swift pins: {sorted(set(pins) - reached)}")
    require(HEX_64.fullmatch(resolved.get("originHash", "")) is not None, "Package.resolved originHash is invalid")
    return 1, len(transitives)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit", type=Path, required=True)
    parser.add_argument("--package-json", type=Path, required=True)
    parser.add_argument("--package-lock", type=Path, required=True)
    parser.add_argument("--requirements-in", type=Path, required=True)
    parser.add_argument("--requirements-lock", type=Path, required=True)
    parser.add_argument("--swift-package", type=Path, required=True)
    parser.add_argument("--swift-resolved", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        audit = load_json(args.audit)
        candidates = verify_audit(audit)
        js = verify_javascript(candidates, audit, args.package_json, args.package_lock)
        py = verify_python(candidates, audit, args.requirements_in, args.requirements_lock)
        swift = verify_swift(candidates, audit, args.swift_package, args.swift_resolved)
    except (OSError, VerificationError) as exc:
        print(f"phase-01 dependency verification: FAIL: {exc}", file=sys.stderr)
        return 1
    print(
        "phase-01 dependency verification: PASS "
        f"(6 decisions; direct npm/python/swift={js[0]}/{py[0]}/{swift[0]}; "
        f"audited reachable transitives={js[1] + py[1] + swift[1]})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
