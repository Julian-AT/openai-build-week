import { expect, test } from "bun:test";

import { createFixedRoomModel } from "./fixed-room-model.ts";

test("the fixed room model is deterministic and well formed", () => {
  const model = createFixedRoomModel();
  const again = createFixedRoomModel();

  expect(model.id).toBe("reframe-fixed-room-model-v1");
  expect(model.parts.length).toBeGreaterThan(0);
  expect(model).toEqual(again);

  for (const part of model.parts) {
    expect(part.size.every((value) => value > 0)).toBeTrue();
    expect(part.position).toHaveLength(3);
    expect(part.color).toMatch(/^#[0-9a-f]{6}$/u);
  }
});
