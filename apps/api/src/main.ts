import { createOpenAIRealtimeSessionService } from "@reframe/agent";

import { createDurableRoomSessionStore } from "./durable-session-store.ts";
import { createInferenceWorkerClientFromEnvironment } from "./inference-client.ts";
import { runtimeReadinessFromEnvironment } from "./runtime-readiness.ts";
import { createGatewayApp, type GatewayLogRecord, MAX_REQUEST_BYTES } from "./server.ts";

const host = process.env.REFRAME_GATEWAY_HOST?.trim() || "0.0.0.0";
const port = parsePort(process.env.REFRAME_GATEWAY_PORT);
const gatewayToken = requiredEnvironment("REFRAME_GATEWAY_TOKEN");
const dataDirectory = requiredEnvironment("REFRAME_DATA_DIR");
const roomSigningSecret = requiredEnvironment("REFRAME_ROOM_SIGNING_SECRET");
const openAIAPIKey = process.env.OPENAI_API_KEY;

const realtimeService = openAIAPIKey
  ? createOpenAIRealtimeSessionService({ apiKey: openAIAPIKey })
  : undefined;
const inferenceService = createInferenceWorkerClientFromEnvironment({
  REFRAME_VISION_URL: process.env.REFRAME_VISION_URL,
  REFRAME_VISION_TOKEN: process.env.REFRAME_VISION_TOKEN,
});
const runtimeReadiness = await runtimeReadinessFromEnvironment(process.env);
const durableSessionStore = await createDurableRoomSessionStore({
  dataDirectory,
  signingSecret: roomSigningSecret,
});

const app = createGatewayApp({
  gatewayToken,
  runtimeReadiness,
  durableSessionStore,
  ...(realtimeService ? { realtimeService } : {}),
  ...(inferenceService ? { inferenceService } : {}),
  logger: writeRequestLog,
});

const server = Bun.serve({
  hostname: host,
  port,
  fetch: app.fetch,
  maxRequestBodySize: MAX_REQUEST_BYTES,
  error() {
    process.stderr.write(`${JSON.stringify({ event: "gateway_error" })}\n`);
    return Response.json({ error: "internal_failure" }, { status: 500 });
  },
});

process.stdout.write(
  `${JSON.stringify({
    event: "gateway_started",
    host: server.hostname,
    port: server.port,
    protected_routes_enabled: gatewayToken.length > 0,
    realtime_enabled: realtimeService !== undefined,
    agent_turns_enabled: false,
    inference_routes_enabled: inferenceService !== undefined,
    durable_capture_enabled: true,
  })}\n`,
);

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, () => {
    void durableSessionStore.close().finally(() => {
      server.stop();
      process.exit(0);
    });
  });
}

function requiredEnvironment(name: string): string {
  const value = process.env[name]?.trim();
  if (value === undefined || value.length === 0) throw new Error(`missing_${name.toLowerCase()}`);
  return value;
}

function parsePort(value: string | undefined): number {
  if (value === undefined || value.trim() === "") {
    return 8787;
  }
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 1 || parsed > 65_535) {
    throw new Error("invalid_gateway_port");
  }
  return parsed;
}

function writeRequestLog(record: GatewayLogRecord): void {
  process.stdout.write(`${JSON.stringify({ event: "request", ...record })}\n`);
}
