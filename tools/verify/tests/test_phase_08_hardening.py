from __future__ import annotations

import hashlib
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools.verify import verify_phase_08_hardening as hardening


class Phase08HardeningTests(unittest.TestCase):
    def _upstream_root(self) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        for specification in hardening.UPSTREAMS:
            for key in ("summary", "verifier", "evidence", "verification"):
                path = root / specification[key]
                path.parent.mkdir(parents=True, exist_ok=True)
                if key == "verification":
                    path.write_text("---\nstatus: human_needed\n---\n", encoding="utf-8")
                elif key == "evidence":
                    path.write_text("{}\n", encoding="utf-8")
                else:
                    path.write_text("fixture\n", encoding="utf-8")
            (root / specification["verifier"]).chmod(0o755)
        return root

    def test_readiness_requires_every_upstream_surface_and_authority_pass(self) -> None:
        root = self._upstream_root()
        calls: list[str] = []

        rows = hardening.audit_readiness(root, lambda phase, _root: calls.append(phase))

        self.assertEqual([row["status"] for row in rows], ["READY"] * len(hardening.UPSTREAMS))
        self.assertEqual(calls, [item["phase_id"] for item in hardening.UPSTREAMS])

        (root / hardening.UPSTREAMS[0]["summary"]).unlink()
        rows = hardening.audit_readiness(root, lambda _phase, _root: None)
        self.assertEqual(rows[0]["status"], "BLOCKED_BY_UPSTREAM")

    def test_readiness_rejects_gap_status_and_validator_failure(self) -> None:
        root = self._upstream_root()
        verification = root / hardening.UPSTREAMS[1]["verification"]
        verification.write_text("---\nstatus: gaps_found\n---\n", encoding="utf-8")

        rows = hardening.audit_readiness(root, lambda _phase, _root: None)
        self.assertEqual(rows[1]["status"], "FAILED")

        def fail(phase: str, _root: Path) -> None:
            if phase == hardening.UPSTREAMS[2]["phase_id"]:
                raise ValueError("sensitive upstream output")

        rows = hardening.audit_readiness(root, fail)
        self.assertEqual(rows[2]["status"], "FAILED")
        self.assertNotIn("sensitive", json.dumps(rows))

    def test_credential_scan_returns_only_a_stable_classification(self) -> None:
        token = b"sk" + b"-" + b"A" * 24
        with self.assertRaises(hardening.HardeningRejected) as caught:
            hardening.scan_bytes(token, "tracked_source")
        self.assertEqual(caught.exception.code, "E08_CREDENTIAL_SIGNATURE")
        self.assertEqual(str(caught.exception), "E08_CREDENTIAL_SIGNATURE:tracked_source")
        self.assertNotIn(token.decode(), str(caught.exception))

    def test_bom_is_exact_closed_and_must_remain_blocked(self) -> None:
        bom = hardening.seal_bom(
            hardening.build_bom(
                implementation_revision="git:" + "a" * 40,
                recorded_at_utc="2026-01-01T00:00:00Z",
                members=[hardening.fixture_bom_member()],
            )
        )
        hardening.validate_bom(bom, expected_member_ids={"asset:fixture"})
        self.assertEqual(bom["shipping_status"], "BLOCKED")
        self.assertEqual(bom["requirements"], {"OPS-LICENSE-001": "PENDING"})
        self.assertEqual(bom["gates"], {"GATE-011": "PENDING"})

        mutated = json.loads(json.dumps(bom))
        mutated["shipping_status"] = "PASS"
        with self.assertRaises(hardening.HardeningRejected):
            hardening.validate_bom(mutated, expected_member_ids={"asset:fixture"})

        mutated = json.loads(json.dumps(bom))
        mutated["members"].append(dict(mutated["members"][0], member_id="asset:extra"))
        mutated["evidence_sha256"] = hardening.document_sha256(mutated)
        with self.assertRaises(hardening.HardeningRejected):
            hardening.validate_bom(mutated, expected_member_ids={"asset:fixture"})

    def test_preflight_closed_shape_cannot_promote_pending_claims(self) -> None:
        report = hardening.seal_preflight(
            hardening.build_preflight(
                implementation_revision="git:" + "b" * 40,
                recorded_at_utc="2026-01-01T00:00:00Z",
                readiness=[hardening.fixture_readiness_row()],
                checks=[hardening.fixture_check()],
                source_bindings={"fixture": "c" * 64},
                bom_sha256="d" * 64,
            )
        )
        hardening.validate_preflight(report)

        for section, key in (
            ("requirements", "SEC-CREDENTIAL-001"),
            ("formal_gates", "GATE-011"),
            ("claims", "device_evidence"),
            ("claims", "browser_evidence"),
        ):
            mutated = json.loads(json.dumps(report))
            mutated[section][key] = "PASS"
            mutated["evidence_sha256"] = hardening.document_sha256(mutated)
            with self.assertRaises(hardening.HardeningRejected):
                hardening.validate_preflight(mutated)

        mutated = json.loads(json.dumps(report))
        mutated["unexpected"] = True
        mutated["evidence_sha256"] = hardening.document_sha256(mutated)
        with self.assertRaises(hardening.HardeningRejected):
            hardening.validate_preflight(mutated)

    def test_self_digest_and_source_binding_are_fail_closed(self) -> None:
        report = hardening.seal_preflight(
            hardening.build_preflight(
                implementation_revision="git:" + "b" * 40,
                recorded_at_utc="2026-01-01T00:00:00Z",
                readiness=[hardening.fixture_readiness_row()],
                checks=[hardening.fixture_check()],
                source_bindings={"fixture": "c" * 64},
                bom_sha256="d" * 64,
            )
        )
        report["limitations"].append("tampered")
        with self.assertRaises(hardening.HardeningRejected):
            hardening.validate_preflight(report)

    def test_historical_and_current_binding_scopes_remain_independent(self) -> None:
        historical = b"historical verifier"
        report = {
            "implementation_revision": "git:" + "a" * 40,
            "verification_parent_revision": "git:" + "b" * 40,
            "source_bindings": {
                "core": hashlib.sha256(b"current core").hexdigest(),
                "verifier": hashlib.sha256(historical).hexdigest(),
            },
        }
        paths = {"core": "core.swift", "verifier": "verify.py"}
        completed = subprocess.CompletedProcess([], 0, stdout=historical, stderr=b"")
        with mock.patch.object(hardening.subprocess, "run", return_value=completed) as invoked:
            hardening._validate_historical_bindings(
                Path("."), report, paths,
                revision_field="verification_parent_revision", keys={"verifier"},
            )
        self.assertIn("b" * 40 + ":verify.py", invoked.call_args.args[0])

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "core.swift").write_bytes(b"current core")
            (root / "verify.py").write_bytes(b"successor verifier")
            hardening._validate_current_bindings(
                root, report, paths, historical_only_keys={"verifier"},
            )
            (root / "core.swift").write_bytes(b"drifted core")
            with self.assertRaises(hardening.HardeningRejected):
                hardening._validate_current_bindings(
                    root, report, paths, historical_only_keys={"verifier"},
                )

    def test_atomic_publish_preserves_existing_pair_when_validation_fails(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        directory = Path(temporary.name)
        bom_path = directory / "bom.json"
        report_path = directory / "report.json"
        bom_path.write_text("old-bom\n", encoding="utf-8")
        report_path.write_text("old-report\n", encoding="utf-8")

        with self.assertRaises(hardening.HardeningRejected):
            hardening.publish_pair(
                bom_path,
                report_path,
                {"invalid": True},
                {"invalid": True},
                expected_member_ids=set(),
            )
        self.assertEqual(bom_path.read_text(encoding="utf-8"), "old-bom\n")
        self.assertEqual(report_path.read_text(encoding="utf-8"), "old-report\n")

    def test_absolute_paths_and_private_identifiers_are_rejected(self) -> None:
        report = hardening.seal_preflight(
            hardening.build_preflight(
                implementation_revision="git:" + "b" * 40,
                recorded_at_utc="2026-01-01T00:00:00Z",
                readiness=[hardening.fixture_readiness_row()],
                checks=[hardening.fixture_check()],
                source_bindings={"fixture": "c" * 64},
                bom_sha256="d" * 64,
            )
        )
        report["limitations"][0] = "/Users/example/private/output"
        report["evidence_sha256"] = hardening.document_sha256(report)
        with self.assertRaises(hardening.HardeningRejected):
            hardening.validate_preflight(report)


if __name__ == "__main__":
    unittest.main()
