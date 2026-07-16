import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator


ROOT = Path(__file__).resolve().parents[3]
TEMPLATES = ROOT / "evidence" / "templates"
FIXTURES = ROOT / "evidence" / "fixtures"
SHA_A = "a" * 64
SHA_B = "b" * 64
SHA_C = "c" * 64


def load_schema(name: str) -> dict:
    with (TEMPLATES / name).open("r", encoding="utf-8") as handle:
        return json.load(handle)


def artifact() -> dict:
    return {
        "opaque_artifact_id": "opaque-gate-002-run-0001",
        "artifact_kind": "automated_report",
        "sha256": SHA_A,
        "external_retention": True,
    }


def base_report(state: str = "UNRUN", actor: str = "automation") -> dict:
    report = {
        "schema_version": "1.0.0",
        "gate_id": "GATE-002",
        "gate_state": state,
        "decision_actor": actor,
        "recorded_at_utc": "2026-07-16T10:15:30Z",
        "implementation_revision": "git:0123456789abcdef0123456789abcdef01234567",
        "test_ids": ["TST-COORD-001"],
        "requirement_ids": ["NFR-COORD-001"],
        "adr_ids": ["ADR-003"],
        "fixture_refs": [
            {
                "fixture_id": "FX-COORD-001",
                "fixture_revision": "rev-001",
                "sha256": SHA_A,
            }
        ],
        "environment": {
            "device_model": None,
            "os_version": None,
            "xcode_version": None,
            "runtime_tier": "local-contract-runner",
            "capability_flags": {
                "camera_permission": "not_tested",
                "arkit_world_tracking": "not_tested",
                "plane_detection": "not_tested",
                "lidar_required": False,
            },
            "signing_result": "not_tested",
        },
        "value_classification": "TARGET",
        "evidence_artifacts": [],
        "automated_report_sha256": None,
        "operator_checklist_sha256": None,
        "locked_decision_change_id": None,
        "prd_sha256": None,
        "affected_adr_sha256": [],
    }
    if state == "RUNNING":
        report["evidence_artifacts"] = [artifact()]
    elif state == "RED":
        report["evidence_artifacts"] = [artifact()]
        report["automated_report_sha256"] = SHA_A
    elif state == "GREEN":
        report["decision_actor"] = "human"
        report["value_classification"] = "MEASURED"
        report["evidence_artifacts"] = [artifact()]
        report["automated_report_sha256"] = SHA_A
        report["operator_checklist_sha256"] = SHA_B
    elif state == "WAIVED_BY_HUMAN":
        report["decision_actor"] = "human"
        report["evidence_artifacts"] = [artifact()]
        report["operator_checklist_sha256"] = SHA_B
        report["locked_decision_change_id"] = "OD-2026-001"
        report["prd_sha256"] = SHA_C
        report["affected_adr_sha256"] = [{"adr_id": "ADR-003", "sha256": SHA_A}]
    return report


def base_checklist(decision: str = "GREEN") -> dict:
    items = [
        {"check_id": "automated_report_reviewed", "outcome": "checked"},
        {"check_id": "evidence_links_verified", "outcome": "checked"},
        {"check_id": "privacy_redaction_reviewed", "outcome": "checked"},
        {"check_id": "physical_or_human_observations_approved", "outcome": "checked"},
    ]
    if decision == "WAIVED_BY_HUMAN":
        items = [
            {"check_id": "locked_decision_change_verified", "outcome": "checked"},
            {"check_id": "prd_update_verified", "outcome": "checked"},
            {"check_id": "affected_adr_updates_verified", "outcome": "checked"},
            {"check_id": "privacy_redaction_reviewed", "outcome": "checked"},
        ]
    return {
        "schema_version": "1.0.0",
        "gate_id": "GATE-002",
        "decision": decision,
        "decision_actor": "human",
        "report_sha256": SHA_A,
        "reviewed_at_utc": "2026-07-16T10:20:30Z",
        "checklist_items": items,
        "signature_sha256": SHA_B,
    }


class GateReportSchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.schema = load_schema("gate-report.schema.json")
        Draft202012Validator.check_schema(cls.schema)
        cls.validator = Draft202012Validator(cls.schema)

    def assert_valid(self, instance: dict) -> None:
        self.assertEqual([], list(self.validator.iter_errors(instance)))

    def assert_rejected(self, instance: dict) -> None:
        self.assertTrue(list(self.validator.iter_errors(instance)))

    def test_accepts_all_five_canonical_states(self) -> None:
        for state in ("UNRUN", "RUNNING", "GREEN", "RED", "WAIVED_BY_HUMAN"):
            with self.subTest(state=state):
                self.assert_valid(base_report(state))

    def test_rejects_unknown_state_actor_and_property(self) -> None:
        unknown_state = base_report()
        unknown_state["gate_state"] = "PASS"
        self.assert_rejected(unknown_state)
        unknown_actor = base_report()
        unknown_actor["decision_actor"] = "service"
        self.assert_rejected(unknown_actor)
        self.assert_rejected(dict(base_report(), device_uuid="private"))

    def test_automation_can_only_emit_unrun_running_or_red(self) -> None:
        for state in ("GREEN", "WAIVED_BY_HUMAN"):
            report = base_report(state)
            report["decision_actor"] = "automation"
            with self.subTest(state=state):
                self.assert_rejected(report)

    def test_green_requires_automated_report_and_signed_checklist_digests(self) -> None:
        for field in ("automated_report_sha256", "operator_checklist_sha256"):
            report = base_report("GREEN")
            report[field] = None
            with self.subTest(field=field):
                self.assert_rejected(report)

    def test_green_rejects_waiver_fields_and_target_only_claim(self) -> None:
        report = base_report("GREEN")
        report["locked_decision_change_id"] = "OD-2026-001"
        self.assert_rejected(report)
        report = base_report("GREEN")
        report["value_classification"] = "TARGET"
        self.assert_rejected(report)

    def test_waiver_requires_lock_prd_adr_updates_and_signed_checklist(self) -> None:
        invalid_mutations = (
            ("locked_decision_change_id", None),
            ("prd_sha256", None),
            ("affected_adr_sha256", []),
            ("operator_checklist_sha256", None),
        )
        for field, value in invalid_mutations:
            report = base_report("WAIVED_BY_HUMAN")
            report[field] = value
            with self.subTest(field=field):
                self.assert_rejected(report)

    def test_rejects_private_fields_paths_and_malformed_artifacts(self) -> None:
        forbidden_fields = ("device_uuid", "team_id", "account", "user_path", "raw_logs")
        for field in forbidden_fields:
            report = base_report("RED")
            report[field] = "private"
            with self.subTest(field=field):
                self.assert_rejected(report)
        report = base_report("RED")
        report["evidence_artifacts"][0]["opaque_artifact_id"] = "/Users/name/raw.log"
        self.assert_rejected(report)
        report = base_report("RED")
        report["evidence_artifacts"][0]["sha256"] = "not-a-digest"
        self.assert_rejected(report)


class OperatorChecklistSchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.schema = load_schema("operator-checklist.schema.json")
        Draft202012Validator.check_schema(cls.schema)
        cls.validator = Draft202012Validator(cls.schema)

    def assert_valid(self, instance: dict) -> None:
        self.assertEqual([], list(self.validator.iter_errors(instance)))

    def assert_rejected(self, instance: dict) -> None:
        self.assertTrue(list(self.validator.iter_errors(instance)))

    def test_accepts_report_bound_signed_green_and_waiver_checklists(self) -> None:
        self.assert_valid(base_checklist("GREEN"))
        self.assert_valid(base_checklist("WAIVED_BY_HUMAN"))

    def test_rejects_automation_unsigned_unknown_and_extra_properties(self) -> None:
        automation = base_checklist()
        automation["decision_actor"] = "automation"
        self.assert_rejected(automation)
        unsigned = base_checklist()
        unsigned["signature_sha256"] = None
        self.assert_rejected(unsigned)
        unknown = base_checklist()
        unknown["decision"] = "RED"
        self.assert_rejected(unknown)
        self.assert_rejected(dict(base_checklist(), operator_account="private"))

    def test_green_requires_every_approval_check(self) -> None:
        checklist = base_checklist()
        checklist["checklist_items"] = checklist["checklist_items"][:-1]
        self.assert_rejected(checklist)

    def test_waiver_requires_every_escalation_check(self) -> None:
        checklist = base_checklist("WAIVED_BY_HUMAN")
        checklist["checklist_items"] = checklist["checklist_items"][:-1]
        self.assert_rejected(checklist)

    def test_rejects_malformed_report_and_signature_digests(self) -> None:
        for field in ("report_sha256", "signature_sha256"):
            checklist = base_checklist()
            checklist[field] = "ABC"
            with self.subTest(field=field):
                self.assert_rejected(checklist)


class CheckedInEvidenceFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.gate_validator = Draft202012Validator(load_schema("gate-report.schema.json"))
        cls.checklist_validator = Draft202012Validator(load_schema("operator-checklist.schema.json"))

    def validator_for(self, path: Path) -> Draft202012Validator:
        if path.name.startswith("gate-report."):
            return self.gate_validator
        if path.name.startswith("operator-checklist."):
            return self.checklist_validator
        self.fail(f"fixture name does not identify its schema: {path.name}")

    def test_all_valid_fixtures_validate(self) -> None:
        paths = sorted((FIXTURES / "valid").glob("*.json"))
        self.assertGreaterEqual(len(paths), 7)
        for path in paths:
            with self.subTest(path=path.name):
                instance = json.loads(path.read_text(encoding="utf-8"))
                self.assertEqual([], list(self.validator_for(path).iter_errors(instance)))

    def test_all_invalid_fixtures_fail_closed(self) -> None:
        paths = sorted((FIXTURES / "invalid").glob("*.json"))
        self.assertGreaterEqual(len(paths), 12)
        for path in paths:
            with self.subTest(path=path.name):
                instance = json.loads(path.read_text(encoding="utf-8"))
                self.assertTrue(list(self.validator_for(path).iter_errors(instance)))

    def test_negative_fixtures_cover_every_forbidden_private_field(self) -> None:
        names = {path.name for path in (FIXTURES / "invalid").glob("*.json")}
        required = {
            "gate-report.invalid.device-uuid.json",
            "gate-report.invalid.team-id.json",
            "gate-report.invalid.account.json",
            "gate-report.invalid.user-path.json",
            "gate-report.invalid.raw-room-bytes.json",
            "gate-report.invalid.raw-logs.json",
            "gate-report.invalid.signing-material.json",
            "gate-report.invalid.private-artifact-path.json",
            "gate-report.invalid.automation-waiver.json",
        }
        self.assertEqual(set(), required - names)


if __name__ == "__main__":
    unittest.main()
