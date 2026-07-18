from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from tools.verify import verify_phase_08_evidence as evidence


class Phase08EvidenceTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        artifact = self.root / "evidence/example.json"
        artifact.parent.mkdir(parents=True)
        artifact.write_text("{}\n", encoding="utf-8")
        self.digest = hashlib.sha256(artifact.read_bytes()).hexdigest()

    def _index(self) -> dict[str, object]:
        return evidence.seal_index(evidence.build_index(
            implementation_revision="git:" + "a" * 40,
            recorded_at_utc="2026-07-18T00:00:00Z",
            entries=[evidence.fixture_automated_entry(self.digest)],
        ))

    def _gates(self) -> dict[str, object]:
        return evidence.seal_gates(evidence.build_gate_report(
            implementation_revision="git:" + "a" * 40,
            recorded_at_utc="2026-07-18T00:00:00Z",
            gate_rows=evidence.fixture_gate_rows(),
        ))

    def test_digest_bound_tracked_evidence_accepts(self) -> None:
        evidence.validate_index(self._index(), root=self.root)

    def test_missing_escape_and_digest_drift_reject(self) -> None:
        for location in ("../escape.json", "/tmp/private.json", "evidence/missing.json"):
            index = self._index()
            index["entries"][0]["location"] = location
            index["evidence_sha256"] = evidence.document_sha256(index)
            with self.assertRaises(evidence.EvidenceRejected):
                evidence.validate_index(index, root=self.root)

        index = self._index()
        index["entries"][0]["sha256"] = "b" * 64
        index["evidence_sha256"] = evidence.document_sha256(index)
        with self.assertRaises(evidence.EvidenceRejected):
            evidence.validate_index(index, root=self.root)

    def test_automated_output_cannot_impersonate_other_evidence_classes(self) -> None:
        for classification in ("device_smoke", "browser_smoke", "human_observation", "external_submission"):
            index = self._index()
            index["entries"][0]["classification"] = classification
            index["evidence_sha256"] = evidence.document_sha256(index)
            with self.assertRaises(evidence.EvidenceRejected):
                evidence.validate_index(index, root=self.root)

    def test_pending_external_rows_cannot_become_verified_without_provenance(self) -> None:
        index = self._index()
        pending = evidence.fixture_pending_external_entry()
        index["entries"].append(pending)
        index["evidence_sha256"] = evidence.document_sha256(index)
        evidence.validate_index(index, root=self.root)

        index["entries"][1]["state"] = "VERIFIED"
        index["evidence_sha256"] = evidence.document_sha256(index)
        with self.assertRaises(evidence.EvidenceRejected):
            evidence.validate_index(index, root=self.root)

    def test_formal_and_sprint_gate_domains_cannot_promote_each_other(self) -> None:
        gates = self._gates()
        evidence.validate_gate_report(gates, root=self.root)

        gates["gates"][0]["formal_state"] = "PENDING"
        gates["evidence_sha256"] = evidence.document_sha256(gates)
        with self.assertRaises(evidence.EvidenceRejected):
            evidence.validate_gate_report(gates, root=self.root)

        gates = self._gates()
        gates["gates"][0]["formal_state"] = "GREEN"
        gates["evidence_sha256"] = evidence.document_sha256(gates)
        with self.assertRaises(evidence.EvidenceRejected):
            evidence.validate_gate_report(gates, root=self.root)

        gates = self._gates()
        gates["requirements"][0]["completed"] = True
        gates["evidence_sha256"] = evidence.document_sha256(gates)
        with self.assertRaises(evidence.EvidenceRejected):
            evidence.validate_gate_report(gates, root=self.root)

    def test_private_credentials_and_unsupported_claims_reject_safely(self) -> None:
        forbidden = (
            "/Users/example/private/log",
            "sk" + "-" + "A" * 24,
            "P0 complete",
            "licensed for shipping",
            "real-time performance",
        )
        for value in forbidden:
            index = self._index()
            index["limitations"].append(value)
            index["evidence_sha256"] = evidence.document_sha256(index)
            with self.assertRaises(evidence.EvidenceRejected) as caught:
                evidence.validate_index(index, root=self.root)
            self.assertNotIn(value, str(caught.exception))

    def test_docs_require_locked_claim_commands_pending_language_and_unchecked_actions(self) -> None:
        runbook, handoff = evidence.fixture_docs()
        evidence.validate_docs_text(runbook, handoff)

        mutations = (
            (runbook.replace(evidence.PERMITTED_CLAIM, "P0 complete"), handoff),
            (runbook.replace("OPS-GOLDEN-001 remains PENDING until 5/5", "OPS-GOLDEN-001 complete"), handoff),
            (runbook, handoff.replace("- [ ] Human: upload public demo video", "- [x] Human: upload public demo video")),
            (runbook, handoff.replace("https://openai.devpost.com/rules", "https://example.invalid/rules")),
            (runbook, handoff.replace("Retrieved: 2026-07-18", "Retrieved: unknown")),
        )
        for changed_runbook, changed_handoff in mutations:
            with self.assertRaises(evidence.EvidenceRejected):
                evidence.validate_docs_text(changed_runbook, changed_handoff)

    def test_docs_cannot_present_degraded_remove_as_normal_signed_device_behavior(self) -> None:
        runbook, handoff = evidence.fixture_docs()
        evidence.validate_docs_text(runbook, handoff)

        for changed_runbook, changed_handoff in (
            (runbook.replace(evidence.DEGRADED_REMOVE_NOTICE, "Remove is available in the normal signed build."), handoff),
            (runbook, handoff.replace(evidence.DEGRADED_REMOVE_NOTICE, "The signed native sequence includes remove.")),
            (runbook.replace(evidence.DEMO_REVEAL_ARGUMENT, "--room-edit-remove"), handoff),
            (runbook, handoff.replace(evidence.DEMO_REVEAL_ARGUMENT, "--room-edit-remove")),
        ):
            with self.assertRaises(evidence.EvidenceRejected):
                evidence.validate_docs_text(changed_runbook, changed_handoff)

    def test_docs_paths_are_locked_to_the_two_repository_files(self) -> None:
        runbook, handoff = evidence.fixture_docs()
        runbook_path = self.root / evidence.RUNBOOK_PATH
        handoff_path = self.root / evidence.HANDOFF_PATH
        runbook_path.parent.mkdir(parents=True)
        runbook_path.write_text(runbook, encoding="utf-8")
        handoff_path.write_text(handoff, encoding="utf-8")
        evidence.validate_docs(self.root, evidence.RUNBOOK_PATH, evidence.HANDOFF_PATH)
        with self.assertRaises(evidence.EvidenceRejected):
            evidence.validate_docs(self.root, "../runbook.md", evidence.HANDOFF_PATH)

    def test_self_digest_and_closed_shapes_reject_mutation(self) -> None:
        index = self._index()
        index["unexpected"] = True
        index["evidence_sha256"] = evidence.document_sha256(index)
        with self.assertRaises(evidence.EvidenceRejected):
            evidence.validate_index(index, root=self.root)

        gates = self._gates()
        gates["limitations"].append("tampered")
        with self.assertRaises(evidence.EvidenceRejected):
            evidence.validate_gate_report(gates, root=self.root)


if __name__ == "__main__":
    unittest.main()
