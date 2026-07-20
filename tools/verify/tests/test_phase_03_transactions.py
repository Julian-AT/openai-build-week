"""Fail-closed comparator and orchestration gates for Phase 03 transactions."""

from __future__ import annotations

import copy
import importlib.machinery
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path

from tools.verify.compare_transaction_traces import (
    MAXIMUM_RESULT_BYTES,
    RUNTIME_IDENTITIES,
    TransactionComparisonError,
    canonical_bytes,
    compare_transaction_traces,
    verify_transaction_fixture,
)


REPO_ROOT = Path(__file__).resolve().parents[3]
MANIFEST = REPO_ROOT / "fixtures/transactions/1.0.0/rev-001/manifest.json"
REVISION = "git:" + "a" * 40
RUNTIMES = ("swift", "typescript", "python")


def _run(command: list[str]) -> str:
    completed = subprocess.run(
        command,
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout.strip()


class FreshTransactionOutputs(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="reroom-phase-03-comparator-")
        cls.root = Path(cls.temporary.name)
        _run([
            "swift", "build", "--package-path", "apps/ios/Packages/ReRoomContracts",
            "--product", "ReRoomTransactionTraceExporter",
        ])
        bin_root = Path(_run([
            "swift", "build", "--package-path", "apps/ios/Packages/ReRoomContracts",
            "--show-bin-path",
        ]))
        common = [
            "--manifest", str(MANIFEST), "--repo-root", str(REPO_ROOT),
            "--implementation-revision", REVISION,
        ]
        commands = {
            "swift": [str(bin_root / "ReRoomTransactionTraceExporter")],
            "typescript": ["node", "packages/contracts/src/transaction.ts"],
            "python": [sys.executable, "-m", "tools.python.reroom_verify.transaction"],
        }
        cls.outputs: dict[str, Path] = {}
        for runtime in RUNTIMES:
            output = cls.root / f"{runtime}.json"
            _run([*commands[runtime], *common, "--output", str(output)])
            cls.outputs[runtime] = output

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def copied_outputs(self, root: Path) -> dict[str, Path]:
        outputs: dict[str, Path] = {}
        for runtime, source in self.outputs.items():
            target = root / source.name
            shutil.copyfile(source, target)
            outputs[runtime] = target
        return outputs

    def compare(self, outputs: dict[str, Path]):
        return compare_transaction_traces(
            MANIFEST,
            outputs,
            repo_root=REPO_ROOT,
            implementation_revision=REVISION,
        )

    @staticmethod
    def mutate(path: Path, function) -> None:
        value = json.loads(path.read_bytes())
        function(value)
        path.write_bytes(canonical_bytes(value))

    def test_complete_actual_three_runtime_corpus_agrees(self) -> None:
        result = self.compare(self.outputs)
        self.assertEqual(RUNTIMES, result.runtimes)
        self.assertEqual(24, result.case_count)
        self.assertEqual(0, result.semantic_disagreements)
        self.assertEqual(0, result.provenance_disagreements)
        self.assertEqual(tuple(RUNTIME_IDENTITIES), result.runtimes)

    def test_closed_schema_rejects_unknown_missing_and_oversized_results(self) -> None:
        mutations = ("unknown", "missing", "oversized")
        for mutation in mutations:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                outputs = self.copied_outputs(Path(directory))
                target = outputs["swift"]
                if mutation == "unknown":
                    self.mutate(target, lambda value: value.update(unexpected=True))
                    expected = "result_schema:swift:root"
                elif mutation == "missing":
                    self.mutate(target, lambda value: value.pop("fingerprints"))
                    expected = "result_schema:swift:root"
                else:
                    target.write_bytes(b" " * (MAXIMUM_RESULT_BYTES + 1))
                    expected = "result:swift:size_limit"
                with self.assertRaisesRegex(TransactionComparisonError, expected):
                    self.compare(outputs)

    def test_runtime_revision_fixture_and_source_provenance_drift_reject(self) -> None:
        mutations = ("runtime", "revision", "fixture", "source_digest", "source_files")
        for mutation in mutations:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                outputs = self.copied_outputs(Path(directory))
                target = outputs["typescript"]
                if mutation == "runtime":
                    self.mutate(target, lambda value: value["runtime"].update(version="node-v0.0.0"))
                    expected = "runtime_identity:typescript"
                elif mutation == "revision":
                    self.mutate(target, lambda value: value["implementation"].update(repository_revision="git:HEAD"))
                    expected = "result_schema:typescript:implementation.repository_revision"
                elif mutation == "fixture":
                    self.mutate(target, lambda value: value["fixture"].update(manifest_sha256="0" * 64))
                    expected = "fixture_identity:typescript"
                elif mutation == "source_digest":
                    self.mutate(target, lambda value: value["implementation"].update(source_tree_sha256="0" * 64))
                    expected = "source_binding:typescript"
                else:
                    self.mutate(target, lambda value: value["implementation"]["source_files"].pop())
                    expected = "source_binding:typescript"
                with self.assertRaisesRegex(TransactionComparisonError, expected):
                    self.compare(outputs)

    def test_case_set_order_outcome_and_rejection_drift_reject(self) -> None:
        mutations = ("missing", "duplicate", "order", "outcome", "rejection")
        for mutation in mutations:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                outputs = self.copied_outputs(Path(directory))
                target = outputs["python"]
                if mutation == "missing":
                    self.mutate(target, lambda value: value["cases"].pop())
                    expected = "case_set:python"
                elif mutation == "duplicate":
                    self.mutate(target, lambda value: value["cases"].__setitem__(1, copy.deepcopy(value["cases"][0])))
                    expected = "result_schema:python:cases"
                elif mutation == "order":
                    self.mutate(target, lambda value: value["cases"].reverse())
                    expected = "case_set:python"
                elif mutation == "outcome":
                    self.mutate(target, lambda value: value["cases"][0].update(outcome="reject"))
                    expected = "case_oracle:python:authority.native-pair"
                else:
                    self.mutate(target, lambda value: value["cases"][1].update(rejection="stale_scene_revision"))
                    expected = "case_oracle:python:authority.wrong-branch"
                with self.assertRaisesRegex(TransactionComparisonError, expected):
                    self.compare(outputs)

    def test_proposal_blocker_operation_and_injection_drift_reject(self) -> None:
        mutations = ("place", "restore_authority", "replace", "remove", "order", "injection")
        for mutation in mutations:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                outputs = self.copied_outputs(Path(directory))
                target = outputs["swift"]
                if mutation == "place":
                    self.mutate(target, lambda value: value["proposals"][0].update(status="rejected"))
                    expected = "proposal_oracle:swift"
                elif mutation == "restore_authority":
                    self.mutate(target, lambda value: value["proposals"][3].update(preauthorized_commit=True))
                    expected = "proposal_oracle:swift"
                elif mutation == "replace":
                    self.mutate(target, lambda value: value["proposals"][1]["blocker"].update(mutation_count=1))
                    expected = "proposal_oracle:swift"
                elif mutation == "remove":
                    self.mutate(target, lambda value: value["proposals"][2]["blocker"].update(code="restore_source_required"))
                    expected = "proposal_oracle:swift"
                elif mutation == "order":
                    self.mutate(target, lambda value: value["operation_order"].reverse())
                    expected = "operation_oracle:swift"
                else:
                    self.mutate(target, lambda value: value["safety"].update(injection_verdict="accept"))
                    expected = "injection_oracle:swift"
                with self.assertRaisesRegex(TransactionComparisonError, expected):
                    self.compare(outputs)

    def test_each_transaction_semantic_family_has_an_independent_oracle_kill(self) -> None:
        mutations = (
            "fingerprints", "projections", "revisions", "receipts", "retry",
            "restore", "divergence", "traces",
        )
        for mutation in mutations:
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                outputs = self.copied_outputs(Path(directory))
                for target in outputs.values():
                    if mutation == "fingerprints":
                        self.mutate(target, lambda value: value["fingerprints"].update(place_request_sha256="0" * 64))
                    elif mutation == "projections":
                        self.mutate(target, lambda value: value["projections"].update(placed_sha256="0" * 64))
                    elif mutation == "revisions":
                        self.mutate(target, lambda value: value["revisions"].update(place_scene_revision=2))
                    elif mutation == "receipts":
                        self.mutate(target, lambda value: value["receipts"][0].update(committed_scene_revision=2))
                    elif mutation == "retry":
                        self.mutate(target, lambda value: value["retry"].update(duplicate_mutation_count=1))
                    elif mutation == "restore":
                        self.mutate(target, lambda value: value["restore"].update(network_reads=1))
                    elif mutation == "divergence":
                        self.mutate(target, lambda value: value["divergence"].update(automatic_merge_permitted=True))
                    else:
                        self.mutate(target, lambda value: value["traces"].pop())
                with self.assertRaisesRegex(TransactionComparisonError, f"{mutation}_oracle:swift"):
                    self.compare(outputs)

    def test_fixture_byte_drift_rejects_before_runtime_comparison(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / "rev-001"
            shutil.copytree(MANIFEST.parent, fixture)
            expected = fixture / "expected-traces.json"
            changed = bytearray(expected.read_bytes())
            changed[0] ^= 1
            expected.write_bytes(changed)
            with self.assertRaisesRegex(TransactionComparisonError, "fixture_file_sha256"):
                verify_transaction_fixture(fixture / "manifest.json", repo_root=REPO_ROOT)


class PhaseThreePreflightContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        path = REPO_ROOT / "scripts/verify-phase-03-transactions"
        loader = importlib.machinery.SourceFileLoader("phase_03_preflight", str(path))
        specification = importlib.util.spec_from_loader(loader.name, loader)
        if specification is None:
            raise RuntimeError("phase 03 verifier could not be loaded")
        cls.module = importlib.util.module_from_spec(specification)
        sys.modules[loader.name] = cls.module
        loader.exec_module(cls.module)

    def valid_report(self) -> dict:
        return self.module._evidence_template(
            recorded_at_utc="2026-07-18T12:00:00Z",
            checks=[
                {"check_id": check_id, "status": "PASS", "outcome_sha256": "1" * 64}
                for check_id in self.module.EXPECTED_FULL_CHECKS
            ],
            runtime_runs={
                runtime: {
                    "byte_identical": True,
                    "run_count": 2,
                    "result_sha256": str(index) * 64,
                    "source_tree_sha256": str(index + 3) * 64,
                }
                for index, runtime in enumerate(("swift", "typescript", "python"), start=1)
            },
            source_bindings={
                "comparator_sha256": "7" * 64,
                "orchestrator_sha256": "8" * 64,
                "result_schema_sha256": "9" * 64,
            },
            working_tree_counts={"tracked_modified": 3, "untracked": 4},
        )

    def test_closed_evidence_accepts_only_honest_pending_gate_report(self) -> None:
        report = self.valid_report()
        self.module.validate_evidence(report)
        self.assertEqual("automated sprint slice passed", report["claim"])
        self.assertTrue(all(value == "PENDING" for value in report["pending_gates"].values()))
        self.assertNotIn("GREEN", canonical_bytes(report).decode("utf-8"))

    def test_evidence_rejects_overclaim_missing_binding_and_private_content(self) -> None:
        mutations = {
            "green_claim": lambda value: value.update(claim="GATE-010 GREEN"),
            "green_gate": lambda value: value["pending_gates"].update({"GATE-010": "PASS"}),
            "missing_check": lambda value: value["checks"].pop(),
            "dynamic_revision": lambda value: value.update(implementation_revision="git:HEAD"),
            "fixture_drift": lambda value: value["fixture"].update(manifest_sha256="0" * 64),
            "missing_source": lambda value: value["source_bindings"].pop("comparator_sha256"),
            "machine_path": lambda value: value["limitations"].append("/Users/example/private"),
            "credential": lambda value: value["limitations"].append("api_key=secret-value"),
            "raw_room": lambda value: value.update(raw_room_text="private bedroom"),
            "fabricated_observation": lambda value: value.update(human_observation="looked correct"),
        }
        for label, mutation in mutations.items():
            with self.subTest(label=label):
                report = self.valid_report()
                mutation(report)
                with self.assertRaises(self.module.EvidenceError):
                    self.module.validate_evidence(report)

    def test_atomic_publication_does_not_replace_prior_evidence_on_failure(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "automated-preflight.json"
            target.write_bytes(b"prior-evidence")
            with mock.patch.object(self.module.os, "replace", side_effect=OSError("injected")):
                with self.assertRaises(self.module.EvidenceError):
                    self.module._atomic_publish(target, b"new-evidence")
            self.assertEqual(b"prior-evidence", target.read_bytes())
            self.assertEqual([], list(target.parent.glob(".automated-preflight.*.tmp")))

    def test_orchestrator_declares_exact_two_run_quick_and_full_surface(self) -> None:
        path = REPO_ROOT / "scripts/verify-phase-03-transactions"
        source = path.read_text(encoding="utf-8")
        required = (
            "v22.22.3", "packages/contracts/src/transaction.ts", "TemporaryDirectory",
            "byte_identical", "quick", "full", "RoomEditModelTests",
            "RoomEditJourneyTests", "Debug", "Release",
            "scripts/verify-reroom-release-surface", "git", "diff", "--check",
            "evidence/transactions/phase-03/automated-preflight.json",
        )
        for token in required:
            with self.subTest(token=token):
                self.assertIn(token, source)
        self.assertTrue(path.stat().st_mode & 0o111)


if __name__ == "__main__":
    unittest.main()
