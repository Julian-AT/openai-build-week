import { test } from "bun:test";
import assert from "node:assert/strict";

import {
  buildDesignCopilotInstructions,
  createOpenAIProposalModelClient,
  PROPOSAL_MODEL,
  type ProposalGenerationRequest,
} from "../src/index.ts";

const outputSchema = {
  type: "object",
  additionalProperties: false,
  properties: { status: { type: "string" } },
  required: ["status"],
} as const;

test("the AI SDK adapter binds model, schema, consented image, and abort signal", async () => {
  let receivedRequest: ProposalGenerationRequest | undefined;
  let receivedSignal: AbortSignal | undefined;
  const modelOutput = { status: "ready" };
  const client = createOpenAIProposalModelClient({
    apiKey: "test-api-key",
    instructions: "Return only the semantic proposal.",
    outputSchema,
    generator: {
      generate: async (request, signal) => {
        receivedRequest = request;
        receivedSignal = signal;
        return { responseID: "resp_vision", output: modelOutput };
      },
    },
  });
  const controller = new AbortController();

  const result = await client.generate(
    {
      prompt: "Add a small blue table.",
      image_data_url: "data:image/jpeg;base64,/9j/2Q==",
    },
    controller.signal,
  );

  assert.deepEqual(result, { responseID: "resp_vision", output: modelOutput });
  assert.equal(receivedSignal, controller.signal);
  assert.deepEqual(receivedRequest, {
    model: PROPOSAL_MODEL,
    prompt: "Add a small blue table.",
    imageDataURL: "data:image/jpeg;base64,/9j/2Q==",
    instructions: "Return only the semantic proposal.",
    outputSchema,
    maxOutputTokens: 800,
    store: false,
  });
});

test("the adapter omits image input when the native boundary did not consent", async () => {
  let receivedRequest: ProposalGenerationRequest | undefined;
  const client = createOpenAIProposalModelClient({
    apiKey: "test-api-key",
    instructions: "Return only JSON.",
    outputSchema,
    generator: {
      generate: async (request) => {
        receivedRequest = request;
        return { responseID: "resp_typed", output: { status: "ready" } };
      },
    },
  });

  await client.generate({ prompt: "Add a table." }, new AbortController().signal);

  assert(receivedRequest !== undefined);
  assert.equal("imageDataURL" in receivedRequest, false);
});

test("the provider adapter fails closed without a server API key", () => {
  assert.throws(
    () =>
      createOpenAIProposalModelClient({
        apiKey: "",
        instructions: "Return only JSON.",
        outputSchema,
      }),
    /^Error: missing_openai_api_key$/u,
  );
});

test("the production AI SDK path sends a non-retained strict Responses request", async () => {
  let capturedURL: string | undefined;
  let capturedInit: RequestInit | undefined;
  const controller = new AbortController();
  const fakeFetch = Object.assign(
    async (input: URL | RequestInfo, init?: RequestInit) => {
      capturedURL = input instanceof Request ? input.url : input.toString();
      capturedInit = init;
      return Response.json({
        id: "resp_sdk",
        object: "response",
        status: "completed",
        created_at: 1_750_000_000,
        model: PROPOSAL_MODEL,
        output: [
          {
            type: "message",
            role: "assistant",
            id: "msg_sdk",
            content: [
              {
                type: "output_text",
                text: JSON.stringify({ status: "ready" }),
                annotations: [],
                logprobs: [],
              },
            ],
          },
        ],
        usage: {
          input_tokens: 10,
          input_tokens_details: { cached_tokens: 0 },
          output_tokens: 4,
          output_tokens_details: { reasoning_tokens: 0 },
        },
      });
    },
    { preconnect: (_url: string | URL) => undefined },
  );
  const client = createOpenAIProposalModelClient({
    apiKey: "test-api-key",
    instructions: "Return only the semantic proposal.",
    outputSchema,
    fetch: fakeFetch,
  });

  const result = await client.generate(
    {
      prompt: "Add a small blue table.",
      image_data_url: "data:image/jpeg;base64,/9j/2Q==",
    },
    controller.signal,
  );

  assert.deepEqual(result, { responseID: "resp_sdk", output: { status: "ready" } });
  assert.equal(capturedURL, "https://api.openai.com/v1/responses");
  assert(capturedInit?.signal instanceof AbortSignal);
  assert.equal(capturedInit.signal.aborted, false);
  assert(capturedInit?.body !== undefined && capturedInit.body !== null);
  const body = JSON.parse(capturedInit.body.toString()) as Record<string, unknown>;
  assert.equal(body.model, PROPOSAL_MODEL);
  assert.equal(body.store, false);
  assert.equal(body.max_output_tokens, 800);
  assert.deepEqual(body.reasoning, { effort: "low" });
  assert.deepEqual(body.text, {
    format: {
      type: "json_schema",
      name: "semantic_proposal",
      strict: true,
      schema: outputSchema,
    },
    verbosity: "low",
  });
  assert.equal(body.instructions, "Return only the semantic proposal.");
  assert.deepEqual(body.input, [
    {
      role: "user",
      content: [
        { type: "input_text", text: "Add a small blue table." },
        {
          type: "input_image",
          image_url: "data:image/jpeg;base64,/9j/2Q==",
          detail: "low",
        },
      ],
    },
  ]);
});

test("the design instructions close catalog and mutation authority", () => {
  const instructions = buildDesignCopilotInstructions([
    { assetID: "asset_one", name: "Warm Arc Chair" },
    { assetID: "asset_two", name: "Halo Side Table" },
  ]);

  assert.match(instructions, /asset_one: Warm Arc Chair/u);
  assert.match(instructions, /asset_two: Halo Side Table/u);
  assert.match(instructions, /never.*transform/iu);
  assert.match(instructions, /never[\s\S]*commit/iu);
  assert.match(instructions, /untrusted data/iu);
});
