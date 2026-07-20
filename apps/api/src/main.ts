import {
  buildDesignCopilotInstructions,
  createOpenAIProposalModelClient,
  createOpenAIRealtimeTokenService,
} from "@reroom/ai";

import { CURATED_CATALOG } from "./catalog.ts";
import { createProposalService } from "./proposal-service.ts";
import { MODEL_PROPOSAL_OUTPUT_SCHEMA } from "./semantic-schema.ts";
import { createGatewayApp, MAX_REQUEST_BYTES, type GatewayLogRecord } from "./server.ts";

const host = process.env.REROOM_GATEWAY_HOST?.trim() || "0.0.0.0";
const port = parsePort(process.env.REROOM_GATEWAY_PORT);
const gatewayToken = process.env.REROOM_GATEWAY_TOKEN ?? "";
const openAIAPIKey = process.env.OPENAI_API_KEY;

const proposalService = openAIAPIKey
  ? createProposalService({
      modelClient: createOpenAIProposalModelClient({
        apiKey: openAIAPIKey,
        instructions: buildDesignCopilotInstructions(
          CURATED_CATALOG.map((asset) => ({ assetID: asset.asset_id, name: asset.name })),
        ),
        outputSchema: MODEL_PROPOSAL_OUTPUT_SCHEMA,
      }),
    })
  : undefined;
const realtimeService = openAIAPIKey
  ? createOpenAIRealtimeTokenService({ apiKey: openAIAPIKey })
  : undefined;

const app = createGatewayApp({
  gatewayToken,
  ...(proposalService ? { proposalService } : {}),
  ...(realtimeService ? { realtimeService } : {}),
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
    openai_routes_enabled: openAIAPIKey !== undefined,
  })}\n`,
);

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, () => {
    server.stop();
    process.exit(0);
  });
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
