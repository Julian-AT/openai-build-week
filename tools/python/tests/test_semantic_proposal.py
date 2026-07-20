from __future__ import annotations

import copy
import hashlib
import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker


ROOT = Path(__file__).resolve().parents[3]
SCHEMA_PATH = ROOT / "docs/contracts/semantic-proposal.schema.json"
FIXTURE_PATH = ROOT / "fixtures/semantic-proposals/1.0.0/rev-001/cases.json"


class SemanticProposalContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.schema_bytes = SCHEMA_PATH.read_bytes()
        cls.schema = json.loads(cls.schema_bytes)
        cls.fixtures = json.loads(FIXTURE_PATH.read_bytes())
        Draft202012Validator.check_schema(cls.schema)
        cls.validator = Draft202012Validator(
            cls.schema,
            format_checker=FormatChecker(),
        )

    def test_fixture_revision_is_sorted_unique_and_bound_to_schema(self) -> None:
        self.assertEqual(self.fixtures["fixture_id"], "FX-SEMANTIC-PROPOSAL-001")
        self.assertEqual(self.fixtures["contract_id"], "CON-006")
        self.assertEqual(
            self.fixtures["contract_schema_sha256"],
            hashlib.sha256(self.schema_bytes).hexdigest(),
        )
        case_ids = [case["case_id"] for case in self.fixtures["cases"]]
        self.assertEqual(len(case_ids), 10)
        self.assertEqual(case_ids, sorted(case_ids))
        self.assertEqual(len(case_ids), len(set(case_ids)))

    def test_all_accepted_gateway_vectors_are_valid_con006(self) -> None:
        accepted = [
            case["expected_envelope"]
            for case in self.fixtures["cases"]
            if case["expected_verdict"] == "accept"
        ]
        self.assertEqual(len(accepted), 3)
        for envelope in accepted:
            with self.subTest(envelope_id=envelope["envelope_id"]):
                self.validator.validate(envelope)

    def test_closed_schema_rejects_authority_and_unsafe_mutations(self) -> None:
        ready = copy.deepcopy(
            next(
                case["expected_envelope"]
                for case in self.fixtures["cases"]
                if case["case_id"] == "semantic.valid.ready"
            )
        )

        mutations: dict[str, object] = {}

        commit = copy.deepcopy(ready)
        commit["commit"] = True
        mutations["root commit authority"] = commit

        transform = copy.deepcopy(ready)
        transform["intent"]["world_from_asset"] = [1, 0, 0, 0]
        mutations["intent transform authority"] = transform

        unsafe_url = copy.deepcopy(ready)
        unsafe_url["explanation"] = "Open https://attacker.invalid"
        mutations["URL copy"] = unsafe_url

        unknown_asset = copy.deepcopy(ready)
        unknown_asset["intent"]["arguments"]["asset_id"] = (
            "asset_53000000-0000-4000-8000-000000000099"
        )
        mutations["unknown asset"] = unknown_asset

        unsafe_response = copy.deepcopy(ready)
        unsafe_response["semantic_model"]["response_id"] = "response id with spaces"
        mutations["unsafe response id"] = unsafe_response

        wrong_nullability = copy.deepcopy(ready)
        wrong_nullability["intent"] = None
        wrong_nullability["clarification"] = "Which object?"
        mutations["ready nullability"] = wrong_nullability

        missing_context_member = copy.deepcopy(ready)
        del missing_context_member["request_context"]["selected_object_id"]
        mutations["missing selected-object key"] = missing_context_member

        duplicate_constraint = copy.deepcopy(ready)
        duplicate_constraint["intent"]["constraints"] *= 2
        mutations["duplicate constraint"] = duplicate_constraint

        for name, envelope in mutations.items():
            with self.subTest(name=name):
                self.assertFalse(self.validator.is_valid(envelope))


if __name__ == "__main__":
    unittest.main()
