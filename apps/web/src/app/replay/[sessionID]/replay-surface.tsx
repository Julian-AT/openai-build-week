"use client";

import { useEffect, useRef, useState } from "react";
import * as THREE from "three";

import { loadVerifiedGLB, type RemoteDeliveredAsset } from "../../../lib/delivered-asset.ts";
import { parseReplayEvents, type ReplayEvent, replayEventsURL } from "../../../lib/replay-data.ts";

const DEFAULT_GATEWAY = "http://localhost:8787";

export default function ReplaySurface({ sessionID }: { readonly sessionID: string }) {
  const canvasHost = useRef<HTMLDivElement>(null);
  const [events, setEvents] = useState<readonly ReplayEvent[]>([]);
  const [status, setStatus] = useState("Waiting for a room credential");
  const [assetStatus, setAssetStatus] = useState("No verified asset selected");

  useEffect(() => {
    const credential = window.sessionStorage.getItem("reframe.roomCredential");
    if (!credential) return;
    const gateway = process.env.NEXT_PUBLIC_REFRAME_GATEWAY_URL ?? DEFAULT_GATEWAY;
    const controller = new AbortController();
    setStatus("Loading authoritative event journal…");
    fetch(replayEventsURL(gateway, sessionID), {
      headers: { Authorization: `Bearer ${credential}` },
      cache: "no-store",
      signal: controller.signal,
    })
      .then(async (response) => {
        if (!response.ok) throw new Error("replay_unavailable");
        return parseReplayEvents(await response.json());
      })
      .then((nextEvents) => {
        setEvents(nextEvents);
        setStatus(`${nextEvents.length} authoritative events`);
      })
      .catch((error: unknown) => {
        if (!controller.signal.aborted)
          setStatus(error instanceof Error ? error.message : "replay_unavailable");
      });
    return () => controller.abort();
  }, [sessionID]);

  useEffect(() => {
    const host = canvasHost.current;
    if (!host) return;
    const scene = new THREE.Scene();
    scene.background = new THREE.Color("#10120f");
    const camera = new THREE.PerspectiveCamera(42, 1, 0.01, 100);
    camera.position.set(0, 0.8, 2.5);
    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    host.replaceChildren(renderer.domElement);
    const resize = () => {
      const width = Math.max(1, host.clientWidth);
      const height = Math.max(1, host.clientHeight);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
      renderer.setSize(width, height, false);
    };
    resize();
    const resizeObserver = new ResizeObserver(resize);
    resizeObserver.observe(host);
    const light = new THREE.HemisphereLight(0xf1f0e8, 0x171a16, 2.2);
    scene.add(light);
    const grid = new THREE.GridHelper(3, 12, 0x59644b, 0x2b3328);
    scene.add(grid);
    const descriptorJSON = window.sessionStorage.getItem("reframe.replayAsset");
    let disposed = false;
    if (descriptorJSON) {
      try {
        const descriptor = JSON.parse(descriptorJSON) as RemoteDeliveredAsset;
        if (descriptor.derivative !== "glb") throw new Error("unsupported_replay_derivative");
        setAssetStatus("Verifying GLB…");
        loadVerifiedGLB({ ...descriptor, derivative: "glb" })
          .then((gltf) => {
            if (disposed) return;
            gltf.scene.position.y = 0;
            scene.add(gltf.scene);
            setAssetStatus("Verified GLB active");
          })
          .catch(() => setAssetStatus("Asset verification failed; scene remains empty"));
      } catch {
        setAssetStatus("Invalid asset descriptor; scene remains empty");
      }
    }
    let animationFrame = 0;
    const render = () => {
      renderer.render(scene, camera);
      animationFrame = window.requestAnimationFrame(render);
    };
    render();
    return () => {
      disposed = true;
      window.cancelAnimationFrame(animationFrame);
      resizeObserver.disconnect();
      renderer.dispose();
      host.replaceChildren();
    };
  }, []);

  return (
    <main className="replay-shell">
      <header className="replay-header">
        <a href="/" className="replay-brand">
          Reframe
        </a>
        <span className="replay-mode">MODE B0 · VERIFIED REPLAY</span>
      </header>
      <section className="replay-intro">
        <span className="eyebrow">Room session</span>
        <h1>{sessionID}</h1>
        <p>{status}. The timeline is read-only and ordered by the gateway journal.</p>
      </section>
      <section className="replay-layout" aria-label="Session replay">
        <div
          className="replay-canvas"
          ref={canvasHost}
          role="img"
          aria-label="Three.js scene twin"
        />
        <aside className="replay-panel">
          <div className="replay-panel__heading">
            <h2>Event journal</h2>
            <span>{events.length}</span>
          </div>
          <p className="replay-asset-status">{assetStatus}</p>
          {events.length === 0 ? (
            <p className="replay-muted">
              No events loaded. Add a room credential to this browser session.
            </p>
          ) : (
            <ol className="replay-events">
              {events.map((event) => (
                <li key={event.event_id}>
                  <span>#{event.event_sequence}</span>
                  <strong>{event.type}</strong>
                </li>
              ))}
            </ol>
          )}
        </aside>
      </section>
    </main>
  );
}
