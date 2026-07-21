import { expect, test } from "bun:test";

import { labelVoxels } from "./apartment-analysis.ts";

function buildScene(): Float32Array {
  const points: number[] = [];
  // A large 100x100 floor plane at y = 0 dominates the scene.
  for (let ix = 0; ix < 100; ix += 1) {
    for (let iz = 0; iz < 100; iz += 1) {
      points.push(ix, 0, iz);
    }
  }
  // A small dense object resting on the floor, separated from its edges.
  for (let ix = 48; ix < 54; ix += 1) {
    for (let iy = 3; iy < 9; iy += 1) {
      for (let iz = 48; iz < 54; iz += 1) {
        points.push(ix, iy, iz);
      }
    }
  }
  return new Float32Array(points);
}

test("labels the dominant plane and a separated cluster from geometry alone", () => {
  const { labels, up } = labelVoxels(buildScene(), 1);
  const texts = labels.map((label) => label.text);

  expect(texts).toContain("Floor");
  expect(texts.some((text) => text.startsWith("Region"))).toBeTrue();
  for (const label of labels) {
    expect(label.position).toHaveLength(3);
    expect(label.position.every((value) => Number.isFinite(value))).toBeTrue();
  }
  // The floor is the y = 0 plane, so the detected up-axis is vertical.
  expect(up).not.toBeNull();
  const upVec = up as readonly [number, number, number];
  expect(Math.abs(upVec[1])).toBeGreaterThan(0.9);
});

test("returns nothing for an empty cloud", () => {
  expect(labelVoxels(new Float32Array([]), 1)).toEqual({ labels: [], up: null });
});
