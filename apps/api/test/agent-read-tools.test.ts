import { expect, test } from "bun:test";
import type { AgentToolCall, AuthoritativeTurnContext } from "@reframe/agent";
import type { CatalogRetriever } from "@reframe/catalog";

import { createAgentReadTools, type SceneAgentQueries } from "../src/agent-read-tools.ts";

const context: AuthoritativeTurnContext = {
  sessionID: "session_authoritative",
  sceneRevision: 7,
  pointerContextID: "pointer_authoritative",
};

test("catalog search combines semantic hints with geometry-owned fit scope", async () => {
  const searches: unknown[] = [];
  const retriever: CatalogRetriever = {
    search: async (request) => {
      searches.push(request);
      return [
        {
          id: "ikea-chair",
          assetID: "asset_chair",
          score: 0.92,
          name: "Chair",
          category: "chair",
          dimensionsM: { width: 0.8, height: 1, depth: 0.8 },
          supportType: "floor",
          cacheProfile: "iphone17",
        },
      ];
    },
  };
  const scene = sceneQueries();
  const tools = createAgentReadTools({ scene, catalog: retriever });

  const result = await tools.execute(
    call("search_catalog", {
      query: "comfortable",
      category: "chair",
      style: "warm modern",
      color: "red",
      material: null,
      limit: 8,
    }),
    context,
    new AbortController().signal,
  );

  expect(searches).toEqual([
    {
      query: "comfortable; style: warm modern; color: red",
      category: "chair",
      maxDimensionsM: { width: 0.9, height: 1.2, depth: 0.9 },
      supportType: "floor",
      cacheProfile: "iphone17",
      limit: 8,
    },
  ]);
  expect(result).toEqual({ candidates: expect.any(Array) });
});

test("all scene tools receive immutable server authority", async () => {
  const received: Array<[string, AuthoritativeTurnContext]> = [];
  let resolvedPointer: string | null | undefined;
  const scene = {
    ...sceneQueries(received),
    resolveTarget: async (
      authority: AuthoritativeTurnContext,
      request: { pointerContextID: string | null },
    ) => {
      received.push(["resolve", authority]);
      resolvedPointer = request.pointerContextID;
      return { target_id: "object_chair" };
    },
  } satisfies SceneAgentQueries;
  const tools = createAgentReadTools({
    scene,
    catalog: { search: async () => [] },
  });
  const signal = new AbortController().signal;

  await tools.execute(
    call("get_scene_context", { region: null, detail_level: "summary" }),
    context,
    signal,
  );
  await tools.execute(
    call("resolve_target", {
      pointer_context_id: "pointer_model_claim",
      language_reference: "the chair",
    }),
    context,
    signal,
  );
  await tools.execute(
    call("validate_candidate", {
      target_id: "object_chair",
      asset_id: "asset_chair",
      constraints: [],
    }),
    context,
    signal,
  );
  await tools.execute(
    call("prepare_edit_preview", {
      intent: "replace",
      target_id: "object_chair",
      asset_id: "asset_chair",
      constraints: [],
    }),
    context,
    signal,
  );

  expect(received.map(([name]) => name)).toEqual(["scene", "resolve", "validate", "preview"]);
  expect(received.every(([, authority]) => authority === context)).toBeTrue();
  expect(resolvedPointer).toBe("pointer_authoritative");
});

test("malformed and unknown arguments fail before domain calls", async () => {
  let calls = 0;
  const scene = sceneQueries([], () => {
    calls += 1;
  });
  const tools = createAgentReadTools({ scene, catalog: { search: async () => [] } });
  const signal = new AbortController().signal;

  await expect(
    tools.execute(
      call("search_catalog", {
        query: "chair",
        category: null,
        style: null,
        color: null,
        material: null,
        limit: 8,
        max_dimensions_m: { width: 99 },
      }),
      context,
      signal,
    ),
  ).rejects.toThrow("invalid_agent_tool_arguments");
  await expect(
    tools.execute(
      call("prepare_edit_preview", {
        intent: "replace",
        target_id: null,
        asset_id: "asset_chair",
        constraints: [],
      }),
      context,
      signal,
    ),
  ).rejects.toThrow("invalid_agent_tool_arguments");
  expect(calls).toBe(0);
});

function call(name: AgentToolCall["name"], args: unknown): AgentToolCall {
  return { type: "tool_call", callID: `call_${name}`, name, arguments: args };
}

function sceneQueries(
  received: Array<[string, AuthoritativeTurnContext]> = [],
  called: () => void = () => undefined,
): SceneAgentQueries {
  return {
    getSceneContext: async (authority) => {
      called();
      received.push(["scene", authority]);
      return { scene_revision: authority.sceneRevision };
    },
    resolveTarget: async (authority) => {
      called();
      received.push(["resolve", authority]);
      return { target_id: "object_chair" };
    },
    catalogScope: async () => ({
      category: "chair",
      maxDimensionsM: { width: 0.9, height: 1.2, depth: 0.9 },
      supportType: "floor",
      cacheProfile: "iphone17",
    }),
    validateCandidate: async (authority) => {
      called();
      received.push(["validate", authority]);
      return { valid: true };
    },
    prepareEditPreview: async (authority) => {
      called();
      received.push(["preview", authority]);
      return { preview_id: "preview_1" };
    },
  };
}
