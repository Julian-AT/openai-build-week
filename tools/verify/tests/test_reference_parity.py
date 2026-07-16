"""Integration tests for the fresh two-runtime parity command."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

from tools.verify.compare_results import (
    ComparisonError,
    compare_runner_results,
    verify_fixture,
)


REPO_ROOT = Path(__file__).resolve().parents[3]
PARITY_COMMAND = REPO_ROOT / "scripts/run-reference-parity"
JAVASCRIPT_MUTATIONS = REPO_ROOT / "tools/javascript/test/parity-mutations.test.mjs"
PYTHON_MUTATIONS = REPO_ROOT / "tools/python/tests/test_parity_mutations.py"
MANIFESTS = {
    "contracts": REPO_ROOT / "fixtures/contracts/1.0.0/rev-001/manifest.json",
    "jcs": REPO_ROOT / "fixtures/policies/RR-JCS-SHA256-1/rev-001/manifest.json",
    "coord": REPO_ROOT / "fixtures/policies/RR-COORD-1/rev-001/manifest.json",
}


def _oracle_hashes() -> dict[str, str]:
    roots = (REPO_ROOT / "fixtures", REPO_ROOT / "docs/contracts")
    return {
        str(path.relative_to(REPO_ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
        for root in roots
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def _refresh_result_digest(result: dict) -> None:
    unsigned = {key: value for key, value in result.items() if key != "result_digest_sha256"}
    canonical = json.dumps(
        unsigned,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    result["result_digest_sha256"] = hashlib.sha256(canonical).hexdigest()


class ReferenceParityTests(unittest.TestCase):
    maxDiff = None

    def test_cross_runtime_mutation_gates_are_present(self) -> None:
        self.assertTrue(
            JAVASCRIPT_MUTATIONS.is_file(), "JavaScript mutation gates are absent"
        )
        self.assertTrue(PYTHON_MUTATIONS.is_file(), "Python mutation gates are absent")

    def test_comparator_kills_fresh_result_and_copied_oracle_mutations(self) -> None:
        before = _oracle_hashes()
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            output = temporary / "fresh-results"
            completed = subprocess.run(
                [str(PARITY_COMMAND), "--output-dir", str(output)],
                cwd=REPO_ROOT,
                check=False,
                capture_output=True,
                text=True,
                timeout=60,
            )
            self.assertEqual(0, completed.returncode, completed.stderr)

            def assert_result_mutation_rejected(
                stem: str,
                diagnostic: str,
                mutate,
            ) -> None:
                javascript = output / f"{stem}.javascript.json"
                python = output / f"{stem}.python.json"
                result = json.loads(javascript.read_bytes())
                mutate(result)
                _refresh_result_digest(result)
                tampered = temporary / f"{stem}-{diagnostic}.json"
                tampered.write_text(
                    json.dumps(result, ensure_ascii=False, sort_keys=True) + "\n",
                    encoding="utf-8",
                )
                with self.assertRaisesRegex(ComparisonError, diagnostic):
                    compare_runner_results(
                        MANIFESTS[stem],
                        [tampered, python],
                        repo_root=REPO_ROOT,
                        required_runtimes=("javascript", "python"),
                    )

            assert_result_mutation_rejected(
                "contracts",
                "contract.compatibility.named-up-migration:verdict",
                lambda result: result["case_results"][1].update(
                    verdict="reject",
                    rejection_class="semantic_invariant",
                    output_artifacts=[],
                ),
            )
            assert_result_mutation_rejected(
                "jcs",
                "jcs.basic-object:artifact_sha256",
                lambda result: result["case_results"][0]["output_artifacts"][0].update(
                    sha256="0" * 64
                ),
            )
            assert_result_mutation_rejected(
                "coord",
                "coord.correction-forward:artifact_sha256",
                lambda result: result["case_results"][1]["output_artifacts"][0].update(
                    sha256="0" * 64
                ),
            )

            def remove_last_case(result: dict) -> None:
                result["case_results"].pop()
                accepted = sum(
                    row["verdict"] == "accept" for row in result["case_results"]
                )
                total = len(result["case_results"])
                result["summary"] = {
                    "total": total,
                    "accepted": accepted,
                    "rejected": total - accepted,
                }

            assert_result_mutation_rejected(
                "jcs", "missing_case", remove_last_case
            )
            assert_result_mutation_rejected(
                "coord",
                "manifest_sha256",
                lambda result: result["fixture"].update(manifest_sha256="0" * 64),
            )

            copied = temporary / "copied-jcs-rev-001"
            shutil.copytree(MANIFESTS["jcs"].parent, copied)
            copied_manifest = copied / "manifest.json"
            manifest = json.loads(copied_manifest.read_bytes())
            target = copied / manifest["cases"][0]["input"]["relative_path"]
            target.write_bytes(target.read_bytes() + b"x")
            with self.assertRaisesRegex(ComparisonError, "input_byte_length"):
                verify_fixture(copied_manifest, repo_root=REPO_ROOT)

        self.assertEqual(before, _oracle_hashes(), "mutation gates changed their oracle")

    def test_fresh_actual_runtimes_and_fail_closed_harness(self) -> None:
        self.assertTrue(PARITY_COMMAND.is_file(), "reference parity command is absent")
        self.assertTrue(os.access(PARITY_COMMAND, os.X_OK), "parity command is not executable")

        before = _oracle_hashes()
        completed = subprocess.run(
            [str(PARITY_COMMAND)],
            cwd=REPO_ROOT,
            check=False,
            capture_output=True,
            text=True,
            timeout=60,
        )
        self.assertEqual(0, completed.returncode, completed.stderr)
        self.assertIn("reference-parity: PASS", completed.stdout)
        self.assertIn("FX-CONTRACT-001", completed.stdout)
        self.assertIn("FX-JCS-001", completed.stdout)
        self.assertIn("FX-COORD-001", completed.stdout)

        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            stale = temporary / "stale-results"
            stale.mkdir()
            (stale / "contracts.javascript.json").write_text("stale", encoding="utf-8")
            rejected = subprocess.run(
                [str(PARITY_COMMAND), "--output-dir", str(stale)],
                cwd=REPO_ROOT,
                check=False,
                capture_output=True,
                text=True,
                timeout=60,
            )
            self.assertNotEqual(0, rejected.returncode)
            self.assertIn("output directory already exists", rejected.stderr)

            missing = subprocess.run(
                [str(PARITY_COMMAND), "--node", str(temporary / "missing-node")],
                cwd=REPO_ROOT,
                check=False,
                capture_output=True,
                text=True,
                timeout=60,
            )
            self.assertNotEqual(0, missing.returncode)
            self.assertIn("node executable", missing.stderr)

            wrapper = temporary / "faulty-node"
            wrapper.write_text(
                textwrap.dedent(
                    """\
                    #!/usr/bin/env python3
                    import hashlib
                    import json
                    import os
                    import subprocess
                    import sys

                    completed = subprocess.run(
                        [os.environ["REAL_NODE"], *sys.argv[1:]], check=False
                    )
                    if completed.returncode:
                        raise SystemExit(completed.returncode)
                    output = sys.argv[sys.argv.index("--output") + 1]
                    with open(output, encoding="utf-8") as source:
                        result = json.load(source)
                    fault = os.environ["PARITY_FAULT"]
                    if fault == "identity":
                        result["runner"]["name"] = "impostor"
                    elif fault == "revision":
                        result["runner"]["implementation_revision"] = "git:" + "0" * 40
                    elif fault == "missing_case":
                        result["case_results"] = result["case_results"][:-1]
                    with open(output, "w", encoding="utf-8") as destination:
                        json.dump(result, destination, separators=(",", ":"), sort_keys=True)
                        destination.write("\\n")
                    """
                ),
                encoding="utf-8",
            )
            wrapper.chmod(0o700)
            real_node = shutil.which("node")
            self.assertIsNotNone(real_node)
            for fault, diagnostic in (
                ("identity", "javascript runner identity"),
                ("revision", "implementation revision"),
                ("missing_case", "missing_case"),
            ):
                with self.subTest(fault=fault):
                    environment = dict(os.environ, REAL_NODE=real_node, PARITY_FAULT=fault)
                    rejected = subprocess.run(
                        [str(PARITY_COMMAND), "--node", str(wrapper)],
                        cwd=REPO_ROOT,
                        env=environment,
                        check=False,
                        capture_output=True,
                        text=True,
                        timeout=60,
                    )
                    self.assertNotEqual(0, rejected.returncode)
                    self.assertIn(diagnostic, rejected.stderr)

        self.assertEqual(before, _oracle_hashes(), "parity command changed its oracle")


if __name__ == "__main__":
    unittest.main()
