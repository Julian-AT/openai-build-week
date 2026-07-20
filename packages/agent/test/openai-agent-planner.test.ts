import { expect, test } from "bun:test";

import {
  type AgentResponseGenerationRequest,
  createOpenAIResponsesAgentPlanner,
  REFRAME_AGENT_TOOLS,
} from "../src/index.ts";

test("every nested agent tool object is closed for strict function calling", () => {
  const serialized = JSON.stringify(REFRAME_AGENT_TOOLS);
  const objectSchemas = [...serialized.matchAll(/\{"type":"object"/gu)];
  const closedSchemas = [
    ...serialized.matchAll(/\{"type":"object","additionalProperties":false/gu),
  ];
  expect(closedSchemas).toHaveLength(objectSchemas.length);
});

test("preserves response items and tool outputs across a GPT-5.6 planning turn", async () => {
  const requests: AgentResponseGenerationRequest[] = [];
  const responses = [
    {
      responseID: "resp_1",
      outputItems: [
        { type: "reasoning", id: "reason_1", encrypted_content: "encrypted" },
        {
          type: "function_call",
          call_id: "call_search",
          name: "search_catalog",
          arguments: JSON.stringify({ query: "warm chair", limit: 8 }),
        },
      ],
      outputText: "",
    },
    {
      responseID: "resp_2",
      outputItems: [{ type: "message", id: "message_1" }],
      outputText: JSON.stringify({ operation: "replace", asset_id: "asset_red" }),
    },
  ];
  const planner = createOpenAIResponsesAgentPlanner({
    apiKey: "test-key",
    instructions: "Plan one safe preview.",
    proposalSchema: { type: "object" },
    generator: {
      generate: async (request) => {
        requests.push(request);
        const response = responses.shift();
        if (response === undefined) throw new Error("unexpected_response");
        return response;
      },
    },
  });
  const input = {
    clientTurnID: "turn_1",
    utterance: "Replace this chair",
    authoritativeContext: {
      sessionID: "session_1",
      sceneRevision: 3,
      pointerContextID: "pointer_1",
    },
  };

  const toolStep = await planner.next(input, [], new AbortController().signal);
  expect(toolStep).toEqual({
    type: "tool_call",
    callID: "call_search",
    name: "search_catalog",
    arguments: { query: "warm chair", limit: 8 },
  });
  const proposal = await planner.next(
    input,
    [{ callID: "call_search", name: "search_catalog", output: { candidates: ["asset_red"] } }],
    new AbortController().signal,
  );

  expect(proposal).toEqual({
    type: "proposal",
    responseID: "resp_2",
    proposal: { operation: "replace", asset_id: "asset_red" },
  });
  expect(requests[1]?.input).toContainEqual({
    type: "function_call_output",
    call_id: "call_search",
    output: JSON.stringify({ candidates: ["asset_red"] }),
  });
  expect(requests[1]?.input).toContainEqual({
    type: "reasoning",
    id: "reason_1",
    encrypted_content: "encrypted",
  });
  expect(requests[0]?.parallelToolCalls).toBeFalse();
});
