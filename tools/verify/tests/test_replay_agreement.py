"""Mutation and publication gates for Phase 02 replay agreement."""

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

from tools.verify.compare_replay_reports import (
    ReplayComparisonError,
    canonical_bytes,
    compare_replay_reports,
    verify_fixture_integrity,
)


REPO_ROOT = Path(__file__).resolve().parents[3]
MANIFEST = REPO_ROOT / "fixtures/capture/1.0.0/rev-001/manifest.json"
PUBLISHER_PATH = REPO_ROOT / "scripts/run-phase-02-replay-agreement"
RUNTIMES = ("swift", "node", "python")


def _load_publisher():
    loader = importlib.machinery.SourceFileLoader(
        "reroom_phase_02_replay_agreement", str(PUBLISHER_PATH)
    )
    spec = importlib.util.spec_from_loader(loader.name, loader)
    if spec is None:
        raise RuntimeError("replay agreement publisher import spec is unavailable")
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


PUBLISHER = _load_publisher()


def _run(command: list[str]) -> str:
    completed = subprocess.run(
        command,
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout.strip()


def _report_path(root: Path, case_id: str) -> Path:
    return root / f"{case_id}.replay-report.json"


def _resign(path: Path, mutate) -> None:
    report = json.loads(path.read_bytes())
    mutate(report)
    unsigned = dict(report)
    del unsigned["report_sha256"]
    report["report_sha256"] = PUBLISHER._sha256(canonical_bytes(unsigned))
    path.write_bytes(canonical_bytes(report))


class FreshRuntimeOutputs(unittest.TestCase):
    """One actual Swift/Node/Python generation shared by comparator mutations."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="reroom-replay-agreement-tests-")
        cls.root = Path(cls.temporary.name)
        _run(
            [
                "swift",
                "build",
                "--package-path",
                "apps/ios/Packages/ReRoomContracts",
                "--product",
                "ReRoomReplayRunner",
            ]
        )
        binary_root = Path(
            _run(
                [
                    "swift",
                    "build",
                    "--package-path",
                    "apps/ios/Packages/ReRoomContracts",
                    "--show-bin-path",
                ]
            )
        )
        common = [
            "--manifest",
            str(MANIFEST),
            "--repo-root",
            str(REPO_ROOT),
            "--implementation-revision",
            PUBLISHER.IMPLEMENTATION_REVISION,
        ]
        commands = {
            "swift": [str(binary_root / "ReRoomReplayRunner")],
            "node": ["node", "packages/contracts/src/replay.ts"],
            "python": [str(REPO_ROOT / ".venv/bin/python"), "-m", "tools.python.reroom_verify.replay"],
        }
        for runtime, command in commands.items():
            _run([*command, *common, "--output-root", str(cls.root / runtime)])

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def copied_outputs(self, parent: Path) -> dict[str, Path]:
        outputs: dict[str, Path] = {}
        for runtime in RUNTIMES:
            destination = parent / runtime
            shutil.copytree(self.root / runtime, destination)
            outputs[runtime] = destination
        return outputs

    def compare(self, outputs: dict[str, Path]):
        return compare_replay_reports(
            MANIFEST,
            outputs,
            repo_root=REPO_ROOT,
            implementation_revision=PUBLISHER.IMPLEMENTATION_REVISION,
        )

    def test_actual_outputs_form_one_complete_zero_disagreement_artifact(self) -> None:
        result = self.compare({runtime: self.root / runtime for runtime in RUNTIMES})

        self.assertEqual(16, len(result.cases))
        self.assertEqual(RUNTIMES, result.runtimes)
        self.assertEqual(0, result.missing_cases)
        self.assertEqual(0, result.extra_cases)
        self.assertEqual(0, result.semantic_disagreements)
        self.assertEqual(
            [case.case_id for case in result.cases],
            sorted(case.case_id for case in result.cases),
        )

    def test_omitted_extra_and_stale_report_sets_fail_closed(self) -> None:
        mutations = ("omitted", "extra", "stale")
        for mutation in mutations:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                outputs = self.copied_outputs(Path(directory))
                if mutation == "omitted":
                    _report_path(outputs["swift"], "fr-b0.empty").unlink()
                    expected = "missing_case:swift:fr-b0.empty"
                elif mutation == "extra":
                    shutil.copyfile(
                        _report_path(outputs["swift"], "fr-b0.empty"),
                        outputs["swift"] / "unexpected.replay-report.json",
                    )
                    expected = "extra_case:swift:unexpected"
                else:
                    target = _report_path(outputs["python"], "fr-b0.empty")
                    _resign(
                        target,
                        lambda report: report["implementation"].update(
                            repository_revision="git:" + "0" * 40
                        ),
                    )
                    expected = "stale_result:python:fr-b0.empty"
                with self.assertRaisesRegex(ReplayComparisonError, expected):
                    self.compare(outputs)

    def test_runtime_digest_and_semantic_mutations_have_stable_kills(self) -> None:
        mutations = ("runtime", "digest", "semantic")
        for mutation in mutations:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                outputs = self.copied_outputs(Path(directory))
                target = _report_path(outputs["node"], "fr-capture.ordering")
                if mutation == "runtime":
                    _resign(
                        target,
                        lambda report: report["implementation"].update(runtime="node-v0.0.0"),
                    )
                    expected = "runtime_identity:node:fr-capture.ordering"
                elif mutation == "digest":
                    report = json.loads(target.read_bytes())
                    report["report_sha256"] = "0" * 64
                    target.write_bytes(canonical_bytes(report))
                    expected = "report_digest:node:fr-capture.ordering"
                else:
                    _resign(target, lambda report: report.update(verdict="accept", rejection=None))
                    expected = "oracle_mismatch:node:fr-capture.ordering:verdict"
                with self.assertRaisesRegex(ReplayComparisonError, expected):
                    self.compare(outputs)

    def test_fixture_integrity_mutation_fails_before_comparison(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture_root = Path(directory) / "rev-001"
            shutil.copytree(MANIFEST.parent, fixture_root)
            raw = fixture_root / "archives/finalized-one-frame.rrcap/events/event_0000.json"
            mutated = bytearray(raw.read_bytes())
            mutated[-2] ^= 1
            raw.write_bytes(mutated)

            with self.assertRaisesRegex(ReplayComparisonError, "fixture_file_sha256"):
                verify_fixture_integrity(
                    fixture_root / "manifest.json", repo_root=REPO_ROOT
                )


class SourceClosureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="reroom-replay-source-")
        self.root = Path(self.temporary.name)
        subprocess.run(["git", "init", "--quiet"], cwd=self.root, check=True)
        subprocess.run(
            ["git", "config", "user.email", "tests@reroom.invalid"],
            cwd=self.root,
            check=True,
        )
        subprocess.run(
            ["git", "config", "user.name", "ReRoom Tests"],
            cwd=self.root,
            check=True,
        )
        source = self.root / "runtime/replay.py"
        source.parent.mkdir(parents=True)
        source.write_text("value = 1\n", encoding="utf-8")
        subprocess.run(["git", "add", "runtime/replay.py"], cwd=self.root, check=True)
        subprocess.run(
            ["git", "commit", "--quiet", "-m", "bound runtime"],
            cwd=self.root,
            check=True,
        )
        self.revision = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=self.root,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def require_sources(self):
        with (
            mock.patch.object(PUBLISHER, "BOUND_REVISION", self.revision),
            mock.patch.object(PUBLISHER, "BOUND_SOURCE_SCOPES", ("runtime",)),
        ):
            return PUBLISHER._require_bound_sources(self.root)

    def test_rejects_untracked_ignored_symlinked_executable_and_drifted_sources(self) -> None:
        mutations = ("untracked", "ignored", "symlink", "executable", "drift")
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                source = self.root / "runtime/replay.py"
                extra = self.root / "runtime/extra.py"
                ignore = self.root / ".gitignore"
                if mutation == "untracked":
                    extra.write_text("value = 2\n", encoding="utf-8")
                elif mutation == "ignored":
                    ignore.write_text("runtime/extra.py\n", encoding="utf-8")
                    extra.write_text("value = 2\n", encoding="utf-8")
                elif mutation == "symlink":
                    source.unlink()
                    source.symlink_to(self.root / ".git/HEAD")
                elif mutation == "executable":
                    source.chmod(source.stat().st_mode | 0o111)
                else:
                    source.write_text("value = 2\n", encoding="utf-8")
                with self.assertRaises(PUBLISHER.AgreementError):
                    self.require_sources()
                if extra.exists() or extra.is_symlink():
                    extra.unlink()
                if ignore.exists():
                    ignore.unlink()
                if source.is_symlink():
                    source.unlink()
                    source.write_text("value = 1\n", encoding="utf-8")
                else:
                    source.write_text("value = 1\n", encoding="utf-8")
                source.chmod(0o644)


class EvidenceTransactionTests(unittest.TestCase):
    def test_replacement_fault_restores_previous_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "replay-agreement.json"
            old = b'{"generation":"old"}\n'
            target.write_bytes(old)
            with (
                mock.patch.object(
                    PUBLISHER,
                    "_replace_evidence_path",
                    side_effect=OSError("injected replacement fault"),
                ),
                self.assertRaisesRegex(PUBLISHER.AgreementError, "previous evidence was restored"),
            ):
                PUBLISHER._atomic_write_evidence(target, b'{"generation":"new"}\n')
            self.assertEqual(old, target.read_bytes())
            self.assertFalse((Path(directory) / PUBLISHER.TRANSACTION_DIRECTORY_NAME).exists())

    def test_restart_recovers_interrupted_prepared_generation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "replay-agreement.json"
            old = b'{"generation":"old"}\n'
            target.write_bytes(old)

            def replace_then_interrupt(source: Path, destination: Path) -> None:
                os.replace(source, destination)
                raise KeyboardInterrupt("simulated termination")

            with (
                mock.patch.object(
                    PUBLISHER,
                    "_replace_evidence_path",
                    side_effect=replace_then_interrupt,
                ),
                self.assertRaises(KeyboardInterrupt),
            ):
                PUBLISHER._atomic_write_evidence(target, b'{"generation":"new"}\n')
            self.assertNotEqual(old, target.read_bytes())

            PUBLISHER._recover_evidence_transaction(target)

            self.assertEqual(old, target.read_bytes())
            self.assertFalse((Path(directory) / PUBLISHER.TRANSACTION_DIRECTORY_NAME).exists())


class PublisherFailureTests(unittest.TestCase):
    def test_missing_swift_binary_and_runner_exit_never_replace_evidence(self) -> None:
        failures = (
            PUBLISHER.AgreementError("Swift replay target or binary is unavailable"),
            PUBLISHER.AgreementError("Swift replay runner failed"),
        )
        for failure in failures:
            with self.subTest(failure=str(failure)), tempfile.TemporaryDirectory() as directory:
                target = Path(directory) / "replay-agreement.json"
                baseline = b'{"verified":"previous"}\n'
                target.write_bytes(baseline)
                with mock.patch.object(PUBLISHER, "_generate_evidence", side_effect=failure):
                    with self.assertRaises(PUBLISHER.AgreementError):
                        PUBLISHER.run(evidence_path=target)
                self.assertEqual(baseline, target.read_bytes())

    def test_preexisting_runtime_root_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "swift"
            root.mkdir()
            with self.assertRaisesRegex(PUBLISHER.AgreementError, "must not exist"):
                PUBLISHER._require_exclusive_output(root)

    def test_two_actual_publications_are_byte_identical_and_verify(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "replay-agreement.json"
            PUBLISHER.run(evidence_path=target)
            first = target.read_bytes()
            PUBLISHER.run(evidence_path=target)
            second = target.read_bytes()

            self.assertEqual(first, second)
            PUBLISHER.verify_evidence(target)
            report = json.loads(second)
            self.assertEqual("pass", report["agreement"]["verdict"])
            self.assertEqual(0, report["agreement"]["semantic_disagreements"])
            self.assertEqual(16, len(report["cases"]))


if __name__ == "__main__":
    unittest.main()
