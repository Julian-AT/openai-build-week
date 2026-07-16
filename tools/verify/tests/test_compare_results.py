import copy
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.verify.compare_results import ComparisonError, compare_runner_results, verify_fixture


ROOT = Path(__file__).resolve().parents[3]
MANIFESTS = (
    ROOT / "fixtures/contracts/1.0.0/rev-001/manifest.json",
    ROOT / "fixtures/policies/RR-JCS-SHA256-1/rev-001/manifest.json",
    ROOT / "fixtures/policies/RR-COORD-1/rev-001/manifest.json",
)


def canonical_bytes(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def result_for(manifest_path, runtime="python"):
    manifest = json.loads(manifest_path.read_text())
    rows = []
    for case in manifest["cases"]:
        rows.append(
            {
                "case_id": case["case_id"],
                "verdict": case["expected"]["verdict"],
                "rejection_class": case["expected"]["rejection_class"],
                "output_artifacts": [
                    {key: artifact[key] for key in ("kind", "byte_length", "sha256", "value_sha256") if key in artifact}
                    for artifact in case["expected"]["artifacts"]
                ],
            }
        )
    accepted = sum(row["verdict"] == "accept" for row in rows)
    result = {
        "schema_version": "1.0.0",
        "runner": {
            "runtime": runtime,
            "name": f"test-{runtime}",
            "version": "1.0.0",
            "implementation_revision": "git:" + "0" * 40,
        },
        "fixture": {
            "fixture_id": manifest["fixture_id"],
            "fixture_revision": manifest["fixture_revision"],
            "manifest_sha256": hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
        },
        "case_order": "lexicographic_case_id",
        "case_results": rows,
        "summary": {"total": len(rows), "accepted": accepted, "rejected": len(rows) - accepted},
        "oracle_unchanged": True,
        "result_digest_algorithm": "RR-JCS-SHA256-1",
        "result_digest_scope": "entire_runner_result_with_result_digest_sha256_omitted",
    }
    result["result_digest_sha256"] = hashlib.sha256(canonical_bytes(result)).hexdigest()
    return result


class CompareResultsTests(unittest.TestCase):
    def write_result(self, directory, name, value):
        path = Path(directory) / name
        path.write_text(json.dumps(value))
        return path

    def test_all_checked_in_fixtures_are_integrity_valid(self):
        for manifest in MANIFESTS:
            with self.subTest(manifest=manifest):
                verified = verify_fixture(manifest, repo_root=ROOT)
                self.assertEqual(verified.fixture_id, json.loads(manifest.read_text())["fixture_id"])

    def test_changed_checked_in_oracle_bytes_are_rejected(self):
        source = MANIFESTS[1]
        with tempfile.TemporaryDirectory() as temporary:
            copied = Path(temporary) / "rev-001"
            shutil.copytree(source.parent, copied)
            manifest = json.loads((copied / "manifest.json").read_text())
            target = copied / manifest["cases"][0]["input"]["relative_path"]
            target.write_bytes(target.read_bytes() + b"x")
            with self.assertRaisesRegex(ComparisonError, "input_byte_length"):
                verify_fixture(copied / "manifest.json", repo_root=ROOT)

    def test_valid_normalized_result_passes(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = self.write_result(temporary, "python.json", result_for(MANIFESTS[1]))
            compared = compare_runner_results(MANIFESTS[1], [path], repo_root=ROOT, required_runtimes=("python",))
            self.assertEqual(compared, ("python",))

    def test_missing_extra_duplicate_and_out_of_order_cases_fail_closed(self):
        mutations = {}
        baseline = result_for(MANIFESTS[1])
        mutations["missing_case"] = baseline["case_results"][:-1]
        mutations["extra_case"] = baseline["case_results"] + [dict(baseline["case_results"][-1], case_id="jcs.zzz-extra")]
        mutations["duplicate_case"] = baseline["case_results"] + [baseline["case_results"][-1]]
        mutations["case_order"] = list(reversed(baseline["case_results"]))
        for mismatch, rows in mutations.items():
            with self.subTest(mismatch=mismatch), tempfile.TemporaryDirectory() as temporary:
                value = copy.deepcopy(baseline)
                value["case_results"] = rows
                value["summary"]["total"] = len(rows)
                value["result_digest_sha256"] = hashlib.sha256(canonical_bytes({k: v for k, v in value.items() if k != "result_digest_sha256"})).hexdigest()
                path = self.write_result(temporary, "bad.json", value)
                with self.assertRaisesRegex(ComparisonError, mismatch):
                    compare_runner_results(MANIFESTS[1], [path], repo_root=ROOT)

    def test_every_oracle_result_field_is_compared_exactly(self):
        mutations = (
            ("verdict", lambda row: row.update(verdict="reject", rejection_class="semantic_invariant", output_artifacts=[])),
            ("rejection_class", lambda row: row.update(rejection_class="semantic_invariant")),
            ("artifact_kind", lambda row: row["output_artifacts"][0].update(kind="wire_bytes")),
            ("artifact_byte_length", lambda row: row["output_artifacts"][0].update(byte_length=999)),
            ("artifact_sha256", lambda row: row["output_artifacts"][0].update(sha256="0" * 64)),
            ("artifact_value_sha256", lambda row: row["output_artifacts"][1].update(value_sha256="0" * 64)),
        )
        for mismatch, mutate in mutations:
            with self.subTest(mismatch=mismatch), tempfile.TemporaryDirectory() as temporary:
                value = result_for(MANIFESTS[1])
                mutate(value["case_results"][0])
                unsigned = {key: item for key, item in value.items() if key != "result_digest_sha256"}
                value["result_digest_sha256"] = hashlib.sha256(canonical_bytes(unsigned)).hexdigest()
                path = self.write_result(temporary, "bad.json", value)
                with self.assertRaisesRegex(ComparisonError, mismatch):
                    compare_runner_results(MANIFESTS[1], [path], repo_root=ROOT)

    def test_manifest_digest_result_digest_and_runtime_set_are_enforced(self):
        with tempfile.TemporaryDirectory() as temporary:
            bad_manifest = result_for(MANIFESTS[1])
            bad_manifest["fixture"]["manifest_sha256"] = "0" * 64
            bad_manifest["result_digest_sha256"] = hashlib.sha256(canonical_bytes({k: v for k, v in bad_manifest.items() if k != "result_digest_sha256"})).hexdigest()
            path = self.write_result(temporary, "bad-manifest.json", bad_manifest)
            with self.assertRaisesRegex(ComparisonError, "manifest_sha256"):
                compare_runner_results(MANIFESTS[1], [path], repo_root=ROOT)

            bad_digest = result_for(MANIFESTS[1])
            bad_digest["result_digest_sha256"] = "0" * 64
            path = self.write_result(temporary, "bad-digest.json", bad_digest)
            with self.assertRaisesRegex(ComparisonError, "result_digest_sha256"):
                compare_runner_results(MANIFESTS[1], [path], repo_root=ROOT)

            valid = self.write_result(temporary, "valid.json", result_for(MANIFESTS[1]))
            with self.assertRaisesRegex(ComparisonError, "missing_runtime"):
                compare_runner_results(MANIFESTS[1], [valid], repo_root=ROOT, required_runtimes=("python", "swift"))

    def test_duplicate_runtime_and_runner_disagreement_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            python_a = self.write_result(temporary, "a.json", result_for(MANIFESTS[1]))
            python_b = self.write_result(temporary, "b.json", result_for(MANIFESTS[1]))
            with self.assertRaisesRegex(ComparisonError, "duplicate_runtime"):
                compare_runner_results(MANIFESTS[1], [python_a, python_b], repo_root=ROOT)

            swift = result_for(MANIFESTS[1], "swift")
            swift["case_results"][0]["output_artifacts"][0]["sha256"] = "0" * 64
            swift["result_digest_sha256"] = hashlib.sha256(canonical_bytes({k: v for k, v in swift.items() if k != "result_digest_sha256"})).hexdigest()
            swift_path = self.write_result(temporary, "swift.json", swift)
            with self.assertRaisesRegex(ComparisonError, "artifact_sha256"):
                compare_runner_results(MANIFESTS[1], [python_a, swift_path], repo_root=ROOT)


class VerificationModeTests(unittest.TestCase):
    SCRIPT = ROOT / "scripts/verify-phase-01-contracts"

    def run_mode(self, mode, **environment):
        return subprocess.run(
            [self.SCRIPT, mode],
            cwd=ROOT,
            env=dict(os.environ, **environment),
            capture_output=True,
            text=True,
        )

    def make_gate_evidence(self, directory, states=("GREEN", "GREEN")):
        directory = Path(directory)
        evidence_dir = directory / "physical"
        evidence_dir.mkdir()
        preflight = json.loads((ROOT / "evidence/fixtures/valid/gate-report.running.json").read_text())
        preflight.update(gate_id="GATE-013")
        preflight["environment"]["signing_result"] = "pass"
        preflight["evidence_artifacts"][0]["opaque_artifact_id"] = "opaque-phase-01-candidate-build"
        preflight_path = directory / "automated-preflight.json"
        preflight_path.write_text(json.dumps(preflight, indent=2, sort_keys=True) + "\n")
        preflight_sha = hashlib.sha256(preflight_path.read_bytes()).hexdigest()

        for gate_id, state in zip(("GATE-013", "GATE-002"), states, strict=True):
            report = json.loads((ROOT / f"evidence/fixtures/valid/gate-report.{state.lower()}.json").read_text())
            report["gate_id"] = gate_id
            if state == "GREEN":
                checklist = json.loads((ROOT / "evidence/fixtures/valid/operator-checklist.green.json").read_text())
                checklist["gate_id"] = gate_id
                checklist["report_sha256"] = preflight_sha
                checklist_path = evidence_dir / f"{gate_id.lower()}-operator-checklist.json"
                checklist_path.write_text(json.dumps(checklist, indent=2, sort_keys=True) + "\n")
                report["automated_report_sha256"] = preflight_sha
                report["operator_checklist_sha256"] = hashlib.sha256(checklist_path.read_bytes()).hexdigest()
            report_path = evidence_dir / f"{gate_id.lower()}-report.json"
            report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        return preflight_path, evidence_dir

    def test_unknown_mode_fails_and_fixture_integrity_passes(self):
        self.assertNotEqual(self.run_mode("unknown").returncode, 0)
        self.assertEqual(self.run_mode("fixture-integrity").returncode, 0)

    def test_gate_passes_only_for_two_bound_signed_green_reports(self):
        with tempfile.TemporaryDirectory() as temporary:
            preflight, evidence = self.make_gate_evidence(temporary)
            result = self.run_mode(
                "gate",
                REROOM_PHASE01_AUTOMATED_PREFLIGHT=str(preflight),
                REROOM_PHASE01_EVIDENCE_DIR=str(evidence),
            )
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_schema_valid_red_is_retained_but_never_gate_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            preflight, evidence = self.make_gate_evidence(temporary, ("GREEN", "RED"))
            result = self.run_mode(
                "gate",
                REROOM_PHASE01_AUTOMATED_PREFLIGHT=str(preflight),
                REROOM_PHASE01_EVIDENCE_DIR=str(evidence),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("GREEN,RED", result.stderr)

    def test_full_boundary_contains_no_physical_gate_inputs(self):
        source = self.SCRIPT.read_text()
        body = source.split("full_checks() {", 1)[1].split("gate_checks() {", 1)[0]
        self.assertNotIn("PHYSICAL_DIR", body)
        self.assertNotIn("gate-013-report", body)
        self.assertNotIn("gate-002-report", body)


if __name__ == "__main__":
    unittest.main()
