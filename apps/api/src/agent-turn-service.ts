import {
  type AgentPlanner,
  type AgentReadToolExecutor,
  type AgentTurnInput,
  type AuthoritativeTurnContext,
  createOpenAIResponsesAgentPlanner,
  type OpenAIResponsesAgentPlannerOptions,
  runBoundedAgentTurn,
} from "@reframe/agent";

import type { AgentTurnIntentHint, AgentTurnRequest, AgentTurnService } from "./agent-turn.ts";

export interface TurnContextResolutionRequest {
  readonly clientTurnID: string;
  readonly requestedSceneRevision: number;
  readonly requestedPointerContextID: string | null;
  readonly pendingProposalID: string | null;
  readonly intentHint: AgentTurnIntentHint | null;
}

export interface AuthoritativeTurnContextResolver {
  resolve(
    credential: string,
    request: TurnContextResolutionRequest,
    signal: AbortSignal,
  ): Promise<AuthoritativeTurnContext>;
}

export interface AgentPlannerFactory {
  create(): AgentPlanner;
}

export interface AgentTurnServiceOptions {
  readonly contextResolver: AuthoritativeTurnContextResolver;
  readonly plannerFactory: AgentPlannerFactory;
  readonly tools: AgentReadToolExecutor;
}

export function createOpenAIResponsesPlannerFactory(
  options: OpenAIResponsesAgentPlannerOptions,
): AgentPlannerFactory {
  return {
    create: () => createOpenAIResponsesAgentPlanner(options),
  };
}

export function createAgentTurnService(options: AgentTurnServiceOptions): AgentTurnService {
  return {
    async submit(credential, turn, signal) {
      signal.throwIfAborted();
      const context = freezeValidatedContext(
        await options.contextResolver.resolve(credential, resolutionRequest(turn), signal),
      );
      signal.throwIfAborted();
      const input: AgentTurnInput = Object.freeze({
        clientTurnID: turn.client_turn_id,
        utterance: turn.utterance,
        authoritativeContext: context,
      });
      const planner = options.plannerFactory.create();
      return await runBoundedAgentTurn(input, planner, options.tools, signal);
    },
  };
}

function resolutionRequest(turn: AgentTurnRequest): TurnContextResolutionRequest {
  return Object.freeze({
    clientTurnID: turn.client_turn_id,
    requestedSceneRevision: turn.client_scene_revision,
    requestedPointerContextID: turn.pointer_context_id,
    pendingProposalID: turn.pending_proposal_id,
    intentHint: turn.intent_hint,
  });
}

function freezeValidatedContext(context: AuthoritativeTurnContext): AuthoritativeTurnContext {
  if (
    !isOpaqueReference(context.sessionID) ||
    !Number.isSafeInteger(context.sceneRevision) ||
    context.sceneRevision < 0 ||
    !(context.pointerContextID === null || isOpaqueReference(context.pointerContextID))
  ) {
    throw new TypeError("invalid authoritative turn context");
  }
  return Object.freeze({
    sessionID: context.sessionID,
    sceneRevision: context.sceneRevision,
    pointerContextID: context.pointerContextID,
  });
}

function isOpaqueReference(value: string): boolean {
  return /^[A-Za-z][A-Za-z0-9_-]{0,127}$/u.test(value);
}
