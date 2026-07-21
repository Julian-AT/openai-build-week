import { expect, test } from "bun:test";

import submitUserTurn from "../schemas/submit-user-turn.schema.json";
import targetSeed from "../schemas/target-seed.schema.json";

test("submit_user_turn is a closed non-mutating intent envelope", () => {
  expect(submitUserTurn.additionalProperties).toBeFalse();
  expect(submitUserTurn.required).toEqual([
    "client_turn_id",
    "utterance",
    "intent_hint",
    "pointer_context_id",
    "client_scene_revision",
    "pending_proposal_id",
  ]);
  // The turn carries only an opaque pointer reference. It must not expose a
  // client-supplied world position; spatial context is bound server-side from
  // authoritative durable state.
  expect(Object.keys(submitUserTurn.properties).sort()).toEqual(
    [...submitUserTurn.required].sort(),
  );
  expect(submitUserTurn.properties).not.toHaveProperty("pointer_context");
});

test("all native pointing modes share one closed target seed contract", () => {
  expect(targetSeed.additionalProperties).toBeFalse();
  expect(targetSeed.properties.source.enum).toEqual([
    "reticle_dwell",
    "tap",
    "voice_capture",
    "debug_web",
  ]);
  expect(targetSeed.required).toContain("ray_world");
  expect(targetSeed.required).toContain("pixel_encoded");
});
