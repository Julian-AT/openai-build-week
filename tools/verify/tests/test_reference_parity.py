"""Integration tests for the fresh two-runtime parity command."""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
PARITY_COMMAND = REPO_ROOT / "scripts/run-reference-parity"
JAVASCRIPT_MUTATIONS = REPO_ROOT / "tools/javascript/test/parity-mutations.test.mjs"
PYTHON_MUTATIONS = REPO_ROOT / "tools/python/tests/test_parity_mutations.py"


def _oracle_hashes() -> dict[str, str]:
    roots = (REPO_ROOT / "fixtures", REPO_ROOT / "docs/contracts")
    return {
        str(path.relative_to(REPO_ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
        for root in roots
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


class ReferenceParityTests(unittest.TestCase):
    maxDiff = None

    def test_cross_runtime_mutation_gates_are_present(self) -> None:
        self.assertTrue(
            JAVASCRIPT_MUTATIONS.is_file(), "JavaScript mutation gates are absent"
        )
        self.assertTrue(PYTHON_MUTATIONS.is_file(), "Python mutation gates are absent")

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
