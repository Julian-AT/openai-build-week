import { Database } from "bun:sqlite";
import { createHash, createHmac, randomUUID, timingSafeEqual } from "node:crypto";
import { mkdir, open, readFile, rename, rm } from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";

import {
  type CaptureEventInput,
  type CoordinationEventPayload,
  canonicalJSONSHA256,
  canonicalJSONStringify,
  type FramePacket,
  parseCaptureEvent,
  parseFramePacket,
} from "@reframe/protocol";

const SESSION_DIRECTORY = "sessions";
const DATABASE_NAME = "gateway.sqlite";
const FRAME_WINDOW_MILLISECONDS = 5_000;
const MAX_RECENT_FRAMES = 64;
const MAX_CREDENTIAL_LIFETIME_MILLISECONDS = 15 * 60 * 1_000;
const CREDENTIAL_HEADER = { alg: "HS256", typ: "JWT" };
const BASE64_URL = /^[A-Za-z0-9_-]+$/u;
const ROOM_ID = /^room_[a-z0-9_]{3,120}$/u;
const ARTIFACT_ID =
  /^artifact_[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u;
const ALLOWED_PATH = /^(?:frames|events|artifacts|scene)$/u;

export interface CreateDurableRoomSessionStoreOptions {
  readonly dataDirectory: string;
  /** Server-only HMAC secret; it is never serialized or returned by this store. */
  readonly signingSecret: string;
  readonly nowMilliseconds?: () => number;
}

export interface CreateRoomSessionInput {
  readonly sessionID: string;
  readonly expiresAtMilliseconds: number;
  readonly allowedPaths: readonly ("frames" | "events" | "artifacts" | "scene")[];
}

export interface CreatedRoomSession {
  readonly sessionID: string;
  readonly credential: string;
  readonly expiresAtMilliseconds: number;
}

export interface CaptureFrameReceipt {
  readonly sessionID: string;
  readonly frameID: number;
  readonly sha256: string;
  readonly byteLength: number;
  readonly acceptedAtMilliseconds: number;
  readonly replayed: boolean;
  /** Internal runtime path only; never serialize this through a public gateway response. */
  readonly rfcapDirectory: string;
}

export interface CaptureArtifactReceipt {
  readonly sessionID: string;
  readonly artifactID: string;
  readonly sha256: string;
  readonly byteLength: number;
  readonly contentType: string;
  readonly acceptedAtMilliseconds: number;
  readonly replayed: boolean;
}

export interface CaptureEventReceipt extends CaptureEventInput {
  readonly sessionID: string;
  readonly payloadSha256: string;
  readonly acceptedAtMilliseconds: number;
  readonly replayed: boolean;
}

export interface ActiveTargetStatus {
  readonly sessionID: string;
  readonly targetID: string;
  readonly objectID: string;
  readonly pointerID: string;
  readonly targetRevision: number;
  readonly frameID: number;
  readonly pixelEncoded: readonly [number, number];
  readonly source: string;
  readonly status: "seeded" | "closed";
  readonly seededAtMilliseconds: number;
}

export const isRoomSessionID = (value: string): boolean => ROOM_ID.test(value);

interface RoomCredentialClaims {
  readonly version: 1;
  readonly session_id: string;
  readonly role: "editor";
  readonly allowed_paths: readonly string[];
  readonly exp: number;
  readonly nonce: string;
}

interface SessionRow {
  session_id: string;
  nonce_sha256: string;
  expires_at_ms: number;
  deleted_at_ms: number | null;
}

interface FrameRow {
  session_id: string;
  frame_id: number;
  image_sha256: string;
  image_bytes: number;
  accepted_at_ms: number;
  metadata_json: string;
}

interface ArtifactRow {
  session_id: string;
  artifact_id: string;
  artifact_sha256: string;
  artifact_bytes: number;
  content_type: string;
  accepted_at_ms: number;
}

interface EventRow {
  session_id: string;
  event_id: string;
  event_sequence: number;
  monotonic_timestamp_ns: string;
  event_type: CaptureEventInput["type"];
  payload_json: string;
  payload_sha256: string;
  accepted_at_ms: number;
}

export class RoomCredentialError extends Error {
  constructor() {
    super("invalid_room_credential");
    this.name = "RoomCredentialError";
  }
}

export class CaptureFrameConflictError extends Error {
  constructor() {
    super("capture_frame_conflict");
    this.name = "CaptureFrameConflictError";
  }
}

export class CaptureArtifactConflictError extends Error {
  constructor() {
    super("capture_artifact_conflict");
    this.name = "CaptureArtifactConflictError";
  }
}

export class CaptureArtifactNotFoundError extends Error {
  constructor() {
    super("capture_artifact_not_found");
    this.name = "CaptureArtifactNotFoundError";
  }
}

export class CaptureEventConflictError extends Error {
  constructor() {
    super("capture_event_conflict");
    this.name = "CaptureEventConflictError";
  }
}

/**
 * SQLite is the authoritative session/frame journal. RFCAP files are a durable
 * projection of that journal; frame bytes are atomically committed before the
 * journal row makes the packet visible to consumers.
 */
export class DurableRoomSessionStore {
  readonly #database: Database;
  readonly #sessionsDirectory: string;
  readonly #signingSecret: Uint8Array;
  readonly #now: () => number;
  #serial: Promise<void> = Promise.resolve();

  constructor(options: {
    database: Database;
    sessionsDirectory: string;
    signingSecret: Uint8Array;
    now: () => number;
  }) {
    this.#database = options.database;
    this.#sessionsDirectory = options.sessionsDirectory;
    this.#signingSecret = options.signingSecret;
    this.#now = options.now;
  }

  async createSession(input: CreateRoomSessionInput): Promise<CreatedRoomSession> {
    return await this.#exclusive(async () => {
      assertRoomID(input.sessionID);
      assertTimestamp(input.expiresAtMilliseconds);
      const now = this.#now();
      if (
        input.expiresAtMilliseconds <= now ||
        input.expiresAtMilliseconds > now + MAX_CREDENTIAL_LIFETIME_MILLISECONDS
      ) {
        throw new RoomCredentialError();
      }
      const allowedPaths = normalizeAllowedPaths(input.allowedPaths);
      const nonce = randomUUID();
      const claims: RoomCredentialClaims = {
        version: 1,
        session_id: input.sessionID,
        role: "editor",
        allowed_paths: allowedPaths,
        exp: Math.floor(input.expiresAtMilliseconds / 1_000),
        nonce,
      };
      const credential = this.#sign(claims);
      const sessionDirectory = this.#sessionDirectory(input.sessionID);
      await mkdir(join(sessionDirectory, "session.rfcap", "frames"), { recursive: true });
      await writeAtomically(
        join(sessionDirectory, "session.rfcap", "manifest.json"),
        canonicalJSONStringify({
          format: "rfcap",
          version: 1,
          session_id: input.sessionID,
          world: { handedness: "right", units: "metres", up_axis: "+Y" },
          image_orientation: "up",
          matrix_layout: "row_major",
          camera_convention: "arkit",
          consent: { upload: true, retain_raw_until_ms: input.expiresAtMilliseconds },
        }),
      );
      try {
        this.#database
          .prepare(
            "INSERT INTO room_sessions (session_id, nonce_sha256, expires_at_ms, created_at_ms) VALUES (?1, ?2, ?3, ?4)",
          )
          .run(input.sessionID, sha256(nonce), input.expiresAtMilliseconds, now);
      } catch (error) {
        await rm(sessionDirectory, { recursive: true, force: true });
        throw error;
      }
      return {
        sessionID: input.sessionID,
        credential,
        expiresAtMilliseconds: input.expiresAtMilliseconds,
      };
    });
  }

  /** Runs a trusted scene operation after validating the room-scoped credential. */
  async withAuthorizedScene<T>(
    credential: string,
    operation: (sessionID: string, database: Database) => T | Promise<T>,
    expectedSessionID?: string,
  ): Promise<T> {
    return await this.#exclusive(async () => {
      const claims = this.#authorize(credential, "scene");
      if (expectedSessionID !== undefined && expectedSessionID !== claims.session_id) {
        throw new RoomCredentialError();
      }
      return await operation(claims.session_id, this.#database);
    });
  }

  async acceptFrame(input: {
    credential: string;
    bytes: Uint8Array;
    expectedSessionID?: string;
  }): Promise<CaptureFrameReceipt> {
    return await this.#exclusive(async () => {
      const claims = this.#authorize(input.credential, "frames");
      if (input.expectedSessionID !== undefined && input.expectedSessionID !== claims.session_id) {
        throw new RoomCredentialError();
      }
      const packet = parseFramePacket(input.bytes);
      if (packet.metadata.session_id !== claims.session_id) throw new RoomCredentialError();
      return await this.#persistFrame(claims.session_id, packet);
    });
  }

  async recentFrames(
    credential: string,
    expectedSessionID?: string,
  ): Promise<readonly CaptureFrameReceipt[]> {
    return await this.#exclusive(async () => {
      const claims = this.#authorize(credential, "frames");
      if (expectedSessionID !== undefined && expectedSessionID !== claims.session_id) {
        throw new RoomCredentialError();
      }
      const threshold = this.#now() - FRAME_WINDOW_MILLISECONDS;
      const rows = this.#database
        .query<FrameRow, [string, number, number]>(
          "SELECT session_id, frame_id, image_sha256, image_bytes, accepted_at_ms, metadata_json FROM capture_frames WHERE session_id = ?1 AND accepted_at_ms >= ?2 ORDER BY accepted_at_ms DESC, frame_id DESC LIMIT ?3",
        )
        .all(claims.session_id, threshold, MAX_RECENT_FRAMES);
      return Object.freeze(rows.map((row) => this.#receipt(row, false)));
    });
  }

  async acceptArtifact(input: {
    credential: string;
    artifactID: string;
    bytes: Uint8Array;
    contentType: string;
    expectedSessionID?: string;
  }): Promise<CaptureArtifactReceipt> {
    return await this.#exclusive(async () => {
      const claims = this.#authorize(input.credential, "artifacts");
      if (input.expectedSessionID !== undefined && input.expectedSessionID !== claims.session_id) {
        throw new RoomCredentialError();
      }
      assertArtifactID(input.artifactID);
      assertContentType(input.contentType);
      if (input.bytes.byteLength === 0) throw new CaptureArtifactConflictError();
      const sessionID = claims.session_id;
      const digest = sha256(input.bytes);
      const existing = this.#database
        .query<ArtifactRow, [string, string]>(
          "SELECT session_id, artifact_id, artifact_sha256, artifact_bytes, content_type, accepted_at_ms FROM capture_artifacts WHERE session_id = ?1 AND artifact_id = ?2",
        )
        .get(sessionID, input.artifactID);
      if (existing !== null) {
        if (
          existing.artifact_sha256 !== digest ||
          existing.content_type !== input.contentType ||
          existing.artifact_bytes !== input.bytes.byteLength
        ) {
          throw new CaptureArtifactConflictError();
        }
        return artifactReceipt(existing, true);
      }
      const now = this.#now();
      assertTimestamp(now);
      const artifactPath = join(this.#rfcapDirectory(sessionID), "artifacts", input.artifactID);
      await writeBinaryAtomically(artifactPath, input.bytes);
      const row: ArtifactRow = {
        session_id: sessionID,
        artifact_id: input.artifactID,
        artifact_sha256: digest,
        artifact_bytes: input.bytes.byteLength,
        content_type: input.contentType,
        accepted_at_ms: now,
      };
      this.#database.exec("BEGIN IMMEDIATE");
      try {
        this.#database
          .prepare(
            "INSERT INTO capture_artifacts (session_id, artifact_id, artifact_sha256, artifact_bytes, content_type, accepted_at_ms) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
          )
          .run(
            row.session_id,
            row.artifact_id,
            row.artifact_sha256,
            row.artifact_bytes,
            row.content_type,
            row.accepted_at_ms,
          );
        this.#database.exec("COMMIT");
      } catch (error) {
        this.#database.exec("ROLLBACK");
        await rm(artifactPath, { force: true });
        throw error;
      }
      return artifactReceipt(row, false);
    });
  }

  async readArtifact(input: {
    credential: string;
    artifactID: string;
    expectedSessionID?: string;
  }): Promise<{ readonly receipt: CaptureArtifactReceipt; readonly bytes: Uint8Array }> {
    return await this.#exclusive(async () => {
      const claims = this.#authorize(input.credential, "artifacts");
      if (input.expectedSessionID !== undefined && input.expectedSessionID !== claims.session_id) {
        throw new RoomCredentialError();
      }
      assertArtifactID(input.artifactID);
      const row = this.#database
        .query<ArtifactRow, [string, string]>(
          "SELECT session_id, artifact_id, artifact_sha256, artifact_bytes, content_type, accepted_at_ms FROM capture_artifacts WHERE session_id = ?1 AND artifact_id = ?2",
        )
        .get(claims.session_id, input.artifactID);
      if (row === null) throw new CaptureArtifactNotFoundError();
      const bytes = new Uint8Array(
        await readFile(join(this.#rfcapDirectory(claims.session_id), "artifacts", row.artifact_id)),
      );
      if (bytes.byteLength !== row.artifact_bytes || sha256(bytes) !== row.artifact_sha256) {
        throw new CaptureArtifactNotFoundError();
      }
      return { receipt: artifactReceipt(row, false), bytes };
    });
  }

  async acceptEvent(input: {
    credential: string;
    event: CaptureEventInput;
    expectedSessionID?: string;
  }): Promise<CaptureEventReceipt> {
    return await this.#exclusive(async () => {
      const claims = this.#authorize(input.credential, "events");
      if (input.expectedSessionID !== undefined && input.expectedSessionID !== claims.session_id) {
        throw new RoomCredentialError();
      }
      const event = parseCaptureEvent(input.event);
      const sessionID = claims.session_id;
      validateCoordinationEvent(this.#database, sessionID, event);
      const payloadSHA256 = canonicalJSONSHA256(event.payload);
      const existingByID = this.#database
        .query<EventRow, [string, string]>(
          "SELECT session_id, event_id, event_sequence, monotonic_timestamp_ns, event_type, payload_json, payload_sha256, accepted_at_ms FROM capture_events WHERE session_id = ?1 AND event_id = ?2",
        )
        .get(sessionID, event.event_id);
      if (existingByID !== null) {
        if (
          existingByID.event_sequence !== event.event_sequence ||
          existingByID.monotonic_timestamp_ns !== event.monotonic_timestamp_ns ||
          existingByID.event_type !== event.type ||
          existingByID.payload_json !== canonicalJSONStringify(event.payload)
        ) {
          throw new CaptureEventConflictError();
        }
        await synchronizeEventJournal(this.#database, this.#rfcapDirectory(sessionID), sessionID);
        return eventReceipt(existingByID, true);
      }
      const previous = this.#database
        .query<{ event_sequence: number }, [string]>(
          "SELECT event_sequence FROM capture_events WHERE session_id = ?1 ORDER BY event_sequence DESC LIMIT 1",
        )
        .get(sessionID);
      const expectedSequence = previous === null ? 0 : previous.event_sequence + 1;
      if (event.event_sequence !== expectedSequence) throw new CaptureEventConflictError();
      const sequenceConflict = this.#database
        .query<EventRow, [string, number]>(
          "SELECT session_id, event_id, event_sequence, monotonic_timestamp_ns, event_type, payload_json, payload_sha256, accepted_at_ms FROM capture_events WHERE session_id = ?1 AND event_sequence = ?2",
        )
        .get(sessionID, event.event_sequence);
      if (sequenceConflict !== null) throw new CaptureEventConflictError();
      const now = this.#now();
      assertTimestamp(now);
      const row: EventRow = {
        session_id: sessionID,
        event_id: event.event_id,
        event_sequence: event.event_sequence,
        monotonic_timestamp_ns: event.monotonic_timestamp_ns,
        event_type: event.type,
        payload_json: canonicalJSONStringify(event.payload),
        payload_sha256: payloadSHA256,
        accepted_at_ms: now,
      };
      this.#database.exec("BEGIN IMMEDIATE");
      try {
        this.#database
          .prepare(
            "INSERT INTO capture_events (session_id, event_id, event_sequence, monotonic_timestamp_ns, event_type, payload_json, payload_sha256, accepted_at_ms) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
          )
          .run(
            row.session_id,
            row.event_id,
            row.event_sequence,
            row.monotonic_timestamp_ns,
            row.event_type,
            row.payload_json,
            row.payload_sha256,
            row.accepted_at_ms,
          );
        if (event.type === "target_seed") {
          const payload = event.payload as CoordinationEventPayload & { type: "target_seed" };
          this.#database
            .prepare(
              "INSERT OR REPLACE INTO active_targets (session_id,target_id,object_id,pointer_id,target_revision,frame_id,pixel_x,pixel_y,source,status,seeded_at_ms) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,'seeded',?10)",
            )
            .run(
              sessionID,
              `target_${randomUUID()}`,
              `object_${randomUUID()}`,
              `pointer_${randomUUID()}`,
              1,
              payload.frame_id,
              payload.pixel_encoded[0],
              payload.pixel_encoded[1],
              payload.source,
              now,
            );
        }
        this.#database.exec("COMMIT");
      } catch (error) {
        this.#database.exec("ROLLBACK");
        throw error;
      }
      await synchronizeEventJournal(this.#database, this.#rfcapDirectory(sessionID), sessionID);
      return eventReceipt(row, false);
    });
  }

  async recentEvents(
    credential: string,
    expectedSessionID?: string,
  ): Promise<readonly CaptureEventReceipt[]> {
    return await this.#exclusive(async () => {
      const claims = this.#authorize(credential, "events");
      if (expectedSessionID !== undefined && expectedSessionID !== claims.session_id) {
        throw new RoomCredentialError();
      }
      const rows = this.#database
        .query<EventRow, [string]>(
          "SELECT session_id, event_id, event_sequence, monotonic_timestamp_ns, event_type, payload_json, payload_sha256, accepted_at_ms FROM capture_events WHERE session_id = ?1 ORDER BY event_sequence",
        )
        .all(claims.session_id);
      return Object.freeze(rows.map((row) => eventReceipt(row, false)));
    });
  }

  async activeTarget(
    credential: string,
    expectedSessionID?: string,
  ): Promise<ActiveTargetStatus | null> {
    return await this.#exclusive(async () => {
      const claims = this.#authorize(credential, "scene");
      if (expectedSessionID !== undefined && expectedSessionID !== claims.session_id) {
        throw new RoomCredentialError();
      }
      const row = this.#database
        .query<
          {
            session_id: string;
            target_id: string;
            object_id: string;
            pointer_id: string;
            target_revision: number;
            frame_id: number;
            pixel_x: number;
            pixel_y: number;
            source: string;
            status: "seeded" | "closed";
            seeded_at_ms: number;
          },
          [string]
        >(
          "SELECT session_id,target_id,object_id,pointer_id,target_revision,frame_id,pixel_x,pixel_y,source,status,seeded_at_ms FROM active_targets WHERE session_id = ?1 AND status = 'seeded'",
        )
        .get(claims.session_id);
      if (row === null) return null;
      return Object.freeze({
        sessionID: row.session_id,
        targetID: row.target_id,
        objectID: row.object_id,
        pointerID: row.pointer_id,
        targetRevision: row.target_revision,
        frameID: row.frame_id,
        pixelEncoded: [row.pixel_x, row.pixel_y] as const,
        source: row.source,
        status: row.status,
        seededAtMilliseconds: row.seeded_at_ms,
      });
    });
  }

  /** Floor-contact point from the most recent durable target seed's ARKit hit. */
  async authoritativeFloorContact(
    credential: string,
    expectedSessionID?: string,
  ): Promise<{ readonly x: number; readonly y: number; readonly z: number } | null> {
    return await this.#exclusive(async () => {
      const claims = this.#authorize(credential, "scene");
      if (expectedSessionID !== undefined && expectedSessionID !== claims.session_id) {
        throw new RoomCredentialError();
      }
      const row = this.#database
        .query<{ payload_json: string }, [string]>(
          "SELECT payload_json FROM capture_events WHERE session_id = ?1 AND event_type = 'target_seed' ORDER BY event_sequence DESC LIMIT 1",
        )
        .get(claims.session_id);
      if (row === null) return null;
      let payload: CoordinationEventPayload;
      try {
        payload = JSON.parse(row.payload_json) as CoordinationEventPayload;
      } catch {
        return null;
      }
      if (payload.type !== "target_seed" || payload.arkit_hit === null) return null;
      const [x, y, z] = payload.arkit_hit.position_world;
      if (![x, y, z].every((component) => Number.isFinite(component))) return null;
      return Object.freeze({ x, y, z });
    });
  }

  async deleteSession(credential: string, expectedSessionID?: string): Promise<void> {
    await this.#exclusive(async () => {
      const claims = this.#authorize(credential);
      if (expectedSessionID !== undefined && expectedSessionID !== claims.session_id) {
        throw new RoomCredentialError();
      }
      const directory = this.#sessionDirectory(claims.session_id);
      await rm(directory, { recursive: true, force: true });
      this.#database.exec("BEGIN IMMEDIATE");
      try {
        deleteSceneRows(this.#database, claims.session_id);
        this.#database
          .prepare("DELETE FROM capture_frames WHERE session_id = ?1")
          .run(claims.session_id);
        this.#database
          .prepare("DELETE FROM room_sessions WHERE session_id = ?1")
          .run(claims.session_id);
        this.#database.exec("COMMIT");
      } catch (error) {
        this.#database.exec("ROLLBACK");
        throw error;
      }
    });
  }

  async close(): Promise<void> {
    await this.#exclusive(async () => this.#database.close());
  }

  async #persistFrame(sessionID: string, packet: FramePacket): Promise<CaptureFrameReceipt> {
    const now = this.#now();
    assertTimestamp(now);
    const imageSHA256 = sha256(packet.image);
    const metadataJSON = canonicalJSONStringify(packet.metadata);
    const existing = this.#database
      .query<FrameRow, [string, number]>(
        "SELECT session_id, frame_id, image_sha256, image_bytes, accepted_at_ms, metadata_json FROM capture_frames WHERE session_id = ?1 AND frame_id = ?2",
      )
      .get(sessionID, packet.metadata.frame_id);
    if (existing !== null) {
      if (existing.image_sha256 !== imageSHA256 || existing.metadata_json !== metadataJSON) {
        throw new CaptureFrameConflictError();
      }
      await synchronizeFrameJournal(this.#database, this.#rfcapDirectory(sessionID), sessionID);
      return this.#receipt(existing, true);
    }
    const rfcapDirectory = this.#rfcapDirectory(sessionID);
    const framePath = join(
      rfcapDirectory,
      "frames",
      `${packet.metadata.frame_id.toString().padStart(12, "0")}.jpg`,
    );
    await writeBinaryAtomically(framePath, packet.image);
    const row: FrameRow = {
      session_id: sessionID,
      frame_id: packet.metadata.frame_id,
      image_sha256: imageSHA256,
      image_bytes: packet.image.byteLength,
      accepted_at_ms: now,
      metadata_json: metadataJSON,
    };
    this.#database.exec("BEGIN IMMEDIATE");
    try {
      this.#database
        .prepare(
          "INSERT INTO capture_frames (session_id, frame_id, image_sha256, image_bytes, accepted_at_ms, metadata_json) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        )
        .run(
          row.session_id,
          row.frame_id,
          row.image_sha256,
          row.image_bytes,
          row.accepted_at_ms,
          row.metadata_json,
        );
      this.#database.exec("COMMIT");
    } catch (error) {
      this.#database.exec("ROLLBACK");
      await rm(framePath, { force: true });
      throw error;
    }
    // The accepted SQLite row and frame bytes are recoverable before the RFCAP
    // projection is appended. A retried packet reconciles it if publication fails.
    await appendFrameJournal(rfcapDirectory, row);
    return this.#receipt(row, false);
  }

  #receipt(row: FrameRow, replayed: boolean): CaptureFrameReceipt {
    return Object.freeze({
      sessionID: row.session_id,
      frameID: row.frame_id,
      sha256: row.image_sha256,
      byteLength: row.image_bytes,
      acceptedAtMilliseconds: row.accepted_at_ms,
      replayed,
      rfcapDirectory: this.#rfcapDirectory(row.session_id),
    });
  }

  #authorize(credential: string, requiredPath?: string): RoomCredentialClaims {
    const claims = this.#verify(credential);
    if (requiredPath !== undefined && !claims.allowed_paths.includes(requiredPath)) {
      throw new RoomCredentialError();
    }
    const row = this.#database
      .query<SessionRow, [string]>(
        "SELECT session_id, nonce_sha256, expires_at_ms, deleted_at_ms FROM room_sessions WHERE session_id = ?1",
      )
      .get(claims.session_id);
    if (
      row === null ||
      row.deleted_at_ms !== null ||
      row.expires_at_ms <= this.#now() ||
      !safeEqual(row.nonce_sha256, sha256(claims.nonce))
    ) {
      throw new RoomCredentialError();
    }
    return claims;
  }

  #sign(claims: RoomCredentialClaims): string {
    const header = base64URL(canonicalJSONStringify(CREDENTIAL_HEADER));
    const payload = base64URL(canonicalJSONStringify(claims));
    const signed = `${header}.${payload}`;
    return `${signed}.${createHmac("sha256", this.#signingSecret).update(signed).digest("base64url")}`;
  }

  #verify(credential: string): RoomCredentialClaims {
    const parts = credential.split(".");
    if (parts.length !== 3 || !parts.every((part) => part.length > 0 && BASE64_URL.test(part))) {
      throw new RoomCredentialError();
    }
    const [header, payload, signature] = parts;
    if (header === undefined || payload === undefined || signature === undefined)
      throw new RoomCredentialError();
    const signed = `${header}.${payload}`;
    const expected = createHmac("sha256", this.#signingSecret).update(signed).digest("base64url");
    if (!safeEqual(signature, expected)) throw new RoomCredentialError();
    let parsed: unknown;
    try {
      parsed = JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
    } catch {
      throw new RoomCredentialError();
    }
    if (!isRoomCredentialClaims(parsed)) throw new RoomCredentialError();
    if (parsed.exp < Math.floor(this.#now() / 1_000)) throw new RoomCredentialError();
    return parsed;
  }

  #sessionDirectory(sessionID: string): string {
    const path = resolve(this.#sessionsDirectory, sessionID);
    if (relative(this.#sessionsDirectory, path).startsWith("..")) throw new RoomCredentialError();
    return path;
  }

  #rfcapDirectory(sessionID: string): string {
    return join(this.#sessionDirectory(sessionID), "session.rfcap");
  }

  async #exclusive<T>(operation: () => Promise<T>): Promise<T> {
    let release: (() => void) | undefined;
    const next = new Promise<void>((resolve) => {
      release = resolve;
    });
    const previous = this.#serial;
    this.#serial = previous.then(
      () => next,
      () => next,
    );
    await previous;
    try {
      return await operation();
    } finally {
      release?.();
    }
  }
}

function deleteSceneRows(database: Database, sessionID: string): void {
  for (const table of [
    "scene_transactions",
    "scene_previews",
    "scene_replacements",
    "scene_state",
    "active_targets",
  ] as const) {
    const exists = database
      .query<{ name: string }, [string]>(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?1",
      )
      .get(table);
    if (exists !== null)
      database.prepare(`DELETE FROM ${table} WHERE session_id = ?1`).run(sessionID);
  }
}

export async function createDurableRoomSessionStore(
  options: CreateDurableRoomSessionStoreOptions,
): Promise<DurableRoomSessionStore> {
  if (!isAbsolute(options.dataDirectory)) throw new Error("invalid_reframe_data_dir");
  if (options.signingSecret.length < 32 || options.signingSecret.length > 512) {
    throw new Error("invalid_room_signing_secret");
  }
  const dataDirectory = resolve(options.dataDirectory);
  const sessionsDirectory = resolve(dataDirectory, SESSION_DIRECTORY);
  if (relative(dataDirectory, sessionsDirectory).startsWith("..")) {
    throw new Error("invalid_reframe_data_dir");
  }
  await mkdir(sessionsDirectory, { recursive: true });
  const database = new Database(join(sessionsDirectory, DATABASE_NAME), {
    create: true,
    strict: true,
  });
  database.exec("PRAGMA journal_mode = WAL;");
  database.exec("PRAGMA synchronous = FULL;");
  database.exec("PRAGMA foreign_keys = ON;");
  database.exec(`
    CREATE TABLE IF NOT EXISTS room_sessions (
      session_id TEXT PRIMARY KEY,
      nonce_sha256 TEXT NOT NULL,
      expires_at_ms INTEGER NOT NULL,
      created_at_ms INTEGER NOT NULL,
      deleted_at_ms INTEGER
    ) STRICT;
    CREATE TABLE IF NOT EXISTS capture_frames (
      session_id TEXT NOT NULL REFERENCES room_sessions(session_id) ON DELETE CASCADE,
      frame_id INTEGER NOT NULL,
      image_sha256 TEXT NOT NULL,
      image_bytes INTEGER NOT NULL,
      accepted_at_ms INTEGER NOT NULL,
      metadata_json TEXT NOT NULL,
      PRIMARY KEY (session_id, frame_id)
    ) STRICT;
    CREATE INDEX IF NOT EXISTS capture_frames_recent ON capture_frames (session_id, accepted_at_ms DESC);
    CREATE TABLE IF NOT EXISTS capture_artifacts (
      session_id TEXT NOT NULL REFERENCES room_sessions(session_id) ON DELETE CASCADE,
      artifact_id TEXT NOT NULL,
      artifact_sha256 TEXT NOT NULL,
      artifact_bytes INTEGER NOT NULL,
      content_type TEXT NOT NULL,
      accepted_at_ms INTEGER NOT NULL,
      PRIMARY KEY (session_id, artifact_id)
    ) STRICT;
    CREATE TABLE IF NOT EXISTS capture_events (
      session_id TEXT NOT NULL REFERENCES room_sessions(session_id) ON DELETE CASCADE,
      event_id TEXT NOT NULL,
      event_sequence INTEGER NOT NULL,
      monotonic_timestamp_ns TEXT NOT NULL,
      event_type TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      payload_sha256 TEXT NOT NULL,
      accepted_at_ms INTEGER NOT NULL,
      PRIMARY KEY (session_id, event_id),
      UNIQUE (session_id, event_sequence)
    ) STRICT;
    CREATE TABLE IF NOT EXISTS active_targets (
      session_id TEXT PRIMARY KEY REFERENCES room_sessions(session_id) ON DELETE CASCADE,
      target_id TEXT NOT NULL,
      object_id TEXT NOT NULL,
      pointer_id TEXT NOT NULL,
      target_revision INTEGER NOT NULL,
      frame_id INTEGER NOT NULL,
      pixel_x REAL NOT NULL,
      pixel_y REAL NOT NULL,
      source TEXT NOT NULL,
      status TEXT NOT NULL CHECK (status IN ('seeded','closed')),
      seeded_at_ms INTEGER NOT NULL
    ) STRICT;
  `);
  return new DurableRoomSessionStore({
    database,
    sessionsDirectory,
    signingSecret: new TextEncoder().encode(options.signingSecret),
    now: options.nowMilliseconds ?? Date.now,
  });
}

function validateCoordinationEvent(
  database: Database,
  sessionID: string,
  event: CaptureEventInput,
): void {
  if (
    event.type !== "target_seed" &&
    event.type !== "plane_upsert" &&
    event.type !== "plane_remove"
  ) {
    return;
  }
  const payload = event.payload as CoordinationEventPayload;
  if (payload.session_id !== sessionID) throw new TypeError("invalid_capture_event");
  if (payload.type !== "target_seed") return;

  const frame = database
    .query<{ metadata_json: string }, [string, number]>(
      "SELECT metadata_json FROM capture_frames WHERE session_id = ?1 AND frame_id = ?2",
    )
    .get(sessionID, payload.frame_id);
  if (frame === null) throw new TypeError("invalid_capture_event");
  const metadata = JSON.parse(frame.metadata_json) as FramePacket["metadata"];
  const [pixelX, pixelY] = payload.pixel_encoded;
  if (
    pixelX < 0 ||
    pixelY < 0 ||
    pixelX >= metadata.image.width ||
    pixelY >= metadata.image.height
  ) {
    throw new TypeError("invalid_capture_event");
  }
}

async function synchronizeFrameJournal(
  database: Database,
  rfcapDirectory: string,
  sessionID: string,
): Promise<void> {
  const rows = database
    .query<FrameRow, [string]>(
      "SELECT session_id, frame_id, image_sha256, image_bytes, accepted_at_ms, metadata_json FROM capture_frames WHERE session_id = ?1 ORDER BY frame_id",
    )
    .all(sessionID);
  const lines = rows.map(frameJournalLine).join("\n");
  await writeAtomically(
    join(rfcapDirectory, "frames.jsonl"),
    lines.length === 0 ? "" : `${lines}\n`,
  );
}

async function appendFrameJournal(rfcapDirectory: string, row: FrameRow): Promise<void> {
  const handle = await open(join(rfcapDirectory, "frames.jsonl"), "a", 0o600);
  try {
    await handle.writeFile(`${frameJournalLine(row)}\n`);
    await handle.sync();
  } finally {
    await handle.close();
  }
}

function frameJournalLine(row: FrameRow): string {
  return canonicalJSONStringify({
    frame_id: row.frame_id,
    image_sha256: row.image_sha256,
    image_bytes: row.image_bytes,
    accepted_at_ms: row.accepted_at_ms,
    metadata_sha256: canonicalJSONSHA256(JSON.parse(row.metadata_json)),
    metadata: JSON.parse(row.metadata_json),
  });
}

function artifactReceipt(row: ArtifactRow, replayed: boolean): CaptureArtifactReceipt {
  return Object.freeze({
    sessionID: row.session_id,
    artifactID: row.artifact_id,
    sha256: row.artifact_sha256,
    byteLength: row.artifact_bytes,
    contentType: row.content_type,
    acceptedAtMilliseconds: row.accepted_at_ms,
    replayed,
  });
}

function eventReceipt(row: EventRow, replayed: boolean): CaptureEventReceipt {
  return Object.freeze({
    ...(JSON.parse(
      canonicalJSONStringify({
        event_id: row.event_id,
        event_sequence: row.event_sequence,
        monotonic_timestamp_ns: row.monotonic_timestamp_ns,
        type: row.event_type,
        payload: JSON.parse(row.payload_json),
      }),
    ) as CaptureEventInput),
    sessionID: row.session_id,
    payloadSha256: row.payload_sha256,
    acceptedAtMilliseconds: row.accepted_at_ms,
    replayed,
  });
}

async function synchronizeEventJournal(
  database: Database,
  rfcapDirectory: string,
  sessionID: string,
): Promise<void> {
  const rows = database
    .query<EventRow, [string]>(
      "SELECT session_id, event_id, event_sequence, monotonic_timestamp_ns, event_type, payload_json, payload_sha256, accepted_at_ms FROM capture_events WHERE session_id = ?1 ORDER BY event_sequence",
    )
    .all(sessionID);
  const lines = rows.map(eventJournalLine).join("\n");
  await writeAtomically(
    join(rfcapDirectory, "events", "events.jsonl"),
    lines.length === 0 ? "" : `${lines}\n`,
  );
}

function eventJournalLine(row: EventRow): string {
  return canonicalJSONStringify({
    event_id: row.event_id,
    event_sequence: row.event_sequence,
    monotonic_timestamp_ns: row.monotonic_timestamp_ns,
    type: row.event_type,
    payload: JSON.parse(row.payload_json),
    payload_sha256: row.payload_sha256,
    accepted_at_ms: row.accepted_at_ms,
  });
}

async function writeBinaryAtomically(path: string, bytes: Uint8Array): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
  const temporary = `${path}.${randomUUID()}.tmp`;
  try {
    const handle = await open(temporary, "wx", 0o600);
    try {
      await handle.writeFile(bytes);
      await handle.sync();
    } finally {
      await handle.close();
    }
    await rename(temporary, path);
  } catch (error) {
    await rm(temporary, { force: true });
    throw error;
  }
}

async function writeAtomically(path: string, text: string): Promise<void> {
  await writeBinaryAtomically(path, new TextEncoder().encode(text));
}

function assertRoomID(value: string): void {
  if (!isRoomSessionID(value)) throw new Error("invalid_room_id");
}

function assertArtifactID(value: string): void {
  if (!ARTIFACT_ID.test(value)) throw new CaptureArtifactConflictError();
}

function assertContentType(value: string): void {
  if (
    value.length === 0 ||
    value.length > 160 ||
    !/^[a-z0-9!#$%&'*+.^_`|~-]+\/[a-z0-9!#$%&'*+.^_`|~-]+(?:\s*;\s*[a-z0-9-]+=[^;\s]+)*$/iu.test(
      value,
    )
  ) {
    throw new CaptureArtifactConflictError();
  }
}

function assertTimestamp(value: number): void {
  if (!Number.isSafeInteger(value) || value < 0) throw new Error("invalid_timestamp");
}

function normalizeAllowedPaths(value: readonly string[]): string[] {
  if (
    value.length === 0 ||
    value.length > 4 ||
    value.some((path) => !ALLOWED_PATH.test(path)) ||
    new Set(value).size !== value.length
  ) {
    throw new RoomCredentialError();
  }
  return [...value].sort();
}

function isRoomCredentialClaims(value: unknown): value is RoomCredentialClaims {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
  const claims = value as Record<string, unknown>;
  return (
    Object.keys(claims).length === 6 &&
    claims.version === 1 &&
    typeof claims.session_id === "string" &&
    isRoomSessionID(claims.session_id) &&
    claims.role === "editor" &&
    Array.isArray(claims.allowed_paths) &&
    normalizeAllowedPathsSafely(claims.allowed_paths) &&
    Number.isSafeInteger(claims.exp) &&
    typeof claims.nonce === "string" &&
    /^[0-9a-f-]{36}$/u.test(claims.nonce)
  );
}

function normalizeAllowedPathsSafely(value: unknown[]): boolean {
  try {
    normalizeAllowedPaths(value.filter((entry): entry is string => typeof entry === "string"));
    return value.every((entry) => typeof entry === "string");
  } catch {
    return false;
  }
}

function base64URL(value: string): string {
  return Buffer.from(value, "utf8").toString("base64url");
}

function sha256(value: string | Uint8Array): string {
  return createHash("sha256").update(value).digest("hex");
}

function safeEqual(left: string, right: string): boolean {
  const leftBytes = Buffer.from(left, "utf8");
  const rightBytes = Buffer.from(right, "utf8");
  return leftBytes.length === rightBytes.length && timingSafeEqual(leftBytes, rightBytes);
}
