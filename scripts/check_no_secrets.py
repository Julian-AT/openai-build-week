#!/usr/bin/env python3
"""Conservative, dependency-free repository secret scanner."""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path


SKIP_DIRS = {".git", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", "node_modules"}
SKIP_FILES = {Path(__file__).name}
MAX_TEXT_BYTES = 2_000_000

TOKEN_PATTERNS = (
    ("OpenAI-style key", re.compile(r"\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{16,}\b")),
    ("Firecrawl-style key", re.compile(r"\bfc-[A-Za-z0-9_-]{16,}\b")),
    ("AWS access key", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("GitHub token", re.compile(r"\bgh[opusr]_[A-Za-z0-9]{20,}\b")),
    ("Google API key", re.compile(r"\bAIza[0-9A-Za-z_-]{30,}\b")),
    ("private key material", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----")),
)

ASSIGNMENT = re.compile(
    r"(?i)\b(api[_-]?key|client[_-]?secret|access[_-]?token|auth[_-]?token|password|passwd)"
    r"\s*[:=]\s*([\"']?)([^\s,;#\"']+)\2"
)

PLACEHOLDER_VALUES = {
    "",
    "null",
    "none",
    "redacted",
    "placeholder",
    "replace_me",
    "changeme",
    "example",
    "example_value",
}


def is_placeholder(value: str) -> bool:
    lowered = value.strip().lower()
    return (
        lowered in PLACEHOLDER_VALUES
        or lowered.startswith("<") and lowered.endswith(">")
        or lowered.startswith("${") and lowered.endswith("}")
        or lowered.startswith("$env:")
        or lowered.startswith("your_")
        or lowered.startswith("example_")
        or "do-not-store" in lowered
        or "set-in-private" in lowered
    )


def is_unquoted_code_reference(key: str, quote: str, value: str) -> bool:
    if quote:
        return False
    normalize = lambda text: re.sub(r"[^a-z0-9]", "", text.lower())
    key_name = normalize(key)
    value_name = normalize(value)
    return (
        value_name in {"string", "substring", "str", "bytes", "data"}
        or value_name == key_name
        or value_name == f"current{key_name}"
    )


def iter_files(root: Path):
    for current, dirs, files in os.walk(root):
        dirs[:] = [name for name in dirs if name not in SKIP_DIRS]
        base = Path(current)
        for name in files:
            path = base / name
            if name in SKIP_FILES or path.is_symlink():
                continue
            yield path


def read_text(path: Path) -> str | None:
    try:
        if path.stat().st_size > MAX_TEXT_BYTES:
            return None
        data = path.read_bytes()
    except OSError:
        return None
    if b"\x00" in data:
        return None
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


def scan(root: Path) -> list[tuple[Path, int, str]]:
    findings: list[tuple[Path, int, str]] = []
    for path in iter_files(root):
        text = read_text(path)
        if text is None:
            continue
        rel = path.relative_to(root)
        for line_number, line in enumerate(text.splitlines(), 1):
            for label, pattern in TOKEN_PATTERNS:
                if pattern.search(line):
                    findings.append((rel, line_number, label))
            for match in ASSIGNMENT.finditer(line):
                value = match.group(3)
                if rel.as_posix() == ".env.example" and value == "":
                    continue
                if not is_placeholder(value) and not is_unquoted_code_reference(
                    match.group(1), match.group(2), value
                ):
                    findings.append((rel, line_number, f"non-placeholder {match.group(1)} assignment"))
    return sorted(set(findings), key=lambda item: (str(item[0]), item[1], item[2]))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    root = Path(args.root).resolve()
    findings = scan(root)
    if findings:
        for path, line, label in findings:
            print(f"FAIL {path}:{line}: possible {label}")
        print(f"Secret scan: FAIL ({len(findings)} finding(s))")
        return 1
    print("Secret scan: PASS (no obvious plaintext credentials)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
