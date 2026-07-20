import { test } from "bun:test";
import assert from "node:assert/strict";

import { GpuLaneCoordinator, type GpuWorkKind } from "../src/gpu-lane-coordinator.ts";

test("runs active target semantics ahead of queued depth once a background kernel boundary completes", async () => {
  const coordinator = new GpuLaneCoordinator();
  const started: GpuWorkKind[] = [];
  let releaseBackground: (() => void) | undefined;
  const background = coordinator.submit({
    id: "background_1",
    kind: "dense_background",
    run: async () => {
      started.push("dense_background");
      await new Promise<void>((resolve) => {
        releaseBackground = resolve;
      });
    },
  });
  await eventually(() => started.length === 1);
  const depth = coordinator.submit({
    id: "depth_1",
    kind: "live_depth",
    run: async () => {
      started.push("live_depth");
    },
  });
  const target = coordinator.submit({
    id: "target_1",
    kind: "target_semantics",
    run: async () => {
      started.push("target_semantics");
    },
  });

  releaseBackground?.();
  assert.deepEqual(await background, { status: "completed" });
  assert.deepEqual(await target, { status: "completed" });
  assert.deepEqual(await depth, { status: "completed" });
  assert.deepEqual(started, ["dense_background", "target_semantics", "live_depth"]);
});

test("retains only the newest queued live depth frame and never launches Mode B1 during Mode A", async () => {
  const coordinator = new GpuLaneCoordinator({ modeAActive: () => true });
  const started: string[] = [];
  let releaseTarget: (() => void) | undefined;
  const target = coordinator.submit({
    id: "target_2",
    kind: "target_semantics",
    run: async () => {
      started.push("target");
      await new Promise<void>((resolve) => {
        releaseTarget = resolve;
      });
    },
  });
  await eventually(() => started.length === 1);
  const staleDepth = coordinator.submit({
    id: "depth_stale",
    kind: "live_depth",
    run: async () => {
      started.push("stale");
    },
  });
  const newestDepth = coordinator.submit({
    id: "depth_newest",
    kind: "live_depth",
    run: async () => {
      started.push("newest");
    },
  });
  const polish = coordinator.submit({
    id: "polish_1",
    kind: "b1_polish",
    run: async () => {
      started.push("polish");
    },
  });

  assert.deepEqual(await staleDepth, { status: "dropped", reason: "superseded" });
  assert.deepEqual(await polish, { status: "dropped", reason: "mode_a_active" });
  releaseTarget?.();
  assert.deepEqual(await target, { status: "completed" });
  assert.deepEqual(await newestDepth, { status: "completed" });
  assert.deepEqual(started, ["target", "newest"]);
});

test("does not launch work cancelled before it reaches the GPU", async () => {
  const coordinator = new GpuLaneCoordinator();
  const controller = new AbortController();
  controller.abort();
  const result = await coordinator.submit({
    id: "cancelled_1",
    kind: "reveal_generation",
    signal: controller.signal,
    run: async () => {
      throw new Error("must not run");
    },
  });
  assert.deepEqual(result, { status: "cancelled" });
});

async function eventually(predicate: () => boolean): Promise<void> {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  assert.fail("condition was not reached");
}
