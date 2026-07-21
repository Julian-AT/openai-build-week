import { createOpenAIRealtimeSessionService } from "@reframe/agent";
import { createFilesystemAssetDeliveryService } from "./asset-delivery-service.ts";
import { createCachedAgentTurnService } from "./cached-agent-turn-service.ts";
import type { DurableEditTransactionService } from "./durable-edit-transaction-service.ts";
import { createDurableEditTransactionService } from "./durable-edit-transaction-service.ts";
import { createDurableRoomSessionStore } from "./durable-session-store.ts";
import { createInferenceWorkerClientFromEnvironment } from "./inference-client.ts";
import {
  createInMemoryKnownTargetRegistry,
  type KnownTarget,
  type KnownTargetRegistry,
} from "./known-target-registry.ts";
import { createRoomAgentTurnService } from "./room-agent-service.ts";
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
const editTransactionService = createDurableEditTransactionService(durableSessionStore);
const assetDeliveryService = createFilesystemAssetDeliveryService({
  dataDirectory,
  cacheProfile: process.env.REFRAME_AGENT_CACHE_PROFILE?.trim() || "ios-primary",
});
const agentTurnService = createAgentTurnServiceFromEnvironment(
  process.env,
  durableSessionStore,
  openAIAPIKey,
  editTransactionService,
);
const cachedAgentTurnService =
  agentTurnService === undefined ? undefined : createCachedAgentTurnService(agentTurnService);

const app = createGatewayApp({
  gatewayToken,
  runtimeReadiness,
  durableSessionStore,
  editTransactionService,
  assetDeliveryService,
  ...(cachedAgentTurnService ? { agentTurnService: cachedAgentTurnService } : {}),
  ...(realtimeService ? { realtimeService } : {}),
  ...(inferenceService ? { inferenceService } : {}),
  requestTimeoutMilliseconds: requestTimeoutFromEnvironment(process.env),
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
    agent_turns_enabled: cachedAgentTurnService !== undefined,
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

function createAgentTurnServiceFromEnvironment(
  environment: Record<string, string | undefined>,
  sessionStore: typeof durableSessionStore,
  openAIAPIKey: string | undefined,
  editTransactionService: DurableEditTransactionService,
) {
  if (environment.REFRAME_AGENT_TURNS_ENABLED !== "true" || openAIAPIKey === undefined) {
    return undefined;
  }
  const qdrantURL = environment.REFRAME_QDRANT_URL?.trim();
  if (qdrantURL === undefined || qdrantURL.length === 0) return undefined;
  const targetRegistry = knownTargetRegistryFromEnvironment(environment);
  try {
    return createRoomAgentTurnService({
      openAIAPIKey,
      qdrantURL,
      ...(environment.QDRANT_API_KEY === undefined
        ? {}
        : { qdrantAPIKey: environment.QDRANT_API_KEY }),
      sessionStore,
      editTransactionService,
      category: environment.REFRAME_AGENT_CATEGORY?.trim() || "side_table",
      maxDimensionsM: {
        width: positiveMeter(environment.REFRAME_AGENT_MAX_WIDTH_M, 2),
        height: positiveMeter(environment.REFRAME_AGENT_MAX_HEIGHT_M, 2),
        depth: positiveMeter(environment.REFRAME_AGENT_MAX_DEPTH_M, 2),
      },
      supportType: "floor",
      cacheProfile: environment.REFRAME_AGENT_CACHE_PROFILE?.trim() || "ios-primary",
      floorContactRF: { x: 0, y: 0, z: -2 },
      yawRadians: 0,
      ...(environment.REFRAME_SHOWCASE_ASSET_ID?.trim()
        ? { showcaseAssetID: environment.REFRAME_SHOWCASE_ASSET_ID.trim() }
        : {}),
      ...(targetRegistry === undefined ? {} : { targetRegistry }),
    });
  } catch {
    return undefined;
  }
}

function knownTargetRegistryFromEnvironment(
  environment: Record<string, string | undefined>,
): KnownTargetRegistry | undefined {
  const encoded = environment.REFRAME_KNOWN_TARGETS_JSON?.trim();
  if (encoded === undefined || encoded.length === 0 || encoded.length > 1_000_000) return undefined;
  try {
    const records: unknown = JSON.parse(encoded);
    if (!Array.isArray(records)) return undefined;
    return createInMemoryKnownTargetRegistry(records as readonly KnownTarget[]);
  } catch {
    return undefined;
  }
}

function positiveMeter(value: string | undefined, fallback: number): number {
  const parsed = value === undefined ? fallback : Number(value);
  return Number.isFinite(parsed) && parsed > 0 && parsed < 100 ? parsed : fallback;
}

function requestTimeoutFromEnvironment(environment: Record<string, string | undefined>): number {
  const value = environment.REFRAME_REQUEST_TIMEOUT_MS;
  if (value === undefined || value.trim() === "") return 15_000;
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 1_000 || parsed > 60_000) return 15_000;
  return parsed;
}
