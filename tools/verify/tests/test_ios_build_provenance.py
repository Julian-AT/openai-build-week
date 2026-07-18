"""Regression tests for local Xcode package and Debug provenance wiring."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
PROJECT_PATH = (
    REPOSITORY_ROOT
    / "ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/project.pbxproj"
)


MINIMAL_PROJECT = """// !$*UTF8*$!
{
    archiveVersion = 1;
    classes = {};
    objectVersion = 77;
    objects = {
        PROJECT = {
            isa = PBXProject;
            targets = ();
        };
        CONFIG = {
            isa = XCBuildConfiguration;
            buildSettings = {
                DEVELOPMENT_TEAM = "";
                PRODUCT_NAME = ReRoomDeviceProof;
            };
            name = Debug;
        };
    };
    rootObject = PROJECT;
}
"""


class IOSBuildProvenanceTests(unittest.TestCase):
    def test_local_products_are_bound_to_the_local_package(self) -> None:
        result = subprocess.run(
            ["plutil", "-convert", "json", "-o", "-", PROJECT_PATH],
            check=True,
            capture_output=True,
            text=True,
        )
        objects = json.loads(result.stdout)["objects"]
        package_id = "AD0000000000000000000001"

        self.assertEqual(
            objects["A30000000000000000000001"].get("package"), package_id
        )
        self.assertEqual(
            objects["E30000000000000000000001"].get("package"), package_id
        )

    def test_debug_provenance_allows_only_a_local_signing_override(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = Path(temporary_directory)
            script = repository / "scripts/embed-ios-build-provenance"
            project = (
                repository
                / "ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/project.pbxproj"
            )
            manifest = repository / "fixtures/contracts/1.0.0/rev-001/manifest.json"

            script.parent.mkdir(parents=True)
            project.parent.mkdir(parents=True)
            manifest.parent.mkdir(parents=True)
            shutil.copy2(REPOSITORY_ROOT / "scripts/embed-ios-build-provenance", script)
            project.write_text(MINIMAL_PROJECT, encoding="utf-8")
            manifest.write_text("{}\n", encoding="utf-8")

            self._run(["git", "init", "-q"], repository)
            self._run(["git", "config", "user.name", "ReRoom Test"], repository)
            self._run(
                ["git", "config", "user.email", "reroom-test@example.invalid"],
                repository,
            )
            self._run(["git", "add", "."], repository)
            self._run(["git", "commit", "-qm", "fixture"], repository)

            project.write_text(
                MINIMAL_PROJECT.replace(
                    'DEVELOPMENT_TEAM = "";',
                    "DEVELOPMENT_TEAM = LOCALTEAM123;",
                ),
                encoding="utf-8",
            )

            environment = os.environ.copy()
            environment.update(
                {
                    "CONFIGURATION": "Debug",
                    "DERIVED_FILE_DIR": str(repository / "derived"),
                    "SRCROOT": str(repository / "ios/ReRoomDeviceProof"),
                    "TARGET_BUILD_DIR": str(repository / "build"),
                    "UNLOCALIZED_RESOURCES_FOLDER_PATH": "ReRoomDeviceProof.app",
                }
            )
            allowed = subprocess.run(
                ["/bin/sh", str(script)],
                cwd=repository,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(allowed.returncode, 0, allowed.stderr)

            project.write_text(
                project.read_text(encoding="utf-8").replace(
                    "PRODUCT_NAME = ReRoomDeviceProof;",
                    "PRODUCT_NAME = DifferentProduct;",
                ),
                encoding="utf-8",
            )
            rejected = subprocess.run(
                ["/bin/sh", str(script)],
                cwd=repository,
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(rejected.returncode, 0)

    def _run(self, command: list[str], cwd: Path) -> None:
        subprocess.run(command, cwd=cwd, check=True, capture_output=True, text=True)


if __name__ == "__main__":
    unittest.main()
