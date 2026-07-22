import { expect, test } from "bun:test";

import { reconstructSurface } from "./apartment-surface.ts";

function spherePoints(radius: number, samples: number): Float32Array {
  const values: number[] = [];
  for (let i = 0; i < samples; i += 1) {
    const y = 1 - (2 * (i + 0.5)) / samples;
    const r = Math.sqrt(Math.max(0, 1 - y * y));
    const angle = Math.PI * (3 - Math.sqrt(5)) * i;
    values.push(Math.cos(angle) * r * radius, y * radius, Math.sin(angle) * r * radius);
  }
  return new Float32Array(values);
}

test("reconstructs a closed surface hugging a sphere of points", () => {
  const radius = 10;
  const mesh = reconstructSurface(spherePoints(radius, 6000), 32);

  expect(mesh.positions.length).toBeGreaterThan(0);
  expect(mesh.indices.length).toBeGreaterThan(0);
  expect(mesh.indices.length % 3).toBe(0);

  let sum = 0;
  const vertexCount = mesh.positions.length / 3;
  for (let i = 0; i < mesh.positions.length; i += 3) {
    sum += Math.hypot(mesh.positions[i], mesh.positions[i + 1], mesh.positions[i + 2]);
  }
  const meanRadius = sum / vertexCount;
  // The isosurface sits within a couple of cells of the sampled sphere.
  expect(meanRadius).toBeGreaterThan(radius - 2);
  expect(meanRadius).toBeLessThan(radius + 2);

  // Every index references a real vertex.
  for (const index of mesh.indices) {
    expect(index).toBeLessThan(vertexCount);
  }
});

test("returns an empty mesh for an empty cloud", () => {
  const mesh = reconstructSurface(new Float32Array(), 32);
  expect(mesh.positions.length).toBe(0);
  expect(mesh.indices.length).toBe(0);
});
