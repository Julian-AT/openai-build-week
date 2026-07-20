export type JsonPrimitive = boolean | number | string | null;
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };
export type JsonObject = { [key: string]: JsonValue };

export type ReplayCapabilityState = "available" | "not_present" | "unavailable";

export interface ReplayCapability {
  id:
    | "verified_replay"
    | "timeline"
    | "frame_preview"
    | "scene"
    | "transactions"
    | "sparse_geometry"
    | "providers"
    | "sharing"
    | "typed_proposals"
    | "ordinary_video"
    | "live_phone";
  label: string;
  state: ReplayCapabilityState;
  detail: string;
}

export interface ReplayEventView {
  eventId: string;
  type: string;
  eventSequence: number;
  durableJournalSequence: number;
  monotonicTimestampNs: string;
  payloadSha256: string;
  recordSha256: string;
  payload: JsonObject;
}

export interface ReplayFrameView {
  frameId: string;
  captureSequence: number;
  sequence: number;
  durableJournalSequence: number;
  serverAcknowledged: boolean;
  monotonicTimestampNs: string;
  packetSha256: string;
  payloadSha256: string;
  worldFrameId: string;
  worldFrameVersion: number;
  submapId: string;
  tracking: JsonObject;
  quality: JsonObject;
  intrinsicsEncodedPixels: JsonObject;
  worldFromCamera: JsonObject;
  image: {
    codec: string;
    colorSpace: string;
    orientation: string;
    width: number;
    height: number;
    sha256: string;
  };
  preview: {
    mediaType: "image/png";
    dataUrl: string;
  };
}

export interface VerifiedReplayView {
  labels: {
    mode: "MODE B0 — RECORDED REPLAY";
    provider: "PROVIDER-INDEPENDENT";
    fixture: "LOCAL DEMO FIXTURE";
    gate: "GATE-008 PENDING";
  };
  verification: {
    verdict: "accept";
    reportVersion: string;
    reportSha256: string;
    fixtureId: string;
    fixtureRevision: string;
    fixtureManifestSha256: string;
    evaluator: JsonObject;
    implementation: JsonObject;
  };
  archive: {
    caseId: string;
    archiveName: string;
    formatVersion: string;
    captureKind: string;
    sessionId: string;
    finalizationState: string;
    manifestSha256: string;
    acceptedFrameCount: number;
    eventCount: number;
    journalRecordCount: number;
    lastDurableJournalSequence: number;
    captureSettings: JsonObject;
    coordinateConvention: JsonObject;
    source: JsonObject;
    orderingAuthority: string;
    replayInputDigest: string;
    providerLock: JsonValue[];
    digests: {
      eventProjectionSha256: string;
      frameProjectionSha256: string;
      journalTupleSha256: string;
      revisionTraceSha256: string;
    };
  };
  events: ReplayEventView[];
  frames: ReplayFrameView[];
  privacy: {
    captureConsentRecorded: boolean;
    containsRoomImagery: boolean;
    deletionState: string;
    retentionPolicy: string;
    shareAccessState: string;
    browserPersistence: "none";
  };
  content: {
    scene: "not_present";
    transactions: "not_present";
  };
  capabilities: ReplayCapability[];
}

export type GoldenReplayResult =
  | { status: "verified"; replay: VerifiedReplayView }
  | {
      status: "rejected";
      error: {
        code: "verification_failed";
        message: string;
      };
    };
