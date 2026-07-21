"use client";

import { useRef, useState } from "react";

import { connectRealtimeVoice, type RealtimeVoiceConnection } from "../lib/realtime-room.ts";

const DEFAULT_GATEWAY = "http://localhost:8787";

export default function RealtimeVoicePanel() {
  const audio = useRef<HTMLAudioElement>(null);
  const connection = useRef<RealtimeVoiceConnection | null>(null);
  const [status, setStatus] = useState("Voice is off");
  const [connected, setConnected] = useState(false);

  async function toggleVoice() {
    if (connection.current !== null) {
      connection.current.close();
      connection.current = null;
      setConnected(false);
      return;
    }
    const roomCredential = window.sessionStorage.getItem("reframe.roomCredential");
    if (!roomCredential) {
      setStatus("Open a room session before starting voice");
      return;
    }
    const audioElement = audio.current;
    if (!audioElement) return;
    try {
      connection.current = await connectRealtimeVoice({
        gatewayURL:
          window.sessionStorage.getItem("reframe.gatewayURL") ??
          process.env.NEXT_PUBLIC_REFRAME_GATEWAY_URL ??
          DEFAULT_GATEWAY,
        roomCredential,
        audioElement,
        onStatus: setStatus,
      });
      setConnected(true);
    } catch (error) {
      connection.current = null;
      setConnected(false);
      setStatus(error instanceof Error ? error.message : "Voice connection failed");
    }
  }

  return (
    <section className="voice-panel" aria-label="Realtime voice collaboration">
      {/* The Realtime service returns speech; transcripts remain in the data channel. */}
      {/* biome-ignore lint/a11y/useMediaCaption: live captions are delivered separately by Realtime events. */}
      <audio ref={audio} autoPlay playsInline />
      <button type="button" className="voice-button" onClick={() => void toggleVoice()}>
        {connected ? "Stop voice" : "Start voice"}
      </button>
      <span className="voice-status" role="status">
        {status}
      </span>
    </section>
  );
}
