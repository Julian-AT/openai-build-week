import { test } from "bun:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { encodeFramePacket } from "@reframe/protocol";

import { createDurableRoomSessionStore } from "../src/durable-session-store.ts";
import { createGatewayApp } from "../src/server.ts";

const frameContentType = "application/vnd.reframe.framepacket";
const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);

test("issues room-scoped credentials and durably ingests authenticated binary frames", async () => {
  const dataDirectory = await mkdtemp(join(tmpdir(), "reframe-capture-routes-"));
  const store = await createDurableRoomSessionStore({
    dataDirectory,
    signingSecret: "test-signing-secret-with-sufficient-length",
    nowMilliseconds: () => 1_000,
  });
  try {
    const app = createGatewayApp({
      gatewayToken: "gateway-token",
      durableSessionStore: store,
    });
    const create = await app.request("/v1/sessions", {
      method: "POST",
      headers: {
        authorization: "Bearer gateway-token",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        session_id: "room_2026_07_13_03",
        expires_at_ms: 61_000,
        allowed_paths: ["frames", "events", "artifacts"],
      }),
    });
    assert.equal(create.status, 201);
    const created = (await create.json()) as {
      session_id: string;
      credential: string;
      expires_at_ms: number;
    };
    assert.deepEqual(Object.keys(created).sort(), ["credential", "expires_at_ms", "session_id"]);
    assert.equal(created.session_id, "room_2026_07_13_03");

    const frame = packet(created.session_id);
    const accepted = await app.request(`/v1/sessions/${created.session_id}/frames`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${created.credential}`,
        "content-type": frameContentType,
      },
      body: frameBody(frame),
    });
    assert.equal(accepted.status, 202);
    assert.deepEqual(await accepted.json(), {
      accepted_at_ms: 1_000,
      byte_length: jpeg.byteLength,
      frame_id: 842,
      replayed: false,
      session_id: created.session_id,
      sha256: "32461d5bd1773012acef0ba15636752949bd7c2ce50f9172159d9f56cf0dd9af",
    });

    const replay = await app.request(`/v1/sessions/${created.session_id}/frames`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${created.credential}`,
        "content-type": frameContentType,
      },
      body: frameBody(frame),
    });
    assert.equal(replay.status, 200);
    assert.equal(((await replay.json()) as { replayed: boolean }).replayed, true);

    const recent = await app.request(`/v1/sessions/${created.session_id}/frames/recent`, {
      headers: { authorization: `Bearer ${created.credential}` },
    });
    assert.deepEqual(await recent.json(), {
      frames: [
        {
          accepted_at_ms: 1_000,
          byte_length: jpeg.byteLength,
          frame_id: 842,
          session_id: created.session_id,
          sha256: "32461d5bd1773012acef0ba15636752949bd7c2ce50f9172159d9f56cf0dd9af",
        },
      ],
    });

    const protectedFrame = await app.request(`/v1/sessions/${created.session_id}/frames`, {
      method: "POST",
      headers: {
        authorization: "Bearer gateway-token",
        "content-type": frameContentType,
      },
      body: frameBody(frame),
    });
    assert.deepEqual(
      [protectedFrame.status, await protectedFrame.json()],
      [401, { error: "unauthorized" }],
    );

    const deleted = await app.request(`/v1/sessions/${created.session_id}`, {
      method: "DELETE",
      headers: { authorization: `Bearer ${created.credential}` },
    });
    assert.equal(deleted.status, 204);
    const deletedFrame = await app.request(`/v1/sessions/${created.session_id}/frames`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${created.credential}`,
        "content-type": frameContentType,
      },
      body: frameBody(frame),
    });
    assert.deepEqual(
      [deletedFrame.status, await deletedFrame.json()],
      [401, { error: "unauthorized" }],
    );
  } finally {
    await store.close();
    await rm(dataDirectory, { recursive: true, force: true });
  }
});

test("rejects a frame whose scoped path and packet session do not match", async () => {
  const dataDirectory = await mkdtemp(join(tmpdir(), "reframe-capture-routes-mismatch-"));
  const store = await createDurableRoomSessionStore({
    dataDirectory,
    signingSecret: "test-signing-secret-with-sufficient-length",
  });
  try {
    const app = createGatewayApp({ gatewayToken: "gateway-token", durableSessionStore: store });
    const session = await store.createSession({
      sessionID: "room_2026_07_13_04",
      expiresAtMilliseconds: Date.now() + 60_000,
      allowedPaths: ["frames"],
    });
    const response = await app.request("/v1/sessions/room_2026_07_13_04/frames", {
      method: "POST",
      headers: {
        authorization: `Bearer ${session.credential}`,
        "content-type": frameContentType,
      },
      body: frameBody(packet("room_2026_07_13_05")),
    });
    assert.deepEqual([response.status, await response.json()], [401, { error: "unauthorized" }]);
  } finally {
    await store.close();
    await rm(dataDirectory, { recursive: true, force: true });
  }
});

test("uploads and hash-verifies room-scoped artifacts with idempotent replay", async () => {
  const dataDirectory = await mkdtemp(join(tmpdir(), "reframe-artifact-routes-"));
  const store = await createDurableRoomSessionStore({
    dataDirectory,
    signingSecret: "test-signing-secret-with-sufficient-length",
    nowMilliseconds: () => 2_000,
  });
  try {
    const app = createGatewayApp({ gatewayToken: "gateway-token", durableSessionStore: store });
    const session = await store.createSession({
      sessionID: "room_2026_07_13_artifact",
      expiresAtMilliseconds: 61_000,
      allowedPaths: ["artifacts"],
    });
    const artifactID = "artifact_12345678-1234-4123-8123-123456789abc";
    const bytes = new Uint8Array([1, 2, 3, 4]);
    const headers = {
      authorization: `Bearer ${session.credential}`,
      "content-type": "application/octet-stream",
    };
    const upload = await app.request(`/v1/sessions/${session.sessionID}/artifacts/${artifactID}`, {
      method: "POST",
      headers,
      body: bytes,
    });
    assert.equal(upload.status, 202);
    assert.deepEqual(await upload.json(), {
      accepted_at_ms: 2_000,
      artifact_id: artifactID,
      byte_length: 4,
      content_type: "application/octet-stream",
      replayed: false,
      session_id: session.sessionID,
      sha256: "9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a",
    });
    const replay = await app.request(`/v1/sessions/${session.sessionID}/artifacts/${artifactID}`, {
      method: "POST",
      headers,
      body: bytes,
    });
    assert.equal(replay.status, 200);
    assert.equal(((await replay.json()) as { replayed: boolean }).replayed, true);

    const download = await app.request(
      `/v1/sessions/${session.sessionID}/artifacts/${artifactID}`,
      { headers: { authorization: `Bearer ${session.credential}` } },
    );
    assert.equal(download.status, 200);
    assert.equal(
      download.headers.get("x-content-sha256"),
      "9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a",
    );
    assert.deepEqual(new Uint8Array(await download.arrayBuffer()), bytes);

    const conflict = await app.request(
      `/v1/sessions/${session.sessionID}/artifacts/${artifactID}`,
      { method: "POST", headers, body: new Uint8Array([9]) },
    );
    assert.deepEqual(
      [conflict.status, await conflict.json()],
      [409, { error: "artifact_conflict" }],
    );
  } finally {
    await store.close();
    await rm(dataDirectory, { recursive: true, force: true });
  }
});

function packet(sessionID: string): Uint8Array {
  return encodeFramePacket({
    flags: 0,
    image: jpeg,
    metadata: {
      protocol_version: 1,
      session_id: sessionID,
      submap_id: 0,
      frame_id: 842,
      timestamp_ns: 1_783_918_472_391_823,
      clock_domain: "ios_monotonic_uptime",
      image: {
        codec: "jpeg",
        width: 640,
        height: 480,
        orientation: "up",
        color_space: "sRGB",
        payload_bytes: jpeg.byteLength,
      },
      intrinsics_encoded: [514.4, 0, 319.8, 0, 513.9, 239.6, 0, 0, 1],
      world_from_camera_arkit: [1, 0, 0, 1.42, 0, 1, 0, 1.53, 0, 0, 1, -2.18, 0, 0, 0, 1],
      tracking: { state: "normal", reason: "none", world_frame_version: 1 },
      capture_quality: {
        blur_score: 0.08,
        angular_velocity_rad_s: 0.19,
        translation_since_last_m: 0.034,
        rotation_since_last_deg: 3.2,
        exposure_s: 0.0083,
        iso: 142,
      },
    },
  });
}

function frameBody(frame: Uint8Array): ArrayBuffer {
  const copied = new Uint8Array(frame.byteLength);
  copied.set(frame);
  return copied.buffer;
}
