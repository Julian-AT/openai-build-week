import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator

from tools.verify import verify_phase_02_gate as gate
from tools.verify.verify_evidence import report_decision_sha256, unsigned_checklist_sha256


ROOT = Path(__file__).resolve().parents[3]
TEMPLATES = ROOT / "evidence" / "templates"
SHA_A = "a" * 64
SHA_B = "b" * 64
SHA_C = "c" * 64
SHA_D = "d" * 64
REVISION = "git:0123456789abcdef0123456789abcdef01234567"
BUILD_REVISION = "phase-02-release-candidate-001"
EVALUATOR_ID = "opaque-evaluator-gate-001-0001"


def canonical_bytes(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def digest(value: object) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def environment() -> dict:
    return {
        "device_model": "iPhone 17",
        "os_version": "iOS candidate",
        "xcode_version": "Xcode candidate",
        "runtime_tier": "base-iphone-17",
        "capability_flags": {
            "camera_permission": "granted",
            "arkit_world_tracking": "pass",
            "plane_detection": "pass",
            "lidar_required": False,
        },
        "signing_result": "pass",
    }


def fixture(fixture_id: str, sha256: str) -> dict:
    return {
        "fixture_id": fixture_id,
        "fixture_revision": "rev-001",
        "sha256": sha256,
    }


def external_artifact(identifier: str, sha256: str, kind: str = "trace") -> dict:
    return {
        "opaque_artifact_id": identifier,
        "artifact_kind": kind,
        "artifact_role": "supporting_evidence",
        "sha256": sha256,
        "external_retention": True,
    }


def replay(run_suffix: str, journal_sha: str = SHA_A) -> dict:
    return {
        "replay_id": f"opaque-replay-{run_suffix}",
        "evaluator_id": EVALUATOR_ID,
        "journal_digest_sha256": journal_sha,
        "projection_digest_sha256": SHA_B,
        "accepted_order_digest_sha256": SHA_C,
        "matches_expected": True,
    }


def physical_run(state: str, seconds: int) -> dict:
    duration_name = "010s" if seconds == 10 else "060s"
    fixture_id = f"FX-RRCAP-{duration_name.upper()}"
    prefix = {
        "selected": [],
        "image_and_metadata_durable": [],
        "journaled": [1],
        "network_eligible": [1],
        "server_acknowledged": [1],
    }[state]
    journal_sha = hashlib.sha256(f"{state}-{seconds}".encode()).hexdigest()
    return {
        "fixture_id": fixture_id,
        "target_duration_seconds": seconds,
        "observed_duration_milliseconds": seconds * 1000,
        "build_revision": BUILD_REVISION,
        "evaluator_id": EVALUATOR_ID,
        "environment_sha256": digest(environment()),
        "raw_artifact": {
            "opaque_artifact_id": f"opaque-gate-001-{state.replace('_', '-')}-{duration_name}",
            "sha256": hashlib.sha256(f"raw-{state}-{seconds}".encode()).hexdigest(),
            "external_retention": True,
        },
        "consent_state": "granted",
        "local_capture_state": "recovered_hash_valid_prefix",
        "upload_state": "paused_or_blackholed",
        "packet_image_binding_valid": True,
        "non_journaled_upload_reference_count": 0,
        "earlier_record_corruption_count": 0,
        "expected_recovered_global_sequence": prefix,
        "actual_recovered_global_sequence": prefix,
        "recovered_prefix_exact": True,
        "queue_observation": {
            "capacity": 3,
            "maximum_depth": 3,
            "stale_drop_count": 2,
            "pressure_applied": True,
            "network_blackholed": True,
            "upload_paused_first": True,
        },
        "replays": [
            replay(f"{state.replace('_', '-')}-{duration_name}-a", journal_sha),
            replay(f"{state.replace('_', '-')}-{duration_name}-b", journal_sha),
        ],
    }


def observations() -> dict:
    env = environment()
    return {
        "schema_version": "1.0.0",
        "gate_id": "GATE-001",
        "decision_actor": "human",
        "evidence_origin": "physical_base_device",
        "value_classification": "MEASURED",
        "recorded_at_utc": "2026-07-18T10:00:00Z",
        "implementation_revision": REVISION,
        "build_revision": BUILD_REVISION,
        "evaluator_id": EVALUATOR_ID,
        "environment": env,
        "environment_sha256": digest(env),
        "fixture_refs": [
            fixture("FX-RRCAP-010S", SHA_A),
            fixture("FX-RRCAP-060S", SHA_B),
        ],
        "consent_denial_observation": {
            "attempted": True,
            "local_capture_created": False,
            "upload_reference_count": 0,
            "raw_artifact": {
                "opaque_artifact_id": "opaque-gate-001-consent-denial",
                "sha256": SHA_C,
                "external_retention": True,
            },
        },
        "termination_observations": [
            {
                "termination_state": state,
                "build_revision": BUILD_REVISION,
                "evaluator_id": EVALUATOR_ID,
                "environment_sha256": digest(env),
                "runs": [physical_run(state, 10), physical_run(state, 60)],
            }
            for state in gate.CANONICAL_TERMINATION_STATES
        ],
        "fallback_and_kill_acknowledgement": {
            "pause_upload_first": True,
            "preserve_valid_local_prefix": True,
            "provider_work_uses_replay_fixtures_only_if_red": True,
            "live_integration_blocked_unless_green": True,
        },
    }


def preflight() -> dict:
    value = {
        "schema_version": "1.0.0",
        "gate_id": "GATE-001",
        "gate_state": "RUNNING",
        "decision_actor": "automation",
        "recorded_at_utc": "2026-07-18T09:00:00Z",
        "implementation_revision": REVISION,
        "source_tree_sha256": SHA_B,
        "fixture_refs": [
            fixture("FX-PREFLIGHT-CAPTURE-SHORT", SHA_C),
            fixture("FX-PREFLIGHT-CAPTURE-LONG", SHA_D),
        ],
        "environment": {
            "runtime_tier": "local-deterministic-preflight",
            "platform": "macOS",
            "python": "Python 3.13.12",
            "swift": "Apple Swift version 6.3",
            "node": "v22.22.3",
            "xcode": "Xcode 26.0",
        },
        "value_classification": "HYPOTHESIS",
        "checks": [
            {"check_id": check_id, "status": "PASS", "output_sha256": SHA_A}
            for check_id in gate.FULL_CHECK_IDS
        ],
        "synthetic_metrics": [
            {
                "metric_id": "queue_capacity_bound",
                "value": 3,
                "unit": "items",
                "value_classification": "HYPOTHESIS",
            }
        ],
        "evidence_bindings": [
            {
                "evidence_id": "evidence_phase_02_replay_agreement_rev_001",
                "sha256": SHA_C,
                "implementation_revision": "git:0d371bc1de9a057cbf61b70142729f6cbe620eec",
            }
        ],
        "physical_evidence_state": "pending",
        "limitations": [
            "This automated preflight is not physical-device GATE-001 evidence.",
            "The NFR-REPLAY-001 three-minute goal remains a hypothesis until separately measured with raw timing evidence.",
        ],
    }
    value["preflight_sha256"] = digest(value)
    return value


def pending_report(preflight_sha: str) -> dict:
    return {
        "schema_version": "2.0.0",
        "gate_id": "GATE-001",
        "gate_state": "RUNNING",
        "decision_actor": "automation",
        "recorded_at_utc": "2026-07-18T09:05:00Z",
        "implementation_revision": REVISION,
        "test_ids": ["TST-CAPTURE-001", "TST-REPLAY-001", "TST-QUEUE-001"],
        "requirement_ids": [
            "FR-CAPTURE-001",
            "FR-B0-001",
            "NFR-REPLAY-001",
            "SEC-CONSENT-001",
        ],
        "adr_ids": ["ADR-004", "ADR-013", "ADR-014"],
        "fixture_refs": [
            fixture("FX-RRCAP-010S", SHA_A),
            fixture("FX-RRCAP-060S", SHA_B),
        ],
        "environment": environment(),
        "value_classification": "TARGET",
        "evidence_artifacts": [
            external_artifact("opaque-gate-001-automated-preflight", preflight_sha, "automated_report")
        ],
        "automated_report_sha256": None,
        "operator_checklist_sha256": None,
        "locked_decision_change_id": None,
        "prd_sha256": None,
        "affected_adr_sha256": [],
    }


def green_pair(preflight_sha: str, observation_sha: str) -> tuple[dict, dict]:
    report = pending_report(preflight_sha)
    report.update(
        gate_state="GREEN",
        decision_actor="human",
        value_classification="MEASURED",
        automated_report_sha256=preflight_sha,
    )
    report["evidence_artifacts"].extend(
        [
            external_artifact("opaque-gate-001-physical-observations", observation_sha),
            {
                "opaque_artifact_id": "opaque-gate-001-operator-attestation",
                "artifact_kind": "ballot",
                "artifact_role": "operator_attestation",
                "sha256": SHA_D,
                "external_retention": True,
            },
        ]
    )
    checklist = {
        "schema_version": "2.0.0",
        "gate_id": "GATE-001",
        "decision": "GREEN",
        "decision_actor": "human",
        "automated_report_sha256": preflight_sha,
        "report_decision_sha256": report_decision_sha256(report),
        "reviewed_at_utc": "2026-07-18T10:10:00Z",
        "checklist_items": [
            {"check_id": "automated_report_reviewed", "outcome": "checked"},
            {"check_id": "evidence_links_verified", "outcome": "checked"},
            {"check_id": "privacy_redaction_reviewed", "outcome": "checked"},
            {"check_id": "physical_or_human_observations_approved", "outcome": "checked"},
        ],
        "signature_scope": "RR-GATE-CHECKLIST-SHA256-1",
        "unsigned_checklist_sha256": SHA_A,
        "signature_sha256": SHA_D,
    }
    checklist["unsigned_checklist_sha256"] = unsigned_checklist_sha256(checklist)
    return report, checklist


def write_json(path: Path, value: object) -> bytes:
    data = canonical_bytes(value) + b"\n"
    path.write_bytes(data)
    return data


class ObservationSchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        with (TEMPLATES / "gate-001-physical-observations.schema.json").open() as handle:
            cls.schema = json.load(handle)
        Draft202012Validator.check_schema(cls.schema)
        cls.validator = Draft202012Validator(cls.schema)

    def assert_rejected(self, value: dict) -> None:
        self.assertTrue(list(self.validator.iter_errors(value)))

    def test_closed_schema_accepts_only_the_complete_physical_shape(self) -> None:
        self.assertEqual([], list(self.validator.iter_errors(observations())))
        value = observations()
        value["device_uuid"] = "private"
        self.assert_rejected(value)

    def test_schema_enum_is_exactly_the_five_canonical_states(self) -> None:
        enum = self.schema["$defs"]["terminationObservation"]["properties"][
            "termination_state"
        ]["enum"]
        self.assertEqual(list(gate.CANONICAL_TERMINATION_STATES), enum)


class PhysicalObservationMutationTests(unittest.TestCase):
    def assert_rejected(self, value: dict) -> None:
        with self.assertRaises(gate.GateVerificationError):
            gate.validate_physical_observations(value)

    def test_accepts_complete_physical_observations(self) -> None:
        gate.validate_physical_observations(observations())

    def test_each_missing_canonical_state_rejects_green(self) -> None:
        for state in gate.CANONICAL_TERMINATION_STATES:
            value = observations()
            value["termination_observations"] = [
                item for item in value["termination_observations"] if item["termination_state"] != state
            ]
            with self.subTest(state=state):
                self.assert_rejected(value)

    def test_duplicate_unknown_and_reordered_states_reject(self) -> None:
        duplicate = observations()
        duplicate["termination_observations"][-1] = copy.deepcopy(
            duplicate["termination_observations"][0]
        )
        self.assert_rejected(duplicate)

        unknown = observations()
        unknown["termination_observations"][0]["termination_state"] = "uploaded"
        self.assert_rejected(unknown)

        reordered = observations()
        reordered["termination_observations"][0:2] = reversed(
            reordered["termination_observations"][0:2]
        )
        self.assert_rejected(reordered)

    def test_rejects_synthetic_simulator_or_automation_substitution(self) -> None:
        mutations = (
            ("decision_actor", "automation"),
            ("evidence_origin", "simulator"),
            ("value_classification", "HYPOTHESIS"),
        )
        for key, replacement in mutations:
            value = observations()
            value[key] = replacement
            with self.subTest(key=key):
                self.assert_rejected(value)

    def test_rejects_wrong_fixture_build_evaluator_environment_or_raw_digest(self) -> None:
        mutations = []
        wrong_fixture = observations()
        wrong_fixture["termination_observations"][0]["runs"][0]["fixture_id"] = "FX-RRCAP-060S"
        mutations.append(wrong_fixture)
        wrong_build = observations()
        wrong_build["termination_observations"][0]["build_revision"] = "stale-build"
        mutations.append(wrong_build)
        wrong_evaluator = observations()
        wrong_evaluator["termination_observations"][0]["runs"][0]["evaluator_id"] = "opaque-evaluator-stale"
        mutations.append(wrong_evaluator)
        wrong_environment = observations()
        wrong_environment["termination_observations"][0]["environment_sha256"] = SHA_D
        mutations.append(wrong_environment)
        wrong_raw_digest = observations()
        wrong_raw_digest["termination_observations"][0]["runs"][0]["raw_artifact"]["sha256"] = "BAD"
        mutations.append(wrong_raw_digest)
        for index, value in enumerate(mutations):
            with self.subTest(index=index):
                self.assert_rejected(value)

    def test_rejects_threshold_failures_and_nonmatching_replays(self) -> None:
        mutations = []
        for field, value in (
            ("non_journaled_upload_reference_count", 1),
            ("earlier_record_corruption_count", 1),
            ("recovered_prefix_exact", False),
        ):
            item = observations()
            item["termination_observations"][0]["runs"][0][field] = value
            mutations.append(item)
        queue = observations()
        queue["termination_observations"][0]["runs"][0]["queue_observation"]["maximum_depth"] = 4
        mutations.append(queue)
        replay_mismatch = observations()
        replay_mismatch["termination_observations"][0]["runs"][0]["replays"][1][
            "journal_digest_sha256"
        ] = SHA_D
        mutations.append(replay_mismatch)
        for index, value in enumerate(mutations):
            with self.subTest(index=index):
                self.assert_rejected(value)


class GateBindingTests(unittest.TestCase):
    def prepare(self, directory: Path) -> tuple[Path, Path, Path, Path]:
        preflight_path = directory / "preflight.json"
        observation_path = directory / "observations.json"
        report_path = directory / "report.json"
        checklist_path = directory / "checklist.json"
        preflight_bytes = write_json(preflight_path, preflight())
        observation_bytes = write_json(observation_path, observations())
        report, checklist = green_pair(
            hashlib.sha256(preflight_bytes).hexdigest(),
            hashlib.sha256(observation_bytes).hexdigest(),
        )
        # The report decision excludes the final checklist attachment, then the
        # checklist bytes are attached to the report without creating a cycle.
        checklist["report_decision_sha256"] = report_decision_sha256(report)
        checklist["unsigned_checklist_sha256"] = unsigned_checklist_sha256(checklist)
        checklist_bytes = write_json(checklist_path, checklist)
        report["operator_checklist_sha256"] = hashlib.sha256(checklist_bytes).hexdigest()
        write_json(report_path, report)
        return preflight_path, report_path, checklist_path, observation_path

    def test_accepts_only_a_fully_bound_human_green(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            paths = self.prepare(Path(temp))
            gate.verify_gate_paths(*paths)

    def test_missing_observations_remains_pending(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            preflight_path = root / "preflight.json"
            report_path = root / "report.json"
            write_json(preflight_path, preflight())
            preflight_sha = hashlib.sha256(preflight_path.read_bytes()).hexdigest()
            write_json(report_path, pending_report(preflight_sha))
            with self.assertRaises(gate.GatePending):
                gate.verify_gate_paths(preflight_path, report_path, None, None)

    def test_rejects_automation_green_and_stale_or_mixed_bindings(self) -> None:
        mutators = (
            lambda report, checklist: report.__setitem__("decision_actor", "automation"),
            lambda report, checklist: report.__setitem__("automated_report_sha256", SHA_D),
            lambda report, checklist: checklist.__setitem__("automated_report_sha256", SHA_D),
            lambda report, checklist: checklist.__setitem__("report_decision_sha256", SHA_D),
            lambda report, checklist: checklist.__setitem__("signature_sha256", SHA_C),
        )
        for index, mutate in enumerate(mutators):
            with tempfile.TemporaryDirectory() as temp:
                paths = self.prepare(Path(temp))
                report = json.loads(paths[1].read_text())
                checklist = json.loads(paths[2].read_text())
                mutate(report, checklist)
                write_json(paths[1], report)
                write_json(paths[2], checklist)
                with self.subTest(index=index), self.assertRaises(gate.GateVerificationError):
                    gate.verify_gate_paths(*paths)

    def test_observation_digest_mutation_rejects_green(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            paths = self.prepare(Path(temp))
            value = json.loads(paths[3].read_text())
            value["recorded_at_utc"] = "2026-07-18T10:01:00Z"
            write_json(paths[3], value)
            with self.assertRaises(gate.GateVerificationError):
                gate.verify_gate_paths(*paths)

    def test_valid_red_is_failure_evidence_and_never_success(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            preflight_path = root / "preflight.json"
            report_path = root / "report.json"
            preflight_bytes = write_json(preflight_path, preflight())
            report = pending_report(hashlib.sha256(preflight_bytes).hexdigest())
            report.update(gate_state="RED", automated_report_sha256=hashlib.sha256(preflight_bytes).hexdigest())
            write_json(report_path, report)
            with self.assertRaises(gate.GateRed):
                gate.verify_gate_paths(preflight_path, report_path, None, None)


class RoutingAndSanitizationTests(unittest.TestCase):
    def test_quick_full_and_gate_have_explicit_distinct_routes(self) -> None:
        self.assertEqual(tuple(gate.QUICK_CHECK_IDS), tuple(gate.declared_check_ids("quick")))
        self.assertEqual(tuple(gate.FULL_CHECK_IDS), tuple(gate.declared_check_ids("full")))
        self.assertTrue(set(gate.QUICK_CHECK_IDS) < set(gate.FULL_CHECK_IDS))
        with self.assertRaises(gate.GateVerificationError):
            gate.declared_check_ids("gate")
        with self.assertRaises(gate.GateVerificationError):
            gate.declared_check_ids("unknown")

    def test_any_failed_or_missing_declared_check_rejects(self) -> None:
        passing = [
            {"check_id": check_id, "exit_code": 0, "output": f"{check_id} passed"}
            for check_id in gate.QUICK_CHECK_IDS
        ]
        gate.sanitize_check_results(gate.QUICK_CHECK_IDS, passing)
        with self.assertRaises(gate.GateVerificationError):
            gate.sanitize_check_results(gate.QUICK_CHECK_IDS, passing[:-1])
        failed = copy.deepcopy(passing)
        failed[0]["exit_code"] = 1
        with self.assertRaises(gate.GateVerificationError):
            gate.sanitize_check_results(gate.QUICK_CHECK_IDS, failed)

    def test_sanitizer_reconstructs_allowlisted_shape_and_rejects_private_input(self) -> None:
        raw = [
            {"check_id": check_id, "exit_code": 0, "output": f"safe output for {check_id}"}
            for check_id in gate.QUICK_CHECK_IDS
        ]
        sanitized = gate.sanitize_check_results(gate.QUICK_CHECK_IDS, raw)
        self.assertEqual(
            {"check_id", "status", "output_sha256"},
            set(sanitized[0]),
        )
        private = copy.deepcopy(raw)
        private[0]["device_uuid"] = "private"
        with self.assertRaises(gate.GateVerificationError):
            gate.sanitize_check_results(gate.QUICK_CHECK_IDS, private)


class OperatorProcedureTests(unittest.TestCase):
    def test_procedure_names_gate_states_thresholds_and_privacy_boundary(self) -> None:
        text = (TEMPLATES / "gate-001-operator-procedure.md").read_text()
        for phrase in (
            "base iPhone 17",
            "--gate-001-termination-controls",
            "Arm abrupt termination",
            "Save explicit capture frame",
            "SIGKILL",
            "relaunch",
            "10 seconds",
            "60 seconds",
            *gate.CANONICAL_TERMINATION_STATES,
            "two independent replays",
            "zero upload references to non-journaled frames",
            "zero earlier-record corruption",
            "exact recovered prefix",
            "outside Git",
            "REROOM_GATE_001_OBSERVATIONS_PATH",
            "RED",
            "blocks live integration",
        ):
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, text)


def replay_agreement_bytes() -> bytes:
    value = {
        "schema_version": "1.0.0",
        "evidence_id": "evidence_phase_02_replay_agreement_rev_001",
        "implementation": {
            "revision": "git:0d371bc1de9a057cbf61b70142729f6cbe620eec",
        },
        "agreement": {
            "verdict": "pass",
            "runtime_count": 3,
            "case_count": 16,
            "missing_cases": 0,
            "extra_cases": 0,
            "semantic_disagreements": 0,
            "runtime_identity_disagreements": 0,
            "report_digest_disagreements": 0,
            "fixture_integrity_disagreements": 0,
        },
        "limitations": [
            "This host-runtime result is not physical-device, signing, ARKit, compositor, or thermal evidence.",
            "The NFR-REPLAY-001 three-minute goal remains a hypothesis until separately measured with raw timing evidence.",
        ],
    }
    value["evidence_sha256"] = digest(value)
    return canonical_bytes(value) + b"\n"


class PreflightPublicationTests(unittest.TestCase):
    def results(self) -> list[dict]:
        return [
            {"check_id": check_id, "status": "PASS", "output_sha256": SHA_A}
            for check_id in gate.FULL_CHECK_IDS
        ]

    def build(self, **overrides: object) -> dict:
        arguments = {
            "check_results": self.results(),
            "implementation_revision": REVISION,
            "recorded_at_utc": "2026-07-18T11:00:00Z",
            "source_tree_sha256": SHA_B,
            "replay_agreement_bytes": replay_agreement_bytes(),
            "environment_facts": {
                "runtime_tier": "local-deterministic-preflight",
                "platform": "Darwin arm64",
                "python": "Python 3.13.12",
                "swift": "Apple Swift version 6.3",
                "node": "v22.22.3",
                "xcode": "Xcode 26.0",
            },
        }
        arguments.update(overrides)
        return gate.build_automated_preflight(**arguments)

    def test_builder_rejects_missing_failed_unknown_or_private_facts(self) -> None:
        invalid_results = self.results()[:-1]
        with self.assertRaises(gate.GateVerificationError):
            self.build(check_results=invalid_results)

        failed_results = self.results()
        failed_results[0]["status"] = "FAIL"
        with self.assertRaises(gate.GateVerificationError):
            self.build(check_results=failed_results)

        unknown_results = self.results()
        unknown_results[0]["raw_output"] = "private"
        with self.assertRaises(gate.GateVerificationError):
            self.build(check_results=unknown_results)

        private_environment = {
            "runtime_tier": "local-deterministic-preflight",
            "platform": "Darwin arm64",
            "python": "Python 3.13.12",
            "swift": "Apple Swift version 6.3",
            "node": "v22.22.3",
            "xcode": "Xcode 26.0",
            "device_uuid": "private-device-id",
        }
        with self.assertRaises(gate.GateVerificationError):
            self.build(environment_facts=private_environment)

    def test_builder_rejects_stale_replay_agreement_binding(self) -> None:
        stale = json.loads(replay_agreement_bytes())
        stale["agreement"]["semantic_disagreements"] = 1
        with self.assertRaises(gate.GateVerificationError):
            self.build(replay_agreement_bytes=canonical_bytes(stale) + b"\n")

    def test_builder_records_only_synthetic_hypothesis_target_facts(self) -> None:
        value = self.build()
        self.assertEqual("automation", value["decision_actor"])
        self.assertEqual("RUNNING", value["gate_state"])
        self.assertEqual("pending", value["physical_evidence_state"])
        self.assertTrue(
            all(
                item["value_classification"] in {"HYPOTHESIS", "TARGET"}
                for item in value["synthetic_metrics"]
            )
        )
        serialized = canonical_bytes(value).decode()
        self.assertNotIn("FX-RRCAP-010S", serialized)
        self.assertNotIn("FX-RRCAP-060S", serialized)
        self.assertIn("three-minute goal remains a hypothesis", serialized)

    def test_pending_bundle_has_no_human_or_physical_claim(self) -> None:
        value = self.build()
        report, checklist = gate.build_pending_gate_bundle(value)
        self.assertEqual(("RUNNING", "automation", "TARGET"), (
            report["gate_state"], report["decision_actor"], report["value_classification"]
        ))
        self.assertEqual(("UNRUN", "human_required"), (
            checklist["checklist_state"], checklist["decision_actor"]
        ))
        serialized = canonical_bytes([value, report, checklist]).decode()
        self.assertNotIn("FX-RRCAP-010S", serialized)
        self.assertNotIn("FX-RRCAP-060S", serialized)
        self.assertNotIn('"decision":"GREEN"', serialized)

    def test_atomic_publication_fault_preserves_previous_generation(self) -> None:
        value = self.build()
        report, checklist = gate.build_pending_gate_bundle(value)
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            expected = {}
            for name in (
                "automated-preflight.json",
                "gate-001-report.json",
                "gate-001-checklist.json",
            ):
                target = directory / name
                target.write_bytes(f"previous-{name}\n".encode())
                expected[name] = target.read_bytes()

            def fail_after_first_replace(point: str) -> None:
                if point == "replaced:automated-preflight.json":
                    raise RuntimeError("injected publication fault")

            with self.assertRaises(gate.GateVerificationError):
                gate.publish_pending_gate_bundle(
                    value,
                    report,
                    checklist,
                    directory=directory,
                    fault_hook=fail_after_first_replace,
                )
            self.assertEqual(
                expected,
                {name: (directory / name).read_bytes() for name in expected},
            )

    def test_successful_publication_writes_valid_pending_generation(self) -> None:
        value = self.build()
        report, checklist = gate.build_pending_gate_bundle(value)
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            paths = gate.publish_pending_gate_bundle(value, report, checklist, directory=directory)
            self.assertEqual(3, len(paths))
            published_preflight = json.loads(paths[0].read_text())
            gate.validate_automated_preflight(published_preflight)
            with self.assertRaises(gate.GatePending):
                gate.verify_gate_paths(paths[0], paths[1], paths[2], None)


if __name__ == "__main__":
    unittest.main()
