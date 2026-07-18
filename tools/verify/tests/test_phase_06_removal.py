"""Mutation contract for fail-closed Phase 06 removal evidence."""

from __future__ import annotations

import copy
import importlib.machinery
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[3]


class PhaseSixRemovalContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        path = REPO_ROOT / "scripts/verify-phase-06-removal"
        loader = importlib.machinery.SourceFileLoader("phase_06_removal", str(path))
        specification = importlib.util.spec_from_loader(loader.name, loader)
        if specification is None:
            raise RuntimeError("phase 06 removal verifier could not be loaded")
        cls.module = importlib.util.module_from_spec(specification)
        sys.modules[loader.name] = cls.module
        loader.exec_module(cls.module)

    def valid_checks(self) -> list[dict[str, str]]:
        return [
            {"check_id": check_id, "command_id": check_id, "status": "PASS", "outcome_sha256": "1" * 64}
            for check_id in self.module.EXPECTED_FULL_CHECKS
        ]

    def valid_report(self) -> dict:
        return self.module._evidence_template(
            recorded_at_utc="2026-07-18T20:00:00Z",
            checks=self.valid_checks(),
            source_bindings=self.module._source_bindings(REPO_ROOT),
            working_tree_counts={"tracked_modified": 3, "untracked": 4},
        )

    def copied_contract_root(self, directory: str) -> Path:
        root = Path(directory)
        for key in self.module.SOURCE_CONTRACT_PATH_KEYS:
            relative = self.module.SOURCE_BINDING_PATHS[key]
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((REPO_ROOT / relative).read_bytes())
        fixture_key = "fixture_json_sha256"
        provenance_key = "fixture_provenance_sha256"
        for key in (fixture_key, provenance_key):
            relative = self.module.SOURCE_BINDING_PATHS[key]
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((REPO_ROOT / relative).read_bytes())
        project = root / self.module.XCODE_PROJECT / "project.pbxproj"
        project.parent.mkdir(parents=True, exist_ok=True)
        project.write_bytes((REPO_ROOT / self.module.XCODE_PROJECT / "project.pbxproj").read_bytes())
        return root

    def test_manifest_rejects_every_missing_or_reordered_check(self) -> None:
        expected = list(self.module.EXPECTED_FULL_CHECKS)
        self.module._validate_complete_checks(expected)
        for check_id in expected:
            with self.subTest(missing=check_id), self.assertRaises(self.module.EvidenceError):
                self.module._validate_complete_checks([item for item in expected if item != check_id])
        expected[0], expected[1] = expected[1], expected[0]
        with self.assertRaises(self.module.EvidenceError):
            self.module._validate_complete_checks(expected)

    def test_operation_order_rejects_reorder_omission_and_duplication(self) -> None:
        canonical = list(self.module.REMOVE_OPERATION_ORDER)
        self.module._validate_operation_order(canonical)
        for mutation in ([canonical[1], canonical[0]], canonical[:1], canonical[1:], canonical + canonical[-1:]):
            with self.assertRaises(self.module.EvidenceError):
                self.module._validate_operation_order(mutation)

    def test_source_contract_rejects_order_inverse_authority_launch_pose_surface_and_occluder_mutations(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = self.copied_contract_root(directory)
            result = self.module._verify_removal_source_contract(root)
            self.assertIn(b'"captured_inverse_count":1', result)
            self.assertIn(b'"retained_reveal_surface_count":2', result)

            mutations = [
                ("remove_reducer_sha256", ".setRevealBundle(", ".removedReveal("),
                ("remove_reducer_sha256", "let inverse = TransactionOperation.restoreSnapshot(", "let inverse = TransactionOperation.removed("),
                ("transaction_authority_sha256", "active.idempotencyRecords.first", "active.removedRecords.first"),
                ("room_edit_model_sha256", "removeLaunchMode: RoomEditRemoveLaunchMode = .normal", "removeLaunchMode: RoomEditRemoveLaunchMode = .degradedDemoFixture"),
                ("room_edit_model_sha256", "scene.revisionAuthority.revisionBranchID == fixture.branchID", "true"),
                ("room_edit_model_sha256", ".unavailable(.occluderArtifactMissing)", ".available(.localRenderer)"),
                ("room_edit_view_sha256", '"surface_63000000-0000-4000-8000-000000000042"', '"removed_surface"'),
                ("room_edit_view_sha256", "#if DEBUG", "#if true"),
            ]
            for key, token, replacement in mutations:
                with self.subTest(key=key, token=token):
                    path = root / self.module.SOURCE_BINDING_PATHS[key]
                    canonical = path.read_text(encoding="utf-8")
                    self.assertIn(token, canonical)
                    path.write_text(canonical.replace(token, replacement, 1), encoding="utf-8")
                    with self.assertRaises(self.module.EvidenceError):
                        self.module._verify_removal_source_contract(root)
                    path.write_text(canonical, encoding="utf-8")

    def test_fixture_contract_rejects_audit_drift_bundle_pbx_and_one_surface(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = self.copied_contract_root(directory)
            self.module._verify_fixture_contract(root)
            fixture_path = root / self.module.SOURCE_BINDING_PATHS["fixture_json_sha256"]
            canonical_bytes = fixture_path.read_bytes()
            canonical = json.loads(canonical_bytes)
            mutations = []
            one_surface = copy.deepcopy(canonical)
            one_surface["surfaces"].pop()
            mutations.append(one_surface)
            promoted = copy.deepcopy(canonical)
            promoted["classification"] = "ready"
            mutations.append(promoted)
            for mutation in mutations:
                fixture_path.write_text(json.dumps(mutation), encoding="utf-8")
                with self.assertRaises(self.module.EvidenceError):
                    self.module._verify_fixture_contract(root)
            fixture_path.write_bytes(canonical_bytes)

            project = root / self.module.XCODE_PROJECT / "project.pbxproj"
            project.write_text(project.read_text(encoding="utf-8") + "\nPhase6Reveal\n", encoding="utf-8")
            with self.assertRaises(self.module.EvidenceError):
                self.module._verify_fixture_contract(root)

    def test_bound_product_digests_cover_every_product_source(self) -> None:
        expected = set(self.module.SOURCE_BINDING_PATHS) - {"orchestrator_sha256", "mutation_tests_sha256"}
        self.assertEqual(set(self.module.BOUND_PRODUCT_DIGESTS), expected)

    def test_required_tests_cannot_be_removed_silently(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = self.copied_contract_root(directory)
            for key, token in self.module.REQUIRED_TEST_TOKENS.items():
                path = root / self.module.SOURCE_BINDING_PATHS[key]
                canonical = path.read_text(encoding="utf-8")
                path.write_text(canonical.replace(token, "removed_test_token", 1), encoding="utf-8")
                with self.assertRaises(self.module.EvidenceError):
                    self.module._verify_removal_source_contract(root)
                path.write_text(canonical, encoding="utf-8")

    def test_report_rejects_green_gates_forbidden_claims_private_data_and_source_drift(self) -> None:
        forbidden_claims = (
            "degraded_demo_fixture ready",
            "degraded_demo_fixture MEASURED",
            "observed atlas validated",
            "provider result passed",
            "coverage measured",
            "foreground proof passed",
            "seam score validated",
            "physical validation passed",
            "thermal result passed",
            "release-valid CON-004",
            "full P0 complete",
        )
        for claim in forbidden_claims:
            report = self.valid_report()
            report["limitations"].append(claim)
            with self.subTest(claim=claim), self.assertRaises(self.module.EvidenceError):
                self.module._validate_report(report)

        report = self.valid_report()
        report["deferred_gates"]["GATE-006"] = "PASS"
        with self.assertRaises(self.module.EvidenceError):
            self.module._validate_report(report)
        report = self.valid_report()
        report["camera_pose"] = [1, 0, 0, 0]
        with self.assertRaises(self.module.EvidenceError):
            self.module._validate_report(report)
        for key in self.module.BOUND_PRODUCT_DIGESTS:
            report = self.valid_report()
            report["source_bindings"][key] = "0" * 64
            with self.assertRaises(self.module.EvidenceError):
                self.module._validate_report(report)

    def test_report_self_digest_is_tamper_evident(self) -> None:
        report = self.valid_report()
        self.module._seal_report(report)
        self.module._validate_report(report, require_self_digest=True)
        report["functional_counts"]["retained_reveal_surface_count"] = 1
        with self.assertRaises(self.module.EvidenceError):
            self.module._validate_report(report, require_self_digest=True)

    def test_quick_mode_and_failed_atomic_replace_publish_nothing(self) -> None:
        with mock.patch.object(self.module, "_require_bound_sources"), \
             mock.patch.object(self.module, "_isolated_simulator", return_value=("A" * 36, b"")), \
             mock.patch.object(self.module, "_quick", return_value=[]), \
             mock.patch.object(self.module, "_publish_atomic") as publish:
            self.module.run("quick")
            publish.assert_not_called()

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            destination = root / self.module.EVIDENCE_RELATIVE_PATH
            destination.parent.mkdir(parents=True)
            destination.write_bytes(b"prior-evidence")
            report = self.valid_report()
            self.module._seal_report(report)
            with mock.patch.object(self.module.os, "replace", side_effect=OSError("injected")):
                with self.assertRaises(self.module.EvidenceError):
                    self.module._publish_atomic(root, report)
            self.assertEqual(destination.read_bytes(), b"prior-evidence")
            self.assertEqual(list(destination.parent.glob("*.tmp")), [])

    def test_atomic_publish_writes_only_valid_full_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = self.valid_report()
            self.module._seal_report(report)
            self.module._publish_atomic(root, report)
            published = json.loads((root / self.module.EVIDENCE_RELATIVE_PATH).read_text(encoding="utf-8"))
            self.module._validate_report(published, require_self_digest=True)
            invalid = self.valid_report()
            invalid["checks"].pop()
            with self.assertRaises(self.module.EvidenceError):
                self.module._publish_atomic(root, invalid)


if __name__ == "__main__":
    unittest.main()
