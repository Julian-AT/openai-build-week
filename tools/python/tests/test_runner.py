"""Independent Python reference-runner conformance tests."""

from __future__ import annotations

import hashlib
import json
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
CONTRACT_MANIFEST = REPO_ROOT / "fixtures/contracts/1.0.0/rev-001/manifest.json"
JCS_MANIFEST = (
    REPO_ROOT / "fixtures/policies/RR-JCS-SHA256-1/rev-001/manifest.json"
)
COORD_MANIFEST = REPO_ROOT / "fixtures/policies/RR-COORD-1/rev-001/manifest.json"
REVISION = "git:" + ("0" * 40)


def _manifest(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _expected_row(case: dict) -> dict:
    artifacts = []
    for artifact in case["expected"]["artifacts"]:
        row = {
            "kind": artifact["kind"],
            "byte_length": artifact["byte_length"],
            "sha256": artifact["sha256"],
        }
        if "value_sha256" in artifact:
            row["value_sha256"] = artifact["value_sha256"]
        artifacts.append(row)
    return {
        "case_id": case["case_id"],
        "verdict": case["expected"]["verdict"],
        "rejection_class": case["expected"]["rejection_class"],
        "output_artifacts": artifacts,
    }


class PythonRunnerTests(unittest.TestCase):
    def test_contract_jcs_and_wire_boundaries(self) -> None:
        runner_path = REPO_ROOT / "tools/python/reroom_verify/runner.py"
        self.assertTrue(runner_path.is_file(), "Python contract runner is not implemented")

        import rfc8785
        from jsonschema import Draft202012Validator

        from tools.python.reroom_verify.runner import evaluate_case, run_fixture
        from tools.python.reroom_verify.wire_frame import encode_frame

        for manifest_path in (CONTRACT_MANIFEST, JCS_MANIFEST):
            manifest = _manifest(manifest_path)
            result = run_fixture(
                manifest_path,
                repo_root=REPO_ROOT,
                implementation_revision=REVISION,
            )
            expected = [_expected_row(case) for case in manifest["cases"]]
            self.assertEqual(expected, result["case_results"])
            self.assertEqual(
                [row["case_id"] for row in expected],
                sorted(row["case_id"] for row in expected),
            )
            digest_scope = dict(result)
            digest_scope.pop("result_digest_sha256")
            self.assertEqual(
                hashlib.sha256(rfc8785.dumps(digest_scope)).hexdigest(),
                result["result_digest_sha256"],
            )
            result_schema = _manifest(REPO_ROOT / "fixtures/runner-result.schema.json")
            Draft202012Validator(result_schema).validate(result)

        coordinate_manifest = _manifest(COORD_MANIFEST)
        for case in coordinate_manifest["cases"]:
            if case["case_kind"] not in {"wire_bytes", "wire_mutation"}:
                continue
            self.assertEqual(
                _expected_row(case),
                evaluate_case(COORD_MANIFEST, case["case_id"], repo_root=REPO_ROOT),
            )

        wire_input = _manifest(
            COORD_MANIFEST.parent / "inputs/wire.valid.json"
        )
        header = _manifest(
            COORD_MANIFEST.parent / wire_input["header_source"]
        )
        expected_hex = (
            COORD_MANIFEST.parent / wire_input["expected_wire_hex"]
        ).read_text(encoding="ascii").strip()
        wire = encode_frame(header, bytes.fromhex(wire_input["payload_hex"]))
        self.assertEqual(24, len(wire) - len(rfc8785.dumps(header)) - 4)
        self.assertEqual(expected_hex, wire.hex())


if __name__ == "__main__":
    unittest.main()
