"""Fail-closed orchestration and evidence gates for Phase 04 targeting."""

from __future__ import annotations

import copy
import importlib.machinery
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[3]


class PhaseFourPreflightContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        path = REPO_ROOT / "scripts/verify-phase-04-targeting"
        loader = importlib.machinery.SourceFileLoader("phase_04_preflight", str(path))
        specification = importlib.util.spec_from_loader(loader.name, loader)
        if specification is None:
            raise RuntimeError("phase 04 verifier could not be loaded")
        cls.module = importlib.util.module_from_spec(specification)
        sys.modules[loader.name] = cls.module
        loader.exec_module(cls.module)

    def valid_report(self) -> dict:
        return self.module._evidence_template(
            recorded_at_utc="2026-07-18T12:00:00Z",
            checks=[
                {
                    "check_id": check_id,
                    "command_id": check_id,
                    "status": "PASS",
                    "outcome_sha256": "1" * 64,
                }
                for check_id in self.module.EXPECTED_FULL_CHECKS
            ],
            source_bindings={
                "ar_session_controller_sha256": "2" * 64,
                "room_edit_model_sha256": "3" * 64,
                "room_edit_view_sha256": "4" * 64,
                "model_tests_sha256": "5" * 64,
                "ar_policy_tests_sha256": "6" * 64,
                "ui_tests_sha256": "7" * 64,
                "orchestrator_sha256": "8" * 64,
                "mutation_tests_sha256": "9" * 64,
            },
            working_tree_counts={"tracked_modified": 3, "untracked": 4},
        )

    def test_check_manifest_rejects_every_missing_or_reordered_check(self) -> None:
        expected = list(self.module.EXPECTED_FULL_CHECKS)
        self.module._validate_complete_checks(expected)
        for check_id in expected:
            with self.subTest(missing=check_id):
                mutated = [value for value in expected if value != check_id]
                with self.assertRaises(self.module.EvidenceError):
                    self.module._validate_complete_checks(mutated)
        reordered = expected[:]
        reordered[0], reordered[1] = reordered[1], reordered[0]
        with self.assertRaises(self.module.EvidenceError):
            self.module._validate_complete_checks(reordered)

    def test_exact_six_layer_descriptor_rejects_all_mutation_families(self) -> None:
        canonical = list(copy.deepcopy(self.module.COMPOSITOR_DESCRIPTOR))
        self.module._validate_compositor_descriptor(canonical)
        mutations = {
            "reorder": lambda value: value.__setitem__(slice(0, 2), reversed(value[:2])),
            "duplicate": lambda value: value.append(copy.deepcopy(value[0])),
            "omit": lambda value: value.pop(),
            "promote_reveal": lambda value: value[1].update(availability="available"),
            "promote_occluder": lambda value: value[2].update(availability="available"),
            "rename_asset": lambda value: value[3].update(layer_id="asset"),
        }
        for label, mutation in mutations.items():
            with self.subTest(label=label):
                descriptor = copy.deepcopy(canonical)
                mutation(descriptor)
                with self.assertRaises(self.module.EvidenceError):
                    self.module._validate_compositor_descriptor(descriptor)

    def test_static_boundary_audit_rejects_production_external_dependencies_only(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            production = root / "Production.swift"
            fixture = root / "ProductionTests.swift"
            production.write_text("struct LocalRenderer {}\n", encoding="utf-8")
            fixture.write_text("let fake = \"URLSession\"\n", encoding="utf-8")
            self.module._audit_production_boundaries(root, ("Production.swift",))
            for token in self.module.FORBIDDEN_PRODUCTION_TOKENS:
                with self.subTest(token=token):
                    production.write_text(f"struct LocalRenderer {{ let injected = \"{token}\" }}\n", encoding="utf-8")
                    with self.assertRaises(self.module.EvidenceError):
                        self.module._audit_production_boundaries(root, ("Production.swift",))

    def test_closed_evidence_accepts_only_pending_fallback_report(self) -> None:
        report = self.valid_report()
        self.module.validate_evidence(report)
        self.assertEqual("automated sprint fallback slice passed", report["claim"])
        self.assertEqual(
            {
                "GATE-003": "PENDING",
                "GATE-004": "PENDING",
                "GATE-005": "PENDING",
                "GATE-007": "PENDING",
                "GATE-012": "PENDING",
            },
            report["pending_gates"],
        )
        self.assertEqual(
            {
                "target_selection": "manual tap and explicit reseed",
                "geometry": "no-dense ARKit plane and conservative proxy",
                "runtime": "local demo only",
            },
            report["fallbacks"],
        )

    def test_evidence_rejects_overclaim_private_content_and_unsafe_provenance(self) -> None:
        mutations = {
            "green_claim": lambda value: value.update(claim="GATE-003 GREEN"),
            "green_gate": lambda value: value["pending_gates"].update({"GATE-004": "PASS"}),
            "measured": lambda value: value.update(value_classification="MEASURED"),
            "performance": lambda value: value["limitations"].append("60 FPS measured"),
            "provider": lambda value: value["limitations"].append("dense provider qualified"),
            "physical": lambda value: value.update(physical_observation="looked correct on device"),
            "absolute_path": lambda value: value["limitations"].append("/Users/example/private"),
            "credential": lambda value: value["limitations"].append("api_key=secret-value"),
            "raw_room": lambda value: value.update(raw_room_text="private bedroom"),
            "missing_check": lambda value: value["checks"].pop(),
            "dynamic_revision": lambda value: value.update(implementation_revision="git:HEAD"),
            "missing_binding": lambda value: value["source_bindings"].pop("room_edit_view_sha256"),
        }
        for label, mutation in mutations.items():
            with self.subTest(label=label):
                report = self.valid_report()
                mutation(report)
                with self.assertRaises(self.module.EvidenceError):
                    self.module.validate_evidence(report)

    def test_atomic_publication_preserves_prior_evidence_on_failure(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "automated-preflight.json"
            target.write_bytes(b"prior-evidence")
            with mock.patch.object(self.module.os, "replace", side_effect=OSError("injected")):
                with self.assertRaises(self.module.EvidenceError):
                    self.module._atomic_publish(target, b"partial-evidence")
            self.assertEqual(b"prior-evidence", target.read_bytes())
            self.assertEqual([], list(target.parent.glob(".automated-preflight.*.tmp")))

    def test_orchestrator_declares_full_fail_closed_surface(self) -> None:
        path = REPO_ROOT / "scripts/verify-phase-04-targeting"
        source = path.read_text(encoding="utf-8")
        required = (
            "quick", "full", "RoomEditModelTests", "ARSessionPolicyTests",
            "RoomEditJourneyTests", "Debug", "Release",
            "scripts/verify-reroom-release-surface", "production_dependency_audit",
            "tracked_secret_scan", "git", "diff", "--check",
            "evidence/targeting/phase-04/automated-preflight.json",
            "camera", "reveal", "occluder", "asset/proxy", "debug", "SwiftUI",
        )
        for token in required:
            with self.subTest(token=token):
                self.assertIn(token, source)
        self.assertTrue(path.stat().st_mode & 0o111)

    def test_authoritative_full_report_is_revision_bound_sanitized_and_pending(self) -> None:
        self.assertEqual("1.0.0", self.module.REPORT_SCHEMA_REVISION)
        self.assertEqual(12, self.module.PUBLISH_ONLY_AFTER_CHECK_COUNT)
        report = self.valid_report()
        self.module.validate_evidence(report)
        self.assertEqual(self.module.IMPLEMENTATION_REVISION, report["implementation_revision"])
        self.assertEqual(12, len(report["checks"]))
        self.assertTrue(all(value == "PENDING" for value in report["pending_gates"].values()))
        self.assertTrue(all(value is False for value in report["privacy"].values()))


if __name__ == "__main__":
    unittest.main()
