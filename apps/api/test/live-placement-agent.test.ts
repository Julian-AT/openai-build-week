import { expect, test } from "bun:test";
import type { AgentPlanner } from "@reframe/agent";
import type { CatalogRetriever } from "@reframe/catalog";
import { createInMemoryKnownTargetRegistry } from "../src/known-target-registry.ts";
import {
  createLivePlacementAgentTurnService,
  LIVE_PLACEMENT_PROPOSAL_SCHEMA,
} from "../src/live-placement-agent.ts";

const context = {
  sessionID: "session_agent_smoke",
  sceneRevision: 11,
  pointerContextID: "pointer_floor_smoke",
};

const assetID = "ikea-us-40541421-d74d34f0a861";

test("uses a strict-output schema that avoids unsupported regex lookarounds", () => {
  expect(JSON.stringify(LIVE_PLACEMENT_PROPOSAL_SCHEMA)).not.toContain("(?");
});

test("binds a GPT placement preview to a same-turn eligible catalog candidate", async () => {
  const searches: unknown[] = [];
  const service = createLivePlacementAgentTurnService({
    credential: "scoped-agent-smoke-token",
    context,
    catalog: {
      search: async (request) => {
        searches.push(request);
        return [
          {
            id: "ikea-us-40541421",
            assetID,
            score: 0.99,
            name: "HOLMERUD side table",
            category: "side_table",
            dimensionsM: { width: 0.81, height: 0.53, depth: 0.31 },
            supportType: "floor",
            cacheProfile: "ios-primary",
          },
        ];
      },
    } satisfies CatalogRetriever,
    scope: {
      category: "side_table",
      maxDimensionsM: { width: 0.9, height: 0.6, depth: 0.4 },
      supportType: "floor",
      cacheProfile: "ios-primary",
    },
    floorContactRF: { x: 1.25, y: 0, z: -2.5 },
    yawRadians: Math.PI / 2,
    nextProposalID: () => "proposal_10000000-0000-4000-8000-000000000001",
    plannerFactory: {
      create: () => placementPlanner("chair"),
    },
  });

  const result = await service.submit(
    "scoped-agent-smoke-token",
    {
      client_turn_id: "turn_placement_smoke",
      utterance: "Place a small oak side table on the floor.",
      intent_hint: "place",
      pointer_context_id: "ptr_client_claim",
      client_scene_revision: 3,
      pending_proposal_id: null,
    },
    new AbortController().signal,
  );

  expect(searches).toEqual([
    {
      query: "small oak side table",
      category: "side_table",
      maxDimensionsM: { width: 0.9, height: 0.6, depth: 0.4 },
      supportType: "floor",
      cacheProfile: "ios-primary",
      limit: 1,
    },
  ]);
  expect(result).toEqual({
    type: "placement_preview",
    status: "pending_confirmation",
    proposal_id: "proposal_10000000-0000-4000-8000-000000000001",
    base_scene_revision: 11,
    intent: { operation: "place", asset_id: assetID },
    world_from_asset: [0, 0, 1, 1.25, 0, 1, 0, 0, -1, 0, 0, -2.5, 0, 0, 0, 1],
    model: {
      provider: "openai",
      model: "gpt-5.6-sol",
      response_id: "resp_placement_123",
    },
    explanation: "The eligible table is ready for a local floor preview.",
  });
});

test("prepares the configured showcase asset without waiting for catalog or model I/O", async () => {
  let catalogCalls = 0;
  let plannerCalls = 0;
  const service = createLivePlacementAgentTurnService({
    credential: "scoped-agent-smoke-token",
    context,
    showcaseAssetID: assetID,
    catalog: {
      search: async () => {
        catalogCalls += 1;
        throw new Error("catalog_must_not_run");
      },
    },
    scope: {
      category: "side_table",
      maxDimensionsM: { width: 2, height: 2, depth: 2 },
      supportType: "floor",
      cacheProfile: "ios-primary",
    },
    floorContactRF: { x: 0.4, y: 0, z: -1.2 },
    yawRadians: 0,
    nextProposalID: () => "proposal_10000000-0000-4000-8000-000000000009",
    plannerFactory: {
      create: () => {
        plannerCalls += 1;
        return placementPlanner();
      },
    },
  });

  const result = await service.submit(
    "scoped-agent-smoke-token",
    {
      client_turn_id: "turn_showcase_smoke",
      utterance: "Anything at all",
      intent_hint: null,
      pointer_context_id: "pointer_showcase",
      client_scene_revision: 0,
      pending_proposal_id: null,
    },
    new AbortController().signal,
  );

  expect(catalogCalls).toBe(0);
  expect(plannerCalls).toBe(0);
  expect(result).toEqual({
    type: "placement_preview",
    status: "pending_confirmation",
    proposal_id: "proposal_10000000-0000-4000-8000-000000000009",
    base_scene_revision: 11,
    intent: { operation: "place", asset_id: assetID },
    world_from_asset: [1, 0, 0, 0.4, 0, 1, 0, 0, -0, 0, 1, -1.2, 0, 0, 0, 1],
    model: { provider: "deterministic", model: "showcase" },
    explanation: "Showcase asset ready for placement.",
  });
});

test("rejects a model response that does not reference the deterministic preview", async () => {
  const service = createLivePlacementAgentTurnService({
    credential: "scoped-agent-smoke-token",
    context,
    catalog: {
      search: async () => [
        {
          id: "ikea-us-40541421",
          assetID,
          score: 0.99,
          name: "HOLMERUD side table",
          category: "side_table",
          dimensionsM: { width: 0.81, height: 0.53, depth: 0.31 },
          supportType: "floor",
          cacheProfile: "ios-primary",
        },
      ],
    },
    scope: {
      category: "side_table",
      maxDimensionsM: { width: 0.9, height: 0.6, depth: 0.4 },
      supportType: "floor",
      cacheProfile: "ios-primary",
    },
    floorContactRF: { x: 0, y: 0, z: 0 },
    yawRadians: 0,
    nextProposalID: () => "proposal_10000000-0000-4000-8000-000000000001",
    plannerFactory: {
      create: () => invalidProposalPlanner(),
    },
  });

  await expect(
    service.submit(
      "scoped-agent-smoke-token",
      {
        client_turn_id: "turn_placement_smoke",
        utterance: "Place a side table.",
        intent_hint: "place",
        pointer_context_id: null,
        client_scene_revision: 11,
        pending_proposal_id: null,
      },
      new AbortController().signal,
    ),
  ).rejects.toThrow("agent_preview_not_authoritative");
});

test("prepares a replacement only for a resolved trusted target and fitting asset", async () => {
  const replacementContext = {
    sessionID: "room_agent_replace",
    sceneRevision: 4,
    pointerContextID: "pointer_42",
  } as const;
  const targetID = "object_80000000-0000-4000-8000-000000000001";
  const registry = createInMemoryKnownTargetRegistry([
    {
      sessionID: replacementContext.sessionID,
      targetID,
      pointerContextID: "pointer_42",
      languageReferences: ["chair", "the chair"],
      revealBundleID: "reveal_90000000-0000-4000-8000-000000000001",
      worldFromTarget: [1, 0, 0, 1, 0, 1, 0, 0, 0, 0, 1, -2, 0, 0, 0, 1],
      dimensionsM: { width: 0.9, height: 1.1, depth: 0.9 },
    },
  ]);
  const service = createLivePlacementAgentTurnService({
    credential: "scoped-agent-smoke-token",
    context: replacementContext,
    targetRegistry: registry,
    catalog: {
      search: async () => [
        {
          id: "ikea-us-40541421",
          assetID,
          score: 0.99,
          name: "HOLMERUD side table",
          category: "side_table",
          dimensionsM: { width: 0.81, height: 0.53, depth: 0.31 },
          supportType: "floor",
          cacheProfile: "ios-primary",
        },
      ],
    } satisfies CatalogRetriever,
    scope: {
      category: "side_table",
      maxDimensionsM: { width: 0.9, height: 1.2, depth: 0.9 },
      supportType: "floor",
      cacheProfile: "ios-primary",
    },
    floorContactRF: { x: 0, y: 0, z: 0 },
    yawRadians: 0,
    nextProposalID: () => "proposal_10000000-0000-4000-8000-000000000003",
    nextReplacementInstanceID: () => "instance_10000000-0000-4000-8000-000000000004",
    plannerFactory: { create: () => replacementPlanner(targetID) },
  });

  const result = await service.submit(
    "scoped-agent-smoke-token",
    {
      client_turn_id: "turn_replace_smoke",
      utterance: "Replace this chair with something warmer and red.",
      intent_hint: "replace",
      pointer_context_id: "pointer_42",
      client_scene_revision: 4,
      pending_proposal_id: null,
    },
    new AbortController().signal,
  );

  expect(result.intent).toEqual({ operation: "replace", target_id: targetID, asset_id: assetID });
  expect(result.world_from_asset).toEqual([1, 0, 0, 1, 0, 1, 0, 0, 0, 0, 1, -2, 0, 0, 0, 1]);
  expect(result.replacement).toEqual({
    instance_id: "instance_10000000-0000-4000-8000-000000000004",
    reveal_bundle_id: "reveal_90000000-0000-4000-8000-000000000001",
  });
});

function placementPlanner(requestedCategory = "side_table"): AgentPlanner {
  return {
    next: async (_input, outputs) => {
      if (outputs.length === 0) {
        return {
          type: "tool_call",
          callID: "call_catalog",
          name: "search_catalog",
          arguments: {
            query: "small oak side table",
            category: requestedCategory,
            style: null,
            color: null,
            material: null,
            limit: 1,
          },
        };
      }
      if (outputs.length === 1) {
        return {
          type: "tool_call",
          callID: "call_preview",
          name: "prepare_edit_preview",
          arguments: {
            intent: "place",
            target_id: null,
            asset_id: assetID,
            constraints: [],
          },
        };
      }
      const prepared = outputs[1]?.output as { proposal_id: string };
      return {
        type: "proposal",
        responseID: "resp_placement_123",
        proposal: {
          status: "preview_ready",
          proposal_id: prepared.proposal_id,
          explanation: "The eligible table is ready for a local floor preview.",
        },
      };
    },
  };
}

function invalidProposalPlanner(): AgentPlanner {
  const planner = placementPlanner();
  return {
    next: async (input, outputs, signal) => {
      const step = await planner.next(input, outputs, signal);
      if (step.type !== "proposal") return step;
      return {
        type: "proposal",
        ...(step.responseID === undefined ? {} : { responseID: step.responseID }),
        proposal: {
          ...(step.proposal as Record<string, unknown>),
          proposal_id: "proposal_20000000-0000-4000-8000-000000000002",
        },
      };
    },
  };
}

function replacementPlanner(targetID: string): AgentPlanner {
  return {
    next: async (_input, outputs) => {
      if (outputs.length === 0) {
        return {
          type: "tool_call",
          callID: "call_resolve",
          name: "resolve_target",
          arguments: { pointer_context_id: null, language_reference: "chair" },
        };
      }
      if (outputs.length === 1) {
        return {
          type: "tool_call",
          callID: "call_catalog",
          name: "search_catalog",
          arguments: {
            query: "warmer red chair",
            category: "side_table",
            style: null,
            color: "red",
            material: null,
            limit: 1,
          },
        };
      }
      if (outputs.length === 2) {
        return {
          type: "tool_call",
          callID: "call_validate",
          name: "validate_candidate",
          arguments: { target_id: targetID, asset_id: assetID, constraints: [] },
        };
      }
      if (outputs.length === 3) {
        return {
          type: "tool_call",
          callID: "call_preview",
          name: "prepare_edit_preview",
          arguments: { intent: "replace", target_id: targetID, asset_id: assetID, constraints: [] },
        };
      }
      const prepared = outputs[3]?.output as { proposal_id: string };
      return {
        type: "proposal",
        responseID: "resp_replace_123",
        proposal: {
          status: "preview_ready",
          proposal_id: prepared.proposal_id,
          explanation: "The trusted chair target has a fitting replacement preview.",
        },
      };
    },
  };
}
