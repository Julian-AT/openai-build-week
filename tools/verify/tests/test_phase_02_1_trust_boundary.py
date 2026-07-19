"""Fail-closed tests for the Phase 02.1 narrow automated handoff."""

from __future__ import annotations

import copy
import hashlib
import json
import unittest
from pathlib import Path
from typing import Any

from tools.verify import verify_phase_02_1_trust_boundary as verifier


ROOT = Path(__file__).resolve().parents[3]


def _canonical(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def _resign(record: dict[str, Any]) -> dict[str, Any]:
    value = copy.deepcopy(record)
    value.pop("record_sha256", None)
    value["record_sha256"] = hashlib.sha256(_canonical(value)).hexdigest()
    return value


class Phase021TrustBoundaryTests(unittest.TestCase):
    maxDiff = None

    def setUp(self) -> None:
        self.revision = "git:" + "1" * 40
        fixture_root = ROOT / "fixtures/capture/1.0.0/rev-001"
        self.fixture_paths = tuple(
            path.relative_to(ROOT).as_posix()
            for path in sorted(fixture_root.rglob("*"))
            if path.is_file()
        )
        self.environment = {
            "platform": "Darwin test arm64",
            "python": "Python 3.14.0",
            "swift": "Swift version 6.2",
            "xcode": "Xcode 26.4 Build version 17E000",
        }
        self.revision_bytes = {
            path: f"immutable:{path}".encode("utf-8")
            for path in (
                *verifier.BEHAVIOR_SOURCE_PATHS,
                *verifier.SCHEMA_PATHS,
                *self.fixture_paths,
            )
        }
        self.command_outputs = {
            spec.check_id: f"{spec.check_id}: deterministic pass\n"
            for spec in verifier.command_specs(self.revision.removeprefix("git:"))
        }
        self.raw_results = [
            {
                "check_id": spec.check_id,
                "argv": list(spec.argv),
                "exit_code": 0,
                "output": self.command_outputs[spec.check_id],
            }
            for spec in verifier.command_specs(self.revision.removeprefix("git:"))
        ]
        self.record = verifier.build_candidate_record(
            revision=self.revision,
            command_results=self.raw_results,
            environment=self.environment,
            revision_reader=self._revision_reader,
            fixture_paths=self.fixture_paths,
        )

    def _revision_reader(self, path: str) -> bytes:
        return self.revision_bytes[path]

    def _working_reader(self, path: str) -> bytes:
        return self.revision_bytes[path]

    def _runner(self, spec: verifier.CommandSpec) -> dict[str, Any]:
        return {
            "check_id": spec.check_id,
            "argv": list(spec.argv),
            "exit_code": 0,
            "output": self.command_outputs[spec.check_id],
        }

    def _verify(
        self,
        record: dict[str, Any] | None = None,
        *,
        working_reader: Any | None = None,
        runner: Any | None = None,
    ) -> None:
        verifier.verify_candidate_record(
            record or self.record,
            revision_reader=self._revision_reader,
            working_reader=working_reader or self._working_reader,
            fixture_paths=self.fixture_paths,
            command_runner=runner or self._runner,
            environment=self.environment,
        )

    def _assert_code(self, code: str, record: dict[str, Any]) -> None:
        with self.assertRaises(verifier.EvidenceVerificationError) as caught:
            self._verify(record)
        self.assertEqual(code, caught.exception.code)

    def test_exact_record_is_recomputed_and_accepted(self) -> None:
        self._verify()
        self.assertEqual(
            ["CR-03", "CR-04", "CR-12"],
            [item["review_id"] for item in self.record["candidate_findings"]],
        )
        self.assertEqual(
            list(verifier.REQUIRED_CHECK_IDS),
            [item["check_id"] for item in self.record["verification"]["commands"]],
        )

    def test_extra_or_missing_candidate_finding_is_rejected(self) -> None:
        extra = copy.deepcopy(self.record)
        extra["candidate_findings"].append(
            {"review_id": "CR-05", "status": "AUTOMATED_REVIEW_CANDIDATE"}
        )
        self._assert_code("SCOPE_IDS", _resign(extra))

        missing = copy.deepcopy(self.record)
        missing["candidate_findings"].pop()
        self._assert_code("SCOPE_IDS", _resign(missing))

    def test_stored_verdict_only_pass_is_not_evidence(self) -> None:
        changed = copy.deepcopy(self.record)
        changed["verification"]["commands"] = [
            {"check_id": item["check_id"], "status": "PASS"}
            for item in changed["verification"]["commands"]
        ]
        self._assert_code("COMMAND_RESULT_SHAPE", _resign(changed))

    def test_stale_source_schema_and_fixture_inventory_digests_are_rejected(self) -> None:
        source = copy.deepcopy(self.record)
        source["implementation"]["behavior_sources"][0]["sha256"] = "0" * 64
        self._assert_code("SOURCE_BINDING", _resign(source))

        schema = copy.deepcopy(self.record)
        schema["implementation"]["schemas"][0]["sha256"] = "0" * 64
        self._assert_code("SCHEMA_BINDING", _resign(schema))

        fixture = copy.deepcopy(self.record)
        fixture["implementation"]["fixture_inventory"]["members"][0]["sha256"] = "0" * 64
        self._assert_code("FIXTURE_BINDING", _resign(fixture))

    def test_omitted_focused_suite_is_rejected(self) -> None:
        changed = copy.deepcopy(self.record)
        changed["verification"]["commands"] = [
            item
            for item in changed["verification"]["commands"]
            if item["check_id"] != "capture_crash_matrix_tests"
        ]
        self._assert_code("COMMAND_INVENTORY", _resign(changed))

    def test_mutable_head_alias_is_rejected(self) -> None:
        changed = copy.deepcopy(self.record)
        changed["implementation"]["revision"] = "HEAD"
        self._assert_code("REVISION_IMMUTABLE", _resign(changed))

    def test_dirty_behavior_source_is_rejected(self) -> None:
        dirty_path = verifier.BEHAVIOR_SOURCE_PATHS[0]

        def dirty_reader(path: str) -> bytes:
            if path == dirty_path:
                return self.revision_bytes[path] + b"dirty"
            return self.revision_bytes[path]

        with self.assertRaises(verifier.EvidenceVerificationError) as caught:
            self._verify(working_reader=dirty_reader)
        self.assertEqual("DIRTY_BEHAVIOR_SOURCE", caught.exception.code)

    def test_physical_or_human_claim_is_rejected(self) -> None:
        physical = copy.deepcopy(self.record)
        physical["outer_status"]["physical_evidence"] = "complete"
        self._assert_code("PHYSICAL_CLAIM", _resign(physical))

        human = copy.deepcopy(self.record)
        human["outer_status"]["human_evidence"] = "complete"
        self._assert_code("PHYSICAL_CLAIM", _resign(human))

    def test_phase_gate_or_milestone_promotion_is_rejected(self) -> None:
        phase = copy.deepcopy(self.record)
        phase["outer_status"]["phase_2"] = "COMPLETE"
        self._assert_code("OUTER_STATUS", _resign(phase))

        gate = copy.deepcopy(self.record)
        gate["outer_status"]["gate_001"] = "GREEN"
        self._assert_code("OUTER_STATUS", _resign(gate))

        milestone = copy.deepcopy(self.record)
        milestone["outer_status"]["milestone_v1_0"] = "COMPLETE"
        self._assert_code("OUTER_STATUS", _resign(milestone))

    def test_another_review_finding_cannot_be_closed(self) -> None:
        changed = copy.deepcopy(self.record)
        changed["remaining_findings"][0]["status"] = "CLOSED"
        self._assert_code("REMAINING_FINDINGS", _resign(changed))

    def test_rerun_failure_and_output_drift_are_rejected(self) -> None:
        failed_id = verifier.REQUIRED_CHECK_IDS[0]

        def failing(spec: verifier.CommandSpec) -> dict[str, Any]:
            value = self._runner(spec)
            if spec.check_id == failed_id:
                value["exit_code"] = 1
                value["output"] = "failed"
            return value

        with self.assertRaises(verifier.EvidenceVerificationError) as caught:
            self._verify(runner=failing)
        self.assertEqual("COMMAND_FAILED", caught.exception.code)

        def drifted(spec: verifier.CommandSpec) -> dict[str, Any]:
            value = self._runner(spec)
            if spec.check_id == failed_id:
                value["output"] += "changed"
            return value

        with self.assertRaises(verifier.EvidenceVerificationError) as caught:
            self._verify(runner=drifted)
        self.assertEqual("COMMAND_OUTPUT", caught.exception.code)

    def test_environment_and_inventory_format_drift_are_rejected(self) -> None:
        environment = copy.deepcopy(self.record)
        environment["environment"]["swift"] = "Swift version unknown"
        self._assert_code("ENVIRONMENT_BINDING", _resign(environment))

        inventory = copy.deepcopy(self.record)
        inventory["implementation"]["active_generation_inventory_format"][
            "format_sha256"
        ] = "0" * 64
        self._assert_code("INVENTORY_FORMAT", _resign(inventory))

    def test_self_digest_and_canonical_bytes_are_enforced(self) -> None:
        changed = copy.deepcopy(self.record)
        changed["record_sha256"] = "0" * 64
        self._assert_code("SELF_DIGEST", changed)

        encoded = verifier.serialize_record(self.record)
        verifier.decode_record(encoded)
        with self.assertRaises(verifier.EvidenceVerificationError) as caught:
            verifier.decode_record(json.dumps(self.record, indent=2).encode("utf-8"))
        self.assertEqual("NONCANONICAL_RECORD", caught.exception.code)

    def test_private_host_path_and_unknown_fields_are_rejected(self) -> None:
        private = copy.deepcopy(self.record)
        private["limitations"][0] = "/Users/private/raw-room.mov"
        self._assert_code("PRIVACY_UNSAFE", _resign(private))

        unknown = copy.deepcopy(self.record)
        unknown["gate_report"] = {"gate_state": "GREEN"}
        self._assert_code("FIELD_SET", _resign(unknown))


if __name__ == "__main__":
    unittest.main()
