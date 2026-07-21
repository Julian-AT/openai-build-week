import { test } from "bun:test";
import assert from "node:assert/strict";

import {
  connectRealtimeWebRTC,
  type RealtimeDataChannel,
  type RealtimePeerConnection,
} from "../src/realtime-webrtc-client.ts";

test("connects audio, exchanges SDP, and forwards only data-channel events", async () => {
  const sent: string[] = [];
  let stopped = 0;
  let closed = 0;
  let localDescription: unknown;
  let remoteDescription: unknown;
  const micTrack = { stop: () => (stopped += 1) };
  const channel: RealtimeDataChannel = {
    readyState: "open",
    onmessage: null,
    send: (value) => sent.push(value),
    close: () => undefined,
  };
  const peer: RealtimePeerConnection = {
    ontrack: null,
    createDataChannel: (label) => {
      assert.equal(label, "oai-events");
      return channel;
    },
    addTrack: (track, stream) => {
      assert.equal(track, micTrack);
      assert.equal(typeof (stream as { getTracks: unknown }).getTracks, "function");
      return track;
    },
    createOffer: async () => ({ type: "offer", sdp: "v=0\no=offer" }),
    setLocalDescription: async (description) => {
      localDescription = description;
    },
    setRemoteDescription: async (description) => {
      remoteDescription = description;
    },
    close: () => {
      closed += 1;
    },
  };
  const events: unknown[] = [];
  const connection = await connectRealtimeWebRTC({
    gatewayURL: "https://gateway.example.test",
    roomCredential: "room-token",
    createPeerConnection: () => peer,
    mediaDevices: {
      getUserMedia: async () => ({
        getTracks: () => [micTrack],
      }),
    },
    onEvent: (event) => events.push(event),
    fetch: async (input, init) => {
      assert.equal(String(input), "https://gateway.example.test/v1/realtime/calls");
      assert.equal(init?.method, "POST");
      assert.equal(
        init?.headers && (init.headers as Record<string, string>).Authorization,
        "Bearer room-token",
      );
      assert.equal(init?.body, "v=0\no=offer");
      return new Response("v=0\no=answer", { status: 200 });
    },
  });

  assert.deepEqual(localDescription, { type: "offer", sdp: "v=0\no=offer" });
  assert.deepEqual(remoteDescription, { type: "answer", sdp: "v=0\no=answer" });
  connection.sendEvent({ type: "conversation.item.create" });
  assert.deepEqual(sent, ['{"type":"conversation.item.create"}']);
  channel.onmessage?.({ data: '{"type":"response.done"}' });
  channel.onmessage?.({ data: "not-json" });
  assert.deepEqual(events, [{ type: "response.done" }]);
  connection.close();
  connection.close();
  assert.equal(stopped, 1);
  assert.equal(closed, 1);
});

test("rejects malformed gateway addresses before opening the microphone", async () => {
  let opened = false;
  await assert.rejects(
    connectRealtimeWebRTC({
      gatewayURL: "https://user:pass@gateway.example.test",
      roomCredential: "room-token",
      createPeerConnection: () => {
        throw new Error("must not open");
      },
      mediaDevices: {
        getUserMedia: async () => {
          opened = true;
          return { getTracks: () => [] };
        },
      },
    }),
    /^Error: invalid_realtime_gateway_url$/u,
  );
  assert.equal(opened, false);
});

test("stops microphone tracks and closes the peer when gateway negotiation fails", async () => {
  let stopped = 0;
  let closed = 0;
  const peer: RealtimePeerConnection = {
    ontrack: null,
    createDataChannel: () => ({
      readyState: "open",
      onmessage: null,
      send: () => undefined,
      close: () => undefined,
    }),
    addTrack: () => undefined,
    createOffer: async () => ({ type: "offer", sdp: "v=0\no=offer" }),
    setLocalDescription: async () => undefined,
    setRemoteDescription: async () => undefined,
    close: () => {
      closed += 1;
    },
  };
  await assert.rejects(
    connectRealtimeWebRTC({
      gatewayURL: "https://gateway.example.test",
      roomCredential: "room-token",
      createPeerConnection: () => peer,
      mediaDevices: {
        getUserMedia: async () => ({
          getTracks: () => [{ stop: () => (stopped += 1) }],
        }),
      },
      fetch: async () => new Response("no", { status: 503 }),
    }),
    /^Error: realtime_gateway_failure$/u,
  );
  assert.equal(stopped, 1);
  assert.equal(closed, 1);
});
