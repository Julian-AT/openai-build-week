from __future__ import annotations

import copy
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from tools.verify.verify_phase_07_b0 import (
    EvidenceRejected,
    build_evidence,
    seal_evidence,
    validate_evidence,
)


ROOT = Path(__file__).resolve().parents[3]
PASS_DIGESTS = {
    "phase_02_exact_replay": "01" * 32,
    "web_projection_timeline": "02" * 32,
    "web_typecheck": "03" * 32,
    "web_production_build": "04" * 32,
    "source_closure": "05" * 32,
    "local_http_smoke": "06" * 32,
}


def valid_evidence(root: Path = ROOT) -> dict[str, object]:
    return build_evidence(
        root=root,
        implementation_revision="git:" + ("a1" * 20),
        check_output_digests=PASS_DIGESTS,
    )


def rejected_code(value: object, root: Path = ROOT) -> str:
    with unittest.TestCase().assertRaises(EvidenceRejected) as raised:
        validate_evidence(value, root=root)
    return str(raised.exception)


def copy_closed_source(destination: Path) -> None:
    ignored = shutil.ignore_patterns("node_modules", ".next", "*.tsbuildinfo", "__pycache__")
    for relative in ("web", "tools/javascript", "fixtures/capture/1.0.0/rev-001"):
        shutil.copytree(ROOT / relative, destination / relative, ignore=ignored)
    for relative in (
        "tools/verify/verify_phase_07_b0.py",
        "tools/verify/tests/test_phase_07_b0_gate.py",
    ):
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / relative, target)
    producer = ROOT / "scripts/verify-phase-07-b0"
    if producer.exists():
        target = destination / "scripts/verify-phase-07-b0"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(producer, target)


class Phase07EvidenceGateTests(unittest.TestCase):
    def test_complete_closed_preflight_accepts(self) -> None:
        evidence = valid_evidence()
        validate_evidence(evidence, root=ROOT)

    def test_missing_and_extra_top_level_keys_reject(self) -> None:
        missing = valid_evidence()
        missing.pop("limitations")
        self.assertEqual(rejected_code(missing), "E07_SHAPE")

        extra = valid_evidence()
        extra["notes"] = "looks harmless"
        self.assertEqual(rejected_code(extra), "E07_SHAPE")

    def test_identity_version_fixture_and_report_mutations_reject(self) -> None:
        mutations = (
            ("toolchain", "next", "16.2.8"),
            ("toolchain", "react", "19.2.6"),
            ("fixture", "fixture_id", "FX-CAPTURE-999"),
            ("fixture", "manifest_sha256", "f" * 64),
            ("fixture", "archive_id", "archive.other"),
            ("fixture", "report_sha256", "e" * 64),
        )
        for section, key, replacement in mutations:
            with self.subTest(section=section, key=key):
                evidence = valid_evidence()
                section_value = evidence[section]
                self.assertIsInstance(section_value, dict)
                section_value[key] = replacement
                self.assertEqual(rejected_code(evidence), "E07_IDENTITY")

    def test_check_completeness_and_pass_status_are_closed(self) -> None:
        missing = valid_evidence()
        checks = missing["checks"]
        self.assertIsInstance(checks, list)
        checks.pop()
        self.assertEqual(rejected_code(missing), "E07_CHECK_SET")

        failed = valid_evidence()
        failed_checks = failed["checks"]
        self.assertIsInstance(failed_checks, list)
        failed_checks[0]["status"] = "FAIL"
        self.assertEqual(rejected_code(failed), "E07_CHECK_STATUS")

        renamed = valid_evidence()
        renamed_checks = renamed["checks"]
        self.assertIsInstance(renamed_checks, list)
        renamed_checks[0]["check_id"] = "browser_smoke"
        self.assertEqual(rejected_code(renamed), "E07_CHECK_SET")

    def test_browser_gate_and_requirement_promotion_reject(self) -> None:
        for claim in ("browser_smoke", "FR-WEB-001", "SEC-RETENTION-001", "GATE-008"):
            with self.subTest(claim=claim):
                evidence = valid_evidence()
                claims = evidence["claims"]
                self.assertIsInstance(claims, dict)
                claims[claim] = "VERIFIED"
                expected = "E07_BROWSER_ARTIFACT" if claim == "browser_smoke" else "E07_CLAIM"
                self.assertEqual(rejected_code(evidence), expected)

    def test_unsafe_detail_and_raw_private_fields_reject_without_echo(self) -> None:
        unsafe_value = valid_evidence()
        limitations = unsafe_value["limitations"]
        self.assertIsInstance(limitations, list)
        limitations[0] = "response body copied from /tmp/private-run-123"
        self.assertEqual(rejected_code(unsafe_value), "E07_UNSAFE")

        unsafe_key = valid_evidence()
        fixture = unsafe_key["fixture"]
        self.assertIsInstance(fixture, dict)
        fixture["device_identifier"] = "private-value"
        self.assertEqual(rejected_code(unsafe_key), "E07_UNSAFE")

        try:
            validate_evidence(unsafe_value, root=ROOT)
        except EvidenceRejected as error:
            self.assertEqual(str(error), "E07_UNSAFE")
            self.assertNotIn("tmp", str(error).lower())

    def test_tampered_self_digest_rejects(self) -> None:
        evidence = valid_evidence()
        evidence["evidence_sha256"] = "0" * 64
        self.assertEqual(rejected_code(evidence), "E07_EVIDENCE_DIGEST")

    def test_unexpected_dependency_rejects_from_temporary_source(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            copy_closed_source(root)
            package_path = root / "web/package.json"
            package = json.loads(package_path.read_text(encoding="utf-8"))
            package["dependencies"]["axios"] = "1.7.9"
            package_path.write_text(json.dumps(package), encoding="utf-8")
            evidence = valid_evidence(root)
            self.assertEqual(rejected_code(evidence, root), "E07_DEPENDENCY")

    def test_api_route_network_persistence_and_action_controls_reject(self) -> None:
        mutations = (
            ("web/src/app/api/share/route.ts", "export async function POST() { return fetch('https://example.invalid'); }"),
            ("web/src/components/persist.tsx", "export const saved = localStorage.getItem('capture');"),
            ("web/src/components/upload.tsx", "export function Upload() { return <button>Share capture</button>; }"),
        )
        for relative, source in mutations:
            with self.subTest(relative=relative):
                with tempfile.TemporaryDirectory() as temporary:
                    root = Path(temporary)
                    copy_closed_source(root)
                    target = root / relative
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_text(source, encoding="utf-8")
                    evidence = valid_evidence(root)
                    self.assertEqual(rejected_code(evidence, root), "E07_SOURCE_SCOPE")

    def test_only_the_locked_server_loader_may_spawn_the_exact_replay(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            copy_closed_source(root)
            target = root / "web/src/lib/replay/network.server.ts"
            target.write_text("import { exec } from 'node:child_process';\nexport const x = exec;\n", encoding="utf-8")
            evidence = valid_evidence(root)
            self.assertEqual(rejected_code(evidence, root), "E07_SOURCE_SCOPE")

    def test_source_and_evidence_digests_are_independent(self) -> None:
        evidence = valid_evidence()
        source_digest = evidence["source_tree_sha256"]
        resealed = copy.deepcopy(evidence)
        claims = resealed["claims"]
        self.assertIsInstance(claims, dict)
        claims["automated_sprint_slice"] = "FAIL"
        seal_evidence(resealed)
        self.assertEqual(resealed["source_tree_sha256"], source_digest)
        self.assertNotEqual(resealed["evidence_sha256"], evidence["evidence_sha256"])
        self.assertEqual(rejected_code(resealed), "E07_CLAIM")


if __name__ == "__main__":
    unittest.main()
