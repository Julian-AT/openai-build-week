import OpenAI from "openai";

import { createOpenAIProposalModelClient } from "./openai-responses-client.ts";
import { createProposalService } from "./proposal-service.ts";
import { createRealtimeClientSecretService } from "./realtime-client-secret.ts";
import { createGatewayServer, type GatewayLogRecord } from "./server.ts";

const host = process.env.REROOM_GATEWAY_HOST?.trim() || "0.0.0.0";
const port = parsePort(process.env.REROOM_GATEWAY_PORT);
const gatewayToken = process.env.REROOM_GATEWAY_TOKEN ?? "";
const openAIAPIKey = process.env.OPENAI_API_KEY;

const openAI = openAIAPIKey ? new OpenAI({ apiKey: openAIAPIKey }) : undefined;
const proposalService = openAI
  ? createProposalService({ modelClient: createOpenAIProposalModelClient(openAI) })
  : undefined;
const realtimeService = openAIAPIKey
  ? createRealtimeClientSecretService({ apiKey: openAIAPIKey })
  : undefined;

const server = createGatewayServer({
  gatewayToken,
  ...(proposalService ? { proposalService } : {}),
  ...(realtimeService ? { realtimeService } : {}),
  logger: writeRequestLog,
});

server.on("error", () => {
  process.stderr.write(`${JSON.stringify({ event: "gateway_error" })}\n`);
});

server.listen(port, host, () => {
  process.stdout.write(
    `${JSON.stringify({
      event: "gateway_started",
      host,
      port,
      protected_routes_enabled: gatewayToken.length > 0,
      openai_routes_enabled: openAI !== undefined,
    })}\n`,
  );
});

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, () => {
    server.close(() => process.exit(0));
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
