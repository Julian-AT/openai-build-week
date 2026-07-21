import { expect, test } from "bun:test";

import { createOpenAIModelCapabilityProbe, REQUIRED_OPENAI_MODELS } from "../src/index.ts";

test("reports readiness only when both exact configured model IDs exist", async () => {
  const probe = createOpenAIModelCapabilityProbe({
    apiKey: "server-only-test-key",
    nowMilliseconds: () => 123,
    fetch: async (_input, init) => {
      expect(init?.headers).toEqual({ Authorization: "Bearer server-only-test-key" });
      return Response.json({ data: REQUIRED_OPENAI_MODELS.map((id) => ({ id })) });
    },
  });

  await expect(probe.check()).resolves.toEqual({
    status: "ready",
    models: { "gpt-5.6-sol": true, "gpt-realtime-2.1": true },
    checkedAtMilliseconds: 123,
  });
});

test("degrades instead of substituting a missing exact model", async () => {
  const probe = createOpenAIModelCapabilityProbe({
    apiKey: "server-only-test-key",
    fetch: async () => Response.json({ data: [{ id: "gpt-5.6-sol" }] }),
  });

  await expect(probe.check()).resolves.toMatchObject({
    status: "degraded",
    models: { "gpt-5.6-sol": true, "gpt-realtime-2.1": false },
  });
});

test("fails closed for malformed model capability responses", async () => {
  const probe = createOpenAIModelCapabilityProbe({
    apiKey: "server-only-test-key",
    fetch: async () => Response.json({ models: [] }),
  });
  await expect(probe.check()).rejects.toThrow("invalid_openai_model_capability_response");
});
