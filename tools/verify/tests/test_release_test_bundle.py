"""Regression gate for the Release unit-test bundle executable."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
PROJECT = ROOT / "ios/ReRoomDeviceProof/ReRoomDeviceProof.xcodeproj/project.pbxproj"
TEST_SOURCES = ROOT / "ios/ReRoomDeviceProof/ReRoomDeviceProofTests"


class ReleaseTestBundleTests(unittest.TestCase):
    def test_release_unit_bundle_retains_a_non_testable_smoke_source(self) -> None:
        project = PROJECT.read_text(encoding="utf-8")

        sources_match = re.search(
            r"AA0000000000000000000002 /\* Sources \*/ = \{.*?files = \((.*?)\);",
            project,
            re.DOTALL,
        )
        self.assertIsNotNone(sources_match, "unit-test sources phase is missing")
        source_names = set(
            re.findall(r"/\* ([A-Za-z0-9_+.-]+\.swift) in Sources \*/", sources_match.group(1))
        )
        self.assertTrue(source_names, "unit-test target has no declared Swift sources")

        release_match = re.search(
            r"AE0000000000000000000004 /\* Release \*/ = \{.*?buildSettings = \{(.*?)\n\s*\};\n\s*name = Release;",
            project,
            re.DOTALL,
        )
        self.assertIsNotNone(release_match, "unit-test Release configuration is missing")
        excluded_match = re.search(
            r"EXCLUDED_SOURCE_FILE_NAMES = \((.*?)\);",
            release_match.group(1),
            re.DOTALL,
        )
        excluded = (
            set(re.findall(r"([A-Za-z0-9_+.-]+\.swift)", excluded_match.group(1)))
            if excluded_match
            else set()
        )
        eligible = sorted(source_names - excluded)
        self.assertTrue(
            eligible,
            "Release excludes every unit-test source, producing an xctest bundle without an executable",
        )

        for name in eligible:
            source = (TEST_SOURCES / name).read_text(encoding="utf-8")
            self.assertNotIn(
                "@testable import ReRoomDeviceProof",
                source,
                f"Release-eligible smoke source must not require ENABLE_TESTABILITY: {name}",
            )


if __name__ == "__main__":
    unittest.main()
