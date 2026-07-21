"use client";

import { useEffect, useRef, useState } from "react";

import { type CaptureSession, createCaptureSession } from "../lib/capture-upload.ts";

const FRAME_INTERVAL_MS = 1_000;

export default function CapturePanel() {
  const [status, setStatus] = useState("Ready for a browser capture");
  const [sessionID, setSessionID] = useState<string | null>(null);
  const [frameCount, setFrameCount] = useState(0);
  const [running, setRunning] = useState(false);
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const captureRef = useRef<CaptureSession | null>(null);
  const timerRef = useRef<number | null>(null);
  const frameIDRef = useRef(0);
  const uploadingRef = useRef(false);

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) window.clearInterval(timerRef.current);
      const capture = captureRef.current;
      if (capture) {
        void capture
          .appendEvent({ type: "session_finalized", payload: { source: "browser_camera" } })
          .catch(() => undefined);
      }
      streamRef.current?.getTracks().forEach((track) => {
        track.stop();
      });
    };
  }, []);

  async function startCapture() {
    if (running) return;
    if (!navigator.mediaDevices?.getUserMedia) {
      setStatus("Camera capture requires a secure browser context");
      return;
    }
    try {
      setStatus("Requesting camera access…");
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: false,
        video: { facingMode: "environment", width: { ideal: 1280 }, height: { ideal: 720 } },
      });
      const roomResponse = await fetch("/api/capture-session", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: "{}",
      });
      if (!roomResponse.ok) throw new Error("capture_session_unavailable");
      const roomJSON = (await roomResponse.json()) as unknown;
      const room = parseRoomResponse(roomJSON);
      const capture = await createCaptureSession({ room });
      streamRef.current = stream;
      captureRef.current = capture;
      frameIDRef.current = 0;
      setSessionID(capture.sessionID);
      setFrameCount(0);
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        await videoRef.current.play();
      }
      window.sessionStorage.setItem("reframe.roomSessionID", capture.sessionID);
      window.sessionStorage.setItem("reframe.roomCredential", capture.credential);
      window.sessionStorage.setItem("reframe.gatewayURL", room.gatewayURL);
      await capture.appendEvent({ type: "session_started", payload: { source: "browser_camera" } });
      setRunning(true);
      setStatus("Capturing validated frames…");
      timerRef.current = window.setInterval(() => {
        void captureFrame();
      }, FRAME_INTERVAL_MS);
    } catch (error) {
      stopCapture();
      setStatus(error instanceof Error ? error.message : "Capture could not start");
    }
  }

  function stopCapture() {
    if (timerRef.current !== null) {
      window.clearInterval(timerRef.current);
      timerRef.current = null;
    }
    const capture = captureRef.current;
    captureRef.current = null;
    if (capture) {
      void capture
        .appendEvent({ type: "session_finalized", payload: { source: "browser_camera" } })
        .catch(() => undefined);
    }
    streamRef.current?.getTracks().forEach((track) => {
      track.stop();
    });
    streamRef.current = null;
    if (videoRef.current) videoRef.current.srcObject = null;
    setRunning(false);
  }

  async function captureFrame() {
    const capture = captureRef.current;
    const video = videoRef.current;
    const canvas = canvasRef.current;
    if (!capture || !video || !canvas || uploadingRef.current || video.videoWidth === 0) return;
    uploadingRef.current = true;
    try {
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      const context = canvas.getContext("2d", { alpha: false });
      if (!context) throw new Error("capture_canvas_unavailable");
      context.drawImage(video, 0, 0, canvas.width, canvas.height);
      const blob = await new Promise<Blob>((resolve, reject) => {
        canvas.toBlob(
          (value) => (value === null ? reject(new Error("capture_encode_failed")) : resolve(value)),
          "image/jpeg",
          0.72,
        );
      });
      const bytes = new Uint8Array(await blob.arrayBuffer());
      await capture.uploadJPEGFrame({
        bytes,
        width: canvas.width,
        height: canvas.height,
        frameID: frameIDRef.current,
      });
      frameIDRef.current += 1;
      setFrameCount((count) => count + 1);
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "Frame upload failed");
    } finally {
      uploadingRef.current = false;
    }
  }

  return (
    <section className="capture-panel" aria-labelledby="capture-title">
      <div className="capture-copy">
        <p className="eyebrow">Mode B0 · live capture</p>
        <h2 id="capture-title">Record a real room session.</h2>
        <p>
          The browser camera is a convenience path. Every frame is JPEG-validated, wrapped in a
          Reframe FramePacket, and durably journaled with its session events.
        </p>
      </div>
      <div className="capture-controls">
        <div className="capture-actions">
          <button
            className="primary-action"
            type="button"
            onClick={() => void startCapture()}
            disabled={running}
          >
            Start capture
          </button>
          <button
            className="secondary-action"
            type="button"
            onClick={stopCapture}
            disabled={!running}
          >
            Stop
          </button>
        </div>
        <p className="capture-status" role="status">
          {status}
        </p>
        {sessionID ? (
          <p className="capture-meta">
            {sessionID} · {frameCount} frames · <a href={`/replay/${sessionID}`}>Open replay</a>
          </p>
        ) : null}
      </div>
      <video
        ref={videoRef}
        className="capture-video"
        muted
        playsInline
        aria-label="Live camera preview"
      />
      <canvas ref={canvasRef} className="capture-canvas" />
    </section>
  );
}

function parseRoomResponse(value: unknown) {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value) ||
    typeof (value as Record<string, unknown>).gateway_url !== "string" ||
    typeof (value as Record<string, unknown>).session_id !== "string" ||
    typeof (value as Record<string, unknown>).credential !== "string" ||
    typeof (value as Record<string, unknown>).expires_at_ms !== "number"
  ) {
    throw new Error("invalid_capture_session");
  }
  const room = value as Record<string, unknown>;
  return {
    gatewayURL: room.gateway_url as string,
    sessionID: room.session_id as string,
    credential: room.credential as string,
    expiresAtMilliseconds: room.expires_at_ms as number,
  };
}
