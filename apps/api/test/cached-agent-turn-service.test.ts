import { test } from "bun:test";
import assert from "node:assert/strict";

import type { AgentTurnRequest } from "../src/agent-turn.ts";
import { createCachedAgentTurnService } from "../src/cached-agent-turn-service.ts";

const turn: AgentTurnRequest = {
  client_turn_id: "turn_cache_01",
  utterance: "Place the table in front of me.",
  intent_hint: "place",
  pointer_context_id: "pointer_floor_01",
  client_scene_revision: 3,
  pending_proposal_id: null,
};

test("deduplicates identical in-flight turns and reuses the completed preview", async () => {
  let calls = 0;
  let release: (() => void) | undefined;
  const service = createCachedAgentTurnService(
    {
      submit: async () => {
        calls += 1;
        await new Promise<void>((resolve) => {
          release = resolve;
        });
        return Object.freeze({ preview_id: "preview_cache_01", base_scene_revision: 3 });
      },
    },
    { ttlMilliseconds: 30_000 },
  );
  const first = service.submit("room-a", turn, new AbortController().signal);
  const second = service.submit("room-a", turn, new AbortController().signal);
  await Promise.resolve();
  assert.equal(calls, 1);
  release?.();
  assert.deepEqual(await first, await second);
  assert.deepEqual(await service.submit("room-a", turn, new AbortController().signal), {
    preview_id: "preview_cache_01",
    base_scene_revision: 3,
  });
  assert.equal(calls, 1);
});

test("isolates rooms and does not cache failures", async () => {
  let calls = 0;
  const service = createCachedAgentTurnService({
    submit: async (credential) => {
      calls += 1;
      if (credential === "room-a") throw new Error("transient");
      return { room: credential };
    },
  });
  await assert.rejects(service.submit("room-a", turn, new AbortController().signal), /transient/);
  await assert.rejects(service.submit("room-a", turn, new AbortController().signal), /transient/);
  assert.deepEqual(await service.submit("room-b", turn, new AbortController().signal), {
    room: "room-b",
  });
  assert.equal(calls, 3);
});

test("expires entries and keeps cancellation scoped to the waiting request", async () => {
  let timestamp = 1_000;
  let calls = 0;
  const service = createCachedAgentTurnService(
    {
      submit: async () => {
        calls += 1;
        return { preview_id: `preview_${calls}` };
      },
    },
    { now: () => timestamp, ttlMilliseconds: 1_000 },
  );
  const first = await service.submit("room-a", turn, new AbortController().signal);
  const controller = new AbortController();
  const pending = service.submit("room-a", turn, controller.signal);
  controller.abort(new Error("caller_disconnected"));
  await assert.rejects(pending, /caller_disconnected/);
  assert.deepEqual(first, { preview_id: "preview_1" });
  timestamp += 1_001;
  assert.deepEqual(await service.submit("room-a", turn, new AbortController().signal), {
    preview_id: "preview_2",
  });
  assert.equal(calls, 2);
});
