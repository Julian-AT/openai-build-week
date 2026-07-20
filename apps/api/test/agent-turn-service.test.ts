import { test } from "bun:test";
import assert from "node:assert/strict";

import {
  type AgentPlanner,
  type AgentReadToolExecutor,
  AgentToolPolicyError,
  type AgentTurnInput,
  type AuthoritativeTurnContext,
} from "@reframe/agent";
import type { AgentTurnRequest } from "../src/agent-turn.ts";
import {
  createAgentTurnService,
  createOpenAIResponsesPlannerFactory,
  type TurnContextResolutionRequest,
} from "../src/agent-turn-service.ts";

const clientTurn: AgentTurnRequest = {
  client_turn_id: "turn_019",
  utterance: "Replace this chair with something warmer.",
  intent_hint: "replace",
  pointer_context_id: "ptr_client_stale",
  client_scene_revision: 4,
  pending_proposal_id: "proposal_client_pending",
};

const authoritativeContext: AuthoritativeTurnContext = {
  sessionID: "session_server_authority",
  sceneRevision: 12,
  pointerContextID: "ptr_server_current",
};

test("agent turns use resolved authoritative context instead of client claims", async () => {
  let resolutionCredential: string | undefined;
  let resolutionRequest: TurnContextResolutionRequest | undefined;
  let plannerInput: AgentTurnInput | undefined;
  let toolContext: AuthoritativeTurnContext | undefined;
  let plannerCreations = 0;
  const planner: AgentPlanner = {
    next: async (input, outputs) => {
      plannerInput = input;
      if (outputs.length === 0) {
        return {
          type: "tool_call",
          callID: "call_scene",
          name: "get_scene_context",
          arguments: { region: null, detail_level: "summary" },
        };
      }
      return { type: "proposal", proposal: { status: "preview_ready" } };
    },
  };
  const tools: AgentReadToolExecutor = {
    execute: async (_call, context) => {
      toolContext = context;
      return { scene_revision: context.sceneRevision };
    },
  };
  const service = createAgentTurnService({
    contextResolver: {
      resolve: async (credential, request) => {
        resolutionCredential = credential;
        resolutionRequest = request;
        return authoritativeContext;
      },
    },
    plannerFactory: {
      create: () => {
        plannerCreations += 1;
        return planner;
      },
    },
    tools,
  });

  const result = await service.submit(
    "scoped-room-token",
    clientTurn,
    new AbortController().signal,
  );

  assert.deepEqual(result, { status: "preview_ready" });
  assert.equal(resolutionCredential, "scoped-room-token");
  assert.deepEqual(resolutionRequest, {
    clientTurnID: clientTurn.client_turn_id,
    requestedSceneRevision: 4,
    requestedPointerContextID: "ptr_client_stale",
    pendingProposalID: "proposal_client_pending",
    intentHint: "replace",
  });
  assert.deepEqual(plannerInput, {
    clientTurnID: clientTurn.client_turn_id,
    utterance: clientTurn.utterance,
    authoritativeContext,
  });
  assert.deepEqual(toolContext, authoritativeContext);
  assert.notEqual(
    plannerInput?.authoritativeContext.sceneRevision,
    clientTurn.client_scene_revision,
  );
  assert.notEqual(
    plannerInput?.authoritativeContext.pointerContextID,
    clientTurn.pointer_context_id,
  );
  assert.equal(plannerCreations, 1);
});

test("agent turn service makes mutation tools impossible", async () => {
  let toolCalls = 0;
  const service = createAgentTurnService({
    contextResolver: { resolve: async () => authoritativeContext },
    plannerFactory: {
      create: () => ({
        next: async () => ({
          type: "tool_call",
          callID: "call_mutate",
          name: "commit_scene" as never,
          arguments: {},
        }),
      }),
    },
    tools: {
      execute: async () => {
        toolCalls += 1;
        return {};
      },
    },
  });

  await assert.rejects(
    service.submit("scoped-room-token", clientTurn, new AbortController().signal),
    AgentToolPolicyError,
  );
  assert.equal(toolCalls, 0);
});

test("each agent turn receives an isolated planner", async () => {
  let plannerCreations = 0;
  const service = createAgentTurnService({
    contextResolver: { resolve: async () => authoritativeContext },
    plannerFactory: {
      create: () => {
        plannerCreations += 1;
        let used = false;
        return {
          next: async () => {
            assert.equal(used, false);
            used = true;
            return { type: "proposal", proposal: { planner: plannerCreations } };
          },
        };
      },
    },
    tools: { execute: async () => ({}) },
  });

  assert.deepEqual(
    await service.submit("scoped-room-token", clientTurn, new AbortController().signal),
    { planner: 1 },
  );
  assert.deepEqual(
    await service.submit("scoped-room-token", clientTurn, new AbortController().signal),
    { planner: 2 },
  );
  assert.equal(plannerCreations, 2);
});

test("OpenAI planner factories create a fresh bounded Responses planner per turn", async () => {
  const generatedInputs: unknown[][] = [];
  const factory = createOpenAIResponsesPlannerFactory({
    apiKey: "test-key",
    instructions: "Prepare one safe preview.",
    proposalSchema: { type: "object" },
    generator: {
      generate: async (request) => {
        generatedInputs.push([...request.input]);
        return {
          responseID: `response_${generatedInputs.length}`,
          outputItems: [],
          outputText: JSON.stringify({ status: "preview_ready" }),
        };
      },
    },
  });
  const input: AgentTurnInput = {
    clientTurnID: clientTurn.client_turn_id,
    utterance: clientTurn.utterance,
    authoritativeContext,
  };

  const first = await factory.create().next(input, [], new AbortController().signal);
  const second = await factory.create().next(input, [], new AbortController().signal);

  assert.deepEqual(first, {
    type: "proposal",
    responseID: "response_1",
    proposal: { status: "preview_ready" },
  });
  assert.deepEqual(second, {
    type: "proposal",
    responseID: "response_2",
    proposal: { status: "preview_ready" },
  });
  assert.equal(generatedInputs.length, 2);
  assert.equal(generatedInputs[0]?.length, 1);
  assert.equal(generatedInputs[1]?.length, 1);
});
