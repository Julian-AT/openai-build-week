"""Independent Python mutation gates for the shared immutable fixture corpus."""

from __future__ import annotations

import hashlib
import json
import shutil
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path
from typing import Callable, Iterator

from tools.python.reroom_verify.loader import VerificationFailure
from tools.python.reroom_verify.runner import run_fixture


REPO_ROOT = Path(__file__).resolve().parents[3]
REVISION = "git:" + ("0" * 40)
MANIFESTS = {
    "contract": Path("fixtures/contracts/1.0.0/rev-001/manifest.json"),
    "jcs": Path("fixtures/policies/RR-JCS-SHA256-1/rev-001/manifest.json"),
    "coord": Path("fixtures/policies/RR-COORD-1/rev-001/manifest.json"),
}


def _digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _write_manifest(path: Path, manifest: dict) -> None:
    path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


@contextmanager
def _copied_repository() -> Iterator[Path]:
    with tempfile.TemporaryDirectory(prefix="reroom-python-mutations-") as directory:
        root = Path(directory) / "repo"
        root.mkdir()
        shutil.copytree(REPO_ROOT / "fixtures", root / "fixtures")
        (root / "docs").mkdir()
        shutil.copytree(REPO_ROOT / "docs/contracts", root / "docs/contracts")
        yield root


def _point_at_rejected_case(
    root: Path, family: str, target_id: str, source_id: str
) -> tuple[Path, str]:
    manifest_path = root / MANIFESTS[family]
    manifest = _read_json(manifest_path)
    target = next(case for case in manifest["cases"] if case["case_id"] == target_id)
    source = next(case for case in manifest["cases"] if case["case_id"] == source_id)
    target["case_kind"] = source["case_kind"]
    target["input"] = dict(source["input"])
    _write_manifest(manifest_path, manifest)
    return manifest_path, target_id


def _mutate_coordinate(
    root: Path, target_id: str, mutate: Callable[[dict], None]
) -> tuple[Path, str]:
    manifest_path = root / MANIFESTS["coord"]
    manifest = _read_json(manifest_path)
    target = next(case for case in manifest["cases"] if case["case_id"] == target_id)
    input_path = manifest_path.parent / target["input"]["relative_path"]
    document = _read_json(input_path)
    mutate(document)
    raw = (
        json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        + b"\n"
    )
    input_path.write_bytes(raw)
    target["input"]["byte_length"] = len(raw)
    target["input"]["sha256"] = _digest(raw)
    _write_manifest(manifest_path, manifest)
    return manifest_path, target_id


def _oracle_hashes() -> dict[str, str]:
    return {
        str(path.relative_to(REPO_ROOT)): _digest(path.read_bytes())
        for path in sorted((REPO_ROOT / "fixtures").rglob("*"))
        if path.is_file()
    }


class PythonParityMutationTests(unittest.TestCase):
    maxDiff = None

    def _assert_mutation_rejected(self, mutation: dict) -> None:
        with _copied_repository() as root:
            if "mutate" in mutation:
                manifest_path, target_id = _mutate_coordinate(
                    root, mutation["target"], mutation["mutate"]
                )
            else:
                manifest_path, target_id = _point_at_rejected_case(
                    root,
                    mutation["family"],
                    mutation["target"],
                    mutation["source"],
                )
            result = run_fixture(
                manifest_path,
                repo_root=root,
                implementation_revision=REVISION,
            )
            row = next(
                row for row in result["case_results"] if row["case_id"] == target_id
            )
            self.assertEqual(
                ("reject", mutation["rejection"]),
                (row["verdict"], row["rejection_class"]),
                mutation["name"],
            )

    def test_python_kills_contract_jcs_rrfp_path_and_coordinate_mutations(self) -> None:
        before = _oracle_hashes()
        mutations = [
            {
                "name": "closed contract schema",
                "family": "contract",
                "target": "contract.con001.valid",
                "source": "contract.extra-property",
                "rejection": "unknown_property",
            },
            {
                "name": "unsafe archive path",
                "family": "contract",
                "target": "contract.con002.valid",
                "source": "contract.con002.unsafe-path",
                "rejection": "invalid_path",
            },
            {
                "name": "payload digest",
                "family": "contract",
                "target": "contract.con001.valid",
                "source": "contract.hash-mismatch",
                "rejection": "digest_mismatch",
            },
            {
                "name": "JCS duplicate-name bytes",
                "family": "jcs",
                "target": "jcs.basic-object",
                "source": "jcs.duplicate-name",
                "rejection": "duplicate_name",
            },
        ]
        for name, source, rejection in (
            ("RRFP magic", "wire.bad-magic", "wire_magic"),
            ("RRFP version", "wire.bad-version", "wire_version"),
            ("RRFP flags", "wire.nonzero-flags", "wire_flags"),
            ("RRFP length", "wire.header-length-mismatch", "wire_length"),
            ("RRFP sequence", "wire.sequence-mismatch", "wire_sequence"),
            ("RRFP payload SHA", "wire.payload-tamper", "digest_mismatch"),
            ("RRFP truncation", "wire.truncated", "wire_truncated"),
            ("RRFP trailing bytes", "wire.trailing-byte", "wire_trailing_bytes"),
        ):
            mutations.append(
                {
                    "name": name,
                    "family": "coord",
                    "target": "wire.valid",
                    "source": source,
                    "rejection": rejection,
                }
            )
        mutations.extend(
            (
                {
                    "name": "coordinate reflected correction matrix",
                    "target": "coord.correction-forward",
                    "rejection": "coordinate_invalid",
                    "mutate": lambda document: document[
                        "to_from_from_transform"
                    ].__setitem__(0, -1),
                },
                {
                    "name": "coordinate orientation",
                    "target": "coord.crop-scale-rotate",
                    "rejection": "coordinate_invalid",
                    "mutate": lambda document: document.__setitem__(
                        "orientation", "sideways"
                    ),
                },
                {
                    "name": "coordinate correction direction",
                    "target": "coord.correction-forward",
                    "rejection": "coordinate_invalid",
                    "mutate": lambda document: document.__setitem__(
                        "to_world_frame_version",
                        document["from_world_frame_version"],
                    ),
                },
            )
        )

        for mutation in mutations:
            with self.subTest(mutation=mutation["name"]):
                self._assert_mutation_rejected(mutation)

        with _copied_repository() as root:
            manifest_path = root / MANIFESTS["jcs"]
            manifest = _read_json(manifest_path)
            input_path = manifest_path.parent / manifest["cases"][0]["input"][
                "relative_path"
            ]
            input_path.write_bytes(input_path.read_bytes() + b"x")
            with self.assertRaises(VerificationFailure) as raised:
                run_fixture(
                    manifest_path,
                    repo_root=root,
                    implementation_revision=REVISION,
                )
            self.assertEqual("digest_mismatch", raised.exception.rejection_class)

        self.assertEqual(
            before,
            _oracle_hashes(),
            "Python mutation tests changed the immutable repository fixture corpus",
        )


if __name__ == "__main__":
    unittest.main()
