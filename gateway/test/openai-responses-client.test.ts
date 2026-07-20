import assert from "node:assert/strict";
import { test } from "node:test";

import { createOpenAIProposalModelClient } from "../src/openai-responses-client.ts";

test("the Responses adapter sends vision input with a strict server-owned schema", async () => {
  let body: unknown;
  let requestOptions: unknown;
  const modelOutput = {
    status: "ready",
    intent: {
      operation: "place",
      arguments: { asset_id: "asset_53000000-0000-4000-8000-000000000004" },
      constraints: [],
    },
    explanation: "A side table fits the request.",
    clarification: null,
  };
  const client = createOpenAIProposalModelClient({
    responses: {
      create: async (receivedBody, receivedOptions) => {
        body = receivedBody;
        requestOptions = receivedOptions;
        return {
          id: "resp_vision",
          output_text: JSON.stringify(modelOutput),
        };
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
  assert.deepEqual(requestOptions, { signal: controller.signal });
  assert(body && typeof body === "object");
  const request = body as Record<string, unknown>;
  assert.equal(request.model, "gpt-5.6-sol");
  assert.equal(request.store, false);
  assert.equal(request.max_output_tokens, 800);
  assert.deepEqual(request.input, [
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
  assert.match(String(request.instructions), /Warm Arc Chair/u);
  assert.match(String(request.instructions), /never.*transform/iu);

  const text = request.text as {
    format: { type: string; name: string; strict: boolean; schema: Record<string, unknown> };
  };
  assert.equal(text.format.type, "json_schema");
  assert.equal(text.format.name, "reroom_semantic_proposal");
  assert.equal(text.format.strict, true);
  assert.equal(text.format.schema.additionalProperties, false);
  assert.deepEqual(text.format.schema.required, [
    "status",
    "intent",
    "explanation",
    "clarification",
  ]);
});

test("the Responses adapter rejects malformed output without leaking it", async () => {
  const client = createOpenAIProposalModelClient({
    responses: {
      create: async () => ({ id: "resp_bad", output_text: "sk-sensitive-not-json" }),
    },
  });

  await assert.rejects(
    client.generate({ prompt: "A prompt" }, new AbortController().signal),
    /^Error: invalid_model_output$/u,
  );
});

test("the Responses adapter rejects duplicate model-output member names", async () => {
  const client = createOpenAIProposalModelClient({
    responses: {
      create: async () => ({
        id: "resp_duplicate",
        output_text:
          '{"\\u0073tatus":"needs_clarification","status":"ready","intent":{"operation":"restore","arguments":{},"constraints":[]},"explanation":"Restore the latest eligible edit.","clarification":null}',
      }),
    },
  });

  await assert.rejects(
    client.generate({ prompt: "Restore the room" }, new AbortController().signal),
    /^Error: invalid_model_output$/u,
  );
});
