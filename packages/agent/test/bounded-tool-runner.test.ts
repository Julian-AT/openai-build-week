import { expect, test } from "bun:test";

import {
  type AgentPlanner,
  type AgentReadToolExecutor,
  AgentToolPolicyError,
  runBoundedAgentTurn,
  runBoundedAgentTurnResult,
} from "../src/index.ts";

test("runs bounded read-only tools and returns one prepared proposal", async () => {
  const steps = [
    {
      type: "tool_call" as const,
      callID: "call_search",
      name: "search_catalog" as const,
      arguments: { query: "warm red chair", limit: 8 },
    },
    {
      type: "proposal" as const,
      proposal: { operation: "replace", asset_id: "asset_red" },
    },
  ];
  const planner: AgentPlanner = {
    next: async () => {
      const step = steps.shift();
      if (step === undefined) throw new Error("unexpected_step");
      return step;
    },
  };
  const calls: string[] = [];
  const tools: AgentReadToolExecutor = {
    execute: async (call) => {
      calls.push(call.name);
      return { candidates: [{ asset_id: "asset_red" }] };
    },
  };

  const result = await runBoundedAgentTurn(
    {
      clientTurnID: "turn_1",
      utterance: "Replace this with a warm red chair",
      authoritativeContext: {
        sessionID: "session_1",
        sceneRevision: 4,
        pointerContextID: "pointer_1",
      },
    },
    planner,
    tools,
    new AbortController().signal,
  );

  expect(calls).toEqual(["search_catalog"]);
  expect(result).toEqual({ operation: "replace", asset_id: "asset_red" });
});

test("rejects model attempts to invoke mutating tools", async () => {
  const planner: AgentPlanner = {
    next: async () => ({
      type: "tool_call",
      callID: "call_commit",
      name: "commit" as never,
      arguments: {},
    }),
  };
  const tools: AgentReadToolExecutor = { execute: async () => ({}) };

  await expect(
    runBoundedAgentTurn(
      {
        clientTurnID: "turn_1",
        utterance: "Do it",
        authoritativeContext: {
          sessionID: "session_1",
          sceneRevision: 4,
          pointerContextID: "pointer_1",
        },
      },
      planner,
      tools,
      new AbortController().signal,
    ),
  ).rejects.toBeInstanceOf(AgentToolPolicyError);
});

test("caps catalog inspection at eight candidates before executing the tool", async () => {
  const planner: AgentPlanner = {
    next: async () => ({
      type: "tool_call",
      callID: "call_search",
      name: "search_catalog",
      arguments: { query: "chair", limit: 9 },
    }),
  };
  let executed = false;
  const tools: AgentReadToolExecutor = {
    execute: async () => {
      executed = true;
      return {};
    },
  };

  await expect(
    runBoundedAgentTurn(
      {
        clientTurnID: "turn_1",
        utterance: "Find a chair",
        authoritativeContext: {
          sessionID: "session_1",
          sceneRevision: 4,
          pointerContextID: null,
        },
      },
      planner,
      tools,
      new AbortController().signal,
    ),
  ).rejects.toThrow("invalid_catalog_candidate_limit");
  expect(executed).toBeFalse();
});

test("preserves the provider response identifier with a completed proposal", async () => {
  const planner: AgentPlanner = {
    next: async () => ({
      type: "proposal",
      responseID: "resp_placement_123",
      proposal: { status: "preview_ready" },
    }),
  };

  await expect(
    runBoundedAgentTurnResult(
      {
        clientTurnID: "turn_1",
        utterance: "Place a table",
        authoritativeContext: {
          sessionID: "session_1",
          sceneRevision: 4,
          pointerContextID: "pointer_1",
        },
      },
      planner,
      { execute: async () => ({}) },
      new AbortController().signal,
    ),
  ).resolves.toEqual({
    proposal: { status: "preview_ready" },
    responseID: "resp_placement_123",
  });
});
