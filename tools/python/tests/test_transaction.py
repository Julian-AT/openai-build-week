"""Independent Python transaction trace producer behavior and mutation gates."""

from __future__ import annotations

import json
import re
import shutil
import tempfile
import unittest
from pathlib import Path

from tools.python.reroom_verify.transaction import (
    EXACT_PYTHON_VERSION,
    canonical_bytes,
    produce_transaction_trace,
    run_transaction_trace,
)


ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT / "fixtures/transactions/1.0.0/rev-001/manifest.json"
REVISION = "git:0123456789abcdef0123456789abcdef01234567"
FIXTURE_SHA256 = "4aceda98f3dcb6bc0cf3efaef63852b67a86ea22b0455eb07d3fb9cdd34b371a"
OPERATIONS = ["place", "replace", "remove", "restore"]


class PythonTransactionTraceTests(unittest.TestCase):
    def assert_complete(self, result: dict, raw: bytes) -> None:
        self.assertEqual(raw, canonical_bytes(result))
        self.assertEqual("reroom_transaction_trace_v1", result["trace_format"])
        self.assertEqual(
            {"fixture_id": "FX-TRANSACTION-001", "fixture_revision": "rev-001", "manifest_sha256": FIXTURE_SHA256},
            result["fixture"],
        )
        self.assertEqual(
            {"language": "python", "name": "ReRoomTransactionPython", "version": f"python-{EXACT_PYTHON_VERSION}"},
            result["runtime"],
        )
        self.assertEqual(REVISION, result["implementation"]["repository_revision"])
        self.assertRegex(result["implementation"]["source_tree_sha256"], r"^[0-9a-f]{64}$")
        self.assertEqual(["tools/python/reroom_verify/transaction.py"], result["implementation"]["source_files"])
        self.assertEqual(OPERATIONS, result["operation_order"])
        self.assertEqual(OPERATIONS, [proposal["operation"] for proposal in result["proposals"]])
        for proposal in result["proposals"]:
            self.assertEqual("accepted", proposal["status"])
            self.assertEqual("proposal_only", proposal["authority"])
            self.assertFalse(proposal["preauthorized_confirmation"])
            self.assertFalse(proposal["preauthorized_commit"])
        self.assertEqual({"code": "capability_not_ready", "mutation_count": 0}, result["proposals"][1]["blocker"])
        self.assertEqual({"code": "capability_not_ready", "mutation_count": 0}, result["proposals"][2]["blocker"])
        self.assertIsNone(result["proposals"][3]["blocker"])
        self.assertEqual(["restore_snapshot"], result["proposals"][3]["proposed_operation_kinds"])
        self.assertEqual("intent.transform-injection", result["safety"]["injection_case_id"])
        self.assertEqual("reject", result["safety"]["injection_verdict"])
        self.assertEqual(0, result["safety"]["injection_mutation_count"])
        self.assertEqual({"preview_scene_revision": 0, "place_scene_revision": 1, "restore_scene_revision": 2}, result["revisions"])
        self.assertEqual("prior_result", result["retry"]["same_key_same_fingerprint"])
        self.assertEqual("idempotency_conflict", result["retry"]["same_key_changed_fingerprint"])
        self.assertEqual(0, result["restore"]["network_reads"])
        self.assertTrue(result["restore"]["source_transaction_immutable"])
        self.assertFalse(result["divergence"]["automatic_merge_permitted"])
        self.assertTrue(result["divergence"]["mutation_frozen"])
        self.assertEqual(24, len(result["cases"]))
        self.assertEqual(sorted(case["case_id"] for case in result["cases"]), [case["case_id"] for case in result["cases"]])
        self.assertEqual(3, len(result["traces"]))
        self.assertRegex(result["fingerprints"]["place_request_sha256"], r"^[0-9a-f]{64}$")
        self.assertRegex(result["fingerprints"]["restore_request_sha256"], r"^[0-9a-f]{64}$")
        self.assertNotEqual(result["projections"]["base_sha256"], result["projections"]["placed_sha256"])
        self.assertEqual(result["projections"]["base_sha256"], result["projections"]["restored_sha256"])

    def test_dependency_free_python_emits_complete_provenance_bound_corpus(self) -> None:
        raw = produce_transaction_trace(MANIFEST, ROOT, REVISION)
        self.assert_complete(json.loads(raw), raw)

    def test_two_isolated_python_publications_are_byte_identical(self) -> None:
        with tempfile.TemporaryDirectory(prefix="reroom-python-transaction-") as temporary:
            root = Path(temporary)
            first, second = root / "first.json", root / "second.json"
            run_transaction_trace(MANIFEST, first, ROOT, REVISION)
            run_transaction_trace(MANIFEST, second, ROOT, REVISION)
            self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_runtime_revision_fixture_and_oracle_drift_reject_before_publication(self) -> None:
        with self.assertRaisesRegex(ValueError, "Python 3.13.12 is required"):
            produce_transaction_trace(MANIFEST, ROOT, REVISION, runtime_version="3.13.11")
        with self.assertRaisesRegex(ValueError, "git:<40-lowercase-hex>"):
            produce_transaction_trace(MANIFEST, ROOT, "git:HEAD")

        with tempfile.TemporaryDirectory(prefix="reroom-python-transaction-mutation-") as temporary:
            root = Path(temporary)
            fixture = root / "rev-001"
            shutil.copytree(MANIFEST.parent, fixture)
            expected_path = fixture / "expected-traces.json"
            expected = json.loads(expected_path.read_bytes())
            expected["traces"][0]["events"][0]["scene_revision"] = 99
            expected_path.write_text(json.dumps(expected, indent=2) + "\n", encoding="utf-8")
            output = root / "rejected.json"
            with self.assertRaisesRegex(ValueError, "fixture|digest|oracle"):
                run_transaction_trace(fixture / "manifest.json", output, ROOT, REVISION)
            self.assertFalse(output.exists())

    def test_producer_source_is_closed_and_dependency_free(self) -> None:
        source = (ROOT / "tools/python/reroom_verify/transaction.py").read_text(encoding="utf-8")
        self.assertNotRegex(source, r"ReRoomTransactionTraceExporter|tools/javascript|subprocess|expected\s*=\s*actual")
        imports = re.findall(r"^(?:from|import)\s+([^\s.]+)", source, flags=re.MULTILINE)
        self.assertTrue(set(imports) <= {"argparse", "hashlib", "json", "math", "os", "platform", "re", "sys", "uuid", "pathlib", "typing", "__future__"})


if __name__ == "__main__":
    unittest.main()
