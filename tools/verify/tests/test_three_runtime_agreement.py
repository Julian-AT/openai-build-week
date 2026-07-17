"""Focused provenance tests for the three-runtime agreement publisher."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[3]
PUBLISHER_PATH = REPO_ROOT / "scripts/run-three-runtime-agreement"
REPORT_NAMES = (
    "contract-agreement.json",
    "jcs-agreement.json",
    "coordinate-agreement.json",
)


def _load_publisher():
    loader = importlib.machinery.SourceFileLoader(
        "reroom_three_runtime_agreement", str(PUBLISHER_PATH)
    )
    spec = importlib.util.spec_from_loader(loader.name, loader)
    if spec is None:
        raise RuntimeError("three-runtime publisher import spec is unavailable")
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


PUBLISHER = _load_publisher()


def _git(root: Path, *arguments: str) -> str:
    completed = subprocess.run(
        ["git", *arguments],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout.strip()


class BoundSourceSetTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        _git(self.root, "init", "--quiet")
        _git(self.root, "config", "user.email", "tests@reroom.invalid")
        _git(self.root, "config", "user.name", "ReRoom Tests")
        (self.root / ".gitignore").write_text(
            "ignored.swift\nignored.mjs\nignored.py\n__pycache__/\n*.pyc\n",
            encoding="utf-8",
        )
        tracked = {
            "swift/Main.swift": "let value = 1\n",
            "javascript/runner.mjs": "export const value = 1;\n",
            "python/runner.py": "value = 1\n",
        }
        for relative, contents in tracked.items():
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents, encoding="utf-8")
        _git(self.root, "add", ".gitignore", *tracked)
        _git(self.root, "commit", "--quiet", "-m", "fixture")
        self.revision = _git(self.root, "rev-parse", "HEAD")
        self.scopes = ("swift", "javascript", "python")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _require_bound_sources(self):
        with (
            mock.patch.object(PUBLISHER, "BOUND_REVISION", self.revision),
            mock.patch.object(PUBLISHER, "BOUND_SOURCE_SCOPES", self.scopes),
        ):
            return PUBLISHER._require_bound_sources(self.root)

    def test_rejects_untracked_and_ignored_executable_sources(self) -> None:
        cases = (
            ("swift/extra.swift", False),
            ("swift/ignored.swift", True),
            ("javascript/extra.mjs", False),
            ("javascript/ignored.mjs", True),
            ("python/extra.py", False),
            ("python/ignored.py", True),
        )
        for relative, ignored in cases:
            with self.subTest(relative=relative, ignored=ignored):
                path = self.root / relative
                path.write_text("unexpected\n", encoding="utf-8")
                if ignored:
                    self.assertEqual(relative, _git(self.root, "check-ignore", relative))
                with self.assertRaisesRegex(
                    PUBLISHER.AgreementError,
                    "outside the bound implementation revision",
                ):
                    self._require_bound_sources()
                path.unlink()

    def test_rejects_non_regular_and_mode_mismatched_bound_paths(self) -> None:
        source = self.root / "python/runner.py"
        replacement = self.root / "replacement.py"
        replacement.write_text("value = 1\n", encoding="utf-8")
        source.unlink()
        source.symlink_to(replacement)
        with self.assertRaisesRegex(
            PUBLISHER.AgreementError, "not a regular file"
        ):
            self._require_bound_sources()

        source.unlink()
        source.write_text("value = 1\n", encoding="utf-8")
        source.chmod(source.stat().st_mode | 0o111)
        with self.assertRaisesRegex(
            PUBLISHER.AgreementError, "mode differs from the bound revision"
        ):
            self._require_bound_sources()

    def test_ignores_python_bytecode_that_is_isolated_from_execution(self) -> None:
        cache = self.root / "python/__pycache__"
        cache.mkdir()
        (cache / "runner.cpython-313.pyc").write_bytes(b"not executable here")

        records = self._require_bound_sources()

        self.assertEqual(
            ["javascript/runner.mjs", "python/runner.py", "swift/Main.swift"],
            [record["relative_path"] for record in records],
        )


class ReportProvenanceTests(unittest.TestCase):
    def _copy_reports(self, destination: Path) -> None:
        source = REPO_ROOT / "evidence/compatibility"
        for name in REPORT_NAMES:
            shutil.copyfile(source / name, destination / name)

    def test_checked_in_reports_bind_the_exact_metric_publisher(self) -> None:
        fixture_ids = PUBLISHER._verify_reports(REPO_ROOT)

        self.assertEqual(
            ("FX-CONTRACT-001", "FX-JCS-001", "FX-COORD-001"), fixture_ids
        )

    def test_verifier_rejects_missing_and_wrong_publisher_provenance(self) -> None:
        mutations = (
            ("missing", lambda report: report.pop("publisher", None)),
            (
                "wrong",
                lambda report: report["publisher"].update(sha256="0" * 64),
            ),
        )
        for label, mutate in mutations:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as directory:
                reports = Path(directory)
                self._copy_reports(reports)
                target = reports / "contract-agreement.json"
                report = json.loads(target.read_bytes())
                mutate(report)
                target.write_text(
                    json.dumps(report, indent=2, sort_keys=True) + "\n",
                    encoding="utf-8",
                )

                with self.assertRaisesRegex(
                    PUBLISHER.AgreementError,
                    "publisher provenance is invalid",
                ):
                    PUBLISHER._verify_reports(REPO_ROOT, report_directory=reports)

    def test_verifier_rejects_noncanonical_jcs_test_trace(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            reports = Path(directory)
            self._copy_reports(reports)
            target = reports / "jcs-agreement.json"
            report = json.loads(target.read_bytes())
            report["test_ids"] = ["TST-CONTRACT-001"]
            target.write_text(
                json.dumps(report, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(
                PUBLISHER.AgreementError,
                "canonical test IDs are invalid",
            ):
                PUBLISHER._verify_reports(REPO_ROOT, report_directory=reports)


if __name__ == "__main__":
    unittest.main()
