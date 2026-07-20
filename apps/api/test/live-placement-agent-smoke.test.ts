import { expect, test } from "bun:test";

import { parseLivePlacementAgentSmokeEnvironment } from "../src/live-placement-agent-smoke.ts";

test("parses an explicit server-side live placement proof configuration", () => {
  const configuration = parseLivePlacementAgentSmokeEnvironment({
    OPENAI_API_KEY: "test-openai-key",
    REFRAME_QDRANT_URL: "http://127.0.0.1:6333",
    QDRANT_API_KEY: "test-qdrant-key",
    REFRAME_AGENT_SMOKE_CREDENTIAL: "scoped-agent-smoke-token",
    REFRAME_AGENT_SMOKE_SESSION_ID: "session_agent_smoke",
    REFRAME_AGENT_SMOKE_POINTER_CONTEXT_ID: "pointer_floor_smoke",
    REFRAME_AGENT_SMOKE_SCENE_REVISION: "11",
    REFRAME_AGENT_SMOKE_TURN_ID: "turn_placement_smoke",
    REFRAME_AGENT_SMOKE_UTTERANCE: "Place a small oak side table on the floor.",
    REFRAME_AGENT_SMOKE_CATEGORY: "side_table",
    REFRAME_AGENT_SMOKE_MAX_WIDTH_M: "0.9",
    REFRAME_AGENT_SMOKE_MAX_HEIGHT_M: "0.6",
    REFRAME_AGENT_SMOKE_MAX_DEPTH_M: "0.4",
    REFRAME_AGENT_SMOKE_SUPPORT_TYPE: "floor",
    REFRAME_AGENT_SMOKE_CACHE_PROFILE: "ios-primary",
    REFRAME_AGENT_SMOKE_FLOOR_X_M: "1.25",
    REFRAME_AGENT_SMOKE_FLOOR_Y_M: "0",
    REFRAME_AGENT_SMOKE_FLOOR_Z_M: "-2.5",
    REFRAME_AGENT_SMOKE_YAW_RADIANS: "1.5707963267948966",
  });

  expect(configuration.context).toEqual({
    sessionID: "session_agent_smoke",
    sceneRevision: 11,
    pointerContextID: "pointer_floor_smoke",
  });
  expect(configuration.scope).toEqual({
    category: "side_table",
    maxDimensionsM: { width: 0.9, height: 0.6, depth: 0.4 },
    supportType: "floor",
    cacheProfile: "ios-primary",
  });
  expect(configuration.turn).toEqual({
    client_turn_id: "turn_placement_smoke",
    utterance: "Place a small oak side table on the floor.",
    intent_hint: "place",
    pointer_context_id: "pointer_floor_smoke",
    client_scene_revision: 11,
    pending_proposal_id: null,
  });
});

test("fails closed when a live placement proof lacks its Qdrant credential", () => {
  expect(() =>
    parseLivePlacementAgentSmokeEnvironment({
      OPENAI_API_KEY: "test-openai-key",
      REFRAME_QDRANT_URL: "http://127.0.0.1:6333",
    }),
  ).toThrow("missing_qdrant_api_key");
});
