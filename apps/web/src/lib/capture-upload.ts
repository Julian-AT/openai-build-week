const ROOM_ID = /^room_[a-z0-9_]{3,120}$/u;
const CREDENTIAL_MINIMUM = 8;
const MAX_FRAME_BYTES = 2_300_000;
const MAX_RESPONSE_BYTES = 256 * 1024;
const SESSION_LIFETIME_MS = 10 * 60 * 1_000;

// Browser capture is ordinary RGB video: no ARKit pose or intrinsics, routed to
// the video-mapping boundary that owns trajectory and geometry.
const MAPPING_PROVIDER = "lingbot_map";

type FetchImplementation = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export interface CaptureSessionOptions {
  readonly gatewayURL?: string;
  readonly gatewayToken?: string;
  readonly room?: CaptureRoom;
  readonly sessionID?: string;
  readonly expiresAtMilliseconds?: number;
  readonly fetch?: FetchImplementation;
  readonly nowMilliseconds?: () => number;
}

export interface CaptureRoom {
  readonly gatewayURL: string;
  readonly sessionID: string;
  readonly credential: string;
  readonly expiresAtMilliseconds: number;
}

export interface CaptureSession {
  readonly sessionID: string;
  readonly credential: string;
  readonly expiresAtMilliseconds: number;
  uploadOrdinaryVideoFrame(input: OrdinaryVideoFrameInput): Promise<OrdinaryVideoFrameReceipt>;
  appendEvent(input: CaptureEventInput): Promise<EventReceipt>;
}

export interface OrdinaryVideoFrameInput {
  readonly bytes: Uint8Array;
  readonly width: number;
  readonly height: number;
  readonly frameIndex?: number;
  readonly timestampNanoseconds?: number;
}

export interface CaptureEventInput {
  readonly type:
    | "session_started"
    | "ordinary_video_imported"
    | "world_frame_changed"
    | "frame_selected"
    | "frame_image_and_metadata_durable"
    | "frame_journaled"
    | "frame_network_eligible"
    | "frame_server_acknowledged"
    | "tracking_changed"
    | "transaction"
    | "session_finalized";
  readonly payload: unknown;
  readonly eventID?: string;
  readonly eventSequence?: number;
  readonly monotonicTimestampNanoseconds?: string;
}

export interface OrdinaryVideoFrameReceipt {
  readonly session_id: string;
  readonly frame_index: number;
  readonly sha256: string;
  readonly byte_length: number;
  readonly accepted_at_ms: number;
  readonly mapping_provider: string;
}

export interface EventReceipt {
  readonly session_id: string;
  readonly event_id: string;
  readonly event_sequence: number;
  readonly monotonic_timestamp_ns: string;
  readonly type: CaptureEventInput["type"];
  readonly payload: unknown;
  readonly payload_sha256: string;
  readonly accepted_at_ms: number;
  readonly replayed: boolean;
}

export async function createCaptureSession(
  options: CaptureSessionOptions,
): Promise<CaptureSession> {
  const nowMilliseconds = options.nowMilliseconds ?? Date.now;
  const created =
    options.room === undefined
      ? await createRoomFromGateway(options, nowMilliseconds)
      : parseCaptureRoom(options.room);
  const gatewayURL = parseGatewayURL(created.gateway_url);
  let nextFrameIndex = 0;
  let nextEventSequence = 0;
  return {
    sessionID: created.session_id,
    credential: created.credential,
    expiresAtMilliseconds: created.expires_at_ms,
    async uploadOrdinaryVideoFrame(input) {
      const frameIndex = input.frameIndex ?? nextFrameIndex;
      if (!Number.isSafeInteger(frameIndex) || frameIndex < 0 || frameIndex < nextFrameIndex) {
        throw new Error("invalid_capture_frame_index");
      }
      nextFrameIndex = frameIndex + 1;
      const envelope = encodeOrdinaryVideoFrame({
        ...input,
        sessionID: created.session_id,
        frameIndex,
        timestampNanoseconds: input.timestampNanoseconds ?? timestampNanoseconds(),
      });
      const response = await requestBinary(
        options.fetch ?? globalThis.fetch,
        new URL(`/v1/sessions/${created.session_id}/video-frames`, gatewayURL),
        created.credential,
        new TextEncoder().encode(JSON.stringify(envelope)),
        "application/json",
      );
      return parseOrdinaryVideoFrameReceipt(response);
    },
    async appendEvent(input) {
      const eventSequence = input.eventSequence ?? nextEventSequence;
      if (!Number.isSafeInteger(eventSequence) || eventSequence < nextEventSequence) {
        throw new Error("invalid_capture_event_sequence");
      }
      nextEventSequence = eventSequence + 1;
      const eventID = input.eventID ?? `event_${crypto.randomUUID()}`;
      const event = {
        event_id: eventID,
        event_sequence: eventSequence,
        monotonic_timestamp_ns:
          input.monotonicTimestampNanoseconds ?? timestampNanoseconds().toString(),
        type: input.type,
        payload: input.payload,
      } satisfies Record<string, unknown>;
      const response = await requestBinary(
        options.fetch ?? globalThis.fetch,
        new URL(`/v1/sessions/${created.session_id}/events`, gatewayURL),
        created.credential,
        new TextEncoder().encode(JSON.stringify(event)),
        "application/json",
      );
      return parseEventReceipt(response);
    },
  };
}

async function createRoomFromGateway(
  options: CaptureSessionOptions,
  nowMilliseconds: () => number,
): Promise<{ gateway_url: string; session_id: string; credential: string; expires_at_ms: number }> {
  if (options.gatewayURL === undefined) throw new Error("missing_capture_gateway");
  const gatewayURL = parseGatewayURL(options.gatewayURL);
  const gatewayToken = requireCredential(options.gatewayToken, "missing_gateway_token");
  const expiresAtMilliseconds =
    options.expiresAtMilliseconds ?? nowMilliseconds() + SESSION_LIFETIME_MS;
  if (
    !Number.isSafeInteger(expiresAtMilliseconds) ||
    expiresAtMilliseconds <= nowMilliseconds() ||
    expiresAtMilliseconds > nowMilliseconds() + 15 * 60 * 1_000
  ) {
    throw new Error("invalid_capture_expiry");
  }
  const sessionID = options.sessionID ?? generatedSessionID();
  assertSessionID(sessionID);
  const response = await requestJSON(
    options.fetch ?? globalThis.fetch,
    new URL("/v1/sessions", gatewayURL),
    gatewayToken,
    { session_id: sessionID, expires_at_ms: expiresAtMilliseconds, allowed_paths: ["events"] },
  );
  const created = parseCreatedSession(response);
  return { gateway_url: gatewayURL.toString().replace(/\/$/u, ""), ...created };
}

function parseCaptureRoom(room: CaptureRoom): {
  gateway_url: string;
  session_id: string;
  credential: string;
  expires_at_ms: number;
} {
  const gatewayURL = parseGatewayURL(room.gatewayURL);
  if (
    !isValidSessionID(room.sessionID) ||
    room.credential.length < CREDENTIAL_MINIMUM ||
    room.credential.trim() !== room.credential ||
    !Number.isSafeInteger(room.expiresAtMilliseconds) ||
    room.expiresAtMilliseconds <= 0
  ) {
    throw new Error("invalid_capture_room");
  }
  return {
    gateway_url: gatewayURL.toString().replace(/\/$/u, ""),
    session_id: room.sessionID,
    credential: room.credential,
    expires_at_ms: room.expiresAtMilliseconds,
  };
}

interface OrdinaryVideoFrameEnvelope {
  readonly session_id: string;
  readonly frame_index: number;
  readonly timestamp_ns: number;
  readonly clock_domain: "browser_monotonic_performance";
  readonly mapping_provider: typeof MAPPING_PROVIDER;
  readonly pose_source: "none";
  readonly image: {
    readonly codec: "jpeg";
    readonly width: number;
    readonly height: number;
    readonly orientation: "up";
    readonly color_space: "sRGB";
    readonly payload_bytes: number;
    readonly data_base64: string;
  };
}

function encodeOrdinaryVideoFrame(
  input: OrdinaryVideoFrameInput & {
    readonly sessionID: string;
    readonly frameIndex: number;
    readonly timestampNanoseconds: number;
  },
): OrdinaryVideoFrameEnvelope {
  assertJPEGFrame(input);
  return {
    session_id: input.sessionID,
    frame_index: input.frameIndex,
    timestamp_ns: input.timestampNanoseconds,
    clock_domain: "browser_monotonic_performance",
    mapping_provider: MAPPING_PROVIDER,
    pose_source: "none",
    image: {
      codec: "jpeg",
      width: input.width,
      height: input.height,
      orientation: "up",
      color_space: "sRGB",
      payload_bytes: input.bytes.byteLength,
      data_base64: base64FromBytes(input.bytes),
    },
  };
}

function assertJPEGFrame(input: OrdinaryVideoFrameInput): void {
  if (
    input.bytes.byteLength < 4 ||
    input.bytes.byteLength > MAX_FRAME_BYTES ||
    input.bytes[0] !== 0xff ||
    input.bytes[1] !== 0xd8 ||
    input.bytes.at(-2) !== 0xff ||
    input.bytes.at(-1) !== 0xd9 ||
    !Number.isSafeInteger(input.width) ||
    !Number.isSafeInteger(input.height) ||
    input.width < 1 ||
    input.width > 4_096 ||
    input.height < 1 ||
    input.height > 4_096
  ) {
    throw new Error("invalid_capture_jpeg");
  }
}

function base64FromBytes(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let index = 0; index < bytes.byteLength; index += chunk) {
    binary += String.fromCharCode(...bytes.subarray(index, index + chunk));
  }
  return btoa(binary);
}

async function requestJSON(
  fetchImplementation: FetchImplementation,
  url: URL,
  token: string,
  body: unknown,
): Promise<Uint8Array> {
  const bytes = new TextEncoder().encode(JSON.stringify(body));
  return await requestBinary(fetchImplementation, url, token, bytes, "application/json");
}

async function requestBinary(
  fetchImplementation: FetchImplementation,
  url: URL,
  token: string,
  body: Uint8Array,
  contentType: string,
): Promise<Uint8Array> {
  if (body.byteLength > MAX_RESPONSE_BYTES * 20) throw new Error("capture_payload_too_large");
  const response = await fetchImplementation(url, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": contentType },
    body: body as BodyInit,
  });
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.byteLength > MAX_RESPONSE_BYTES) throw new Error("capture_response_too_large");
  if (!response.ok) throw new Error(`capture_gateway_${response.status}`);
  return bytes;
}

function parseCreatedSession(value: Uint8Array): {
  session_id: string;
  credential: string;
  expires_at_ms: number;
} {
  const parsed = parseJSON(value, "invalid_capture_session");
  if (
    !isRecord(parsed) ||
    Object.keys(parsed).some(
      (key) => !["session_id", "credential", "expires_at_ms"].includes(key),
    ) ||
    !isValidSessionID(parsed.session_id) ||
    typeof parsed.credential !== "string" ||
    parsed.credential.length < CREDENTIAL_MINIMUM ||
    typeof parsed.expires_at_ms !== "number" ||
    !Number.isSafeInteger(parsed.expires_at_ms)
  )
    throw new Error("invalid_capture_session");
  return {
    session_id: parsed.session_id,
    credential: parsed.credential,
    expires_at_ms: parsed.expires_at_ms,
  };
}

function parseOrdinaryVideoFrameReceipt(value: Uint8Array): OrdinaryVideoFrameReceipt {
  const parsed = parseJSON(value, "invalid_capture_frame_receipt");
  if (
    !isRecord(parsed) ||
    typeof parsed.session_id !== "string" ||
    typeof parsed.frame_index !== "number" ||
    typeof parsed.sha256 !== "string" ||
    typeof parsed.byte_length !== "number" ||
    typeof parsed.accepted_at_ms !== "number" ||
    typeof parsed.mapping_provider !== "string"
  )
    throw new Error("invalid_capture_frame_receipt");
  return parsed as unknown as OrdinaryVideoFrameReceipt;
}

function parseEventReceipt(value: Uint8Array): EventReceipt {
  const parsed = parseJSON(value, "invalid_capture_event_receipt");
  if (
    !isRecord(parsed) ||
    typeof parsed.session_id !== "string" ||
    typeof parsed.event_id !== "string" ||
    typeof parsed.event_sequence !== "number" ||
    typeof parsed.monotonic_timestamp_ns !== "string" ||
    typeof parsed.type !== "string" ||
    typeof parsed.payload_sha256 !== "string" ||
    typeof parsed.accepted_at_ms !== "number" ||
    typeof parsed.replayed !== "boolean"
  )
    throw new Error("invalid_capture_event_receipt");
  return parsed as unknown as EventReceipt;
}

function parseJSON(bytes: Uint8Array, error: string): unknown {
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)) as unknown;
  } catch {
    throw new Error(error);
  }
}

function parseGatewayURL(value: string): URL {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Error("invalid_capture_gateway");
  }
  if (
    (url.protocol !== "http:" && url.protocol !== "https:") ||
    url.username ||
    url.password ||
    url.search ||
    url.hash
  )
    throw new Error("invalid_capture_gateway");
  return url;
}

function requireCredential(value: string | undefined, error: string): string {
  if (
    typeof value !== "string" ||
    value.length < CREDENTIAL_MINIMUM ||
    value.trim() !== value ||
    value.length > 512
  )
    throw new Error(error);
  return value;
}

function assertSessionID(value: string): void {
  if (!isValidSessionID(value)) throw new Error("invalid_capture_session_id");
}
function isValidSessionID(value: unknown): value is string {
  return typeof value === "string" && ROOM_ID.test(value);
}
function generatedSessionID(): string {
  return `room_browser_${crypto.randomUUID().replaceAll("-", "").slice(0, 20)}`;
}
function timestampNanoseconds(): number {
  const value = Math.floor(
    (typeof performance === "undefined" ? Date.now() : performance.now()) * 1_000_000,
  );
  if (!Number.isSafeInteger(value) || value < 0) throw new Error("invalid_capture_timestamp");
  return value;
}
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
