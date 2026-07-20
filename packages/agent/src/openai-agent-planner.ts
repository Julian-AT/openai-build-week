import OpenAI from "openai";
import type { ResponseInput, Tool } from "openai/resources/responses/responses";

import {
  type AgentPlanner,
  type AgentPlannerStep,
  type AgentReadToolName,
  type AgentToolCall,
  type AgentToolOutput,
  type AgentTurnInput,
  AgentToolPolicyError,
  MAX_AGENT_CANDIDATES,
} from "./bounded-tool-runner.ts";
import { PROPOSAL_MODEL, type ProposalOutputSchema } from "./types.ts";

const MAX_TOOL_OUTPUT_BYTES = 64_000;

export interface AgentFunctionToolDefinition {
  type: "function";
  name: AgentReadToolName;
  description: string;
  strict: true;
  parameters: Record<string, unknown>;
}

export interface AgentResponseGenerationRequest {
  model: typeof PROPOSAL_MODEL;
  instructions: string;
  input: readonly unknown[];
  tools: readonly AgentFunctionToolDefinition[];
  proposalSchema: ProposalOutputSchema;
  store: false;
}

export interface AgentResponseGenerationResult {
  responseID: string;
  outputItems: readonly unknown[];
  outputText: string;
}

export interface AgentResponsesGenerator {
  generate(
    request: AgentResponseGenerationRequest,
    signal: AbortSignal,
  ): Promise<AgentResponseGenerationResult>;
}

export interface OpenAIResponsesAgentPlannerOptions {
  apiKey: string;
  instructions: string;
  proposalSchema: ProposalOutputSchema;
  tools?: readonly AgentFunctionToolDefinition[];
  generator?: AgentResponsesGenerator;
  fetch?: typeof globalThis.fetch;
}

export const REFRAME_AGENT_TOOLS: readonly AgentFunctionToolDefinition[] = [
  closedTool("get_scene_context", "Read authoritative scene facts and capability readiness.", {
    region: nullableString(),
    detail_level: { type: "string", enum: ["summary", "detailed"] },
  }),
  closedTool("resolve_target", "Resolve a pointer or language reference to one canonical object.", {
    pointer_context_id: nullableString(),
    language_reference: nullableString(500),
  }),
  closedTool("search_catalog", "Search only deterministic injection-ready catalog candidates.", {
    query: boundedString(1, 500),
    category: nullableString(),
    style: nullableString(),
    color: nullableString(),
    material: nullableString(),
    limit: { type: "integer", minimum: 1, maximum: MAX_AGENT_CANDIDATES },
  }),
  closedTool("validate_candidate", "Validate physical fit, clearance, cover, and artifact readiness.", {
    target_id: boundedString(1, 128),
    asset_id: boundedString(1, 128),
    constraints: constraintArray(),
  }),
  closedTool("prepare_edit_preview", "Prepare one revision-neutral preview after validation.", {
    intent: { type: "string", enum: ["place", "replace", "remove", "restore"] },
    target_id: nullableString(),
    asset_id: nullableString(),
    constraints: constraintArray(),
  }),
] as const;

export function createOpenAIResponsesAgentPlanner(
  options: OpenAIResponsesAgentPlannerOptions,
): AgentPlanner {
  if (options.apiKey.length === 0) throw new Error("missing_openai_api_key");
  const generator =
    options.generator ?? createOpenAIResponsesGenerator(options.apiKey, options.fetch);
  const tools = options.tools ?? REFRAME_AGENT_TOOLS;
  const history: unknown[] = [];
  const pendingCalls: AgentToolCall[] = [];
  let initialized = false;
  let consumedToolOutputs = 0;

  return {
    async next(input, priorToolOutputs, signal): Promise<AgentPlannerStep> {
      signal.throwIfAborted();
      if (!initialized) {
        history.push(initialTurnMessage(input));
        initialized = true;
      }
      const queued = pendingCalls.shift();
      if (queued !== undefined) return queued;
      appendNewToolOutputs(history, priorToolOutputs, consumedToolOutputs);
      consumedToolOutputs = priorToolOutputs.length;

      const response = await generator.generate(
        {
          model: PROPOSAL_MODEL,
          instructions: options.instructions,
          input: history,
          tools,
          proposalSchema: options.proposalSchema,
          store: false,
        },
        signal,
      );
      history.push(...response.outputItems);
      pendingCalls.push(...parseToolCalls(response.outputItems));
      const call = pendingCalls.shift();
      if (call !== undefined) return call;
      if (response.outputText.length === 0) throw new AgentToolPolicyError("missing_agent_proposal");
      return { type: "proposal", proposal: parseJSON(response.outputText, "invalid_agent_proposal") };
    },
  };
}

function createOpenAIResponsesGenerator(
  apiKey: string,
  fetchImplementation?: typeof globalThis.fetch,
): AgentResponsesGenerator {
  const client = new OpenAI({
    apiKey,
    ...(fetchImplementation === undefined ? {} : { fetch: fetchImplementation }),
  });
  return {
    async generate(request, signal) {
      const response = await client.responses.create(
        {
          model: request.model,
          store: request.store,
          instructions: request.instructions,
          input: request.input as ResponseInput,
          tools: request.tools as Tool[],
          max_output_tokens: 1_200,
          reasoning: { effort: "low" },
          text: {
            verbosity: "low",
            format: {
              type: "json_schema",
              name: "edit_preview_proposal",
              strict: true,
              schema: request.proposalSchema,
            },
          },
        },
        { signal },
      );
      if (response.status !== "completed") throw new Error("incomplete_agent_response");
      return {
        responseID: response.id,
        outputItems: response.output,
        outputText: response.output_text,
      };
    },
  };
}

function initialTurnMessage(input: AgentTurnInput): unknown {
  return {
    role: "user",
    content: [
      {
        type: "input_text",
        text: JSON.stringify({
          client_turn_id: input.clientTurnID,
          utterance: input.utterance,
          authoritative_context: {
            session_id: input.authoritativeContext.sessionID,
            scene_revision: input.authoritativeContext.sceneRevision,
            pointer_context_id: input.authoritativeContext.pointerContextID,
          },
        }),
      },
    ],
  };
}

function appendNewToolOutputs(
  history: unknown[],
  outputs: readonly AgentToolOutput[],
  consumed: number,
): void {
  if (outputs.length < consumed) throw new AgentToolPolicyError("agent_tool_history_rewritten");
  for (const output of outputs.slice(consumed)) {
    history.push({
      type: "function_call_output",
      call_id: output.callID,
      output: boundedJSONStringify(output.output),
    });
  }
}

function parseToolCalls(items: readonly unknown[]): AgentToolCall[] {
  const calls: AgentToolCall[] = [];
  for (const item of items) {
    if (!isRecord(item) || item.type !== "function_call") continue;
    if (typeof item.call_id !== "string" || typeof item.name !== "string") {
      throw new AgentToolPolicyError("invalid_agent_tool_call");
    }
    calls.push({
      type: "tool_call",
      callID: item.call_id,
      name: item.name as AgentReadToolName,
      arguments: parseJSON(item.arguments, "invalid_agent_tool_arguments"),
    });
  }
  return calls;
}

function boundedJSONStringify(value: unknown): string {
  const encoded = JSON.stringify(value);
  if (encoded === undefined || new TextEncoder().encode(encoded).byteLength > MAX_TOOL_OUTPUT_BYTES) {
    throw new AgentToolPolicyError("agent_tool_output_too_large");
  }
  return encoded;
}

function parseJSON(value: unknown, error: string): unknown {
  if (typeof value !== "string") throw new AgentToolPolicyError(error);
  try {
    return JSON.parse(value) as unknown;
  } catch {
    throw new AgentToolPolicyError(error);
  }
}

function closedTool(
  name: AgentReadToolName,
  description: string,
  properties: Record<string, unknown>,
): AgentFunctionToolDefinition {
  return {
    type: "function",
    name,
    description,
    strict: true,
    parameters: {
      type: "object",
      additionalProperties: false,
      required: Object.keys(properties),
      properties,
    },
  };
}

function nullableString(maxLength = 128): Record<string, unknown> {
  return { type: ["string", "null"], maxLength };
}

function boundedString(minLength: number, maxLength: number): Record<string, unknown> {
  return { type: "string", minLength, maxLength };
}

function constraintArray(): Record<string, unknown> {
  return {
    type: "array",
    maxItems: 16,
    items: {
      type: "object",
      additionalProperties: false,
      required: ["kind", "value"],
      properties: {
        kind: boundedString(1, 64),
        value: { type: ["string", "number", "boolean"] },
      },
    },
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
