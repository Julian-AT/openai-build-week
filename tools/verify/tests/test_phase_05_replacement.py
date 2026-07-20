"""Mutation contract for fail-closed Phase 05 replacement evidence."""

from __future__ import annotations

import copy
import importlib.machinery
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[3]


class PhaseFiveReplacementContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        path = REPO_ROOT / "scripts/verify-phase-05-replacement"
        loader = importlib.machinery.SourceFileLoader("phase_05_replacement", str(path))
        specification = importlib.util.spec_from_loader(loader.name, loader)
        if specification is None:
            raise RuntimeError("phase 05 replacement verifier could not be loaded")
        cls.module = importlib.util.module_from_spec(specification)
        sys.modules[loader.name] = cls.module
        loader.exec_module(cls.module)

    def valid_checks(self) -> list[dict[str, str]]:
        return [
            {
                "check_id": check_id,
                "command_id": check_id,
                "status": "PASS",
                "outcome_sha256": "1" * 64,
            }
            for check_id in self.module.EXPECTED_FULL_CHECKS
        ]

    def valid_bindings(self) -> dict[str, str]:
        bindings = self.module._source_bindings(REPO_ROOT)
        # This fixture represents the immutable Phase 5 report, even after a
        # compatible later phase extends shared product files.
        bindings.update(self.module.BOUND_PRODUCT_DIGESTS)
        return bindings

    def valid_report(self) -> dict:
        return self.module._evidence_template(
            recorded_at_utc="2026-07-18T18:45:00Z",
            checks=self.valid_checks(),
            source_bindings=self.valid_bindings(),
            working_tree_counts={"tracked_modified": 3, "untracked": 4},
        )

    def write_bound_source_contract(self, root: Path) -> None:
        for key in self.module.SOURCE_CONTRACT_PATH_KEYS:
            relative = self.module.SOURCE_BINDING_PATHS[key]
            bound_relative = self.module.path_at_bound_revision(relative)
            result = subprocess.run(
                ["git", "show", f"{self.module.BOUND_REVISION}:{bound_relative}"],
                cwd=REPO_ROOT,
                check=True,
                capture_output=True,
            )
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(result.stdout)

    def test_manifest_rejects_every_missing_or_reordered_check(self) -> None:
        expected = list(self.module.EXPECTED_FULL_CHECKS)
        self.module._validate_complete_checks(expected)
        for check_id in expected:
            with self.subTest(missing=check_id):
                with self.assertRaises(self.module.EvidenceError):
                    self.module._validate_complete_checks([item for item in expected if item != check_id])
        reordered = expected[:]
        reordered[0], reordered[1] = reordered[1], reordered[0]
        with self.assertRaises(self.module.EvidenceError):
            self.module._validate_complete_checks(reordered)

    def test_operation_order_rejects_visibility_asset_reorder_or_weakening(self) -> None:
        canonical = list(self.module.REPLACE_OPERATION_ORDER)
        self.module._validate_operation_order(canonical)
        mutations = {
            "reorder": [canonical[1], canonical[0]],
            "missing_visibility": [canonical[-1]],
            "missing_asset": [canonical[0]],
            "duplicate": canonical + [canonical[-1]],
            "reveal_claim": ["set_reveal_bundle", *canonical],
        }
        for label, mutation in mutations.items():
            with self.subTest(label=label):
                with self.assertRaises(self.module.EvidenceError):
                    self.module._validate_operation_order(mutation)

    def test_source_contract_binds_one_time_retained_exact_asset_and_fail_closed_seam(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.write_bound_source_contract(root)

            result = self.module._verify_replacement_source_contract(root)
            self.assertIn(b'"asset_load_count":1', result)
            self.assertIn(b'"retained_template":true', result)
            self.assertIn(b'"load_failure_unavailable":true', result)

            view_path = root / self.module.SOURCE_BINDING_PATHS["room_edit_view_sha256"]
            canonical = view_path.read_text(encoding="utf-8")
            mutations = {
                "per_update_load": canonical.replace(
                    "context.coordinator.apply(snapshot, to: view, fixtureScenario: fixtureScenario)",
                    'let _ = try? Entity.load(named: "proxy-chair.usda", in: .main)',
                    1,
                ),
                "wrong_asset": canonical.replace('Entity.load(named: "proxy-chair.usda"', 'Entity.load(named: "other.usda"', 1),
                "generated_replacement": canonical.replace(
                    "replacementTemplate.clone(recursive: true)",
                    "ModelEntity(mesh: .generateBox(size: 1))",
                    1,
                ),
                "load_failure_ready": canonical.replace(
                    "replacementAssetState = .unavailable(.realityKitLoadFailed)",
                    "replacementAssetState = .available",
                    1,
                ),
            }
            for label, source in mutations.items():
                with self.subTest(label=label):
                    view_path.write_text(source, encoding="utf-8")
                    with self.assertRaises(self.module.EvidenceError):
                        self.module._verify_replacement_source_contract(root)
                    view_path.write_text(canonical, encoding="utf-8")

            model_path = root / self.module.SOURCE_BINDING_PATHS["room_edit_model_sha256"]
            canonical_model = model_path.read_text(encoding="utf-8")
            model_mutations = {
                "default_true": canonical_model.replace(
                    "replacementSupportedViewPolicy: RoomEditSupportedViewPolicy = .denyAll",
                    "replacementSupportedView: Bool = true",
                    1,
                ),
                "fixture_policy_omitted": canonical_model.replace(
                    "replacementSupportedViewPolicy: .fixtureDemoHypothesis",
                    "",
                    1,
                ),
                "live_policy_omitted": canonical_model.replace(
                    "replacementSupportedViewPolicy: .liveDemoHypothesis",
                    "",
                    1,
                ),
            }
            for label, source in model_mutations.items():
                with self.subTest(label=label):
                    self.assertNotEqual(source, canonical_model)
                    model_path.write_text(source, encoding="utf-8")
                    with self.assertRaises(self.module.EvidenceError):
                        self.module._verify_replacement_source_contract(root)
                    model_path.write_text(canonical_model, encoding="utf-8")

    def test_bound_product_digests_cover_every_product_source(self) -> None:
        expected = set(self.module.SOURCE_BINDING_PATHS) - {
            "orchestrator_sha256",
            "mutation_tests_sha256",
        }
        self.assertEqual(set(self.module.BOUND_PRODUCT_DIGESTS), expected)

    def test_source_contract_requires_inverse_idempotency_and_failure_tests(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.write_bound_source_contract(root)
            self.module._verify_replacement_source_contract(root)

            for key, token in self.module.REQUIRED_TEST_TOKENS.items():
                with self.subTest(missing=key):
                    relative = self.module.SOURCE_BINDING_PATHS[key]
                    path = root / relative
                    canonical = path.read_text(encoding="utf-8")
                    self.assertIn(token, canonical)
                    path.write_text(canonical.replace(token, "removed_mutation_token", 1), encoding="utf-8")
                    with self.assertRaises(self.module.EvidenceError):
                        self.module._verify_replacement_source_contract(root)
                    path.write_text(canonical, encoding="utf-8")

    def test_asset_contract_rejects_digest_metadata_and_claim_drift(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for key in ("proxy_asset_sha256", "asset_manifest_sha256", "asset_provenance_sha256"):
                relative = self.module.SOURCE_BINDING_PATHS[key]
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes((REPO_ROOT / relative).read_bytes())
            self.module._verify_asset_contract(root)

            manifest_path = root / self.module.SOURCE_BINDING_PATHS["asset_manifest_sha256"]
            canonical = json.loads(manifest_path.read_text(encoding="utf-8"))
            for field, value in {
                "sha256": "0" * 64,
                "classification": "shipping licensed parity asset",
                "gate_011_status": "PASS",
            }.items():
                with self.subTest(field=field):
                    mutated = copy.deepcopy(canonical)
                    mutated[field] = value
                    manifest_path.write_text(json.dumps(mutated), encoding="utf-8")
                    with self.assertRaises(self.module.EvidenceError):
                        self.module._verify_asset_contract(root)
            manifest_path.write_text(json.dumps(canonical), encoding="utf-8")

    def test_report_rejects_green_gates_overclaims_raw_content_and_drift(self) -> None:
        report = self.valid_report()
        self.module._validate_report(report)
        mutations = []

        green_gate = copy.deepcopy(report)
        green_gate["deferred_gates"]["GATE-011"] = "PASS"
        mutations.append(green_gate)

        overclaim = copy.deepcopy(report)
        overclaim["claim"] = "physical device and native web parity passed"
        mutations.append(overclaim)

        raw_content = copy.deepcopy(report)
        raw_content["raw_room"] = "private capture"
        mutations.append(raw_content)

        for key in self.module.BOUND_PRODUCT_DIGESTS:
            source_drift = copy.deepcopy(report)
            source_drift["source_bindings"][key] = "0" * 64
            mutations.append(source_drift)

        incomplete = copy.deepcopy(report)
        incomplete["checks"].pop()
        mutations.append(incomplete)

        for index, mutation in enumerate(mutations):
            with self.subTest(index=index):
                with self.assertRaises(self.module.EvidenceError):
                    self.module._validate_report(mutation)

    def test_report_self_digest_is_canonical_and_tamper_evident(self) -> None:
        report = self.valid_report()
        self.module._seal_report(report)
        self.module._validate_report(report, require_self_digest=True)
        report["functional_counts"]["automated_fixture_runs"] += 1
        with self.assertRaises(self.module.EvidenceError):
            self.module._validate_report(report, require_self_digest=True)

    def test_atomic_publish_preserves_prior_report_on_replacement_failure(self) -> None:
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
