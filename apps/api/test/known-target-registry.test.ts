import { expect, test } from "bun:test";

import { createInMemoryKnownTargetRegistry } from "../src/known-target-registry.ts";

const target = {
  sessionID: "room_2026_07_21_scene",
  targetID: "object_80000000-0000-4000-8000-000000000001",
  pointerContextID: "pointer_42",
  languageReferences: ["the chair", "chair"],
  revealBundleID: "reveal_90000000-0000-4000-8000-000000000001",
  worldFromTarget: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, -2, 1],
  dimensionsM: { width: 0.8, height: 1, depth: 0.8 },
} as const;

test("resolves only one trusted target in the authenticated room", () => {
  const registry = createInMemoryKnownTargetRegistry([target]);
  expect(
    registry.resolve(target.sessionID, {
      pointerContextID: target.pointerContextID,
      languageReference: null,
    }),
  ).toEqual({ ...target, languageReferences: ["the chair", "chair"] });
  const languageMatch = registry.resolve(target.sessionID, {
    pointerContextID: null,
    languageReference: " Chair ",
  });
  expect(languageMatch?.targetID).toBe(target.targetID);
  expect(
    registry.resolve("room_other_scene", {
      pointerContextID: target.pointerContextID,
      languageReference: null,
    }),
  ).toBeNull();
});

test("fails closed for ambiguous language-only target resolution", () => {
  const second = {
    ...target,
    targetID: "object_80000000-0000-4000-8000-000000000002",
    pointerContextID: "pointer_43",
  } as const;
  const registry = createInMemoryKnownTargetRegistry([target, second]);
  expect(
    registry.resolve(target.sessionID, { pointerContextID: null, languageReference: "chair" }),
  ).toBeNull();
});

test("rejects fabricated or malformed target records", () => {
  expect(() =>
    createInMemoryKnownTargetRegistry([{ ...target, targetID: "object_fabricated" }]),
  ).toThrow("invalid_known_target");
  expect(() => createInMemoryKnownTargetRegistry([{ ...target, worldFromTarget: [1] }])).toThrow(
    "invalid_known_target",
  );
});
