import type { CaptureRoom } from "./capture-upload.ts";

const ROOM_ID = /^room_[a-z0-9_]{3,120}$/u;
const CREDENTIAL_MINIMUM = 8;
const MAX_RESPONSE_BYTES = 64 * 1024;
const SESSION_LIFETIME_MS = 10 * 60 * 1_000;

type FetchImplementation = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export interface CaptureRoomBrokerOptions {
  readonly gatewayURL: string;
  readonly gatewayToken: string;
  readonly sessionID?: string;
  readonly nowMilliseconds?: () => number;
  readonly fetch?: FetchImplementation;
}

export async function createCaptureRoom(options: CaptureRoomBrokerOptions): Promise<CaptureRoom> {
  const gatewayURL = parseGatewayURL(options.gatewayURL);
  if (
    options.gatewayToken.length < CREDENTIAL_MINIMUM ||
    options.gatewayToken.trim() !== options.gatewayToken
  ) {
    throw new Error("missing_gateway_token");
  }
  const nowMilliseconds = options.nowMilliseconds ?? Date.now;
  const expiresAtMilliseconds = nowMilliseconds() + SESSION_LIFETIME_MS;
  const sessionID =
    options.sessionID ?? `room_web_${crypto.randomUUID().replaceAll("-", "").slice(0, 20)}`;
  if (!ROOM_ID.test(sessionID)) throw new Error("invalid_capture_session_id");
  const response = await (options.fetch ?? globalThis.fetch)(new URL("/v1/sessions", gatewayURL), {
    method: "POST",
    headers: {
      Authorization: `Bearer ${options.gatewayToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      session_id: sessionID,
      expires_at_ms: expiresAtMilliseconds,
      allowed_paths: ["events"],
    }),
  });
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.byteLength > MAX_RESPONSE_BYTES || !response.ok)
    throw new Error("capture_gateway_failure");
  const parsed = parseResponse(bytes);
  if (
    parsed.session_id !== sessionID ||
    typeof parsed.credential !== "string" ||
    parsed.credential.length < CREDENTIAL_MINIMUM ||
    typeof parsed.expires_at_ms !== "number" ||
    !Number.isSafeInteger(parsed.expires_at_ms)
  ) {
    throw new Error("invalid_capture_session");
  }
  return {
    gatewayURL: gatewayURL.toString().replace(/\/$/u, ""),
    sessionID: parsed.session_id,
    credential: parsed.credential,
    expiresAtMilliseconds: parsed.expires_at_ms,
  };
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
  ) {
    throw new Error("invalid_capture_gateway");
  }
  return url;
}

function parseResponse(bytes: Uint8Array): {
  session_id: unknown;
  credential: unknown;
  expires_at_ms: unknown;
} {
  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)) as unknown;
  } catch {
    throw new Error("invalid_capture_session");
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed))
    throw new Error("invalid_capture_session");
  const value = parsed as Record<string, unknown>;
  if (
    Object.keys(value).some((key) => !["session_id", "credential", "expires_at_ms"].includes(key))
  )
    throw new Error("invalid_capture_session");
  return {
    session_id: value.session_id,
    credential: value.credential,
    expires_at_ms: value.expires_at_ms,
  };
}
