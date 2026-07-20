import { randomUUID, timingSafeEqual } from "node:crypto";
import {
  createServer,
  type IncomingMessage,
  type Server,
  type ServerResponse,
} from "node:http";

import { parseProposalRequest, ProtocolError, type ProposalRequest } from "./protocol.ts";
import type { RealtimeClientSecretService } from "./realtime-client-secret.ts";
import { parseJSONBytesStrict } from "./strict-json.ts";

const MAX_REQUEST_BYTES = 2_500_000;

export interface ProposalService {
  propose(request: ProposalRequest, signal: AbortSignal): Promise<unknown>;
}

export interface GatewayServerOptions {
  gatewayToken: string;
  proposalService?: ProposalService;
  realtimeService?: RealtimeClientSecretService;
  logger?: (record: GatewayLogRecord) => void;
  requestID?: () => string;
  nowMilliseconds?: () => number;
  requestTimeoutMilliseconds?: number;
}

export interface GatewayLogRecord {
  request_id: string;
  method: string;
  path: string;
  status: number;
  duration_ms: number;
}

export function createGatewayServer(options: GatewayServerOptions): Server {
  return createServer((request, response) => {
    const url = new URL(request.url ?? "/", "http://gateway.local");
    const requestID = (options.requestID ?? randomUUID)();
    const nowMilliseconds = options.nowMilliseconds ?? Date.now;
    const startedAt = nowMilliseconds();
    response.setHeader("x-request-id", requestID);
    response.once("finish", () => {
      if (!options.logger) {
        return;
      }
      const record: GatewayLogRecord = {
        request_id: requestID,
        method: request.method ?? "UNKNOWN",
        path: safeLogPath(url.pathname),
        status: response.statusCode,
        duration_ms: Math.max(0, nowMilliseconds() - startedAt),
      };
      try {
        options.logger(record);
      } catch {
        // Logging must never change the public request outcome.
      }
    });

    if (url.search !== "") {
      writeJSON(response, 404, { error: "not_found" });
      return;
    }

    if (request.method === "GET" && url.pathname === "/health") {
      const body = JSON.stringify({ status: "ok" });
      response.writeHead(200, {
        "cache-control": "no-store",
        "content-type": "application/json; charset=utf-8",
      });
      response.end(body);
      return;
    }

    if (request.method === "POST" && url.pathname === "/v1/proposals") {
      if (!hasValidBearer(request.headers.authorization, options.gatewayToken)) {
        writeJSON(response, 401, { error: "unauthorized" });
        return;
      }
      if (!hasJSONContentType(request.headers["content-type"])) {
        writeJSON(response, 415, { error: "unsupported_media_type" });
        return;
      }

      void handleProposal(
        request,
        response,
        options.proposalService,
        options.requestTimeoutMilliseconds,
      );
      return;
    }

    if (request.method === "POST" && url.pathname === "/v1/realtime/client-secret") {
      if (!hasValidBearer(request.headers.authorization, options.gatewayToken)) {
        writeJSON(response, 401, { error: "unauthorized" });
        return;
      }
      if (!hasJSONContentType(request.headers["content-type"])) {
        writeJSON(response, 415, { error: "unsupported_media_type" });
        return;
      }

      void handleRealtimeSecret(
        request,
        response,
        options.realtimeService,
        options.requestTimeoutMilliseconds,
      );
      return;
    }

    const allowedMethod = allowedMethodForPath(url.pathname);
    if (allowedMethod !== undefined) {
      response.setHeader("allow", allowedMethod);
      writeJSON(response, 405, { error: "method_not_allowed" });
      return;
    }

    writeJSON(response, 404, { error: "not_found" });
  });
}

async function handleRealtimeSecret(
  request: IncomingMessage,
  response: ServerResponse,
  realtimeService: RealtimeClientSecretService | undefined,
  requestTimeoutMilliseconds = 15_000,
): Promise<void> {
  if (!realtimeService) {
    writeJSON(response, 503, { error: "service_unavailable" });
    return;
  }
  const deadline = createDeadline(request, requestTimeoutMilliseconds);
  try {
    const body = await abortable(readJSON(request), deadline.signal);
    if (!isEmptyRecord(body)) {
      writeJSON(response, 400, { error: "invalid_request" });
      return;
    }
    const result = await abortable(realtimeService.mint(deadline.signal), deadline.signal);
    writeJSON(response, 200, result);
  } catch (error) {
    if (deadline.didTimeout()) {
      writeJSON(response, 504, { error: "upstream_timeout" });
      return;
    }
    if (error instanceof BodyTooLargeError) {
      writeJSON(response, 413, { error: "payload_too_large" });
      return;
    }
    if (error instanceof SyntaxError) {
      writeJSON(response, 400, { error: "invalid_request" });
      return;
    }
    writeJSON(response, 502, { error: "upstream_failure" });
  } finally {
    deadline.dispose();
  }
}

async function handleProposal(
  request: IncomingMessage,
  response: ServerResponse,
  proposalService: ProposalService | undefined,
  requestTimeoutMilliseconds = 15_000,
): Promise<void> {
  if (!proposalService) {
    writeJSON(response, 503, { error: "service_unavailable" });
    return;
  }

  const deadline = createDeadline(request, requestTimeoutMilliseconds);
  try {
    const declaredLength = Number(request.headers["content-length"] ?? 0);
    if (Number.isFinite(declaredLength) && declaredLength > MAX_REQUEST_BYTES) {
      request.resume();
      throw new BodyTooLargeError();
    }
    const body = await abortable(readJSON(request), deadline.signal);
    const proposalRequest = parseProposalRequest(body);
    const result = await abortable(
      proposalService.propose(proposalRequest, deadline.signal),
      deadline.signal,
    );
    writeJSON(response, 200, result);
  } catch (error) {
    if (deadline.didTimeout()) {
      writeJSON(response, 504, { error: "upstream_timeout" });
      return;
    }
    if (error instanceof BodyTooLargeError) {
      writeJSON(response, 413, { error: "payload_too_large" });
      return;
    }
    if (error instanceof ProtocolError || error instanceof SyntaxError) {
      writeJSON(response, 400, { error: "invalid_request" });
      return;
    }
    writeJSON(response, 502, { error: "upstream_failure" });
  } finally {
    deadline.dispose();
  }
}

async function readJSON(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let totalBytes = 0;
  for await (const chunk of request) {
    const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    totalBytes += bytes.length;
    if (totalBytes > MAX_REQUEST_BYTES) {
      request.resume();
      throw new BodyTooLargeError();
    }
    chunks.push(bytes);
  }
  return parseJSONBytesStrict(Buffer.concat(chunks));
}

class BodyTooLargeError extends Error {}

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

function createDeadline(request: IncomingMessage, timeoutMilliseconds: number): RequestDeadline {
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
  const abortForDisconnect = () => controller.abort(new DOMException("client aborted", "AbortError"));
  request.once("aborted", abortForDisconnect);

  return {
    signal: controller.signal,
    didTimeout: () => timedOut,
    dispose: () => {
      clearTimeout(timer);
      request.off("aborted", abortForDisconnect);
    },
  };
}

async function abortable<T>(operation: Promise<T>, signal: AbortSignal): Promise<T> {
  if (signal.aborted) {
    throw signal.reason;
  }
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
  if (!authorization?.startsWith("Bearer ") || expectedToken.length === 0) {
    return false;
  }
  const received = Buffer.from(authorization.slice("Bearer ".length), "utf8");
  const expected = Buffer.from(expectedToken, "utf8");
  return received.length === expected.length && timingSafeEqual(received, expected);
}

function hasJSONContentType(contentType: string | undefined): boolean {
  return contentType?.split(";", 1)[0]?.trim().toLowerCase() === "application/json";
}

function allowedMethodForPath(pathname: string): "GET" | "POST" | undefined {
  if (pathname === "/health") {
    return "GET";
  }
  if (pathname === "/v1/proposals" || pathname === "/v1/realtime/client-secret") {
    return "POST";
  }
  return undefined;
}

function safeLogPath(pathname: string): string {
  return allowedMethodForPath(pathname) === undefined ? "/<unknown>" : pathname;
}

function writeJSON(response: ServerResponse, status: number, value: unknown): void {
  response.writeHead(status, {
    "cache-control": "no-store",
    "content-type": "application/json; charset=utf-8",
  });
  response.end(JSON.stringify(value));
}
