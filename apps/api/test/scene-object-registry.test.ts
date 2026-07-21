import { test } from "bun:test";
import assert from "node:assert/strict";

import {
  objectIDForInstance,
  SceneObjectRegistry,
  SceneObjectRegistryError,
} from "../src/scene-object-registry.ts";

const sessionID = "room_registry_001";
const objectID = "object_80000000-0000-4000-8000-000000000001";
const instanceID = "instance_80000000-0000-4000-8000-000000000001";
const bounds = { center: [1, 0.5, -2] as const, halfExtents: [0.4, 0.5, 0.3] as const };
const maskSHA256 = "a".repeat(64);

function createRegistry(): SceneObjectRegistry {
  const registry = new SceneObjectRegistry();
  registry.registerPlacedObject({
    sessionID,
    objectID,
    instanceID,
    assetID: "ikea-us-40541421-d74d34f0a861",
    bounds,
    introducedAtSceneRevision: 1,
  });
  return registry;
}

test("registers placed objects and resolves only authoritative visible targets", () => {
  const registry = createRegistry();
  const resolved = registry.resolveTarget({ sessionID, targetID: objectID, sceneRevision: 1 });
  assert.equal(resolved.instanceID, instanceID);
  assert.equal(objectIDForInstance(instanceID), objectID);
  assert.equal(Object.isFrozen(resolved), true);

  registry.setVisibility(sessionID, objectID, "hidden");
  assert.throws(
    () => registry.resolveTarget({ sessionID, targetID: objectID, sceneRevision: 2 }),
    (error: unknown) =>
      error instanceof SceneObjectRegistryError && error.code === "scene_object_not_visible",
  );
});

test("pointer resolution is bounded, revision-aware, and fails closed for unknown rooms", () => {
  const registry = createRegistry();
  assert.equal(
    registry.resolvePointer({
      sessionID,
      sceneRevision: 1,
      worldPoint: [1.1, 0.5, -2],
    })?.objectID,
    objectID,
  );
  assert.equal(
    registry.resolvePointer({
      sessionID,
      sceneRevision: 0,
      worldPoint: [1.1, 0.5, -2],
    }),
    undefined,
  );
  assert.equal(
    registry.resolvePointer({
      sessionID: "room_registry_other",
      sceneRevision: 1,
      worldPoint: [1.1, 0.5, -2],
    }),
    undefined,
  );
  assert.throws(
    () =>
      registry.resolveTarget({
        sessionID,
        targetID: "object_00000000-0000-4000-8000-000000000002",
        sceneRevision: 1,
      }),
    (error: unknown) =>
      error instanceof SceneObjectRegistryError && error.code === "unknown_scene_object",
  );
});

test("SAM tracks bind only to a known Reframe object and reject unsafe or stale observations", () => {
  const registry = createRegistry();
  const bound = registry.bindSamTrack({
    sessionID,
    targetID: objectID,
    frameID: 12,
    trackRevision: 1,
    confidence: 0.91,
    maskSHA256,
    status: "tracked",
  });
  assert.equal(bound.track?.frameID, 12);
  assert.equal(bound.track?.trackRevision, 1);

  assert.throws(
    () =>
      registry.bindSamTrack({
        sessionID,
        targetID: objectID,
        frameID: 12,
        trackRevision: 2,
        confidence: 0.95,
        maskSHA256,
        status: "tracked",
      }),
    (error: unknown) =>
      error instanceof SceneObjectRegistryError && error.code === "stale_scene_object_track",
  );
  assert.throws(
    () =>
      registry.bindSamTrack({
        sessionID,
        targetID: "object_00000000-0000-4000-8000-000000000002",
        frameID: 13,
        trackRevision: 2,
        confidence: 0.95,
        maskSHA256,
        status: "tracked",
      }),
    (error: unknown) =>
      error instanceof SceneObjectRegistryError && error.code === "unknown_scene_object",
  );
  assert.throws(
    () =>
      registry.bindSamTrack({
        sessionID,
        targetID: objectID,
        frameID: 13,
        trackRevision: 2,
        confidence: 0.49,
        maskSHA256,
        status: "tracked",
      }),
    (error: unknown) =>
      error instanceof SceneObjectRegistryError && error.code === "unsafe_scene_object_track",
  );
});
