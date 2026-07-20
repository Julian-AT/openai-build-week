import { randomUUID as systemRandomUUID } from "node:crypto";

import { type ModelProposalInput, PROPOSAL_MODEL, type ProposalModelClient } from "@reroom/ai";

import { CURATED_ASSET_IDS } from "./catalog.ts";
import type { ProposalRequest, ProposalRequestContext } from "./protocol.ts";
import type { ProposalService } from "./server.ts";

export { PROPOSAL_MODEL } from "@reroom/ai";

export type TypedConstraint =
  | { kind: "color_tag" | "style_tag"; value: string }
  | { kind: "support_required" | "preserve_walkway"; value: boolean }
  | { kind: "max_footprint_m2"; value: number };

export interface SemanticIntent {
  operation: "place" | "replace" | "remove" | "restore";
  arguments: { asset_id?: string };
  constraints: TypedConstraint[];
}

export interface SemanticProposalEnvelope {
  schema_version: "1.0.0";
  envelope_id: string;
  created_at_utc: string;
  request_context: ProposalRequestContext;
  ingress_source: ProposalRequest["ingress_source"];
  semantic_model: {
    provider: "openai";
    model: typeof PROPOSAL_MODEL;
    response_id: string;
  };
  status: "ready" | "needs_clarification";
  intent: SemanticIntent | null;
  explanation: string;
  clarification: string | null;
}

export interface ProposalServiceOptions {
  modelClient: ProposalModelClient;
  now?: () => Date;
  randomUUID?: () => string;
}

export interface SemanticProposalService extends ProposalService {
  propose(request: ProposalRequest, signal: AbortSignal): Promise<SemanticProposalEnvelope>;
}

export function createProposalService(options: ProposalServiceOptions): SemanticProposalService {
  const now = options.now ?? (() => new Date());
  const randomUUID = options.randomUUID ?? systemRandomUUID;

  return {
    async propose(request, signal): Promise<SemanticProposalEnvelope> {
      const modelInput: ModelProposalInput = { prompt: request.prompt };
      if (request.image_data_url !== undefined) {
        modelInput.image_data_url = request.image_data_url;
      }
      const result = await options.modelClient.generate(modelInput, signal);
      if (
        typeof result.responseID !== "string" ||
        result.responseID.length < 1 ||
        result.responseID.length > 128 ||
        !/^[A-Za-z0-9._-]+$/u.test(result.responseID)
      ) {
        throw new Error("invalid_model_output");
      }
      const output = parseInitialModelOutput(result.output);

      return {
        schema_version: "1.0.0",
        envelope_id: `envelope_${randomUUID()}`,
        created_at_utc: now().toISOString(),
        request_context: { ...request.request_context },
        ingress_source: request.ingress_source,
        semantic_model: {
          provider: "openai",
          model: PROPOSAL_MODEL,
          response_id: result.responseID,
        },
        status: output.status,
        intent: output.intent,
        explanation: output.explanation,
        clarification: output.clarification,
      };
    },
  };
}

interface ParsedModelOutput {
  status: "ready" | "needs_clarification";
  intent: SemanticIntent | null;
  explanation: string;
  clarification: string | null;
}

function parseInitialModelOutput(value: unknown): ParsedModelOutput {
  if (
    !isRecord(value) ||
    !hasExactKeys(value, ["status", "intent", "explanation", "clarification"])
  ) {
    throw new Error("invalid_model_output");
  }
  const status = value.status;
  const explanation = value.explanation;
  if (
    (status !== "ready" && status !== "needs_clarification") ||
    typeof explanation !== "string" ||
    explanation.length < 1 ||
    explanation.length > 280 ||
    containsURL(explanation) ||
    !isSingleLine(explanation)
  ) {
    throw new Error("invalid_model_output");
  }
  const intent = value.intent === null ? null : parseSemanticIntent(value.intent);
  const clarification = value.clarification;
  const validReady = status === "ready" && intent !== null && clarification === null;
  const validClarification =
    status === "needs_clarification" &&
    intent === null &&
    typeof clarification === "string" &&
    clarification.length >= 1 &&
    clarification.length <= 280 &&
    !containsURL(clarification) &&
    isSingleLine(clarification);
  if (!validReady && !validClarification) {
    throw new Error("invalid_model_output");
  }
  return {
    status,
    intent,
    explanation,
    clarification,
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseSemanticIntent(value: unknown): SemanticIntent {
  if (!isRecord(value) || !hasExactKeys(value, ["operation", "arguments", "constraints"])) {
    throw new Error("invalid_model_output");
  }
  const operation = value.operation;
  if (
    operation !== "place" &&
    operation !== "replace" &&
    operation !== "remove" &&
    operation !== "restore"
  ) {
    throw new Error("invalid_model_output");
  }
  if (!isRecord(value.arguments) || !Array.isArray(value.constraints)) {
    throw new Error("invalid_model_output");
  }
  if (operation === "place" || operation === "replace") {
    if (
      !hasExactKeys(value.arguments, ["asset_id"]) ||
      typeof value.arguments.asset_id !== "string" ||
      !CURATED_ASSET_IDS.has(value.arguments.asset_id)
    ) {
      throw new Error("invalid_model_output");
    }
  } else if (Object.keys(value.arguments).length !== 0) {
    throw new Error("invalid_model_output");
  }

  const constraints = parseConstraints(value.constraints);
  return {
    operation,
    arguments: { ...value.arguments },
    constraints,
  };
}

function parseConstraints(values: unknown[]): TypedConstraint[] {
  if (values.length > 8) {
    throw new Error("invalid_model_output");
  }
  const constraints = values.map((value): TypedConstraint => {
    if (!isRecord(value) || !hasExactKeys(value, ["kind", "value"])) {
      throw new Error("invalid_model_output");
    }
    const kind = value.kind;
    const constraintValue = value.value;
    const valid =
      ((kind === "color_tag" || kind === "style_tag") &&
        typeof constraintValue === "string" &&
        constraintValue.length >= 1 &&
        constraintValue.length <= 64 &&
        !containsURL(constraintValue) &&
        isSingleLine(constraintValue)) ||
      ((kind === "support_required" || kind === "preserve_walkway") &&
        typeof constraintValue === "boolean") ||
      (kind === "max_footprint_m2" &&
        typeof constraintValue === "number" &&
        Number.isFinite(constraintValue) &&
        constraintValue > 0 &&
        constraintValue <= 20);
    if (!valid) {
      throw new Error("invalid_model_output");
    }
    return { kind, value: constraintValue } as TypedConstraint;
  });

  const keys = constraints.map(
    (constraint) =>
      `${constraint.kind}\u0000${JSON.stringify({ kind: constraint.kind, value: constraint.value })}`,
  );
  const sortedKeys = [...keys].sort();
  if (keys.some((key, index) => key !== sortedKeys[index]) || new Set(keys).size !== keys.length) {
    throw new Error("invalid_model_output");
  }
  return constraints;
}

function hasExactKeys(value: Record<string, unknown>, expected: readonly string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === expected.length && expected.every((key) => key in value);
}

function containsURL(value: string): boolean {
  return /(?:\b[a-z][a-z0-9+.-]*:\/\/|\bwww\.)/iu.test(value);
}

function isSingleLine(value: string): boolean {
  return !value.includes("\n") && !value.includes("\r");
}
