import { createCaptureRoom } from "../../../lib/capture-session-broker.ts";

const MAX_REQUEST_BYTES = 8_192;

export async function POST(request: Request): Promise<Response> {
  const gatewayURL = process.env.REFRAME_GATEWAY_URL?.trim();
  const gatewayToken = process.env.REFRAME_GATEWAY_TOKEN?.trim();
  if (
    gatewayURL === undefined ||
    gatewayURL.length === 0 ||
    gatewayToken === undefined ||
    gatewayToken.length === 0
  ) {
    return Response.json({ error: "capture_service_unavailable" }, { status: 503 });
  }
  const contentLength = request.headers.get("content-length");
  if (
    contentLength !== null &&
    (!/^\d+$/u.test(contentLength) || Number(contentLength) > MAX_REQUEST_BYTES)
  ) {
    return Response.json({ error: "capture_request_too_large" }, { status: 413 });
  }
  try {
    const raw = await request.text();
    if (new TextEncoder().encode(raw).byteLength > MAX_REQUEST_BYTES) {
      return Response.json({ error: "capture_request_too_large" }, { status: 413 });
    }
    const input = raw.trim().length === 0 ? {} : (JSON.parse(raw) as unknown);
    if (!isRecord(input) || Object.keys(input).some((key) => key !== "session_id")) {
      return Response.json({ error: "invalid_capture_request" }, { status: 400 });
    }
    const requestedSessionID = input.session_id;
    if (requestedSessionID !== undefined && typeof requestedSessionID !== "string") {
      return Response.json({ error: "invalid_capture_request" }, { status: 400 });
    }
    const room = await createCaptureRoom({
      gatewayURL,
      gatewayToken,
      ...(requestedSessionID === undefined ? {} : { sessionID: requestedSessionID }),
    });
    return Response.json(
      {
        gateway_url: room.gatewayURL,
        session_id: room.sessionID,
        credential: room.credential,
        expires_at_ms: room.expiresAtMilliseconds,
      },
      { status: 201, headers: { "cache-control": "no-store" } },
    );
  } catch (error) {
    if (error instanceof SyntaxError || error instanceof TypeError) {
      return Response.json({ error: "invalid_capture_request" }, { status: 400 });
    }
    return Response.json({ error: "capture_service_unavailable" }, { status: 503 });
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
