"""Frozen integrity and semantic gates for the Phase 02 capture corpus."""

from __future__ import annotations

import copy
import hashlib
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator, FormatChecker


ROOT = Path(__file__).resolve().parents[3]
FIXTURE_ROOT = ROOT / "fixtures/capture/1.0.0/rev-001"
FIXTURE_MANIFEST = FIXTURE_ROOT / "manifest.json"
REPORT_SCHEMA = ROOT / "fixtures/replay-report.schema.json"
CON001_SCHEMA = ROOT / "docs/contracts/frame-packet.schema.json"
CON002_SCHEMA = ROOT / "docs/contracts/rrcap-manifest.schema.json"

# This is deliberately external to the fixture manifest. Updating the corpus requires
# an explicit oracle review and a matching change to this pinned value.
EXPECTED_FIXTURE_MANIFEST_SHA256 = (
    "bf738a623c99320d28370ea84b032a0995e09ce388cf11ce2de83aec741397b6"
)

ARCHIVE_NAMES = (
    "finalized-empty.rrcap",
    "finalized-one-frame.rrcap",
    "recovered-prefix.rrcap",
)
EDGE_PROBE_IDS = (
    "fr-b0.adjacency",
    "fr-b0.concurrency",
    "fr-b0.empty",
    "fr-b0.ordering",
    "fr-capture.adjacency",
    "fr-capture.boundary",
    "fr-capture.concurrency",
    "fr-capture.empty",
    "fr-capture.ordering",
    "fr-capture.precision",
    "nfr-replay.assumption",
    "sec-consent.concurrent-session-separation",
)
REJECTION_CLASSES = {
    "digest_mismatch",
    "invalid_identity",
    "invalid_path",
    "invalid_unicode",
    "non_contiguous_journal",
    "numeric_out_of_range",
    "schema_validation",
    "semantic_invariant",
    "unknown_property",
    "unsupported_contract_version",
    "wire_length_mismatch",
}


def _load_json(path: Path) -> Any:
    def reject_duplicate(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise AssertionError(f"duplicate JSON key {key!r} in {path}")
            result[key] = value
        return result

    return json.loads(path.read_bytes(), object_pairs_hook=reject_duplicate)


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _canonical_digest(value: Any, *, omit: str | None = None) -> str:
    scope = {key: child for key, child in value.items() if key != omit} if omit else value
    canonical = json.dumps(
        scope,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    return _sha256(canonical)


def _assert_schema(test: unittest.TestCase, schema_path: Path, instance: Any) -> None:
    schema = _load_json(schema_path)
    Draft202012Validator.check_schema(schema)
    errors = sorted(
        Draft202012Validator(schema, format_checker=FormatChecker()).iter_errors(instance),
        key=lambda error: (list(error.absolute_path), error.message),
    )
    test.assertEqual([], errors, "\n".join(error.message for error in errors))


def _file_binding(path: Path, root: Path) -> dict[str, Any]:
    raw = path.read_bytes()
    return {
        "relative_path": path.relative_to(root).as_posix(),
        "byte_length": len(raw),
        "sha256": _sha256(raw),
    }


def _directory_binding(path: Path, root: Path) -> dict[str, Any]:
    files = [_file_binding(candidate, root) for candidate in sorted(path.rglob("*")) if candidate.is_file()]
    return {
        "relative_path": path.relative_to(root).as_posix(),
        "file_count": len(files),
        "byte_length": sum(binding["byte_length"] for binding in files),
        "tree_sha256": _canonical_digest(files),
    }


def _assert_inventory(test: unittest.TestCase, archive: Path, manifest: dict[str, Any]) -> None:
    inventory = {entry["relative_path"]: entry for entry in manifest["files"]}
    test.assertEqual(sorted(inventory), list(inventory), "CON-002 inventory is not lexical")
    for relative_path, expected in inventory.items():
        candidate = archive / relative_path
        test.assertTrue(candidate.is_file(), f"accepted inventory file is absent: {relative_path}")
        actual = _file_binding(candidate, archive)
        test.assertEqual(actual["byte_length"], expected["byte_length"])
        test.assertEqual(actual["sha256"], expected["sha256"])


def _assert_journal(test: unittest.TestCase, archive: Path, manifest: dict[str, Any]) -> None:
    journal = manifest["journal"]
    test.assertEqual(
        list(range(len(journal))), [record["journal_sequence"] for record in journal]
    )
    events = {event["event_id"]: event for event in manifest["events"]}
    frames = {frame["frame_id"]: frame for frame in manifest["accepted_frame_order"]}
    event_sequences: list[int] = []
    frame_sequences: list[int] = []
    for record in journal:
        if record["entry_type"] == "event":
            event = events[record["reference_id"]]
            event_sequences.append(event["event_sequence"])
            test.assertEqual(record["journal_sequence"], event["durable_journal_sequence"])
            test.assertEqual(record["content_sha256"], event["record_sha256"])
            test.assertEqual(
                _canonical_digest(event, omit="record_sha256"), event["record_sha256"]
            )
            payload = archive / event["payload_path"]
            test.assertEqual(event["payload_sha256"], _sha256(payload.read_bytes()))
        else:
            frame = frames[record["reference_id"]]
            frame_sequences.append(frame["sequence"])
            test.assertEqual(record["journal_sequence"], frame["durable_journal_sequence"])
            test.assertEqual(record["content_sha256"], frame["packet_sha256"])
    test.assertEqual(list(range(len(event_sequences))), event_sequences)
    test.assertEqual(list(range(len(frame_sequences))), frame_sequences)
    tuples = [
        [
            record["journal_sequence"],
            record["entry_type"],
            record["reference_id"],
            record["content_sha256"],
        ]
        for record in journal
    ]
    test.assertEqual(_canonical_digest(tuples), manifest["replay"]["input_digest"])


def _projection_digest(manifest: dict[str, Any], key: str) -> str:
    return _canonical_digest(manifest[key])


def _validate_archive(test: unittest.TestCase, archive: Path, oracle: dict[str, Any]) -> None:
    manifest_path = archive / "manifest.json"
    manifest = _load_json(manifest_path)
    _assert_schema(test, CON002_SCHEMA, manifest)
    manifest_scope = copy.deepcopy(manifest)
    manifest_scope["finalization"].pop("manifest_sha256")
    test.assertEqual(
        _canonical_digest(manifest_scope), manifest["finalization"]["manifest_sha256"]
    )
    _assert_inventory(test, archive, manifest)
    _assert_journal(test, archive, manifest)

    test.assertEqual(
        [event["durable_journal_sequence"] for event in manifest["events"]],
        sorted(event["durable_journal_sequence"] for event in manifest["events"]),
    )
    test.assertEqual(
        [frame["durable_journal_sequence"] for frame in manifest["accepted_frame_order"]],
        sorted(frame["durable_journal_sequence"] for frame in manifest["accepted_frame_order"]),
    )

    for accepted in manifest["accepted_frame_order"]:
        packet_path = archive / accepted["packet_path"]
        packet = _load_json(packet_path)
        _assert_schema(test, CON001_SCHEMA, packet)
        test.assertEqual(accepted["packet_sha256"], _sha256(packet_path.read_bytes()))
        payload = packet["image"]["payload"]
        test.assertEqual("rrcap_file", payload["kind"])
        image_path = archive / payload["relative_path"]
        test.assertEqual(payload["byte_length"], image_path.stat().st_size)
        test.assertEqual(payload["sha256"], _sha256(image_path.read_bytes()))
        test.assertEqual(packet["payload_sha256"], payload["sha256"])
        test.assertEqual(accepted["frame_id"], packet["frame_id"])
        test.assertEqual(accepted["sequence"], packet["capture_sequence"])
        test.assertEqual(
            accepted["durable_journal_sequence"], packet["durability"]["journal_sequence"]
        )

    expected = oracle["expected"]
    test.assertEqual(expected["finalization_state"], manifest["finalization"]["state"])
    test.assertEqual(expected["accepted_frame_count"], len(manifest["accepted_frame_order"]))
    test.assertEqual(expected["event_count"], len(manifest["events"]))
    test.assertEqual(expected["journal_record_count"], len(manifest["journal"]))
    test.assertEqual(expected["journal_tuple_sha256"], manifest["replay"]["input_digest"])
    test.assertEqual(
        expected["frame_projection_sha256"], _projection_digest(manifest, "accepted_frame_order")
    )
    test.assertEqual(expected["event_projection_sha256"], _projection_digest(manifest, "events"))
    test.assertEqual(expected["revision_trace_sha256"], _canonical_digest(expected["revision_trace"]))
    test.assertIn(expected["verdict"], {"accept", "reject"})
    if expected["verdict"] == "reject":
        test.assertIn(expected["rejection_class"], REJECTION_CLASSES)


def _validate_fixture_root(test: unittest.TestCase, root: Path) -> None:
    manifest_path = root / "manifest.json"
    test.assertTrue(manifest_path.is_file(), "capture fixture manifest is absent")
    test.assertEqual(EXPECTED_FIXTURE_MANIFEST_SHA256, _sha256(manifest_path.read_bytes()))
    manifest = _load_json(manifest_path)
    test.assertEqual(
        {
            "schema_version",
            "fixture_id",
            "fixture_revision",
            "description",
            "privacy",
            "consent_denied_case",
            "report_schema",
            "archives",
            "directories",
            "files",
            "edge_probes",
        },
        set(manifest),
    )
    test.assertEqual("1.0.0", manifest["schema_version"])
    test.assertEqual("FX-CAPTURE-001", manifest["fixture_id"])
    test.assertEqual("rev-001", manifest["fixture_revision"])
    test.assertEqual(
        {"contains_room_data": False, "synthetic_bytes_only": True}, manifest["privacy"]
    )
    test.assertEqual(
        {
            "session_id": "session_00000000-0000-4000-8000-000000000004",
            "consent_granted": False,
            "archive_created": False,
            "expected_verdict": "reject",
            "rejection_class": "semantic_invariant",
        },
        manifest["consent_denied_case"],
    )
    report_binding = _file_binding(REPORT_SCHEMA, ROOT)
    test.assertEqual(report_binding, manifest["report_schema"])

    expected_files = [_file_binding(path, root) for path in sorted(root.rglob("*")) if path.is_file() and path != manifest_path]
    test.assertEqual(expected_files, manifest["files"])
    expected_directories = [
        _directory_binding(path, root)
        for path in sorted(root.rglob("*"))
        if path.is_dir()
    ]
    test.assertEqual(expected_directories, manifest["directories"])

    archives = manifest["archives"]
    test.assertEqual(list(ARCHIVE_NAMES), [entry["archive_name"] for entry in archives])
    for archive_oracle in archives:
        _validate_archive(
            test,
            root / "archives" / archive_oracle["archive_name"],
            archive_oracle,
        )

    probes = manifest["edge_probes"]
    test.assertEqual(list(EDGE_PROBE_IDS), [probe["case_id"] for probe in probes])
    for probe in probes:
        test.assertEqual(
            {"case_id", "requirement_id", "concern", "input", "expected"}, set(probe)
        )
        test.assertIn(probe["expected"]["verdict"], {"accept", "reject"})
        if probe["expected"]["verdict"] == "reject":
            test.assertIn(probe["expected"]["rejection_class"], REJECTION_CLASSES)


class Phase02FixtureTests(unittest.TestCase):
    maxDiff = None

    def test_capture_corpus_is_complete_and_semantically_exact(self) -> None:
        _validate_fixture_root(self, FIXTURE_ROOT)

    def test_report_schema_is_closed_and_self_hash_omission_is_exact(self) -> None:
        self.assertTrue(REPORT_SCHEMA.is_file(), "replay report schema is absent")
        schema = _load_json(REPORT_SCHEMA)
        Draft202012Validator.check_schema(schema)
        self.assertFalse(schema["additionalProperties"])
        self.assertEqual(
            {
                "report_version",
                "evaluator",
                "fixture",
                "implementation",
                "verdict",
                "digests",
                "rejection",
                "metrics",
                "report_sha256",
            },
            set(schema["properties"]),
        )
        self.assertEqual(
            {"report_sha256"},
            set(schema["properties"]["report_sha256"]["x-digest-omits"]),
        )

    def test_one_byte_drift_is_fatal(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            copied = Path(directory) / "rev-001"
            shutil.copytree(FIXTURE_ROOT, copied)
            target = copied / "archives/finalized-one-frame.rrcap/image/frame_0001.png"
            target.write_bytes(target.read_bytes() + b"!")
            with self.assertRaises(AssertionError):
                _validate_fixture_root(self, copied)

    def test_omitting_any_bound_artifact_is_fatal(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            copied = Path(directory) / "rev-001"
            shutil.copytree(FIXTURE_ROOT, copied)
            target = copied / "archives/finalized-empty.rrcap/events/event_0000.json"
            target.unlink()
            with self.assertRaises(AssertionError):
                _validate_fixture_root(self, copied)

    def test_fixture_manifest_cannot_redefine_the_external_oracle(self) -> None:
        manifest = _load_json(FIXTURE_MANIFEST)
        with tempfile.TemporaryDirectory() as directory:
            copied = Path(directory) / "rev-001"
            shutil.copytree(FIXTURE_ROOT, copied)
            changed = copy.deepcopy(manifest)
            changed["description"] += " changed"
            (copied / "manifest.json").write_text(
                json.dumps(
                    changed,
                    ensure_ascii=False,
                    sort_keys=True,
                    separators=(",", ":"),
                    allow_nan=False,
                )
                + "\n",
                encoding="utf-8",
            )
            with self.assertRaises(AssertionError):
                _validate_fixture_root(self, copied)


if __name__ == "__main__":
    unittest.main()
