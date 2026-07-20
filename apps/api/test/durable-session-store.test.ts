import { test } from "bun:test";
import assert from "node:assert/strict";
import { lstat, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { encodeFramePacket } from "@reframe/protocol";

import {
  CaptureFrameConflictError,
  createDurableRoomSessionStore,
  RoomCredentialError,
} from "../src/durable-session-store.ts";

const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);

test("durably accepts a FramePacket before replayable receipt and never duplicates it", async () => {
  const dataDirectory = await mkdtemp(join(tmpdir(), "reframe-session-store-"));
  try {
    const sessions = await createDurableRoomSessionStore({
      dataDirectory,
      signingSecret: "test-signing-secret-with-sufficient-length",
      nowMilliseconds: () => 1_000,
    });
    const session = await sessions.createSession({
      sessionID: "room_2026_07_13_01",
      expiresAtMilliseconds: 61_000,
      allowedPaths: ["frames", "events", "artifacts"],
    });
    const bytes = packet("room_2026_07_13_01", jpeg);

    const accepted = await sessions.acceptFrame({ credential: session.credential, bytes });
    assert.equal(accepted.replayed, false);
    assert.equal(accepted.frameID, 842);
    assert.equal(accepted.byteLength, jpeg.byteLength);
    assert.deepEqual(
      await Bun.file(join(accepted.rfcapDirectory, "frames", "000000000842.jpg")).bytes(),
      jpeg,
    );
    assert.match(
      await Bun.file(join(accepted.rfcapDirectory, "frames.jsonl")).text(),
      /"frame_id":842/,
    );

    assert.deepEqual(await sessions.acceptFrame({ credential: session.credential, bytes }), {
      ...accepted,
      replayed: true,
    });
    assert.equal((await sessions.recentFrames(session.credential)).length, 1);
  } finally {
    await rm(dataDirectory, { recursive: true, force: true });
  }
});

test("rejects cross-room credentials, divergent frame replays, expired tokens, and deletion reuse", async () => {
  const dataDirectory = await mkdtemp(join(tmpdir(), "reframe-session-store-failure-"));
  let now = 1_000;
  try {
    const sessions = await createDurableRoomSessionStore({
      dataDirectory,
      signingSecret: "test-signing-secret-with-sufficient-length",
      nowMilliseconds: () => now,
    });
    const session = await sessions.createSession({
      sessionID: "room_2026_07_13_02",
      expiresAtMilliseconds: 2_000,
      allowedPaths: ["frames"],
    });
    await sessions.acceptFrame({
      credential: session.credential,
      bytes: packet("room_2026_07_13_02", jpeg),
    });
    await assert.rejects(
      sessions.acceptFrame({
        credential: session.credential,
        bytes: packet("room_2026_07_13_01", jpeg),
      }),
      RoomCredentialError,
    );
    await assert.rejects(
      sessions.acceptFrame({
        credential: session.credential,
        bytes: packet("room_2026_07_13_02", new Uint8Array([0xff, 0xd8, 0, 0xff, 0xd9])),
      }),
      CaptureFrameConflictError,
    );
    now = 2_000;
    await assert.rejects(sessions.recentFrames(session.credential), RoomCredentialError);
    now = 1_500;
    await sessions.deleteSession(session.credential);
    await assert.rejects(sessions.recentFrames(session.credential), RoomCredentialError);
  } finally {
    await rm(dataDirectory, { recursive: true, force: true });
  }
});

test("rebuilds the RFCAP journal from accepted SQLite rows after an interrupted projection", async () => {
  const dataDirectory = await mkdtemp(join(tmpdir(), "reframe-session-store-recovery-"));
  let recovered: Awaited<ReturnType<typeof createDurableRoomSessionStore>> | undefined;
  try {
    const sessions = await createDurableRoomSessionStore({
      dataDirectory,
      signingSecret: "test-signing-secret-with-sufficient-length",
      nowMilliseconds: () => 1_000,
    });
    const session = await sessions.createSession({
      sessionID: "room_2026_07_13_06",
      expiresAtMilliseconds: 61_000,
      allowedPaths: ["frames"],
    });
    const bytes = packet("room_2026_07_13_06", jpeg);
    const accepted = await sessions.acceptFrame({ credential: session.credential, bytes });
    await sessions.close();
    await rm(join(accepted.rfcapDirectory, "frames.jsonl"));

    recovered = await createDurableRoomSessionStore({
      dataDirectory,
      signingSecret: "test-signing-secret-with-sufficient-length",
      nowMilliseconds: () => 1_000,
    });
    assert.equal(
      (await recovered.acceptFrame({ credential: session.credential, bytes })).replayed,
      true,
    );
    assert.match(
      await Bun.file(join(accepted.rfcapDirectory, "frames.jsonl")).text(),
      /"frame_id":842/,
    );
  } finally {
    await recovered?.close();
    await rm(dataDirectory, { recursive: true, force: true });
  }
});

test("appends accepted frame journal records without replacing prior durable bytes", async () => {
  const dataDirectory = await mkdtemp(join(tmpdir(), "reframe-session-store-journal-"));
  try {
    const sessions = await createDurableRoomSessionStore({
      dataDirectory,
      signingSecret: "test-signing-secret-with-sufficient-length",
      nowMilliseconds: () => 1_000,
    });
    const session = await sessions.createSession({
      sessionID: "room_2026_07_13_07",
      expiresAtMilliseconds: 61_000,
      allowedPaths: ["frames"],
    });
    const first = await sessions.acceptFrame({
      credential: session.credential,
      bytes: packet("room_2026_07_13_07", jpeg, 842),
    });
    const journalPath = join(first.rfcapDirectory, "frames.jsonl");
    const before = await lstat(journalPath);

    await sessions.acceptFrame({
      credential: session.credential,
      bytes: packet("room_2026_07_13_07", jpeg, 843),
    });
    const after = await lstat(journalPath);

    assert.equal(after.ino, before.ino);
    assert.deepEqual((await Bun.file(journalPath).text()).trim().split("\n").length, 2);
    await sessions.close();
  } finally {
    await rm(dataDirectory, { recursive: true, force: true });
  }
});

function packet(sessionID: string, image: Uint8Array, frameID = 842): Uint8Array {
  return encodeFramePacket({
    flags: 0,
    image,
    metadata: {
      protocol_version: 1,
      session_id: sessionID,
      submap_id: 0,
      frame_id: frameID,
      timestamp_ns: 1_783_918_472_391_823,
      clock_domain: "ios_monotonic_uptime",
      image: {
        codec: "jpeg",
        width: 640,
        height: 480,
        orientation: "up",
        color_space: "sRGB",
        payload_bytes: image.byteLength,
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
