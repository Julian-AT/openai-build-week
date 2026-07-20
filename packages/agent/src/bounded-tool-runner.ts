export const MAX_AGENT_TOOL_CALLS = 6;
export const MAX_AGENT_CANDIDATES = 8;

export type AgentReadToolName =
  | "get_scene_context"
  | "resolve_target"
  | "search_catalog"
  | "validate_candidate"
  | "prepare_edit_preview";

export interface AgentToolCall {
  type: "tool_call";
  callID: string;
  name: AgentReadToolName;
  arguments: unknown;
}

export interface AgentProposalStep {
  type: "proposal";
  proposal: unknown;
}

export type AgentPlannerStep = AgentToolCall | AgentProposalStep;

export interface AuthoritativeTurnContext {
  sessionID: string;
  sceneRevision: number;
  pointerContextID: string | null;
}

export interface AgentTurnInput {
  clientTurnID: string;
  utterance: string;
  authoritativeContext: AuthoritativeTurnContext;
}

export interface AgentToolOutput {
  callID: string;
  name: AgentReadToolName;
  output: unknown;
}

export interface AgentPlanner {
  next(
    input: AgentTurnInput,
    priorToolOutputs: readonly AgentToolOutput[],
    signal: AbortSignal,
  ): Promise<AgentPlannerStep>;
}

export interface AgentReadToolExecutor {
  execute(
    call: AgentToolCall,
    context: AuthoritativeTurnContext,
    signal: AbortSignal,
  ): Promise<unknown>;
}

export class AgentToolPolicyError extends Error {
  constructor(message = "agent_tool_policy_violation") {
    super(message);
    this.name = "AgentToolPolicyError";
  }
}

const READ_ONLY_TOOLS = new Set<AgentReadToolName>([
  "get_scene_context",
  "resolve_target",
  "search_catalog",
  "validate_candidate",
  "prepare_edit_preview",
]);

export async function runBoundedAgentTurn(
  input: AgentTurnInput,
  planner: AgentPlanner,
  tools: AgentReadToolExecutor,
  signal: AbortSignal,
): Promise<unknown> {
  const outputs: AgentToolOutput[] = [];
  for (let stepIndex = 0; stepIndex <= MAX_AGENT_TOOL_CALLS; stepIndex += 1) {
    signal.throwIfAborted();
    const step = await planner.next(input, outputs, signal);
    if (step.type === "proposal") return step.proposal;
    assertAllowedCall(step);
    if (stepIndex === MAX_AGENT_TOOL_CALLS)
      throw new AgentToolPolicyError("agent_tool_budget_exceeded");
    const output = await tools.execute(step, input.authoritativeContext, signal);
    outputs.push({ callID: step.callID, name: step.name, output });
  }
  throw new AgentToolPolicyError("agent_tool_budget_exceeded");
}

function assertAllowedCall(call: AgentToolCall): void {
  if (!READ_ONLY_TOOLS.has(call.name)) throw new AgentToolPolicyError("unsupported_agent_tool");
  if (call.name !== "search_catalog") return;
  if (!isRecord(call.arguments)) throw new AgentToolPolicyError("invalid_catalog_search");
  const limit = call.arguments.limit;
  if (
    typeof limit !== "number" ||
    !Number.isInteger(limit) ||
    limit < 1 ||
    limit > MAX_AGENT_CANDIDATES
  ) {
    throw new AgentToolPolicyError("invalid_catalog_candidate_limit");
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
