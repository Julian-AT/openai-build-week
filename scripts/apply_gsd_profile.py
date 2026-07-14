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
import json
import os
import shutil
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


PROFILE_NAMES = ("quality-fast", "maximum-assurance")
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


def load_json_object(path: Path, label: str) -> dict[str, Any]:
    if not path.exists():
        raise ProfileError(f"{label} does not exist: {path}")
    if not path.is_file() or path.is_symlink():
        raise ProfileError(f"{label} must be a regular, non-symlink file: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError) as exc:
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


def deep_merge(base: dict[str, Any], overlay: dict[str, Any]) -> dict[str, Any]:
    merged = copy.deepcopy(base)
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = copy.deepcopy(value)
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


def atomic_write(path: Path, content: str) -> None:
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            newline="\n",
            delete=False,
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
        ) as handle:
            temporary_path = Path(handle.name)
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, path)
        temporary_path = None
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def main() -> int:
    args = parse_args()
    repository_root = Path(__file__).resolve().parents[1]
    active_path = repository_root / ".planning" / "config.json"
    profile_path = (
        repository_root
        / "docs"
        / "gsd"
        / "profiles"
        / f"{args.profile}.config.json"
    )

    try:
        active = load_json_object(active_path, "generated GSD config")
        profile = load_json_object(profile_path, "reviewed GSD profile")

        secret_paths = sorted(
            set(find_secret_like_keys(active) + find_secret_like_keys(profile))
        )
        if secret_paths:
            joined = ", ".join(secret_paths)
            raise ProfileError(
                "Refusing to display, back up, or rewrite JSON containing "
                f"secret-like keys: {joined}. Keep secrets outside GSD config."
            )

        merged = deep_merge(active, profile)
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

        backup_path = unique_backup_path(active_path)
        shutil.copy2(active_path, backup_path)
        try:
            atomic_write(active_path, after)
        except Exception:
            shutil.copy2(backup_path, active_path)
            raise

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
