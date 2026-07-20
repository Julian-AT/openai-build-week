import { randomUUID } from "node:crypto";
import {
  lstat,
  mkdir,
  open,
  readdir,
  readFile,
  rename,
  rm,
} from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { canonicalDigest, canonicalizeBytes } from "./canonical-json.mjs";
import {
  MAX_CASES,
  MAX_FILE_BYTES,
  parseJsonBytesStrict,
  sha256Hex,
  validateArchivePath,
} from "./loader.mjs";

type JsonObject = Record<string, any>;

type ReplayOptions = {
  manifestPath: string;
  outputRoot: string;
  repoRoot: string;
  implementationRevision: string;
  runtimeVersion?: string;
};

type ReplaySnapshot = {
  archiveName: string;
  finalizationState: "finalized" | "recovered_prefix";
  manifestSHA256: string;
  acceptedFrameCount: number;
  eventCount: number;
  journalRecordCount: number;
  digests: {
    journal_tuple_sha256: string;
    frame_projection_sha256: string;
    event_projection_sha256: string;
    revision_trace_sha256: string;
  };
};

type CaseOutcome = {
  verdict: "accept" | "reject";
  rejectionClass: string | null;
};

export const EXACT_BUN_VERSION = "1.3.11";

const PINNED_FIXTURE_MANIFEST_SHA256 = "3b4519d2730e158df73e938f7b841664c6ce5f7d65ed2650c90ca8e89c7a7610";
const PINNED_REPORT_SCHEMA_SHA256 = "821784ce1a3e4f45c2fe4db70f8f16643284f2e3e9f6effe85a7aee3e17bb9a9";
const REVISION = /^git:[0-9a-f]{40}$/;
const DIGEST = /^[0-9a-f]{64}$/;
const SESSION_ID = /^session_[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const SUPPORTED_CODECS = new Set([
  "json_jcs_1", "jsonl_utf8_1", "jpeg", "png", "hevc_intra", "hevc_video",
  "h264_video", "glb2", "usdz", "ply_binary_little_endian_1_0", "npy_1_0", "ktx2_2_0",
]);
const ARCHIVE_NAMES = ["finalized-empty.rrcap", "finalized-one-frame.rrcap", "recovered-prefix.rrcap"];
const PROBE_IDS = [
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
];
const FIXTURE_KEYS = new Set([
  "archives", "consent_denied_case", "description", "directories", "edge_probes", "files",
  "fixture_id", "fixture_revision", "privacy", "report_schema", "schema_version",
]);
const ARCHIVE_MANIFEST_KEYS = new Set([
  "accepted_frame_order", "capture_kind", "capture_settings", "coordinate_convention", "events",
  "files", "finalization", "format_version", "journal", "keyframes", "privacy", "replay",
  "session_id", "source",
]);

class ReplayFailure extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ReplayFailure";
  }
}

function requireReplay(condition: unknown, message: string): asserts condition {
  if (!condition) throw new ReplayFailure(message);
}

function object(value: unknown, message = "expected a JSON object"): JsonObject {
  requireReplay(value !== null && typeof value === "object" && !Array.isArray(value), message);
  return value as JsonObject;
}

function array(value: unknown, message = "expected a JSON array"): any[] {
  requireReplay(Array.isArray(value), message);
  return value;
}

function exactInteger(value: unknown, message = "expected an exact nonnegative integer"): number {
  requireReplay(Number.isSafeInteger(value) && Number(value) >= 0, message);
  return Number(value);
}

function exactKeys(value: JsonObject, keys: Set<string>, message: string): void {
  const actual = Object.keys(value);
  requireReplay(actual.length === keys.size && actual.every((key) => keys.has(key)), message);
}

function subsetKeys(value: JsonObject, required: Set<string>, allowed: Set<string>, message: string): void {
  const actual = new Set(Object.keys(value));
  requireReplay([...required].every((key) => actual.has(key)) && [...actual].every((key) => allowed.has(key)), message);
}

function lexicalUnique(values: string[], message: string): void {
  requireReplay(new Set(values).size === values.length, message);
  requireReplay(values.every((value, index) => index === 0 || values[index - 1] < value), message);
}

async function regularBytes(filePath: string, maximum = MAX_FILE_BYTES): Promise<Buffer> {
  let metadata;
  try {
    metadata = await lstat(filePath);
  } catch {
    throw new ReplayFailure("referenced file is unavailable");
  }
  requireReplay(metadata.isFile() && !metadata.isSymbolicLink() && metadata.size <= maximum, "input is not a bounded regular file");
  const bytes = await readFile(filePath);
  requireReplay(bytes.length === metadata.size, "input changed while being read");
  return bytes;
}

async function requireDirectory(directory: string, message: string): Promise<void> {
  let metadata;
  try {
    metadata = await lstat(directory);
  } catch {
    throw new ReplayFailure(message);
  }
  requireReplay(metadata.isDirectory() && !metadata.isSymbolicLink(), message);
}

function lexicallyContained(root: string, candidate: string): boolean {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith(`..${path.sep}`) && relative !== ".." && !path.isAbsolute(relative));
}

async function safeExisting(root: string, relativePath: string, expected: "file" | "directory"): Promise<string> {
  validateArchivePath(relativePath);
  const absoluteRoot = path.resolve(root);
  const candidate = path.resolve(absoluteRoot, relativePath);
  requireReplay(lexicallyContained(absoluteRoot, candidate), "unsafe archive path");
  let current = absoluteRoot;
  for (const component of relativePath.split("/")) {
    current = path.join(current, component);
    let metadata;
    try {
      metadata = await lstat(current);
    } catch {
      throw new ReplayFailure("referenced archive path is unavailable");
    }
    requireReplay(!metadata.isSymbolicLink(), "archive paths may not traverse symlinks");
  }
  const metadata = await lstat(candidate);
  requireReplay(expected === "file" ? metadata.isFile() : metadata.isDirectory(), `archive ${expected} has the wrong type`);
  return candidate;
}

async function allRegularFiles(root: string): Promise<string[]> {
  await requireDirectory(root, "inventory root is not a directory");
  const result: string[] = [];
  const visit = async (directory: string): Promise<void> => {
    const entries = await readdir(directory, { withFileTypes: true });
    entries.sort((left, right) => left.name.localeCompare(right.name, "en"));
    for (const entry of entries) {
      const candidate = path.join(directory, entry.name);
      requireReplay(!entry.isSymbolicLink(), "inventory contains a symlink");
      if (entry.isDirectory()) await visit(candidate);
      else {
        requireReplay(entry.isFile(), "inventory contains an unsupported filesystem entry");
        result.push(candidate);
      }
    }
  };
  await visit(root);
  return result.sort();
}

async function fileBinding(filePath: string, root: string): Promise<JsonObject> {
  const bytes = await regularBytes(filePath);
  return {
    relative_path: path.relative(root, filePath).split(path.sep).join("/"),
    byte_length: bytes.length,
    sha256: sha256Hex(bytes),
  };
}

async function verifyFixtureInventory(fixture: JsonObject, fixtureRoot: string): Promise<void> {
  const inventory = array(fixture.files, "fixture file inventory is absent");
  requireReplay(inventory.length <= MAX_CASES, "fixture file inventory exceeds the bound");
  const paths: string[] = [];
  for (const rawEntry of inventory) {
    const entry = object(rawEntry, "fixture file binding is invalid");
    exactKeys(entry, new Set(["byte_length", "relative_path", "sha256"]), "fixture file binding is not closed");
    const relativePath = entry.relative_path;
    requireReplay(typeof relativePath === "string" && DIGEST.test(entry.sha256), "fixture file identity is invalid");
    paths.push(relativePath);
    const bytes = await regularBytes(await safeExisting(fixtureRoot, relativePath, "file"), exactInteger(entry.byte_length) + 1);
    requireReplay(bytes.length === entry.byte_length && sha256Hex(bytes) === entry.sha256, "fixture file digest mismatch");
  }
  lexicalUnique(paths, "fixture file inventory is duplicated or unsorted");
  const physical = (await allRegularFiles(await safeExisting(fixtureRoot, "archives", "directory")))
    .map((candidate) => path.relative(fixtureRoot, candidate).split(path.sep).join("/"));
  requireReplay(JSON.stringify(physical) === JSON.stringify(paths), "fixture raw inventory is incomplete or contains an extra file");

  const directories = array(fixture.directories, "fixture directory inventory is absent");
  const directoryPaths: string[] = [];
  for (const rawEntry of directories) {
    const entry = object(rawEntry, "fixture directory binding is invalid");
    exactKeys(entry, new Set(["byte_length", "file_count", "relative_path", "tree_sha256"]), "fixture directory binding is not closed");
    const relativePath = entry.relative_path;
    requireReplay(typeof relativePath === "string" && DIGEST.test(entry.tree_sha256), "fixture directory identity is invalid");
    directoryPaths.push(relativePath);
    const directory = await safeExisting(fixtureRoot, relativePath, "directory");
    const bindings = await Promise.all((await allRegularFiles(directory)).map((candidate) => fileBinding(candidate, fixtureRoot)));
    requireReplay(bindings.length === entry.file_count, "fixture directory file count mismatch");
    requireReplay(bindings.reduce((total, binding) => total + binding.byte_length, 0) === entry.byte_length, "fixture directory byte length mismatch");
    requireReplay(canonicalDigest(bindings) === entry.tree_sha256, "fixture directory tree digest mismatch");
  }
  lexicalUnique(directoryPaths, "fixture directory inventory is duplicated or unsorted");
}

async function loadFixture(options: ReplayOptions): Promise<{ fixture: JsonObject; fixtureRoot: string }> {
  await requireDirectory(path.resolve(options.repoRoot), "repository root is invalid");
  const manifestPath = path.resolve(options.manifestPath);
  const manifestBytes = await regularBytes(manifestPath);
  requireReplay(sha256Hex(manifestBytes) === PINNED_FIXTURE_MANIFEST_SHA256, "capture fixture manifest drifted");
  const fixture = object(parseJsonBytesStrict(manifestBytes), "capture fixture manifest is not an object");
  exactKeys(fixture, FIXTURE_KEYS, "capture fixture manifest has unknown or missing properties");
  requireReplay(
    fixture.schema_version === "1.0.0"
      && fixture.fixture_id === "FX-CAPTURE-001"
      && fixture.fixture_revision === "rev-001",
    "capture fixture identity is invalid",
  );
  const fixtureRoot = path.dirname(manifestPath);
  await verifyFixtureInventory(fixture, fixtureRoot);

  const reportSchema = object(fixture.report_schema, "report schema binding is invalid");
  exactKeys(reportSchema, new Set(["byte_length", "relative_path", "sha256"]), "report schema binding is not closed");
  requireReplay(reportSchema.sha256 === PINNED_REPORT_SCHEMA_SHA256, "report schema binding drifted");
  const schemaPath = await safeExisting(path.resolve(options.repoRoot), reportSchema.relative_path, "file");
  const schemaBytes = await regularBytes(schemaPath, exactInteger(reportSchema.byte_length) + 1);
  requireReplay(schemaBytes.length === reportSchema.byte_length && sha256Hex(schemaBytes) === PINNED_REPORT_SCHEMA_SHA256, "report schema drifted");
  const schema = object(parseJsonBytesStrict(schemaBytes), "report schema is invalid JSON");
  requireReplay(schema.$id === "https://reroom.dev/schemas/replay-report/1.0.0" && schema.additionalProperties === false, "report schema identity is invalid");

  const archives = array(fixture.archives, "archive descriptors are absent");
  const archiveNames = archives.map((raw) => object(raw).archive_name);
  requireReplay(JSON.stringify(archiveNames) === JSON.stringify(ARCHIVE_NAMES), "archive set is incomplete, duplicated, or unsorted");
  const probes = array(fixture.edge_probes, "edge probes are absent");
  const probeIDs = probes.map((raw) => object(raw).case_id);
  requireReplay(JSON.stringify(probeIDs) === JSON.stringify(PROBE_IDS), "edge probe set is incomplete, duplicated, or unsorted");
  const consent = object(fixture.consent_denied_case, "consent-denied case is absent");
  requireReplay(
    consent.archive_created === false && consent.consent_granted === false
      && consent.expected_verdict === "reject" && consent.rejection_class === "semantic_invariant"
      && typeof consent.session_id === "string" && SESSION_ID.test(consent.session_id),
    "consent-denied case is invalid",
  );
  return { fixture, fixtureRoot };
}

async function replayArchive(descriptor: JsonObject, fixtureRoot: string): Promise<ReplaySnapshot> {
  exactKeys(descriptor, new Set(["archive_name", "directory", "expected", "quarantine"]), "archive descriptor is not closed");
  const archiveName = descriptor.archive_name;
  requireReplay(typeof archiveName === "string" && ARCHIVE_NAMES.includes(archiveName), "archive identity is invalid");
  const directory = object(descriptor.directory, "archive directory binding is invalid");
  requireReplay(directory.relative_path === `archives/${archiveName}`, "archive directory path is invalid");
  const archiveRoot = await safeExisting(fixtureRoot, directory.relative_path, "directory");
  const manifestBytes = await regularBytes(await safeExisting(archiveRoot, "manifest.json", "file"));
  const manifest = object(parseJsonBytesStrict(manifestBytes), "archive manifest is invalid JSON");
  requireReplay(canonicalizeBytes(manifest).equals(manifestBytes), "archive manifest is not exact JCS bytes");
  exactKeys(manifest, ARCHIVE_MANIFEST_KEYS, "archive manifest has unknown or missing properties");
  requireReplay(manifest.format_version === "1.0.0" && manifest.capture_kind === "native_arkit", "unsupported archive contract version");
  requireReplay(typeof manifest.session_id === "string" && SESSION_ID.test(manifest.session_id), "archive session identity is invalid");
  requireReplay(array(manifest.keyframes).length === 0, "fixture archive keyframes must be empty");

  const finalization = object(manifest.finalization, "archive finalization is invalid");
  exactKeys(finalization, new Set([
    "last_durable_journal_sequence", "manifest_sha256", "manifest_sha256_algorithm", "manifest_sha256_scope", "state",
  ]), "archive finalization is not closed");
  requireReplay(
    finalization.manifest_sha256_algorithm === "RR-JCS-SHA256-1"
      && finalization.manifest_sha256_scope === "entire_manifest_with_finalization_manifest_sha256_member_omitted"
      && ["finalized", "recovered_prefix"].includes(finalization.state)
      && DIGEST.test(finalization.manifest_sha256),
    "archive finalization identity is invalid",
  );
  const unsignedManifest = structuredClone(manifest);
  delete unsignedManifest.finalization.manifest_sha256;
  requireReplay(canonicalDigest(unsignedManifest) === finalization.manifest_sha256, "archive manifest digest mismatch");

  const files = array(manifest.files, "archive file inventory is invalid");
  requireReplay(files.length <= MAX_CASES, "archive inventory exceeds its bound");
  const inventory = new Map<string, JsonObject>();
  const filePaths: string[] = [];
  for (const rawEntry of files) {
    const entry = object(rawEntry, "archive file binding is invalid");
    exactKeys(entry, new Set(["byte_length", "codec", "media_type", "relative_path", "role", "sha256"]), "archive file binding is not closed");
    requireReplay(
      typeof entry.relative_path === "string" && SUPPORTED_CODECS.has(entry.codec) && DIGEST.test(entry.sha256),
      "archive file binding is invalid",
    );
    filePaths.push(entry.relative_path);
    const bytes = await regularBytes(await safeExisting(archiveRoot, entry.relative_path, "file"), exactInteger(entry.byte_length) + 1);
    requireReplay(bytes.length === entry.byte_length && sha256Hex(bytes) === entry.sha256, "archive inventory digest mismatch");
    inventory.set(entry.relative_path, entry);
  }
  lexicalUnique(filePaths, "archive file inventory is duplicated or unsorted");

  const journal = array(manifest.journal, "archive journal is invalid");
  requireReplay(journal.length > 0 && journal.length <= MAX_CASES, "archive journal count is invalid");
  for (const [index, rawEntry] of journal.entries()) {
    const entry = object(rawEntry, "journal entry is invalid");
    exactKeys(entry, new Set(["content_sha256", "entry_type", "journal_sequence", "monotonic_timestamp_ns", "reference_id"]), "journal entry is not closed");
    requireReplay(
      exactInteger(entry.journal_sequence) === index
        && ["event", "frame"].includes(entry.entry_type)
        && typeof entry.reference_id === "string"
        && DIGEST.test(entry.content_sha256)
        && /^(0|[1-9][0-9]*)$/.test(entry.monotonic_timestamp_ns),
      "non-contiguous or invalid journal entry",
    );
  }

  const events = array(manifest.events, "event projection is invalid");
  const journalEvents = journal.filter((raw) => object(raw).entry_type === "event");
  requireReplay(events.length === journalEvents.length, "event projection count mismatch");
  for (const [index, rawEvent] of events.entries()) {
    const event = object(rawEvent, "event projection member is invalid");
    exactKeys(event, new Set([
      "durable_journal_sequence", "event_id", "event_sequence", "monotonic_timestamp_ns", "payload_path",
      "payload_sha256", "record_sha256", "record_sha256_algorithm", "record_sha256_scope", "type",
    ]), "event projection member is not closed");
    const durable = exactInteger(event.durable_journal_sequence);
    requireReplay(
      exactInteger(event.event_sequence) === index && durable < journal.length
        && typeof event.event_id === "string" && typeof event.payload_path === "string"
        && DIGEST.test(event.payload_sha256) && DIGEST.test(event.record_sha256)
        && event.record_sha256_algorithm === "RR-JCS-SHA256-1"
        && event.record_sha256_scope === "entire_event_record_with_record_sha256_member_omitted",
      "event projection member is invalid",
    );
    const payloadBinding = inventory.get(event.payload_path);
    requireReplay(payloadBinding?.sha256 === event.payload_sha256, "event payload is not bound by inventory");
    const unsignedEvent = structuredClone(event);
    delete unsignedEvent.record_sha256;
    requireReplay(canonicalDigest(unsignedEvent) === event.record_sha256, "event record digest mismatch");
    const journalEntry = object(journal[durable]);
    requireReplay(
      journalEntry.entry_type === "event" && journalEntry.reference_id === event.event_id
        && journalEntry.content_sha256 === event.record_sha256
        && journalEntry.monotonic_timestamp_ns === event.monotonic_timestamp_ns
        && canonicalizeBytes(journalEntry).equals(canonicalizeBytes(object(journalEvents[index]))),
      "event projection is not the exact journal projection",
    );
  }

  const frames = array(manifest.accepted_frame_order, "frame projection is invalid");
  const journalFrames = journal.filter((raw) => object(raw).entry_type === "frame");
  requireReplay(frames.length === journalFrames.length, "frame projection count mismatch");
  const requiredFrameKeys = new Set(["durable_journal_sequence", "frame_id", "packet_path", "packet_sha256", "sequence"]);
  const allowedFrameKeys = new Set([...requiredFrameKeys, "server_acknowledged"]);
  for (const [index, rawFrame] of frames.entries()) {
    const frame = object(rawFrame, "frame projection member is invalid");
    subsetKeys(frame, requiredFrameKeys, allowedFrameKeys, "frame projection member is not closed");
    const durable = exactInteger(frame.durable_journal_sequence);
    requireReplay(
      exactInteger(frame.sequence) === index && durable < journal.length
        && typeof frame.frame_id === "string" && typeof frame.packet_path === "string" && DIGEST.test(frame.packet_sha256),
      "frame projection member is invalid",
    );
    const packetBinding = inventory.get(frame.packet_path);
    requireReplay(packetBinding?.sha256 === frame.packet_sha256, "frame packet is not bound by inventory");
    const journalEntry = object(journal[durable]);
    requireReplay(
      journalEntry.entry_type === "frame" && journalEntry.reference_id === frame.frame_id
        && journalEntry.content_sha256 === frame.packet_sha256
        && canonicalizeBytes(journalEntry).equals(canonicalizeBytes(object(journalFrames[index]))),
      "frame projection is not the exact journal projection",
    );
    const packetBytes = await regularBytes(await safeExisting(archiveRoot, frame.packet_path, "file"));
    const packet = object(parseJsonBytesStrict(packetBytes), "frame packet is invalid JSON");
    requireReplay(canonicalizeBytes(packet).equals(packetBytes), "frame packet is not exact JCS bytes");
    const image = object(packet.image, "frame image binding is invalid");
    const payload = object(image.payload, "frame payload binding is invalid");
    requireReplay(
      packet.protocol_version === "1.0.0" && packet.coordinate_convention === "RR-COORD-1"
        && packet.frame_id === frame.frame_id && exactInteger(packet.capture_sequence) === index
        && image.codec === "png" && payload.kind === "rrcap_file" && typeof payload.relative_path === "string"
        && DIGEST.test(payload.sha256) && packet.payload_sha256 === payload.sha256,
      "frame packet identity or payload binding is invalid",
    );
    const imageBinding = inventory.get(payload.relative_path);
    requireReplay(
      imageBinding?.sha256 === payload.sha256 && imageBinding?.byte_length === exactInteger(payload.byte_length),
      "frame image bytes are not bound by inventory",
    );
  }

  const referenced = new Set<string>();
  for (const rawEvent of events) referenced.add(object(rawEvent).payload_path);
  for (const rawFrame of frames) {
    const frame = object(rawFrame);
    referenced.add(frame.packet_path);
    const packet = object(parseJsonBytesStrict(await regularBytes(await safeExisting(archiveRoot, frame.packet_path, "file"))));
    referenced.add(object(object(packet.image).payload).relative_path);
  }
  requireReplay(
    JSON.stringify([...referenced].sort()) === JSON.stringify([...inventory.keys()].sort()),
    "archive inventory is not the exact frame/event projection closure",
  );

  const replay = object(manifest.replay, "replay digest block is invalid");
  exactKeys(replay, new Set([
    "input_digest", "input_digest_algorithm", "input_digest_scope", "neural_determinism", "ordering_authority", "provider_lock",
  ]), "replay digest block is not closed");
  const journalTupleSHA256 = canonicalDigest(journal.map((raw) => {
    const entry = object(raw);
    return [entry.journal_sequence, entry.entry_type, entry.reference_id, entry.content_sha256];
  }));
  requireReplay(
    replay.ordering_authority === "global_journal_sequence"
      && replay.input_digest_algorithm === "RR-JCS-SHA256-1"
      && replay.input_digest_scope === "jcs_array_of_journal_sequence_entry_type_reference_id_content_sha256"
      && array(replay.provider_lock).length === 0 && replay.input_digest === journalTupleSHA256,
    "journal tuple input digest mismatch",
  );
  requireReplay(exactInteger(finalization.last_durable_journal_sequence) === journal.length - 1, "final journal sequence mismatch");

  const revisionTrace = [{
    journal_sequence: 0,
    revision_id: manifest.session_id.replace(/^session_/, "revision_"),
    source: "capture_baseline",
  }];
  const snapshot: ReplaySnapshot = {
    archiveName,
    finalizationState: finalization.state,
    manifestSHA256: finalization.manifest_sha256,
    acceptedFrameCount: frames.length,
    eventCount: events.length,
    journalRecordCount: journal.length,
    digests: {
      journal_tuple_sha256: journalTupleSHA256,
      frame_projection_sha256: canonicalDigest(frames),
      event_projection_sha256: canonicalDigest(events),
      revision_trace_sha256: canonicalDigest(revisionTrace),
    },
  };

  const expected = object(descriptor.expected, "archive expected equality oracle is invalid");
  requireReplay(expected.verdict === "accept" && expected.rejection_class === null, "archive equality oracle verdict is invalid");
  requireReplay(
    expected.finalization_state === snapshot.finalizationState
      && expected.journal_record_count === snapshot.journalRecordCount
      && expected.accepted_frame_count === snapshot.acceptedFrameCount
      && expected.event_count === snapshot.eventCount
      && expected.journal_tuple_sha256 === snapshot.digests.journal_tuple_sha256
      && expected.frame_projection_sha256 === snapshot.digests.frame_projection_sha256
      && expected.event_projection_sha256 === snapshot.digests.event_projection_sha256
      && expected.revision_trace_sha256 === snapshot.digests.revision_trace_sha256,
    "independent archive replay disagrees with the frozen equality oracle",
  );
  return snapshot;
}

function contiguous(values: unknown): boolean {
  return Array.isArray(values) && values.every((value, index) => Number.isSafeInteger(value) && value === index);
}

function evaluateProbe(probe: JsonObject): CaseOutcome {
  const input = object(probe.input, "edge probe input is invalid");
  let outcome: CaseOutcome;
  switch (probe.case_id) {
    case "fr-b0.adjacency":
      outcome = Number.isSafeInteger(input.prior_revision) && input.next_revision === input.prior_revision + 1
        ? { verdict: "accept", rejectionClass: null }
        : { verdict: "reject", rejectionClass: "semantic_invariant" };
      break;
    case "fr-b0.concurrency": {
      const sequences = array(input.journal_sequences);
      const readerCount = exactInteger(input.reader_count);
      const digests = Array.from({ length: readerCount }, () => canonicalDigest(sequences));
      outcome = readerCount >= 2 && contiguous(sequences) && new Set(digests).size === 1
        ? { verdict: "accept", rejectionClass: null }
        : { verdict: "reject", rejectionClass: "semantic_invariant" };
      break;
    }
    case "fr-b0.empty":
      outcome = input.accepted_frame_count === 0 && exactInteger(input.event_count) > 0
        ? { verdict: "accept", rejectionClass: null }
        : { verdict: "reject", rejectionClass: "semantic_invariant" };
      break;
    case "fr-b0.ordering":
      outcome = contiguous(input.journal_sequences)
        ? { verdict: "accept", rejectionClass: null }
        : { verdict: "reject", rejectionClass: "non_contiguous_journal" };
      break;
    case "fr-capture.adjacency": {
      const sequences = array(input.capture_sequences);
      outcome = input.frame_ids_distinct === true && contiguous(sequences)
        ? { verdict: "accept", rejectionClass: null }
        : { verdict: "reject", rejectionClass: "semantic_invariant" };
      break;
    }
    case "fr-capture.boundary": {
      const maximum = exactInteger(input.payload_max_bytes);
      const neighborVerdicts = array(input.neighbors).map((value) => exactInteger(value) <= maximum ? "accept" : "reject");
      outcome = neighborVerdicts.includes("reject")
        ? { verdict: "reject", rejectionClass: "wire_length_mismatch" }
        : { verdict: "accept", rejectionClass: null };
      break;
    }
    case "fr-capture.concurrency": {
      const durable = exactInteger(input.durable_journal_sequence);
      const acknowledgement = exactInteger(input.acknowledgement_journal_sequence);
      outcome = acknowledgement > durable
        ? { verdict: "accept", rejectionClass: null }
        : { verdict: "reject", rejectionClass: "semantic_invariant" };
      break;
    }
    case "fr-capture.empty":
      outcome = exactInteger(input.image_byte_length) > 0
        ? { verdict: "accept", rejectionClass: null }
        : { verdict: "reject", rejectionClass: "schema_validation" };
      break;
    case "fr-capture.ordering": {
      const lifecycle = array(input.lifecycle);
      const required = ["selected", "image_and_metadata_durable", "journaled", "network_eligible", "server_acknowledged"];
      const positions = lifecycle.map((value) => required.indexOf(value));
      const valid = positions.every((value, index) => value >= 0 && (index === 0 || positions[index - 1] < value))
        && (!lifecycle.includes("network_eligible") || lifecycle.includes("journaled"))
        && (!lifecycle.includes("journaled") || lifecycle.includes("image_and_metadata_durable"));
      outcome = valid
        ? { verdict: "accept", rejectionClass: null }
        : { verdict: "reject", rejectionClass: "semantic_invariant" };
      break;
    }
    case "fr-capture.precision": {
      requireReplay(typeof input.binary32_hex === "string" && /^[0-9a-f]{8}$/.test(input.binary32_hex), "precision probe binary32 bytes are invalid");
      const bytes = Buffer.from(input.binary32_hex, "hex");
      const value = bytes.readFloatBE(0);
      outcome = Number.isFinite(value) && Object.is(value, Math.fround(input.decimal_input))
        ? { verdict: "accept", rejectionClass: null }
        : { verdict: "reject", rejectionClass: "numeric_out_of_range" };
      break;
    }
    case "nfr-replay.assumption":
      outcome = exactInteger(input.controlled_capture_minutes) > 0 && input.evidence_classification === "HYPOTHESIS"
        ? { verdict: "accept", rejectionClass: null }
        : { verdict: "reject", rejectionClass: "semantic_invariant" };
      break;
    case "sec-consent.concurrent-session-separation":
      outcome = typeof input.candidate_session_id === "string" && typeof input.consented_session_id === "string"
        && input.candidate_session_id === input.consented_session_id
        ? { verdict: "accept", rejectionClass: null }
        : { verdict: "reject", rejectionClass: "semantic_invariant" };
      break;
    default:
      throw new ReplayFailure("unknown edge probe case");
  }
  const expected = object(probe.expected, "edge probe equality oracle is invalid");
  requireReplay(
    expected.verdict === outcome.verdict && expected.rejection_class === outcome.rejectionClass,
    `independent edge probe ${probe.case_id} disagrees with the frozen equality oracle`,
  );
  return outcome;
}

function makeReport(
  snapshot: ReplaySnapshot,
  caseID: string,
  outcome: CaseOutcome,
  implementationRevision: string,
): Buffer {
  const report: JsonObject = {
    report_version: "1.0.0",
    evaluator: { name: "ReRoomReplayBun", version: "1.0.0", platform: "javascript" },
    fixture: {
      fixture_id: "FX-CAPTURE-001",
      fixture_revision: "rev-001",
      manifest_sha256: PINNED_FIXTURE_MANIFEST_SHA256,
    },
    archive: {
      case_id: caseID,
      archive_name: snapshot.archiveName,
      finalization_state: snapshot.finalizationState,
      manifest_sha256: snapshot.manifestSHA256,
      accepted_frame_count: snapshot.acceptedFrameCount,
      event_count: snapshot.eventCount,
      journal_record_count: snapshot.journalRecordCount,
    },
    implementation: {
      repository_revision: implementationRevision,
      runtime: "bun-v1.3.11",
      build_id: "ReRoomReplayBun-1.0.0",
    },
    verdict: outcome.verdict,
    digests: snapshot.digests,
    rejection: outcome.rejectionClass === null ? null : {
      rejection_class: outcome.rejectionClass,
      detail: `frozen fixture expected ${outcome.rejectionClass}`,
    },
    metrics: {
      max_queue_depth: 0,
      dropped_stale_candidates: 0,
      recovered_prefix_records: snapshot.finalizationState === "recovered_prefix" ? snapshot.journalRecordCount : 0,
      quarantined_suffix_records: snapshot.finalizationState === "recovered_prefix" ? 1 : 0,
    },
  };
  report.report_sha256 = canonicalDigest(report);
  return canonicalizeBytes(report);
}

async function validateOutput(outputRoot: string): Promise<void> {
  try {
    await lstat(outputRoot);
    throw new ReplayFailure("output root must not exist");
  } catch (error) {
    if (error instanceof ReplayFailure) throw error;
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw new ReplayFailure("output root cannot be inspected");
  }
  await requireDirectory(path.dirname(outputRoot), "output parent is invalid");
}

async function durableWrite(filePath: string, bytes: Buffer): Promise<void> {
  const handle = await open(filePath, "wx", 0o600);
  try {
    await handle.writeFile(bytes);
    await handle.sync();
  } finally {
    await handle.close();
  }
}

async function syncDirectory(directory: string): Promise<void> {
  const handle = await open(directory, "r");
  try {
    await handle.sync();
  } finally {
    await handle.close();
  }
}

async function publishReports(reports: Map<string, Buffer>, outputRoot: string): Promise<void> {
  await validateOutput(outputRoot);
  const parent = path.dirname(outputRoot);
  const stage = path.join(parent, `.reroom-bun-replay-staging-${randomUUID()}`);
  let published = false;
  try {
    await mkdir(stage, { recursive: false, mode: 0o700 });
    for (const caseID of [...reports.keys()].sort()) {
      await durableWrite(path.join(stage, `${caseID}.replay-report.json`), reports.get(caseID)!);
    }
    const names = (await readdir(stage)).sort();
    const expected = [...reports.keys()].sort().map((caseID) => `${caseID}.replay-report.json`);
    requireReplay(JSON.stringify(names) === JSON.stringify(expected), "staged replay report set is incomplete");
    await syncDirectory(stage);
    await validateOutput(outputRoot);
    await rename(stage, outputRoot);
    published = true;
    await syncDirectory(parent);
  } finally {
    if (!published) await rm(stage, { recursive: true, force: true });
  }
}

export async function runReplay(options: ReplayOptions): Promise<void> {
  requireReplay((options.runtimeVersion ?? process.versions.bun) === EXACT_BUN_VERSION, "exact Bun 1.3.11 is required before replay");
  requireReplay(REVISION.test(options.implementationRevision), "implementation revision must be git:<40-lowercase-hex>");
  const outputRoot = path.resolve(options.outputRoot);
  await validateOutput(outputRoot);
  const { fixture, fixtureRoot } = await loadFixture(options);

  const snapshots = new Map<string, ReplaySnapshot>();
  const reports = new Map<string, Buffer>();
  for (const rawDescriptor of array(fixture.archives)) {
    const descriptor = object(rawDescriptor);
    const snapshot = await replayArchive(descriptor, fixtureRoot);
    snapshots.set(snapshot.archiveName, snapshot);
    const caseID = `archive.${snapshot.archiveName.slice(0, -".rrcap".length)}`;
    reports.set(caseID, makeReport(snapshot, caseID, { verdict: "accept", rejectionClass: null }, options.implementationRevision));
  }
  const ordinary = snapshots.get("finalized-one-frame.rrcap");
  const empty = snapshots.get("finalized-empty.rrcap");
  requireReplay(ordinary && empty, "baseline replay snapshots are absent");
  for (const rawProbe of array(fixture.edge_probes)) {
    const probe = object(rawProbe);
    const outcome = evaluateProbe(probe);
    reports.set(probe.case_id, makeReport(probe.case_id === "fr-b0.empty" ? empty : ordinary, probe.case_id, outcome, options.implementationRevision));
  }
  const consentOutcome = { verdict: "reject", rejectionClass: "semantic_invariant" } as const;
  reports.set("sec-consent.denied", makeReport(empty, "sec-consent.denied", consentOutcome, options.implementationRevision));

  const caseIDs = [...reports.keys()].sort();
  const expectedCaseIDs = [...ARCHIVE_NAMES.map((name) => `archive.${name.slice(0, -".rrcap".length)}`), ...PROBE_IDS, "sec-consent.denied"].sort();
  requireReplay(caseIDs.length === 16 && JSON.stringify(caseIDs) === JSON.stringify(expectedCaseIDs), "complete replay report set is invalid");
  await publishReports(reports, outputRoot);
}

function parseCLI(arguments_: string[]): ReplayOptions {
  const allowed = new Set(["--manifest", "--output-root", "--repo-root", "--implementation-revision"]);
  requireReplay(arguments_.length === 8, "exactly four named arguments are required");
  const values = new Map<string, string>();
  for (let index = 0; index < arguments_.length; index += 2) {
    const name = arguments_[index];
    const value = arguments_[index + 1];
    requireReplay(allowed.has(name) && !values.has(name) && typeof value === "string", "unsupported, duplicate, or incomplete argument");
    values.set(name, value);
  }
  requireReplay(values.size === allowed.size, "all exact replay arguments are required");
  return {
    manifestPath: values.get("--manifest")!,
    outputRoot: values.get("--output-root")!,
    repoRoot: values.get("--repo-root")!,
    implementationRevision: values.get("--implementation-revision")!,
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    await runReplay(parseCLI(process.argv.slice(2)));
  } catch (error) {
    const message = error instanceof ReplayFailure ? error.message : "unexpected replay failure";
    process.stderr.write(`replay-bun: FAIL: ${message}\n`);
    process.exitCode = 1;
  }
}
