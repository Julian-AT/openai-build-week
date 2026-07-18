import type {
  JsonObject,
  JsonValue,
  ReplayCapability,
  ReplayEventView,
  ReplayFrameView,
  VerifiedReplayView,
} from "./types.ts";

const IMPLEMENTATION_REVISION = "git:0d371bc1de9a057cbf61b70142729f6cbe620eec";
const FIXTURE_MANIFEST_SHA256 = "3b4519d2730e158df73e938f7b841664c6ce5f7d65ed2650c90ca8e89c7a7610";
const ARCHIVE_MANIFEST_SHA256 = "2a6454e6014eb294bee94be36569ce94c6a49adaa3c77e064a2b03756df99c09";
const REPORT_SHA256 = "5a15914545789d20e0255b8ab2bbff55cbd1d9374b54816638ed0d64400acb2b";
const IMAGE_SHA256 = "431ced6916a2a21a156e38701afe55bbd7f88969fbbfc56d7fe099d47f265460";
const PACKET_SHA256 = "cc387742b8b7bc99fbcc9b4e0171ab35626af3e349a71806a57ba9c00f5f7d7f";
const IMAGE_BASE64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
const DIGESTS = {
  event_projection_sha256: "869db922b2e28b7534be6d1ee99dd9202d82eee60f8f3251f66b575f80b8b14b",
  frame_projection_sha256: "0f710fc1527b278bd3b3c8f137487b5690de5ab2e14049a8f37ccee26ddc0466",
  journal_tuple_sha256: "236daa228c1d5ebe91e5e332263ed3a9168a5cfd6d991b29bab0ddc395ed69eb",
  revision_trace_sha256: "ccd7b8ea7bf8c707a87d81f220cf08307e0888b7b35e535095b493daf5da282f",
} as const;

type PathValue = { relativePath: string; value: unknown };
type PathBytes = { relativePath: string; bytes: Uint8Array };

export interface VerifiedProjectionInput {
  report: unknown;
  manifest: unknown;
  eventPayloads: readonly PathValue[];
  framePackets: readonly PathValue[];
  imagePayloads: readonly PathBytes[];
}

function reject(): never {
  throw new Error("verified replay projection mismatch");
}

function record(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) reject();
  return value as Record<string, unknown>;
}

function list(value: unknown): unknown[] {
  if (!Array.isArray(value)) reject();
  return value;
}

function text(value: unknown): string {
  if (typeof value !== "string") reject();
  return value;
}

function integer(value: unknown): number {
  if (!Number.isSafeInteger(value) || Number(value) < 0) reject();
  return Number(value);
}

function flag(value: unknown): boolean {
  if (typeof value !== "boolean") reject();
  return value;
}

function exact(actual: unknown, expected: unknown): void {
  if (actual !== expected) reject();
}

function jsonValue(value: unknown): JsonValue {
  if (value === null || typeof value === "string" || typeof value === "boolean") return value;
  if (typeof value === "number") {
    if (!Number.isFinite(value)) reject();
    return value;
  }
  if (Array.isArray(value)) return value.map(jsonValue);
  const source = record(value);
  const output: JsonObject = {};
  for (const [key, member] of Object.entries(source)) output[key] = jsonValue(member);
  return output;
}

function jsonObject(value: unknown): JsonObject {
  const converted = jsonValue(value);
  if (converted === null || typeof converted !== "object" || Array.isArray(converted)) reject();
  return converted;
}

function mapPaths<T extends PathValue | PathBytes>(values: readonly T[]): Map<string, T> {
  const mapped = new Map<string, T>();
  for (const value of values) {
    if (typeof value.relativePath !== "string" || mapped.has(value.relativePath)) reject();
    mapped.set(value.relativePath, value);
  }
  return mapped;
}

export function assertAcceptedGoldenReport(value: unknown): asserts value is Record<string, unknown> {
  const report = record(value);
  exact(report.report_version, "1.0.0");
  exact(report.verdict, "accept");
  exact(report.rejection, null);
  exact(report.report_sha256, REPORT_SHA256);

  const evaluator = record(report.evaluator);
  exact(evaluator.name, "ReRoomReplayNode");
  exact(evaluator.platform, "javascript");
  exact(evaluator.version, "1.0.0");

  const fixture = record(report.fixture);
  exact(fixture.fixture_id, "FX-CAPTURE-001");
  exact(fixture.fixture_revision, "rev-001");
  exact(fixture.manifest_sha256, FIXTURE_MANIFEST_SHA256);

  const archive = record(report.archive);
  exact(archive.case_id, "archive.finalized-one-frame");
  exact(archive.archive_name, "finalized-one-frame.rrcap");
  exact(archive.finalization_state, "finalized");
  exact(archive.manifest_sha256, ARCHIVE_MANIFEST_SHA256);
  exact(archive.accepted_frame_count, 1);
  exact(archive.event_count, 7);
  exact(archive.journal_record_count, 8);

  const implementation = record(report.implementation);
  exact(implementation.repository_revision, IMPLEMENTATION_REVISION);
  exact(implementation.runtime, "node-v22.22.3");
  exact(implementation.build_id, "ReRoomReplayNode-1.0.0");

  const digests = record(report.digests);
  for (const [name, digest] of Object.entries(DIGESTS)) exact(digests[name], digest);
}

function projectEvents(manifest: Record<string, unknown>, payloadInputs: readonly PathValue[]): ReplayEventView[] {
  const payloads = mapPaths(payloadInputs);
  const events = list(manifest.events);
  exact(events.length, 7);
  exact(payloads.size, events.length);
  return events.map((rawEvent, expectedSequence) => {
    const event = record(rawEvent);
    exact(event.event_sequence, expectedSequence);
    const relativePath = text(event.payload_path);
    const payloadInput = payloads.get(relativePath);
    if (!payloadInput) reject();
    const payload = jsonObject(payloadInput.value);
    exact(payload.type, event.type);
    exact(payload.session_id, manifest.session_id);
    exact(payload.event_version, "1.0.0");
    return {
      eventId: text(event.event_id),
      type: text(event.type),
      eventSequence: integer(event.event_sequence),
      durableJournalSequence: integer(event.durable_journal_sequence),
      monotonicTimestampNs: text(event.monotonic_timestamp_ns),
      payloadSha256: text(event.payload_sha256),
      recordSha256: text(event.record_sha256),
      payload,
    };
  });
}

function projectFrames(
  manifest: Record<string, unknown>,
  packetInputs: readonly PathValue[],
  imageInputs: readonly PathBytes[],
): ReplayFrameView[] {
  const packets = mapPaths(packetInputs);
  const images = mapPaths(imageInputs);
  const acceptedFrames = list(manifest.accepted_frame_order);
  exact(acceptedFrames.length, 1);
  exact(packets.size, acceptedFrames.length);
  exact(images.size, acceptedFrames.length);

  return acceptedFrames.map((rawAccepted, expectedSequence) => {
    const accepted = record(rawAccepted);
    exact(accepted.sequence, expectedSequence);
    exact(accepted.packet_sha256, PACKET_SHA256);
    const packetInput = packets.get(text(accepted.packet_path));
    if (!packetInput) reject();
    const packet = record(packetInput.value);
    exact(packet.frame_id, accepted.frame_id);
    exact(packet.capture_sequence, accepted.sequence);
    exact(record(packet.durability).journal_sequence, accepted.durable_journal_sequence);
    const image = record(packet.image);
    const payload = record(image.payload);
    exact(payload.kind, "rrcap_file");
    exact(payload.relative_path, "image/frame_0001.png");
    exact(payload.sha256, IMAGE_SHA256);
    exact(packet.payload_sha256, IMAGE_SHA256);
    const imageInput = images.get(text(payload.relative_path));
    if (!imageInput) reject();
    const bytes = Buffer.from(imageInput.bytes);
    exact(bytes.length, 68);
    exact(bytes.toString("base64"), IMAGE_BASE64);

    return {
      frameId: text(packet.frame_id),
      captureSequence: integer(packet.capture_sequence),
      sequence: integer(accepted.sequence),
      durableJournalSequence: integer(accepted.durable_journal_sequence),
      serverAcknowledged: flag(accepted.server_acknowledged),
      monotonicTimestampNs: text(packet.monotonic_timestamp_ns),
      packetSha256: text(accepted.packet_sha256),
      payloadSha256: text(packet.payload_sha256),
      worldFrameId: text(packet.world_frame_id),
      worldFrameVersion: integer(packet.world_frame_version),
      submapId: text(packet.submap_id),
      tracking: jsonObject(packet.tracking),
      quality: jsonObject(packet.quality),
      intrinsicsEncodedPixels: jsonObject(packet.intrinsics_encoded_pixels),
      worldFromCamera: jsonObject(packet.world_from_camera),
      image: {
        codec: text(image.codec),
        colorSpace: text(image.color_space),
        orientation: text(image.orientation),
        width: integer(image.width),
        height: integer(image.height),
        sha256: text(payload.sha256),
      },
      preview: {
        mediaType: "image/png",
        dataUrl: `data:image/png;base64,${bytes.toString("base64")}`,
      },
    };
  });
}

function capabilityRows(): ReplayCapability[] {
  return [
    { id: "verified_replay", label: "Verified replay", state: "available", detail: "Accepted by the exact Phase 2 runner." },
    { id: "timeline", label: "Authoritative timeline", state: "available", detail: "Ordered by the verified event and journal sequences." },
    { id: "frame_preview", label: "Accepted frame preview", state: "available", detail: "One synthetic manifest-bound PNG." },
    { id: "scene", label: "Scene", state: "not_present", detail: "Not present in this capture." },
    { id: "transactions", label: "Transactions", state: "not_present", detail: "Not present in this capture." },
    { id: "sparse_geometry", label: "Sparse geometry", state: "not_present", detail: "Not present in this capture." },
    { id: "providers", label: "Learned providers", state: "unavailable", detail: "Disabled for the provider-independent sprint slice." },
    { id: "sharing", label: "Sharing", state: "unavailable", detail: "Deferred; the fixture remains local only." },
    { id: "typed_proposals", label: "Typed proposals", state: "unavailable", detail: "Deferred; this replay is inspection-only." },
    { id: "ordinary_video", label: "Ordinary video", state: "unavailable", detail: "Deferred; only the fixed capture is supported." },
    { id: "live_phone", label: "Live phone", state: "unavailable", detail: "No live device connection is used." },
  ];
}

export function projectVerifiedReplay(input: VerifiedProjectionInput): VerifiedReplayView {
  assertAcceptedGoldenReport(input.report);
  const report = record(input.report);
  const reportFixture = record(report.fixture);
  const reportArchive = record(report.archive);
  const reportDigests = record(report.digests);
  const manifest = record(input.manifest);
  exact(manifest.format_version, "1.0.0");
  exact(manifest.capture_kind, "native_arkit");
  exact(manifest.session_id, "session_00000002-0000-4000-8000-000000000001");
  const finalization = record(manifest.finalization);
  exact(finalization.state, "finalized");
  exact(finalization.manifest_sha256, ARCHIVE_MANIFEST_SHA256);
  const privacy = record(manifest.privacy);
  const replay = record(manifest.replay);
  exact(replay.ordering_authority, "global_journal_sequence");
  exact(replay.input_digest, DIGESTS.journal_tuple_sha256);
  const providerLock = list(replay.provider_lock).map(jsonValue);
  exact(providerLock.length, 0);
  const journal = list(manifest.journal);
  exact(journal.length, 8);

  const events = projectEvents(manifest, input.eventPayloads);
  const frames = projectFrames(manifest, input.framePackets, input.imagePayloads);
  exact(events.length, reportArchive.event_count);
  exact(frames.length, reportArchive.accepted_frame_count);

  return {
    labels: {
      mode: "MODE B0 — RECORDED REPLAY",
      provider: "PROVIDER-INDEPENDENT",
      fixture: "LOCAL DEMO FIXTURE",
      gate: "GATE-008 PENDING",
    },
    verification: {
      verdict: "accept",
      reportVersion: text(report.report_version),
      reportSha256: text(report.report_sha256),
      fixtureId: text(reportFixture.fixture_id),
      fixtureRevision: text(reportFixture.fixture_revision),
      fixtureManifestSha256: text(reportFixture.manifest_sha256),
      evaluator: jsonObject(report.evaluator),
      implementation: jsonObject(report.implementation),
    },
    archive: {
      caseId: text(reportArchive.case_id),
      archiveName: text(reportArchive.archive_name),
      formatVersion: text(manifest.format_version),
      captureKind: text(manifest.capture_kind),
      sessionId: text(manifest.session_id),
      finalizationState: text(reportArchive.finalization_state),
      manifestSha256: text(reportArchive.manifest_sha256),
      acceptedFrameCount: integer(reportArchive.accepted_frame_count),
      eventCount: integer(reportArchive.event_count),
      journalRecordCount: integer(reportArchive.journal_record_count),
      lastDurableJournalSequence: integer(finalization.last_durable_journal_sequence),
      captureSettings: jsonObject(manifest.capture_settings),
      coordinateConvention: jsonObject(manifest.coordinate_convention),
      source: jsonObject(manifest.source),
      orderingAuthority: text(replay.ordering_authority),
      replayInputDigest: text(replay.input_digest),
      providerLock,
      digests: {
        eventProjectionSha256: text(reportDigests.event_projection_sha256),
        frameProjectionSha256: text(reportDigests.frame_projection_sha256),
        journalTupleSha256: text(reportDigests.journal_tuple_sha256),
        revisionTraceSha256: text(reportDigests.revision_trace_sha256),
      },
    },
    events,
    frames,
    privacy: {
      captureConsentRecorded: flag(privacy.capture_consent_recorded),
      containsRoomImagery: flag(privacy.contains_room_imagery),
      deletionState: text(privacy.deletion_state),
      retentionPolicy: text(privacy.retention_policy),
      shareAccessState: text(privacy.share_access_state),
      browserPersistence: "none",
    },
    content: { scene: "not_present", transactions: "not_present" },
    capabilities: capabilityRows(),
  };
}
