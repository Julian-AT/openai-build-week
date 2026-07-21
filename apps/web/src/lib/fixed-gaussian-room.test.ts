import { expect, test } from "bun:test";

import { createFixedGaussianRoom } from "./fixed-gaussian-room.ts";

test("builds the fixed room splat model deterministically within the web render budget", () => {
  const first = createFixedGaussianRoom();
  const second = createFixedGaussianRoom();

  expect(first.id).toBe("reframe-fixed-room-v1");
  expect(first.coordinateSystem).toEqual({ handedness: "right", upAxis: "+Y", units: "metres" });
  expect(first.splatCount).toBe(8_796);
  expect(first.positions.length).toBe(first.splatCount * 3);
  expect(first.colors.length).toBe(first.splatCount * 3);
  expect(first.radii.length).toBe(first.splatCount);
  expect([...first.positions]).toEqual([...second.positions]);
  expect([...first.colors]).toEqual([...second.colors]);
  expect([...first.radii]).toEqual([...second.radii]);
});

test("keeps every fixed room splat finite and inside the staged room envelope", () => {
  const room = createFixedGaussianRoom();

  expect([...room.positions].every(Number.isFinite)).toBe(true);
  expect([...room.colors].every((value) => value >= 0 && value <= 1)).toBe(true);
  expect([...room.radii].every((value) => value >= 0.004 && value <= 0.08)).toBe(true);

  expect(room.bounds.min[0]).toBeGreaterThanOrEqual(-4.1);
  expect(room.bounds.min[1]).toBeGreaterThanOrEqual(-0.1);
  expect(room.bounds.min[2]).toBeGreaterThanOrEqual(-5.1);
  expect(room.bounds.max[0]).toBeLessThanOrEqual(4.1);
  expect(room.bounds.max[1]).toBeLessThanOrEqual(3.7);
  expect(room.bounds.max[2]).toBeLessThanOrEqual(1.1);
});
