"""Independent Python replay runner behavior and mutation gates."""

from __future__ import annotations

import concurrent.futures
import hashlib
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from tools.python.reroom_verify.replay import (
    EXACT_PYTHON_VERSION,
    canonical_bytes,
    run_replay,
)


ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT / "fixtures/capture/1.0.0/rev-001/manifest.json"
REVISION = "git:0123456789abcdef0123456789abcdef01234567"
FIXTURE_SHA256 = "3b4519d2730e158df73e938f7b841664c6ce5f7d65ed2650c90ca8e89c7a7610"


def load_reports(root: Path) -> dict[str, bytes]:
    return {path.name: path.read_bytes() for path in sorted(root.iterdir())}


class PythonReplayTests(unittest.TestCase):
    def test_complete_closed_replay_corpus(self) -> None:
        fixture = json.loads(MANIFEST.read_bytes())
        with tempfile.TemporaryDirectory(prefix="reroom-python-replay-") as temporary:
            output = Path(temporary) / "reports"
            run_replay(MANIFEST, output, ROOT, REVISION)
            reports = load_reports(output)

        expected_ids = sorted(
            [f"archive.{entry['archive_name'][:-len('.rrcap')]}" for entry in fixture["archives"]]
            + [entry["case_id"] for entry in fixture["edge_probes"]]
            + ["sec-consent.denied"]
        )
        self.assertEqual(
            [f"{case_id}.replay-report.json" for case_id in expected_ids],
            list(reports),
        )
        for name, raw in reports.items():
            report = json.loads(raw)
            self.assertEqual(raw, canonical_bytes(report), name)
            self.assertEqual("1.0.0", report["report_version"])
            self.assertEqual(
                {"name": "ReRoomReplayPython", "platform": "python", "version": "1.0.0"},
                report["evaluator"],
            )
            self.assertEqual(
                {
                    "fixture_id": "FX-CAPTURE-001",
                    "fixture_revision": "rev-001",
                    "manifest_sha256": FIXTURE_SHA256,
                },
                report["fixture"],
            )
            self.assertEqual(
                {
                    "build_id": "ReRoomReplayPython-1.0.0",
                    "repository_revision": REVISION,
                    "runtime": f"python-{EXACT_PYTHON_VERSION}",
                },
                report["implementation"],
            )
            unsigned = dict(report)
            del unsigned["report_sha256"]
            self.assertEqual(
                hashlib.sha256(canonical_bytes(unsigned)).hexdigest(),
                report["report_sha256"],
            )

        for descriptor in fixture["archives"]:
            case_id = f"archive.{descriptor['archive_name'][:-len('.rrcap')]}"
            report = json.loads(reports[f"{case_id}.replay-report.json"])
            self.assertEqual(descriptor["expected"]["verdict"], report["verdict"])
            self.assertIsNone(report["rejection"])
            self.assertEqual(
                {
                    "event_projection_sha256": descriptor["expected"]["event_projection_sha256"],
                    "frame_projection_sha256": descriptor["expected"]["frame_projection_sha256"],
                    "journal_tuple_sha256": descriptor["expected"]["journal_tuple_sha256"],
                    "revision_trace_sha256": descriptor["expected"]["revision_trace_sha256"],
                },
                report["digests"],
            )

        for probe in fixture["edge_probes"]:
            report = json.loads(reports[f"{probe['case_id']}.replay-report.json"])
            self.assertEqual(probe["expected"]["verdict"], report["verdict"])
            rejection = report["rejection"]
            self.assertEqual(
                probe["expected"]["rejection_class"],
                None if rejection is None else rejection["rejection_class"],
            )

    def test_sequential_and_concurrent_runs_are_byte_identical(self) -> None:
        with tempfile.TemporaryDirectory(prefix="reroom-python-replay-repeat-") as temporary:
            base = Path(temporary)
            roots = [base / name for name in ("first", "second", "concurrent-a", "concurrent-b")]
            for root in roots[:2]:
                run_replay(MANIFEST, root, ROOT, REVISION)
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
                futures = [executor.submit(run_replay, MANIFEST, root, ROOT, REVISION) for root in roots[2:]]
                for future in futures:
                    future.result()
            outputs = [load_reports(root) for root in roots]
        for output in outputs[1:]:
            self.assertEqual(outputs[0], output)

    def test_wrong_runtime_and_preexisting_output_reject(self) -> None:
        with tempfile.TemporaryDirectory(prefix="reroom-python-replay-boundary-") as temporary:
            base = Path(temporary)
            wrong_runtime = base / "wrong-runtime"
            with self.assertRaisesRegex(ValueError, "Python 3.13.12 is required"):
                run_replay(MANIFEST, wrong_runtime, ROOT, REVISION, runtime_version="3.13.11")
            self.assertFalse(wrong_runtime.exists())

            preexisting = base / "preexisting"
            preexisting.mkdir()
            with self.assertRaisesRegex(ValueError, "must not exist"):
                run_replay(MANIFEST, preexisting, ROOT, REVISION)

    def test_archive_corruption_rejects_without_output(self) -> None:
        with tempfile.TemporaryDirectory(prefix="reroom-python-replay-corrupt-") as temporary:
            base = Path(temporary)
            fixture_root = base / "rev-001"
            shutil.copytree(MANIFEST.parent, fixture_root)
            corrupt = fixture_root / "archives/finalized-one-frame.rrcap/events/event_0000.json"
            mutated = bytearray(corrupt.read_bytes())
            mutated[0] ^= 1
            corrupt.write_bytes(mutated)
            output = base / "output"
            with self.assertRaisesRegex(ValueError, "digest|fixture|inventory"):
                run_replay(fixture_root / "manifest.json", output, ROOT, REVISION)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
