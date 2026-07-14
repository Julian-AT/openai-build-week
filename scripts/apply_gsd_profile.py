#!/usr/bin/env python3
"""Safely merge one reviewed ReRoom GSD profile into generated GSD config.

This utility never invokes GSD. It reads only the selected repository profile
and .planning/config.json, shows a complete JSON diff, requires confirmation by
default, creates a timestamped backup, and replaces the config atomically.
"""

from __future__ import annotations

import argparse
import copy
import difflib
import hashlib
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


PROFILE_NAMES = ("quality-fast", "quality")
PROFILE_SHA256 = {
    "quality-fast": "043107e1e67c42118f30451c305312991887c043f2eaaec0473fa05446110321",
    "quality": "4ade86239f171e0eab8780d527fd9b7520c482827438643d45cafac60cbd9269",
}
REPLACE_TOP_LEVEL_MAPS = (
    "models",
    "model_overrides",
    "model_profile_overrides",
    "granularities",
)
STALE_TOP_LEVEL_KEYS = ("model_policy", "dynamic_routing", "fast_mode")
SECRET_KEY_NAMES = {
    "access_key",
    "apikey",
    "api_key",
    "authorization",
    "client_secret",
    "credential",
    "password",
    "passwd",
    "private_key",
    "secret",
    "token",
}
SECRET_KEY_PREFIXES = (
    "authorization_",
    "credential_",
    "password_",
    "secret_",
    "token_",
)
SECRET_KEY_SUFFIXES = (
    "_access_key",
    "_api_key",
    "_authorization",
    "_client_secret",
    "_credential",
    "_password",
    "_private_key",
    "_secret",
    "_token",
)
SECRET_BEARING_INTEGRATION_KEYS = {
    "brave_search",
    "exa_search",
    "firecrawl",
}


class ProfileError(RuntimeError):
    """Raised for a safe, user-actionable profile application failure."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Merge a reviewed GSD profile into .planning/config.json."
    )
    parser.add_argument("profile", choices=PROFILE_NAMES)
    parser.add_argument(
        "--yes",
        action="store_true",
        help="Apply after printing the diff without an interactive prompt.",
    )
    return parser.parse_args()


def is_link_like(path: Path) -> bool:
    is_junction = getattr(path, "is_junction", None)
    return path.is_symlink() or bool(is_junction and is_junction())


def read_regular_file_bytes(
    path: Path, label: str, repository_root: Path
) -> bytes:
    if not path.exists():
        raise ProfileError(f"{label} does not exist: {path}")
    if not path.is_file() or is_link_like(path):
        raise ProfileError(f"{label} must be a regular, non-link file: {path}")
    resolved_root = repository_root.resolve(strict=True)
    try:
        resolved_path = path.resolve(strict=True)
        resolved_path.relative_to(resolved_root)
    except (OSError, ValueError) as exc:
        raise ProfileError(
            f"{label} must resolve inside the repository: {path}"
        ) from exc
    current = path
    while current != repository_root:
        if is_link_like(current):
            raise ProfileError(f"{label} path contains a link/junction: {current}")
        if current.parent == current:
            raise ProfileError(f"{label} path escapes the repository: {path}")
        current = current.parent
    try:
        return path.read_bytes()
    except OSError as exc:
        raise ProfileError(f"Cannot read {label}: {path}: {exc}") from exc


def load_json_object(raw: bytes, path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(raw.decode("utf-8"))
    except UnicodeError as exc:
        raise ProfileError(f"Cannot read {label}: {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ProfileError(
            f"Malformed JSON in {label}: {path}:{exc.lineno}:{exc.colno}: {exc.msg}"
        ) from exc
    if not isinstance(value, dict):
        raise ProfileError(f"{label} must contain one top-level JSON object: {path}")
    return value


def find_secret_like_keys(value: Any, path: tuple[str, ...] = ()) -> list[str]:
    findings: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            key_text = str(key)
            normalized = key_text.lower().replace("-", "_").replace(" ", "_")
            child_path = path + (key_text,)
            looks_secret = (
                normalized in SECRET_KEY_NAMES
                or normalized.startswith(SECRET_KEY_PREFIXES)
                or normalized.endswith(SECRET_KEY_SUFFIXES)
            )
            if looks_secret:
                findings.append(".".join(child_path))
            elif (
                normalized in SECRET_BEARING_INTEGRATION_KEYS
                and isinstance(child, str)
            ):
                findings.append(".".join(child_path))
            findings.extend(find_secret_like_keys(child, child_path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            findings.extend(find_secret_like_keys(child, path + (f"[{index}]",)))
    return findings


def find_credential_like_values(
    value: Any, path: tuple[str, ...] = ()
) -> list[str]:
    findings: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            findings.extend(find_credential_like_values(child, path + (str(key),)))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            findings.extend(
                find_credential_like_values(child, path + (f"[{index}]",))
            )
    elif isinstance(value, str):
        parsed = urlparse(value)
        has_url_userinfo = bool(parsed.scheme and (parsed.username or parsed.password))
        has_private_key = bool(
            re.search(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----", value)
        )
        has_auth_header = bool(re.match(r"(?i)^(?:bearer|basic)\s+\S+", value))
        has_known_token_shape = bool(
            re.match(
                r"(?i)^(?:sk|rk|pk|ghp|github_pat|xox[baprs])[-_][A-Za-z0-9_-]{16,}$",
                value,
            )
        )
        if has_url_userinfo or has_private_key or has_auth_header or has_known_token_shape:
            findings.append(".".join(path) or "<root>")
    return findings


def deep_merge(base: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
    merged = copy.deepcopy(base)
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = copy.deepcopy(value)
    return merged


def merge_profile(
    active: dict[str, Any], profile: dict[str, Any]
) -> dict[str, Any]:
    merged = deep_merge(active, profile)
    for key in REPLACE_TOP_LEVEL_MAPS:
        if key in profile:
            merged[key] = copy.deepcopy(profile[key])
    if isinstance(profile.get("effort"), dict) and "agent_overrides" in profile["effort"]:
        if not isinstance(merged.get("effort"), dict):
            merged["effort"] = {}
        merged["effort"]["agent_overrides"] = copy.deepcopy(
            profile["effort"]["agent_overrides"]
        )
    for key in STALE_TOP_LEVEL_KEYS:
        merged.pop(key, None)
    return merged


def render_json(value: dict[str, Any]) -> str:
    return json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def make_diff(before: str, after: str, active_path: Path, profile_name: str) -> str:
    return "".join(
        difflib.unified_diff(
            before.splitlines(keepends=True),
            after.splitlines(keepends=True),
            fromfile=str(active_path),
            tofile=f"{active_path} + {profile_name}",
        )
    )


def unique_backup_path(active_path: Path) -> Path:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    candidate = active_path.with_name(f"{active_path.name}.backup-{timestamp}")
    counter = 1
    while candidate.exists():
        candidate = active_path.with_name(
            f"{active_path.name}.backup-{timestamp}-{counter}"
        )
        counter += 1
    return candidate


def ensure_no_workstream(repository_root: Path) -> None:
    if os.environ.get("GSD_WORKSTREAM", "").strip():
        raise ProfileError(
            "GSD_WORKSTREAM is active; deactivate or align the workstream before "
            "applying a root profile."
        )
    workstreams = repository_root / ".planning" / "workstreams"
    if workstreams.exists():
        if is_link_like(workstreams) or not workstreams.is_dir():
            raise ProfileError(
                f"Workstream path must be a regular directory: {workstreams}"
            )
        configs = sorted(workstreams.glob("*/config.json"))
        if configs:
            raise ProfileError(
                "Workstream config exists; align or deactivate workstream overlays "
                "before applying a root-only profile."
            )


def write_exact_backup(path: Path, content: bytes) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    descriptor = os.open(path, flags, 0o600)
    try:
        with os.fdopen(descriptor, "wb", closefd=True) as handle:
            descriptor = -1
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
    finally:
        if descriptor >= 0:
            os.close(descriptor)


def atomic_write(
    path: Path,
    content: bytes,
    expected_active: bytes,
    repository_root: Path,
) -> None:
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb",
            delete=False,
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
        ) as handle:
            temporary_path = Path(handle.name)
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        current = read_regular_file_bytes(path, "generated GSD config", repository_root)
        if current != expected_active:
            raise ProfileError(
                "Generated GSD config changed after backup; refusing concurrent overwrite."
            )
        os.replace(temporary_path, path)
        temporary_path = None
        written = read_regular_file_bytes(path, "generated GSD config", repository_root)
        if written != content:
            raise ProfileError("Atomic replacement verification failed.")
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def main() -> int:
    args = parse_args()
    repository_root = Path(__file__).resolve().parents[1].resolve(strict=True)
    active_path = repository_root / ".planning" / "config.json"
    profile_path = (
        repository_root
        / "docs"
        / "gsd"
        / "profiles"
        / f"{args.profile}.config.json"
    )

    try:
        ensure_no_workstream(repository_root)
        active_bytes = read_regular_file_bytes(
            active_path, "generated GSD config", repository_root
        )
        profile_bytes = read_regular_file_bytes(
            profile_path, "reviewed GSD profile", repository_root
        )
        actual_profile_sha = hashlib.sha256(profile_bytes).hexdigest()
        expected_profile_sha = PROFILE_SHA256[args.profile]
        if actual_profile_sha != expected_profile_sha:
            raise ProfileError(
                f"Reviewed profile byte hash mismatch for {args.profile}: "
                f"{actual_profile_sha}, expected {expected_profile_sha}."
            )
        active = load_json_object(active_bytes, active_path, "generated GSD config")
        profile = load_json_object(profile_bytes, profile_path, "reviewed GSD profile")

        secret_paths = sorted(
            set(find_secret_like_keys(active) + find_secret_like_keys(profile))
        )
        credential_paths = sorted(
            set(
                find_credential_like_values(active)
                + find_credential_like_values(profile)
            )
        )
        if secret_paths or credential_paths:
            findings = []
            if secret_paths:
                findings.append("secret-like keys: " + ", ".join(secret_paths))
            if credential_paths:
                findings.append(
                    "credential-shaped values: " + ", ".join(credential_paths)
                )
            raise ProfileError(
                "Refusing to display, back up, or rewrite JSON containing "
                + "; ".join(findings)
                + ". Keep secrets outside GSD config."
            )

        merged = merge_profile(active, profile)
        before = render_json(active)
        after = render_json(merged)
        diff = make_diff(before, after, active_path, args.profile)

        print(f"Repository: {repository_root}")
        print(f"Profile:    {args.profile}")
        print(f"Config:     {active_path}")
        print("\nProposed changes:\n")
        print(diff if diff else "(no changes)")

        if not diff:
            print("Config already matches the selected profile; nothing written.")
            return 0

        if not args.yes:
            response = input("Type 'apply' to create a backup and write this config: ")
            if response.strip() != "apply":
                print("Cancelled; no files were changed.")
                return 1

        current_bytes = read_regular_file_bytes(
            active_path, "generated GSD config", repository_root
        )
        if current_bytes != active_bytes:
            raise ProfileError(
                "Generated GSD config changed after preview; refusing concurrent overwrite."
            )
        backup_path = unique_backup_path(active_path)
        write_exact_backup(backup_path, active_bytes)
        atomic_write(
            active_path,
            after.encode("utf-8"),
            active_bytes,
            repository_root,
        )

        print(f"Applied profile '{args.profile}'.")
        print(f"Backup: {backup_path}")
        return 0
    except ProfileError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    except (OSError, UnicodeError) as exc:
        print(f"error: filesystem operation failed: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
