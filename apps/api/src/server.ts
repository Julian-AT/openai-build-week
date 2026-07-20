import { randomUUID, timingSafeEqual } from "node:crypto";

import type { RealtimeTokenService } from "@reroom/ai";
import { type Context, Hono } from "hono";

import { type InferenceService, InferenceWorkerError } from "./inference-client.ts";
import { parseInferenceJobRequest } from "./inference-protocol.ts";
import { type ProposalRequest, ProtocolError, parseProposalRequest } from "./protocol.ts";
import { parseJSONBytesStrict } from "./strict-json.ts";

export const MAX_REQUEST_BYTES = 2_500_000;

export interface ProposalService {
  propose(request: ProposalRequest, signal: AbortSignal): Promise<unknown>;
}

export interface GatewayAppOptions {
  gatewayToken: string;
  proposalService?: ProposalService;
  realtimeService?: RealtimeTokenService;
  inferenceService?: InferenceService;
  logger?: (record: GatewayLogRecord) => void;
  requestID?: () => string;
  nowMilliseconds?: () => number;
  requestTimeoutMilliseconds?: number;
  protectedRequestsPerMinute?: number;
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

  app.get("/health", (context) => context.json({ status: "ok" }));

  app.post("/v1/proposals", async (context) => {
    const rejection = authorizeJSONRequest(context, options.gatewayToken);
    if (rejection !== undefined) return rejection;
    return handleProposal(context, options);
  });

  app.post("/v1/realtime/client-secret", async (context) => {
    const rejection = authorizeJSONRequest(context, options.gatewayToken);
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

  app.all("/health", (context) => methodNotAllowed(context, "GET"));
  app.all("/v1/proposals", (context) => methodNotAllowed(context, "POST"));
  app.all("/v1/realtime/client-secret", (context) => methodNotAllowed(context, "POST"));
  app.all("/v1/inference/status", (context) => methodNotAllowed(context, "GET"));
  app.all("/v1/inference/jobs", (context) => methodNotAllowed(context, "POST"));
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

function authorizeBearerRequest(context: Context, gatewayToken: string): Response | undefined {
  if (!hasValidBearer(context.req.header("authorization"), gatewayToken)) {
    return context.json({ error: "unauthorized" }, 401);
  }
  return undefined;
}

async function handleProposal(context: Context, options: GatewayAppOptions): Promise<Response> {
  if (!options.proposalService) {
    return context.json({ error: "service_unavailable" }, 503);
  }

  const deadline = createDeadline(context.req.raw, options.requestTimeoutMilliseconds);
  try {
    const body = await abortable(readJSON(context.req.raw), deadline.signal);
    const proposalRequest = parseProposalRequest(body);
    const result = await abortable(
      options.proposalService.propose(proposalRequest, deadline.signal),
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
    return context.json({ error: "upstream_failure" }, 502);
  } finally {
    deadline.dispose();
  }
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
    const body = await abortable(readJSON(context.req.raw), deadline.signal);
    if (!isEmptyRecord(body)) {
      return context.json({ error: "invalid_request" }, 400);
    }
    const result = await abortable(options.realtimeService.mint(deadline.signal), deadline.signal);
    return context.json(result);
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

function isEmptyRecord(value: unknown): boolean {
  return (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value) &&
    Object.keys(value).length === 0
  );
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

function methodNotAllowed(context: Context, allow: "GET" | "POST"): Response {
  context.header("allow", allow);
  return context.json({ error: "method_not_allowed" }, 405);
}

function allowedMethodForPath(pathname: string): "GET" | "POST" | undefined {
  if (pathname === "/health" || pathname === "/v1/inference/status") return "GET";
  if (
    pathname === "/v1/proposals" ||
    pathname === "/v1/realtime/client-secret" ||
    pathname === "/v1/inference/jobs"
  ) {
    return "POST";
  }
  return undefined;
}

function safeLogPath(pathname: string): string {
  return allowedMethodForPath(pathname) === undefined ? "/<unknown>" : pathname;
}
