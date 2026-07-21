import { Database } from "bun:sqlite";
import { createHash, createHmac, randomUUID, timingSafeEqual } from "node:crypto";
import { mkdir, open, readFile, rename, rm } from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";

import {
  canonicalJSONSHA256,
  canonicalJSONStringify,
  type FramePacket,
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
const ALLOWED_PATH = /^(?:frames|events|artifacts)$/u;

export interface CreateDurableRoomSessionStoreOptions {
  readonly dataDirectory: string;
  /** Server-only HMAC secret; it is never serialized or returned by this store. */
  readonly signingSecret: string;
  readonly nowMilliseconds?: () => number;
}

export interface CreateRoomSessionInput {
  readonly sessionID: string;
  readonly expiresAtMilliseconds: number;
  readonly allowedPaths: readonly ("frames" | "events" | "artifacts")[];
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
  `);
  return new DurableRoomSessionStore({
    database,
    sessionsDirectory,
    signingSecret: new TextEncoder().encode(options.signingSecret),
    now: options.nowMilliseconds ?? Date.now,
  });
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
    value.length > 3 ||
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
