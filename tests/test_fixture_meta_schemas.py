import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[1]
SHA_A = "a" * 64
SHA_B = "b" * 64


def load_schema(name: str) -> dict:
    with (ROOT / "fixtures" / name).open("r", encoding="utf-8") as handle:
        return json.load(handle)


def schema_hashes() -> list[dict]:
    contracts = (
        ("CON-001", "urn:reroom:schema:frame-packet:1", "docs/contracts/frame-packet.schema.json"),
        ("CON-002", "urn:reroom:schema:rrcap-manifest:1", "docs/contracts/rrcap-manifest.schema.json"),
        ("CON-003", "urn:reroom:schema:scene-state:1", "docs/contracts/scene-state.schema.json"),
        ("CON-004", "urn:reroom:schema:edit-artifacts:1", "docs/contracts/edit-artifacts.schema.json"),
        ("CON-005", "urn:reroom:schema:transaction:1", "docs/contracts/transaction.schema.json"),
    )
    return [
        {
            "contract_id": contract_id,
            "schema_id": schema_id,
            "relative_path": path,
            "sha256": SHA_A,
        }
        for contract_id, schema_id, path in contracts
    ]


def fixture_case(case_id: str, verdict: str = "accept") -> dict:
    rejection_class = None if verdict == "accept" else "schema_validation"
    return {
        "case_id": case_id,
        "case_kind": "json_instance",
        "input": {
            "relative_path": f"cases/{case_id}/input.json",
            "media_type": "application/json",
            "byte_length": 2,
            "sha256": SHA_A,
        },
        "expected": {
            "verdict": verdict,
            "rejection_class": rejection_class,
            "artifacts": [],
        },
        "immutable": True,
    }


class FixtureManifestSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.schema = load_schema("manifest.schema.json")
        Draft202012Validator.check_schema(self.schema)
        self.validator = Draft202012Validator(self.schema)
        self.instance = {
            "schema_version": "1.0.0",
            "fixture_id": "FX-CONTRACT-001",
            "fixture_revision": "rev-001",
            "subject": "CON-001-CON-005",
            "oracle": {
                "status": "immutable",
                "source": "checked_in",
                "expected_generation": "forbidden_during_verification",
                "case_order": "lexicographic_case_id",
                "generator_role": "proposal_only",
            },
            "limits": {
                "max_document_depth": 64,
                "max_cases": 2048,
                "max_file_bytes": 33554432,
                "max_path_bytes": 240,
            },
            "schema_hashes": schema_hashes(),
            "cases": [fixture_case("contract.frame.valid-minimal")],
        }

    def assert_rejected(self, instance: dict) -> None:
        self.assertTrue(list(self.validator.iter_errors(instance)))

    def test_accepts_closed_immutable_manifest(self) -> None:
        self.assertFalse(list(self.validator.iter_errors(self.instance)))

    def test_rejects_unknown_fields_nulls_and_empty_cases(self) -> None:
        unknown = dict(self.instance, surprise=True)
        self.assert_rejected(unknown)
        null_revision = dict(self.instance, fixture_revision=None)
        self.assert_rejected(null_revision)
        empty_cases = dict(self.instance, cases=[])
        self.assert_rejected(empty_cases)

    def test_rejects_missing_schema_hash_and_invalid_case_boundary(self) -> None:
        four_hashes = dict(self.instance, schema_hashes=schema_hashes()[:-1])
        self.assert_rejected(four_hashes)
        oversized = fixture_case("contract.frame.oversized")
        oversized["input"]["byte_length"] = 33554433
        invalid_case = dict(self.instance, cases=[oversized])
        self.assert_rejected(invalid_case)

    def test_rejects_accept_with_rejection_class_and_reject_without_one(self) -> None:
        accept = fixture_case("contract.frame.accept-class")
        accept["expected"]["rejection_class"] = "schema_validation"
        self.assert_rejected(dict(self.instance, cases=[accept]))
        reject = fixture_case("contract.frame.reject-class", "reject")
        reject["expected"]["rejection_class"] = None
        self.assert_rejected(dict(self.instance, cases=[reject]))


class RunnerResultSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.schema = load_schema("runner-result.schema.json")
        Draft202012Validator.check_schema(self.schema)
        self.validator = Draft202012Validator(self.schema)
        self.instance = {
            "schema_version": "1.0.0",
            "runner": {
                "runtime": "python",
                "name": "reroom-python-reference",
                "version": "1.0.0",
                "implementation_revision": "git:0123456789abcdef0123456789abcdef01234567",
            },
            "fixture": {
                "fixture_id": "FX-CONTRACT-001",
                "fixture_revision": "rev-001",
                "manifest_sha256": SHA_A,
            },
            "case_order": "lexicographic_case_id",
            "case_results": [
                {
                    "case_id": "contract.frame.valid-minimal",
                    "verdict": "accept",
                    "rejection_class": None,
                    "output_artifacts": [],
                }
            ],
            "summary": {"total": 1, "accepted": 1, "rejected": 0},
            "oracle_unchanged": True,
            "result_digest_algorithm": "RR-JCS-SHA256-1",
            "result_digest_scope": "entire_runner_result_with_result_digest_sha256_omitted",
            "result_digest_sha256": SHA_B,
        }

    def assert_rejected(self, instance: dict) -> None:
        self.assertTrue(list(self.validator.iter_errors(instance)))

    def test_accepts_normalized_runtime_result(self) -> None:
        self.assertFalse(list(self.validator.iter_errors(self.instance)))

    def test_rejects_unknown_runtime_and_empty_results(self) -> None:
        unknown_runtime = json.loads(json.dumps(self.instance))
        unknown_runtime["runner"]["runtime"] = "ruby"
        self.assert_rejected(unknown_runtime)
        empty_results = dict(self.instance, case_results=[])
        self.assert_rejected(empty_results)

    def test_rejects_result_that_mutated_oracle(self) -> None:
        self.assert_rejected(dict(self.instance, oracle_unchanged=False))


if __name__ == "__main__":
    unittest.main()
