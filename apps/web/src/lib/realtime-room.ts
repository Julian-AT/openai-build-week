"use client";

import {
  connectRealtimeWebRTC,
  parseRealtimeSubmitUserTurn,
  type RealtimePeerConnection,
  type RealtimeWebRTCConnection,
} from "@reframe/agent";

const MAX_EVENT_BYTES = 64_000;
const MAX_CALL_ID_LENGTH = 128;
type FetchImplementation = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

export interface RealtimeVoiceOptions {
  readonly gatewayURL: string;
  readonly roomCredential: string;
  readonly audioElement: HTMLAudioElement;
  readonly fetch?: FetchImplementation;
  readonly onStatus?: (status: string) => void;
}

export interface RealtimeVoiceConnection {
  readonly close: () => void;
}

interface RealtimeEventConnection {
  sendEvent(event: unknown): void;
}

/**
 * Connects browser microphone/audio to the gateway. Realtime function calls
 * are forwarded only to the non-mutating /v1/turns route; this client never
 * calls preview, confirmation, restore, or scene mutation endpoints.
 */
export async function connectRealtimeVoice(
  options: RealtimeVoiceOptions,
): Promise<RealtimeVoiceConnection> {
  const gatewayURL = parseGatewayURL(options.gatewayURL);
  if (options.roomCredential.length === 0) throw new Error("missing_room_credential");
  const handledCallIDs = new Set<string>();
  let transport: RealtimeWebRTCConnection | undefined;
  let closed = false;

  options.onStatus?.("Requesting microphone…");
  transport = await connectRealtimeWebRTC({
    gatewayURL: new URL("/v1/realtime/calls", gatewayURL).toString(),
    roomCredential: options.roomCredential,
    fetch: options.fetch,
    createPeerConnection: () => new RTCPeerConnection() as unknown as RealtimePeerConnection,
    mediaDevices: {
      getUserMedia: (constraints) => navigator.mediaDevices.getUserMedia(constraints),
    },
    onRemoteStream: (stream) => {
      options.audioElement.srcObject = stream as MediaStream;
      void options.audioElement.play().catch(() => undefined);
    },
    onEvent: (event) => {
      const call = parseSubmitUserTurnCall(event);
      if (call === null || handledCallIDs.has(call.callID) || closed) return;
      handledCallIDs.add(call.callID);
      void forwardRealtimeTurn({
        gatewayURL,
        roomCredential: options.roomCredential,
        connection: transport as RealtimeWebRTCConnection,
        callID: call.callID,
        argumentsJSON: call.argumentsJSON,
        fetch: options.fetch,
      })
        .then(() => options.onStatus?.("Listening for the next request"))
        .catch(() => options.onStatus?.("Voice request rejected safely"));
    },
  });
  options.onStatus?.("Realtime voice connected");

  return {
    close() {
      if (closed) return;
      closed = true;
      transport?.close();
      options.audioElement.pause();
      options.audioElement.srcObject = null;
      options.onStatus?.("Voice disconnected");
    },
  };
}

export async function forwardRealtimeTurn(options: {
  readonly gatewayURL: URL;
  readonly roomCredential: string;
  readonly connection: RealtimeEventConnection;
  readonly callID: string;
  readonly argumentsJSON: string;
  readonly fetch?: FetchImplementation;
}): Promise<void> {
  const safeCallID = parseCallID(options.callID);
  const output = await submitTurn(options);
  options.connection.sendEvent({
    type: "conversation.item.create",
    item: {
      type: "function_call_output",
      call_id: safeCallID,
      output: JSON.stringify(output),
    },
  });
  options.connection.sendEvent({ type: "response.create" });
}

async function submitTurn(options: {
  readonly gatewayURL: URL;
  readonly roomCredential: string;
  readonly argumentsJSON: string;
  readonly fetch?: FetchImplementation;
}): Promise<unknown> {
  if (new TextEncoder().encode(options.argumentsJSON).byteLength > MAX_EVENT_BYTES) {
    return { status: "error", code: "invalid_turn" };
  }
  let value: unknown;
  try {
    value = JSON.parse(options.argumentsJSON) as unknown;
    parseRealtimeSubmitUserTurn(value);
  } catch {
    return { status: "error", code: "invalid_turn" };
  }

  let response: Response;
  try {
    response = await (options.fetch ?? globalThis.fetch)(new URL("/v1/turns", options.gatewayURL), {
      method: "POST",
      headers: {
        Authorization: `Bearer ${options.roomCredential}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(value),
    });
  } catch {
    return { status: "error", code: "gateway_unavailable" };
  }
  if (!response.ok) return { status: "error", code: "gateway_rejected" };
  try {
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.byteLength === 0 || bytes.byteLength > MAX_EVENT_BYTES) {
      return { status: "error", code: "gateway_invalid_response" };
    }
    return {
      status: "accepted",
      result: JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)),
    };
  } catch {
    return { status: "error", code: "gateway_invalid_response" };
  }
}

function parseSubmitUserTurnCall(value: unknown): { callID: string; argumentsJSON: string } | null {
  if (!isRecord(value)) return null;
  if (value.type === "response.function_call_arguments.done") {
    if (value.name !== "submit_user_turn") return null;
    return parseCallPayload(value.call_id, value.arguments);
  }
  if (value.type === "response.output_item.done" && isRecord(value.item)) {
    if (value.item.type !== "function_call" || value.item.name !== "submit_user_turn") return null;
    return parseCallPayload(value.item.call_id, value.item.arguments);
  }
  return null;
}

function parseCallPayload(callID: unknown, argumentsJSON: unknown) {
  if (
    typeof callID !== "string" ||
    callID.length < 1 ||
    callID.length > MAX_CALL_ID_LENGTH ||
    !/^[A-Za-z0-9._-]+$/u.test(callID) ||
    typeof argumentsJSON !== "string"
  ) {
    return null;
  }
  return { callID, argumentsJSON };
}

function parseCallID(value: string): string {
  if (value.length < 1 || value.length > MAX_CALL_ID_LENGTH || !/^[A-Za-z0-9._-]+$/u.test(value)) {
    throw new Error("invalid_realtime_call");
  }
  return value;
}

function parseGatewayURL(value: string): URL {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Error("invalid_realtime_gateway_url");
  }
  if (url.username || url.password || url.search || url.hash)
    throw new Error("invalid_realtime_gateway_url");
  if (url.protocol !== "https:" && url.protocol !== "http:")
    throw new Error("invalid_realtime_gateway_url");
  return url;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
