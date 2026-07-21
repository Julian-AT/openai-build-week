import { randomUUID, timingSafeEqual } from "node:crypto";

import type { RealtimeSessionService } from "@reframe/agent";
import { parseCaptureEvent } from "@reframe/protocol";
import { type Context, Hono } from "hono";

import { type AgentTurnService, parseAgentTurnRequest } from "./agent-turn.ts";
import {
  CaptureArtifactConflictError,
  CaptureArtifactNotFoundError,
  CaptureEventConflictError,
  CaptureFrameConflictError,
  type DurableRoomSessionStore,
  isRoomSessionID,
  RoomCredentialError,
} from "./durable-session-store.ts";
import {
  type EditTransactionService,
  IdempotencyConflictError,
  RevisionConflictError,
  SessionCredentialError,
  TransactionConflictError,
  TransactionNotFoundError,
} from "./edit-transaction-service.ts";
import { type InferenceService, InferenceWorkerError } from "./inference-client.ts";
import { parseInferenceJobRequest } from "./inference-protocol.ts";
import { ProtocolError } from "./protocol.ts";
import { parseJSONBytesStrict } from "./strict-json.ts";

export const MAX_REQUEST_BYTES = 2_500_000;

export interface GatewayAppOptions {
  gatewayToken: string;
  runtimeReadiness?: GatewayRuntimeReadiness;
  realtimeService?: RealtimeSessionService;
  inferenceService?: InferenceService;
  editTransactionService?: EditTransactionService;
  agentTurnService?: AgentTurnService;
  durableSessionStore?: DurableRoomSessionStore;
  logger?: (record: GatewayLogRecord) => void;
  requestID?: () => string;
  nowMilliseconds?: () => number;
  requestTimeoutMilliseconds?: number;
  protectedRequestsPerMinute?: number;
}

export interface GatewayRuntimeReadiness {
  snapshot(): Promise<GatewayRuntimeSnapshot>;
}

export interface GatewayRuntimeSnapshot {
  status: "ok" | "degraded";
  dependencies: {
    gateway: GatewayRuntimeDependency;
    catalog_store: GatewayRuntimeDependency;
    asset_storage: GatewayRuntimeDependency;
    qdrant: GatewayRuntimeDependency;
  };
}

export interface GatewayRuntimeDependency {
  status: "ready" | "unavailable";
}

export interface GatewayLogRecord {
  request_id: string;
  method: string;
  path: string;
  status: number;
  duration_ms: number;
}

export function createGatewayApp(options: GatewayAppOptions): Hono {
  const app = new Hono();
  const protectedRateLimit = new FixedWindowRateLimit(
    options.protectedRequestsPerMinute,
    options.nowMilliseconds,
  );

  app.use("*", async (context, next) => {
    const url = new URL(context.req.url);
    const requestID = (options.requestID ?? randomUUID)();
    const nowMilliseconds = options.nowMilliseconds ?? Date.now;
    const startedAt = nowMilliseconds();

    context.header("x-request-id", requestID);
    context.header("cache-control", "no-store");
    context.header("x-content-type-options", "nosniff");
    context.header("referrer-policy", "no-referrer");

    if (url.search !== "") {
      context.res = context.json({ error: "not_found" }, 404);
    } else {
      await next();
    }

    try {
      options.logger?.({
        request_id: requestID,
        method: context.req.method || "UNKNOWN",
        path: safeLogPath(url.pathname),
        status: context.res.status,
        duration_ms: Math.max(0, nowMilliseconds() - startedAt),
      });
    } catch {
      // Logging is deliberately unable to change the public response.
    }
  });

  app.use("/v1/*", async (context, next) => {
    const admission = protectedRateLimit.admit();
    if (!admission.allowed) {
      context.header("retry-after", admission.retryAfterSeconds.toString());
      return context.json({ error: "rate_limited" }, 429);
    }
    await next();
  });

  app.get("/health", async (context) => {
    if (options.runtimeReadiness === undefined) return context.json({ status: "ok" });
    return context.json(await options.runtimeReadiness.snapshot());
  });

  app.post("/v1/realtime/calls", async (context) => {
    const rejection = authorizeSDPRequest(context, options.gatewayToken);
    if (rejection !== undefined) return rejection;
    return handleRealtimeSecret(context, options);
  });

  app.get("/v1/inference/status", async (context) => {
    const rejection = authorizeBearerRequest(context, options.gatewayToken);
    if (rejection !== undefined) return rejection;
    return handleInferenceReadiness(context, options);
  });

  app.post("/v1/inference/jobs", async (context) => {
    const rejection = authorizeJSONRequest(context, options.gatewayToken);
    if (rejection !== undefined) return rejection;
    return handleInferenceJob(context, options);
  });

  app.post("/v1/sessions", async (context) => handleSessionCreate(context, options));
  app.post("/v1/sessions/:sessionID/frames", async (context) =>
    handleFrameIngest(context, options),
  );
  app.post("/v1/sessions/:sessionID/artifacts/:artifactID", async (context) =>
    handleArtifactUpload(context, options),
  );
  app.get("/v1/sessions/:sessionID/artifacts/:artifactID", async (context) =>
    handleArtifactDownload(context, options),
  );
  app.post("/v1/sessions/:sessionID/events", async (context) =>
    handleEventIngest(context, options),
  );
  app.get("/v1/sessions/:sessionID/events", async (context) =>
    handleRecentEvents(context, options),
  );
  app.get("/v1/sessions/:sessionID/frames/recent", async (context) =>
    handleRecentFrames(context, options),
  );
  app.delete("/v1/sessions/:sessionID", async (context) => handleSessionDeletion(context, options));

  app.post("/v1/edit/previews", async (context) => handleEditPreview(context, options));
  app.post("/v1/edit/confirmations", async (context) => handleEditConfirmation(context, options));
  app.post("/v1/edit/restores", async (context) => handleEditRestore(context, options));
  app.post("/v1/turns", async (context) => handleAgentTurn(context, options));

  app.all("/health", (context) => methodNotAllowed(context, "GET"));
  app.all("/v1/realtime/calls", (context) => methodNotAllowed(context, "POST"));
  app.all("/v1/inference/status", (context) => methodNotAllowed(context, "GET"));
  app.all("/v1/inference/jobs", (context) => methodNotAllowed(context, "POST"));
  app.all("/v1/sessions", (context) => methodNotAllowed(context, "POST"));
  app.all("/v1/sessions/:sessionID/frames", (context) => methodNotAllowed(context, "POST"));
  app.all("/v1/sessions/:sessionID/artifacts/:artifactID", (context) =>
    methodNotAllowed(context, "GET, POST"),
  );
  app.all("/v1/sessions/:sessionID/events", (context) => methodNotAllowed(context, "GET, POST"));
  app.all("/v1/sessions/:sessionID/frames/recent", (context) => methodNotAllowed(context, "GET"));
  app.all("/v1/sessions/:sessionID", (context) => methodNotAllowed(context, "DELETE"));
  app.all("/v1/edit/previews", (context) => methodNotAllowed(context, "POST"));
  app.all("/v1/edit/confirmations", (context) => methodNotAllowed(context, "POST"));
  app.all("/v1/edit/restores", (context) => methodNotAllowed(context, "POST"));
  app.all("/v1/turns", (context) => methodNotAllowed(context, "POST"));
  app.notFound((context) => context.json({ error: "not_found" }, 404));
  app.onError((_error, context) => context.json({ error: "internal_failure" }, 500));

  return app;
}

function authorizeJSONRequest(context: Context, gatewayToken: string): Response | undefined {
  const bearerRejection = authorizeBearerRequest(context, gatewayToken);
  if (bearerRejection !== undefined) return bearerRejection;
  if (!hasJSONContentType(context.req.header("content-type"))) {
    return context.json({ error: "unsupported_media_type" }, 415);
  }
  return undefined;
}

function authorizeSDPRequest(context: Context, gatewayToken: string): Response | undefined {
  const bearerRejection = authorizeBearerRequest(context, gatewayToken);
  if (bearerRejection !== undefined) return bearerRejection;
  if (context.req.header("content-type")?.split(";", 1)[0]?.trim() !== "application/sdp") {
    return context.json({ error: "unsupported_media_type" }, 415);
  }
  return undefined;
}

function authorizeBearerRequest(context: Context, gatewayToken: string): Response | undefined {
  if (!hasValidBearer(context.req.header("authorization"), gatewayToken)) {
    return context.json({ error: "unauthorized" }, 401);
  }
  return undefined;
}

async function handleRealtimeSecret(
  context: Context,
  options: GatewayAppOptions,
): Promise<Response> {
  if (!options.realtimeService) {
    return context.json({ error: "service_unavailable" }, 503);
  }

  const deadline = createDeadline(context.req.raw, options.requestTimeoutMilliseconds);
  try {
    const offer = await abortable(readText(context.req.raw), deadline.signal);
    const answer = await abortable(
      options.realtimeService.exchange(offer, deadline.signal),
      deadline.signal,
    );
    return context.body(answer, 200, { "content-type": "application/sdp; charset=UTF-8" });
  } catch (error) {
    if (deadline.didTimeout()) {
      return context.json({ error: "upstream_timeout" }, 504);
    }
    if (error instanceof BodyTooLargeError) {
      return context.json({ error: "payload_too_large" }, 413);
    }
    if (error instanceof SyntaxError) {
      return context.json({ error: "invalid_request" }, 400);
    }
    return context.json({ error: "upstream_failure" }, 502);
  } finally {
    deadline.dispose();
  }
}

async function handleInferenceReadiness(
  context: Context,
  options: GatewayAppOptions,
): Promise<Response> {
  if (!options.inferenceService) {
    return context.json({ error: "service_unavailable" }, 503);
  }
  const deadline = createDeadline(context.req.raw, options.requestTimeoutMilliseconds);
  try {
    const result = await abortable(
      options.inferenceService.readiness(deadline.signal),
      deadline.signal,
    );
    return context.json(result);
  } catch (error) {
    return inferenceFailureResponse(context, error, deadline.didTimeout());
  } finally {
    deadline.dispose();
  }
}

async function handleInferenceJob(context: Context, options: GatewayAppOptions): Promise<Response> {
  if (!options.inferenceService) {
    return context.json({ error: "service_unavailable" }, 503);
  }
  const deadline = createDeadline(context.req.raw, options.requestTimeoutMilliseconds);
  try {
    const body = await abortable(readJSON(context.req.raw), deadline.signal);
    const request = parseInferenceJobRequest(body);
    const result = await abortable(
      options.inferenceService.run(request, deadline.signal),
      deadline.signal,
    );
    return context.json(result);
  } catch (error) {
    if (error instanceof BodyTooLargeError) {
      return context.json({ error: "payload_too_large" }, 413);
    }
    if (error instanceof ProtocolError || error instanceof SyntaxError) {
      return context.json({ error: "invalid_request" }, 400);
    }
    return inferenceFailureResponse(context, error, deadline.didTimeout());
  } finally {
    deadline.dispose();
  }
}

async function handleSessionCreate(
  context: Context,
  options: GatewayAppOptions,
): Promise<Response> {
  const rejection = authorizeJSONRequest(context, options.gatewayToken);
  if (rejection !== undefined) return rejection;
  if (!options.durableSessionStore) {
    return context.json({ error: "service_unavailable" }, 503);
  }
  try {
    const input = parseSessionCreateRequest(await readJSON(context.req.raw));
    const created = await options.durableSessionStore.createSession(input);
    return context.json(
      {
        session_id: created.sessionID,
        credential: created.credential,
        expires_at_ms: created.expiresAtMilliseconds,
      },
      201,
    );
  } catch (error) {
    if (error instanceof BodyTooLargeError)
      return context.json({ error: "payload_too_large" }, 413);
    if (
      error instanceof SyntaxError ||
      error instanceof TypeError ||
      error instanceof ProtocolError
    ) {
      return context.json({ error: "invalid_request" }, 400);
    }
    if (error instanceof RoomCredentialError)
      return context.json({ error: "invalid_request" }, 400);
    return context.json({ error: "internal_failure" }, 500);
  }
}

async function handleFrameIngest(context: Context, options: GatewayAppOptions): Promise<Response> {
  if (!options.durableSessionStore) {
    return context.json({ error: "service_unavailable" }, 503);
  }
  const sessionID = context.req.param("sessionID");
  if (typeof sessionID !== "string" || !isRoomSessionID(sessionID)) {
    return context.json({ error: "not_found" }, 404);
  }
  const credential = authorizeRoomFrameRequest(context);
  if (credential instanceof Response) return credential;
  try {
    const receipt = await options.durableSessionStore.acceptFrame({
      credential,
      bytes: await readBinary(context.req.raw),
      expectedSessionID: sessionID,
    });
    return context.json(
      {
        session_id: receipt.sessionID,
        frame_id: receipt.frameID,
        sha256: receipt.sha256,
        byte_length: receipt.byteLength,
        accepted_at_ms: receipt.acceptedAtMilliseconds,
        replayed: receipt.replayed,
      },
      receipt.replayed ? 200 : 202,
    );
  } catch (error) {
    if (error instanceof BodyTooLargeError)
      return context.json({ error: "payload_too_large" }, 413);
    if (error instanceof RoomCredentialError) return context.json({ error: "unauthorized" }, 401);
    if (error instanceof CaptureFrameConflictError) {
      return context.json({ error: "frame_conflict" }, 409);
    }
    if (
      error instanceof ProtocolError ||
      error instanceof SyntaxError ||
      error instanceof TypeError
    ) {
      return context.json({ error: "invalid_request" }, 400);
    }
    return context.json({ error: "internal_failure" }, 500);
  }
}

async function handleRecentFrames(context: Context, options: GatewayAppOptions): Promise<Response> {
  if (!options.durableSessionStore) {
    return context.json({ error: "service_unavailable" }, 503);
  }
  const sessionID = context.req.param("sessionID");
  if (typeof sessionID !== "string" || !isRoomSessionID(sessionID)) {
    return context.json({ error: "not_found" }, 404);
  }
  const credential = authorizeRoomCredential(context);
  if (credential instanceof Response) return credential;
  try {
    const frames = await options.durableSessionStore.recentFrames(credential, sessionID);
    return context.json({
      frames: frames.map((frame) => ({
        session_id: frame.sessionID,
        frame_id: frame.frameID,
        sha256: frame.sha256,
        byte_length: frame.byteLength,
        accepted_at_ms: frame.acceptedAtMilliseconds,
      })),
    });
  } catch (error) {
    if (error instanceof RoomCredentialError) return context.json({ error: "unauthorized" }, 401);
    return context.json({ error: "internal_failure" }, 500);
  }
}

async function handleArtifactUpload(
  context: Context,
  options: GatewayAppOptions,
): Promise<Response> {
  if (!options.durableSessionStore) return context.json({ error: "service_unavailable" }, 503);
  const sessionID = context.req.param("sessionID");
  const artifactID = context.req.param("artifactID");
  if (
    typeof sessionID !== "string" ||
    !isRoomSessionID(sessionID) ||
    typeof artifactID !== "string"
  ) {
    return context.json({ error: "not_found" }, 404);
  }
  const credential = authorizeRoomCredential(context);
  if (credential instanceof Response) return credential;
  const contentType = context.req.header("content-type")?.split(";", 1)[0]?.trim();
  if (contentType === undefined || contentType.length === 0) {
    return context.json({ error: "unsupported_media_type" }, 415);
  }
  try {
    const receipt = await options.durableSessionStore.acceptArtifact({
      credential,
      artifactID,
      bytes: await readBinary(context.req.raw),
      contentType,
      expectedSessionID: sessionID,
    });
    return context.json(
      {
        session_id: receipt.sessionID,
        artifact_id: receipt.artifactID,
        sha256: receipt.sha256,
        byte_length: receipt.byteLength,
        content_type: receipt.contentType,
        accepted_at_ms: receipt.acceptedAtMilliseconds,
        replayed: receipt.replayed,
      },
      receipt.replayed ? 200 : 202,
    );
  } catch (error) {
    if (error instanceof BodyTooLargeError)
      return context.json({ error: "payload_too_large" }, 413);
    if (error instanceof RoomCredentialError) return context.json({ error: "unauthorized" }, 401);
    if (error instanceof CaptureArtifactConflictError) {
      return context.json({ error: "artifact_conflict" }, 409);
    }
    return context.json({ error: "internal_failure" }, 500);
  }
}

async function handleArtifactDownload(
  context: Context,
  options: GatewayAppOptions,
): Promise<Response> {
  if (!options.durableSessionStore) return context.json({ error: "service_unavailable" }, 503);
  const sessionID = context.req.param("sessionID");
  const artifactID = context.req.param("artifactID");
  if (
    typeof sessionID !== "string" ||
    !isRoomSessionID(sessionID) ||
    typeof artifactID !== "string"
  ) {
    return context.json({ error: "not_found" }, 404);
  }
  const credential = authorizeRoomCredential(context);
  if (credential instanceof Response) return credential;
  try {
    const result = await options.durableSessionStore.readArtifact({
      credential,
      artifactID,
      expectedSessionID: sessionID,
    });
    const body = result.bytes.slice().buffer as ArrayBuffer;
    return new Response(body, {
      status: 200,
      headers: {
        "content-type": result.receipt.contentType,
        "content-length": result.receipt.byteLength.toString(),
        etag: `"${result.receipt.sha256}"`,
        "x-content-sha256": result.receipt.sha256,
        "cache-control": "private, no-store",
      },
    });
  } catch (error) {
    if (error instanceof RoomCredentialError) return context.json({ error: "unauthorized" }, 401);
    if (
      error instanceof CaptureArtifactNotFoundError ||
      error instanceof CaptureArtifactConflictError
    )
      return context.json({ error: "not_found" }, 404);
    return context.json({ error: "internal_failure" }, 500);
  }
}

async function handleEventIngest(context: Context, options: GatewayAppOptions): Promise<Response> {
  if (!options.durableSessionStore) return context.json({ error: "service_unavailable" }, 503);
  const sessionID = context.req.param("sessionID");
  if (typeof sessionID !== "string" || !isRoomSessionID(sessionID)) {
    return context.json({ error: "not_found" }, 404);
  }
  const credential = authorizeRoomCredential(context);
  if (credential instanceof Response) return credential;
  if (!hasJSONContentType(context.req.header("content-type"))) {
    return context.json({ error: "unsupported_media_type" }, 415);
  }
  try {
    const event = parseCaptureEvent(await readJSON(context.req.raw));
    const receipt = await options.durableSessionStore.acceptEvent({
      credential,
      event,
      expectedSessionID: sessionID,
    });
    return context.json(
      {
        session_id: receipt.sessionID,
        event_id: receipt.event_id,
        event_sequence: receipt.event_sequence,
        monotonic_timestamp_ns: receipt.monotonic_timestamp_ns,
        type: receipt.type,
        payload: receipt.payload,
        payload_sha256: receipt.payloadSha256,
        accepted_at_ms: receipt.acceptedAtMilliseconds,
        replayed: receipt.replayed,
      },
      receipt.replayed ? 200 : 202,
    );
  } catch (error) {
    if (error instanceof BodyTooLargeError)
      return context.json({ error: "payload_too_large" }, 413);
    if (error instanceof RoomCredentialError) return context.json({ error: "unauthorized" }, 401);
    if (error instanceof SyntaxError || error instanceof TypeError)
      return context.json({ error: "invalid_request" }, 400);
    if (error instanceof CaptureEventConflictError)
      return context.json({ error: "event_conflict" }, 409);
    return context.json({ error: "internal_failure" }, 500);
  }
}

async function handleRecentEvents(context: Context, options: GatewayAppOptions): Promise<Response> {
  if (!options.durableSessionStore) return context.json({ error: "service_unavailable" }, 503);
  const sessionID = context.req.param("sessionID");
  if (typeof sessionID !== "string" || !isRoomSessionID(sessionID)) {
    return context.json({ error: "not_found" }, 404);
  }
  const credential = authorizeRoomCredential(context);
  if (credential instanceof Response) return credential;
  try {
    const events = await options.durableSessionStore.recentEvents(credential, sessionID);
    return context.json({
      events: events.map((event) => ({
        session_id: event.sessionID,
        event_id: event.event_id,
        event_sequence: event.event_sequence,
        monotonic_timestamp_ns: event.monotonic_timestamp_ns,
        type: event.type,
        payload: event.payload,
        payload_sha256: event.payloadSha256,
        accepted_at_ms: event.acceptedAtMilliseconds,
      })),
    });
  } catch (error) {
    if (error instanceof RoomCredentialError) return context.json({ error: "unauthorized" }, 401);
    return context.json({ error: "internal_failure" }, 500);
  }
}

async function handleSessionDeletion(
  context: Context,
  options: GatewayAppOptions,
): Promise<Response> {
  if (!options.durableSessionStore) {
    return context.json({ error: "service_unavailable" }, 503);
  }
  const sessionID = context.req.param("sessionID");
  if (typeof sessionID !== "string" || !isRoomSessionID(sessionID)) {
    return context.json({ error: "not_found" }, 404);
  }
  const credential = authorizeRoomCredential(context);
  if (credential instanceof Response) return credential;
  try {
    await options.durableSessionStore.deleteSession(credential, sessionID);
    return new Response(null, { status: 204 });
  } catch (error) {
    if (error instanceof RoomCredentialError) return context.json({ error: "unauthorized" }, 401);
    return context.json({ error: "internal_failure" }, 500);
  }
}

async function handleEditPreview(context: Context, options: GatewayAppOptions): Promise<Response> {
  const credential = authorizeScopedJSONRequest(context);
  if (credential instanceof Response) return credential;
  if (!options.editTransactionService) {
    return context.json({ error: "service_unavailable" }, 503);
  }
  try {
    const request = parseEditPreviewRequest(await readJSON(context.req.raw));
    const result = await options.editTransactionService.prepareReplacementPreview(
      credential,
      request.proposalID,
    );
    return context.json(result);
  } catch (error) {
    return editFailureResponse(context, error);
  }
}

async function handleEditConfirmation(
  context: Context,
  options: GatewayAppOptions,
): Promise<Response> {
  const credential = authorizeScopedJSONRequest(context);
  if (credential instanceof Response) return credential;
  if (!options.editTransactionService) {
    return context.json({ error: "service_unavailable" }, 503);
  }
  try {
    const request = parseEditConfirmationRequest(await readJSON(context.req.raw));
    const result = await options.editTransactionService.confirmPreview(credential, request);
    return context.json(result);
  } catch (error) {
    return editFailureResponse(context, error);
  }
}

async function handleEditRestore(context: Context, options: GatewayAppOptions): Promise<Response> {
  const credential = authorizeScopedJSONRequest(context);
  if (credential instanceof Response) return credential;
  if (!options.editTransactionService) {
    return context.json({ error: "service_unavailable" }, 503);
  }
  try {
    const request = parseEditRestoreRequest(await readJSON(context.req.raw));
    const result = await options.editTransactionService.restore(credential, request);
    return context.json(result);
  } catch (error) {
    return editFailureResponse(context, error);
  }
}

async function handleAgentTurn(context: Context, options: GatewayAppOptions): Promise<Response> {
  const credential = authorizeScopedJSONRequest(context);
  if (credential instanceof Response) return credential;
  if (!options.agentTurnService) {
    return context.json({ error: "service_unavailable" }, 503);
  }

  const deadline = createDeadline(context.req.raw, options.requestTimeoutMilliseconds);
  try {
    const body = await abortable(readJSON(context.req.raw), deadline.signal);
    const turn = parseAgentTurnRequest(body);
    const result = await abortable(
      options.agentTurnService.submit(credential, turn, deadline.signal),
      deadline.signal,
    );
    return context.json(result);
  } catch (error) {
    if (deadline.didTimeout()) {
      return context.json({ error: "upstream_timeout" }, 504);
    }
    if (error instanceof BodyTooLargeError) {
      return context.json({ error: "payload_too_large" }, 413);
    }
    if (error instanceof ProtocolError || error instanceof SyntaxError) {
      return context.json({ error: "invalid_request" }, 400);
    }
    if (error instanceof SessionCredentialError) {
      return context.json({ error: "unauthorized" }, 401);
    }
    return context.json({ error: "upstream_failure" }, 502);
  } finally {
    deadline.dispose();
  }
}

function authorizeScopedJSONRequest(context: Context): string | Response {
  const authorization = context.req.header("authorization");
  if (!authorization?.startsWith("Bearer ") || authorization.length <= "Bearer ".length) {
    return context.json({ error: "unauthorized" }, 401);
  }
  if (!hasJSONContentType(context.req.header("content-type"))) {
    return context.json({ error: "unsupported_media_type" }, 415);
  }
  return authorization.slice("Bearer ".length);
}

function authorizeRoomFrameRequest(context: Context): string | Response {
  const credential = authorizeRoomCredential(context);
  if (credential instanceof Response) return credential;
  if (
    context.req.header("content-type")?.split(";", 1)[0]?.trim().toLowerCase() !==
    "application/vnd.reframe.framepacket"
  ) {
    return context.json({ error: "unsupported_media_type" }, 415);
  }
  return credential;
}

function authorizeRoomCredential(context: Context): string | Response {
  const authorization = context.req.header("authorization");
  if (!authorization?.startsWith("Bearer ") || authorization.length <= "Bearer ".length) {
    return context.json({ error: "unauthorized" }, 401);
  }
  return authorization.slice("Bearer ".length);
}

function editFailureResponse(context: Context, error: unknown): Response {
  if (error instanceof BodyTooLargeError) {
    return context.json({ error: "payload_too_large" }, 413);
  }
  if (
    error instanceof SyntaxError ||
    error instanceof TypeError ||
    error instanceof ProtocolError
  ) {
    return context.json({ error: "invalid_request" }, 400);
  }
  if (error instanceof SessionCredentialError || error instanceof RoomCredentialError) {
    return context.json({ error: "unauthorized" }, 401);
  }
  if (error instanceof TransactionNotFoundError) {
    return context.json({ error: "not_found" }, 404);
  }
  if (error instanceof RevisionConflictError) {
    return context.json({ error: "revision_conflict", scene_revision: error.actualRevision }, 409);
  }
  if (error instanceof IdempotencyConflictError) {
    return context.json({ error: "idempotency_conflict" }, 409);
  }
  if (error instanceof TransactionConflictError) {
    return context.json({ error: "transaction_conflict" }, 409);
  }
  return context.json({ error: "internal_failure" }, 500);
}

function parseEditPreviewRequest(value: unknown): { readonly proposalID: string } {
  if (!isExactRecord(value, ["proposal_id"]) || !matchesPublicID(value.proposal_id, "proposal")) {
    throw new ProtocolError("invalid_request");
  }
  return { proposalID: value.proposal_id };
}

function parseSessionCreateRequest(value: unknown): {
  readonly sessionID: string;
  readonly expiresAtMilliseconds: number;
  readonly allowedPaths: readonly ("frames" | "events" | "artifacts" | "scene")[];
} {
  if (
    !isExactRecord(value, ["session_id", "expires_at_ms", "allowed_paths"]) ||
    typeof value.session_id !== "string" ||
    !isRoomSessionID(value.session_id) ||
    typeof value.expires_at_ms !== "number" ||
    !Number.isSafeInteger(value.expires_at_ms) ||
    value.expires_at_ms < 0 ||
    !Array.isArray(value.allowed_paths) ||
    value.allowed_paths.length === 0 ||
    value.allowed_paths.length > 4 ||
    new Set(value.allowed_paths).size !== value.allowed_paths.length ||
    !value.allowed_paths.every(
      (path): path is "frames" | "events" | "artifacts" | "scene" =>
        path === "frames" || path === "events" || path === "artifacts" || path === "scene",
    )
  ) {
    throw new ProtocolError("invalid_request");
  }
  return {
    sessionID: value.session_id,
    expiresAtMilliseconds: value.expires_at_ms,
    allowedPaths: value.allowed_paths,
  };
}

function parseEditConfirmationRequest(value: unknown): {
  readonly previewID: string;
  readonly expectedSceneRevision: number;
  readonly idempotencyKey: string;
} {
  if (
    !isExactRecord(value, ["preview_id", "expected_scene_revision", "idempotency_key"]) ||
    !matchesPublicID(value.preview_id, "preview") ||
    !isSceneRevision(value.expected_scene_revision) ||
    !matchesPublicID(value.idempotency_key, "txidem")
  ) {
    throw new ProtocolError("invalid_request");
  }
  return {
    previewID: value.preview_id,
    expectedSceneRevision: value.expected_scene_revision,
    idempotencyKey: value.idempotency_key,
  };
}

function parseEditRestoreRequest(value: unknown): {
  readonly transactionID: string;
  readonly expectedSceneRevision: number;
  readonly idempotencyKey: string;
} {
  if (
    !isExactRecord(value, ["transaction_id", "expected_scene_revision", "idempotency_key"]) ||
    !matchesPublicID(value.transaction_id, "tx") ||
    !isSceneRevision(value.expected_scene_revision) ||
    !matchesPublicID(value.idempotency_key, "txidem")
  ) {
    throw new ProtocolError("invalid_request");
  }
  return {
    transactionID: value.transaction_id,
    expectedSceneRevision: value.expected_scene_revision,
    idempotencyKey: value.idempotency_key,
  };
}

function isExactRecord(value: unknown, keys: readonly string[]): value is Record<string, unknown> {
  return (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value) &&
    Object.keys(value).length === keys.length &&
    keys.every((key) => key in value)
  );
}

function matchesPublicID(value: unknown, prefix: string): value is string {
  return (
    typeof value === "string" &&
    new RegExp(
      `^${prefix}_[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`,
      "u",
    ).test(value)
  );
}

function isSceneRevision(value: unknown): value is number {
  return Number.isSafeInteger(value) && (value as number) >= 0;
}

function inferenceFailureResponse(context: Context, error: unknown, didTimeout: boolean): Response {
  if (didTimeout) return context.json({ error: "upstream_timeout" }, 504);
  if (error instanceof InferenceWorkerError) {
    return context.json({ error: error.publicCode }, error.status);
  }
  return context.json({ error: "upstream_failure" }, 502);
}

async function readJSON(request: Request): Promise<unknown> {
  const declaredLength = request.headers.get("content-length");
  if (
    declaredLength !== null &&
    (!/^(?:0|[1-9][0-9]*)$/u.test(declaredLength) || Number(declaredLength) > MAX_REQUEST_BYTES)
  ) {
    throw new BodyTooLargeError();
  }
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.byteLength > MAX_REQUEST_BYTES) {
    throw new BodyTooLargeError();
  }
  return parseJSONBytesStrict(bytes);
}

async function readText(request: Request): Promise<string> {
  const declaredLength = request.headers.get("content-length");
  if (
    declaredLength !== null &&
    (!/^(?:0|[1-9][0-9]*)$/u.test(declaredLength) || Number(declaredLength) > MAX_REQUEST_BYTES)
  ) {
    throw new BodyTooLargeError();
  }
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.byteLength === 0 || bytes.byteLength > MAX_REQUEST_BYTES) {
    throw new BodyTooLargeError();
  }
  return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}

async function readBinary(request: Request): Promise<Uint8Array> {
  const declaredLength = request.headers.get("content-length");
  if (
    declaredLength !== null &&
    (!/^(?:0|[1-9][0-9]*)$/u.test(declaredLength) || Number(declaredLength) > MAX_REQUEST_BYTES)
  ) {
    throw new BodyTooLargeError();
  }
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.byteLength === 0 || bytes.byteLength > MAX_REQUEST_BYTES) {
    throw new BodyTooLargeError();
  }
  return bytes;
}

class BodyTooLargeError extends Error {}

class FixedWindowRateLimit {
  readonly #maximumRequests: number;
  readonly #nowMilliseconds: () => number;
  #windowStartedAt: number;
  #requestCount = 0;

  constructor(maximumRequests = 60, nowMilliseconds: () => number = Date.now) {
    this.#maximumRequests =
      Number.isSafeInteger(maximumRequests) && maximumRequests > 0
        ? Math.min(maximumRequests, 600)
        : 60;
    this.#nowMilliseconds = nowMilliseconds;
    this.#windowStartedAt = nowMilliseconds();
  }

  admit(): { allowed: true } | { allowed: false; retryAfterSeconds: number } {
    const now = this.#nowMilliseconds();
    if (now - this.#windowStartedAt >= 60_000 || now < this.#windowStartedAt) {
      this.#windowStartedAt = now;
      this.#requestCount = 0;
    }
    this.#requestCount += 1;
    if (this.#requestCount <= this.#maximumRequests) return { allowed: true };
    return {
      allowed: false,
      retryAfterSeconds: Math.max(1, Math.ceil((60_000 - (now - this.#windowStartedAt)) / 1_000)),
    };
  }
}

interface RequestDeadline {
  signal: AbortSignal;
  didTimeout(): boolean;
  dispose(): void;
}

function createDeadline(request: Request, timeoutMilliseconds = 15_000): RequestDeadline {
  const controller = new AbortController();
  let timedOut = false;
  const boundedTimeout =
    Number.isFinite(timeoutMilliseconds) && timeoutMilliseconds > 0
      ? Math.min(timeoutMilliseconds, 60_000)
      : 15_000;
  const timer = setTimeout(() => {
    timedOut = true;
    controller.abort(new DOMException("deadline exceeded", "TimeoutError"));
  }, boundedTimeout);
  timer.unref();
  const abortForDisconnect = () =>
    controller.abort(new DOMException("client aborted", "AbortError"));
  request.signal.addEventListener("abort", abortForDisconnect, { once: true });

  return {
    signal: controller.signal,
    didTimeout: () => timedOut,
    dispose: () => {
      clearTimeout(timer);
      request.signal.removeEventListener("abort", abortForDisconnect);
    },
  };
}

async function abortable<T>(operation: Promise<T>, signal: AbortSignal): Promise<T> {
  if (signal.aborted) throw signal.reason;
  return await new Promise<T>((resolve, reject) => {
    const onAbort = () => reject(signal.reason);
    signal.addEventListener("abort", onAbort, { once: true });
    operation.then(
      (value) => {
        signal.removeEventListener("abort", onAbort);
        resolve(value);
      },
      (error: unknown) => {
        signal.removeEventListener("abort", onAbort);
        reject(error);
      },
    );
  });
}

function hasValidBearer(authorization: string | undefined, expectedToken: string): boolean {
  if (!authorization?.startsWith("Bearer ") || expectedToken.length === 0) return false;
  const received = Buffer.from(authorization.slice("Bearer ".length), "utf8");
  const expected = Buffer.from(expectedToken, "utf8");
  return received.length === expected.length && timingSafeEqual(received, expected);
}

function hasJSONContentType(contentType: string | undefined): boolean {
  return contentType?.split(";", 1)[0]?.trim().toLowerCase() === "application/json";
}

function methodNotAllowed(context: Context, allow: string): Response {
  context.header("allow", allow);
  return context.json({ error: "method_not_allowed" }, 405);
}

function allowedMethodForPath(pathname: string): "GET" | "POST" | "DELETE" | undefined {
  if (pathname === "/health" || pathname === "/v1/inference/status") return "GET";
  if (pathname === "/v1/sessions") return "POST";
  if (/^\/v1\/sessions\/room_[a-z0-9_]{3,120}\/frames\/recent$/u.test(pathname)) return "GET";
  if (/^\/v1\/sessions\/room_[a-z0-9_]{3,120}\/frames$/u.test(pathname)) return "POST";
  if (/^\/v1\/sessions\/room_[a-z0-9_]{3,120}$/u.test(pathname)) return "DELETE";
  if (
    pathname === "/v1/realtime/calls" ||
    pathname === "/v1/inference/jobs" ||
    pathname === "/v1/edit/previews" ||
    pathname === "/v1/edit/confirmations" ||
    pathname === "/v1/edit/restores" ||
    pathname === "/v1/turns"
  ) {
    return "POST";
  }
  return undefined;
}

function safeLogPath(pathname: string): string {
  return allowedMethodForPath(pathname) === undefined ? "/<unknown>" : pathname;
}
