"""Focused provenance tests for the three-runtime agreement publisher."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
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


class SwiftPackageManifestBindingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.package_root = self.root / "ios/Packages/ReRoomContracts"
        self.package_root.mkdir(parents=True)
        self.manifest = self.package_root / "Package.swift"
        self.manifest.write_text(
            "// swift-tools-version: 6.0\nimport PackageDescription\n",
            encoding="utf-8",
        )
        _git(self.root, "init", "--quiet")
        _git(self.root, "config", "user.email", "tests@reroom.invalid")
        _git(self.root, "config", "user.name", "ReRoom Tests")
        (self.root / ".gitignore").write_text(
            "Package@swift-6.swift\n", encoding="utf-8"
        )
        _git(
            self.root,
            "add",
            ".gitignore",
            self.manifest.relative_to(self.root).as_posix(),
        )
        _git(self.root, "commit", "--quiet", "-m", "bound package manifest")
        self.record = {
            "relative_path": "ios/Packages/ReRoomContracts/Package.swift",
            "sha256": PUBLISHER._sha256(self.manifest.read_bytes()),
        }

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _require_manifest(self):
        return PUBLISHER._require_swift_package_manifest(
            self.root, source_records=[self.record]
        )

    def test_selects_only_the_exact_bound_primary_manifest(self) -> None:
        self.assertEqual(self.record, self._require_manifest())

    def test_rejects_major_minor_patch_and_target_redirection_variants(self) -> None:
        cases = (
            ("Package@swift-6.swift", "// major\n"),
            ("Package@swift-06.swift", "// leading-zero major\n"),
            ("Package@swift-6.3.swift", "// minor\n"),
            ("Package@swift-6.3.0.swift", "// patch\n"),
            ("Package@swift-6.3.0.swift", (
                "// swift-tools-version: 6.0\n"
                "import PackageDescription\n"
                "let package = Package(name: \"redirected\", targets: "
                "[.executableTarget(name: \"ReRoomContractRunner\", path: "
                "\"../../../../outside\")])\n"
            )),
        )
        for name, contents in cases:
            with self.subTest(name=name):
                candidate = self.package_root / name
                candidate.write_text(contents, encoding="utf-8")
                with self.assertRaisesRegex(
                    PUBLISHER.AgreementError,
                    "version-specific Swift package manifest",
                ):
                    self._require_manifest()
                candidate.unlink()

    def test_rejects_ignored_and_symlinked_variants(self) -> None:
        ignored = self.package_root / "Package@swift-6.swift"
        ignored.write_text("// ignored\n", encoding="utf-8")
        self.assertEqual(
            "ios/Packages/ReRoomContracts/Package@swift-6.swift",
            _git(
                self.root,
                "check-ignore",
                "ios/Packages/ReRoomContracts/Package@swift-6.swift",
            ),
        )
        with self.assertRaisesRegex(
            PUBLISHER.AgreementError,
            "version-specific Swift package manifest",
        ):
            self._require_manifest()
        ignored.unlink()

        outside = self.root / "outside.swift"
        outside.write_text("// redirected\n", encoding="utf-8")
        ignored.symlink_to(outside)
        with self.assertRaisesRegex(
            PUBLISHER.AgreementError,
            "version-specific Swift package manifest",
        ):
            self._require_manifest()


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

    def test_verifier_rejects_wrong_selected_swift_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            reports = Path(directory)
            self._copy_reports(reports)
            target = reports / "contract-agreement.json"
            report = json.loads(target.read_bytes())
            report["implementation"]["swift_package_manifest"] = {
                "relative_path": "ios/Packages/ReRoomContracts/Package@swift-6.swift",
                "sha256": "0" * 64,
            }
            target.write_text(
                json.dumps(report, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )

            with self.assertRaisesRegex(
                PUBLISHER.AgreementError,
                "Swift package manifest provenance is invalid",
            ):
                PUBLISHER._verify_reports(REPO_ROOT, report_directory=reports)


class ExecutionBindingStabilityTests(unittest.TestCase):
    def test_mutation_during_execution_never_replaces_reports(self) -> None:
        for mutation_target in ("bound_source", "swift_manifest", "publisher"):
            with self.subTest(mutation_target=mutation_target):
                self._assert_mutation_is_rejected(mutation_target)

    def _assert_mutation_is_rejected(self, mutation_target: str) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _git(root, "init", "--quiet")
            _git(root, "config", "user.email", "tests@reroom.invalid")
            _git(root, "config", "user.name", "ReRoom Tests")

            source = root / "source/runner.py"
            source.parent.mkdir(parents=True)
            source.write_text("value = 1\n", encoding="utf-8")
            package_manifest = root / PUBLISHER.SWIFT_PACKAGE_MANIFEST_RELATIVE_PATH
            package_manifest.parent.mkdir(parents=True)
            package_manifest.write_text(
                "// swift-tools-version: 6.0\nimport PackageDescription\n",
                encoding="utf-8",
            )
            _git(
                root,
                "add",
                "source/runner.py",
                PUBLISHER.SWIFT_PACKAGE_MANIFEST_RELATIVE_PATH,
            )
            _git(root, "commit", "--quiet", "-m", "bound source")
            revision = _git(root, "rev-parse", "HEAD")

            publisher = root / PUBLISHER.PUBLISHER_RELATIVE_PATH
            publisher.parent.mkdir(parents=True)
            shutil.copyfile(PUBLISHER_PATH, publisher)

            manifest_relative = "fixtures/test/manifest.json"
            manifest = root / manifest_relative
            manifest.parent.mkdir(parents=True)
            manifest.write_text(
                json.dumps(
                    {
                        "fixture_id": "FX-TEST-001",
                        "fixture_revision": "rev-001",
                        "cases": [{"case_id": "case-001"}],
                        "schema_hashes": [],
                    }
                ),
                encoding="utf-8",
            )
            (root / "fixtures/manifest.schema.json").write_text("{}\n", encoding="utf-8")
            (root / "fixtures/runner-result.schema.json").write_text("{}\n", encoding="utf-8")
            contracts = root / "docs/contracts"
            contracts.mkdir(parents=True)
            (contracts / "README.md").write_text("frozen\n", encoding="utf-8")
            comparator = root / "tools/verify/compare_results.py"
            comparator.parent.mkdir(parents=True)
            comparator.write_text("# frozen comparator\n", encoding="utf-8")

            report = root / "evidence/compatibility/test-agreement.json"
            report.parent.mkdir(parents=True)
            baseline = b"previous verified report\n"
            report.write_bytes(baseline)

            original_run = PUBLISHER._run
            implementation_revision = f"git:{revision}"
            mutated = False

            def fake_run(command, *, root, label, timeout=PUBLISHER.COMMAND_TIMEOUT_SECONDS):
                nonlocal mutated
                if label in {
                    "bound implementation revision",
                    "bound implementation source listing",
                }:
                    return original_run(command, root=root, label=label, timeout=timeout)
                if label == "Swift binary path":
                    return subprocess.CompletedProcess(command, 0, stdout=str(root / "bin"), stderr="")
                if label.endswith(("Swift runner", "JavaScript runner", "Python runner")):
                    runtime = {
                        "Swift runner": "swift",
                        "JavaScript runner": "javascript",
                        "Python runner": "python",
                    }[label.rsplit(" ", 2)[-2] + " runner"]
                    output = Path(command[command.index("--output") + 1])
                    runner_name, runner_version = PUBLISHER.RUNNERS[runtime]
                    output.write_text(
                        json.dumps(
                            {
                                "runner": {
                                    "runtime": runtime,
                                    "name": runner_name,
                                    "version": runner_version,
                                    "implementation_revision": implementation_revision,
                                },
                                "case_results": [
                                    {"case_id": "case-001", "verdict": "accept"}
                                ],
                                "result_digest_sha256": "0" * 64,
                            },
                            sort_keys=True,
                        )
                        + "\n",
                        encoding="utf-8",
                    )
                elif label.endswith("three-runtime comparator") and not mutated:
                    if mutation_target == "bound_source":
                        target = source
                    elif mutation_target == "swift_manifest":
                        target = package_manifest.with_name("Package@swift-6.swift")
                    else:
                        target = publisher
                    with target.open("ab") as handle:
                        handle.write(b"# concurrent mutation\n")
                    mutated = True
                return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

            previous_directory = Path.cwd()
            try:
                with (
                    mock.patch.object(PUBLISHER, "BOUND_REVISION", revision),
                    mock.patch.object(PUBLISHER, "IMPLEMENTATION_REVISION", implementation_revision),
                    mock.patch.object(
                        PUBLISHER,
                        "BOUND_SOURCE_SCOPES",
                        ("source", PUBLISHER.SWIFT_PACKAGE_MANIFEST_RELATIVE_PATH),
                    ),
                    mock.patch.object(
                        PUBLISHER,
                        "MANIFESTS",
                        (
                            (
                                "test",
                                "FX-TEST-001",
                                manifest_relative,
                                report.name,
                                ("NFR-CONTRACT-001",),
                                ("TST-CONTRACT-001",),
                            ),
                        ),
                    ),
                    mock.patch.object(PUBLISHER, "_repo_root", return_value=root),
                    mock.patch.object(
                        PUBLISHER,
                        "_resolve_executable",
                        return_value=root / "fake-executable",
                    ),
                    mock.patch.object(PUBLISHER, "_environment", return_value={}),
                    mock.patch.object(PUBLISHER, "_run", side_effect=fake_run),
                    mock.patch.object(
                        PUBLISHER,
                        "_atomic_write_reports",
                        wraps=PUBLISHER._atomic_write_reports,
                    ) as atomic_write,
                ):
                    expected = {
                        "bound_source": "bound implementation sources differ",
                        "swift_manifest": "version-specific Swift package manifest",
                        "publisher": "publisher changed during agreement execution",
                    }[mutation_target]
                    with self.assertRaisesRegex(PUBLISHER.AgreementError, expected):
                        PUBLISHER.run()
                    atomic_write.assert_not_called()
            finally:
                os.chdir(previous_directory)

            self.assertTrue(mutated)
            self.assertEqual(baseline, report.read_bytes())


if __name__ == "__main__":
    unittest.main()
