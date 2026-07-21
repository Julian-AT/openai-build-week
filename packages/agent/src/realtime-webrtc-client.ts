/**
 * Browser/mobile transport for the gateway's unified Realtime WebRTC route.
 *
 * This module owns SDP and audio transport only. Realtime function events are
 * surfaced to the caller; they must be validated and submitted through the
 * authoritative gateway turn route rather than mutating scene state here.
 */

export interface RealtimeSessionDescription {
  readonly type: "offer" | "answer";
  readonly sdp: string;
}

export interface RealtimeDataChannel {
  readonly readyState: string;
  onmessage: ((event: { readonly data: unknown }) => void) | null;
  send(data: string): void;
  close(): void;
}

export interface RealtimeTrackEvent {
  readonly streams: readonly unknown[];
}

export interface RealtimePeerConnection {
  ontrack: ((event: RealtimeTrackEvent) => void) | null;
  createDataChannel(label: string): RealtimeDataChannel;
  addTrack(track: unknown, stream: unknown): unknown;
  createOffer(): Promise<RealtimeSessionDescription>;
  setLocalDescription(description: RealtimeSessionDescription): Promise<void>;
  setRemoteDescription(description: RealtimeSessionDescription): Promise<void>;
  close(): void;
}

export interface RealtimeMediaStream {
  readonly getTracks: () => readonly RealtimeMediaTrack[];
}

export interface RealtimeMediaTrack {
  stop(): void;
}

export interface RealtimeMediaDevices {
  getUserMedia(constraints: { readonly audio: true }): Promise<RealtimeMediaStream>;
}

export interface RealtimeWebRTCClientOptions {
  readonly gatewayURL: string;
  readonly roomCredential: string;
  readonly fetch?: FetchImplementation;
  readonly createPeerConnection: () => RealtimePeerConnection;
  readonly mediaDevices: RealtimeMediaDevices;
  readonly onEvent?: (event: unknown) => void;
  readonly onRemoteStream?: (stream: unknown) => void;
}

export interface RealtimeWebRTCConnection {
  readonly sendEvent: (event: unknown) => void;
  readonly close: () => void;
}

type FetchImplementation = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

const MAX_SDP_BYTES = 64_000;
const MAX_EVENT_BYTES = 64_000;

export async function connectRealtimeWebRTC(
  options: RealtimeWebRTCClientOptions,
): Promise<RealtimeWebRTCConnection> {
  const gatewayURL = parseGatewayURL(options.gatewayURL);
  if (options.roomCredential.length === 0) throw new Error("missing_room_credential");

  const media = await options.mediaDevices.getUserMedia({ audio: true });
  let peer: RealtimePeerConnection;
  try {
    peer = options.createPeerConnection();
  } catch (error) {
    for (const track of media.getTracks()) track.stop();
    throw error;
  }
  const dataChannel = peer.createDataChannel("oai-events");
  let closed = false;

  peer.ontrack = (event) => {
    const stream = event.streams[0];
    if (stream !== undefined) options.onRemoteStream?.(stream);
  };
  dataChannel.onmessage = (event) => {
    const raw = typeof event.data === "string" ? event.data : String(event.data);
    if (new TextEncoder().encode(raw).byteLength > MAX_EVENT_BYTES) return;
    try {
      options.onEvent?.(JSON.parse(raw) as unknown);
    } catch {
      // Realtime event payloads are untrusted; malformed events are ignored.
    }
  };

  try {
    for (const track of media.getTracks()) peer.addTrack(track, media);
    const offer = await peer.createOffer();
    if (offer.type !== "offer" || !isBoundedSDP(offer.sdp)) {
      throw new Error("invalid_realtime_offer");
    }
    await peer.setLocalDescription(offer);

    const response = await (options.fetch ?? globalThis.fetch)(gatewayURL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${options.roomCredential}`,
        "Content-Type": "application/sdp",
      },
      body: offer.sdp,
    });
    if (!response.ok) throw new Error("realtime_gateway_failure");
    const answerSDP = await readBoundedText(response, MAX_SDP_BYTES);
    if (!isBoundedSDP(answerSDP)) throw new Error("invalid_realtime_response");
    await peer.setRemoteDescription({ type: "answer", sdp: answerSDP });
  } catch (error) {
    closeResources(peer, media);
    throw error;
  }

  return {
    sendEvent(event) {
      if (closed) throw new Error("realtime_connection_closed");
      const encoded = JSON.stringify(event);
      if (encoded === undefined || new TextEncoder().encode(encoded).byteLength > MAX_EVENT_BYTES) {
        throw new Error("invalid_realtime_event");
      }
      if (dataChannel.readyState !== "open") throw new Error("realtime_channel_not_ready");
      dataChannel.send(encoded);
    },
    close() {
      if (closed) return;
      closed = true;
      dataChannel.close();
      closeResources(peer, media);
    },
  };
}

function parseGatewayURL(value: string): URL {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Error("invalid_realtime_gateway_url");
  }
  if (url.username || url.password || (url.protocol !== "https:" && url.protocol !== "http:")) {
    throw new Error("invalid_realtime_gateway_url");
  }
  url.pathname = url.pathname.replace(/\/+$/u, "");
  if (!url.pathname.endsWith("/v1/realtime/calls"))
    url.pathname = `${url.pathname}/v1/realtime/calls`.replace(/^\/\//u, "/");
  if (url.search || url.hash) throw new Error("invalid_realtime_gateway_url");
  return url;
}

function isBoundedSDP(value: string): boolean {
  return value.length > 0 && new TextEncoder().encode(value).byteLength <= MAX_SDP_BYTES;
}

async function readBoundedText(response: Response, maximumBytes: number): Promise<string> {
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.length === 0 || bytes.length > maximumBytes)
    throw new Error("invalid_realtime_response");
  return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}

function closeResources(peer: RealtimePeerConnection, media: RealtimeMediaStream): void {
  for (const track of media.getTracks()) track.stop();
  peer.close();
}
