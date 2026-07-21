export interface RegionLabel {
  readonly text: string;
  readonly position: readonly [number, number, number];
}

export interface ScanLabels {
  readonly labels: RegionLabel[];
  /** Unit up-axis (dominant plane normal, oriented toward the interior), or null. */
  readonly up: readonly [number, number, number] | null;
}

interface Vec3 {
  readonly x: number;
  readonly y: number;
  readonly z: number;
}

interface Plane {
  readonly normal: Vec3;
  readonly inliers: number[];
}

/**
 * Derives honest, geometry-only region labels from a voxelized scan: the
 * dominant plane becomes Floor/Ceiling, planes perpendicular to it become Walls,
 * and the remaining connected voxel clusters become Regions. No object semantics
 * are invented.
 */
export function labelVoxels(centers: Float32Array, voxelSize: number): ScanLabels {
  const count = Math.floor(centers.length / 3);
  if (count < 3 || voxelSize <= 0) return { labels: [], up: null };
  const random = seededRandom(0x52_46_52_4d);
  const threshold = voxelSize * 1.5;
  const active = new Uint8Array(count).fill(1);
  const labels: RegionLabel[] = [];

  let up: Vec3 | null = null;
  const floor = ransacPlane(centers, active, threshold, 240, random);
  if (floor && floor.inliers.length > count * 0.04) {
    up = orientToward(floor.normal, centroid(centers, floor.inliers), meanPoint(centers));
    consume(active, floor.inliers);
    const opposite = ransacPlane(centers, active, threshold, 240, random);
    const parallel =
      opposite !== null &&
      opposite.inliers.length > count * 0.02 &&
      Math.abs(dot(opposite.normal, up)) > 0.8;
    // Gravity is unknown, so the larger of the two dominant horizontal planes is
    // taken as the floor and its parallel opposite as the ceiling.
    const floorInliers =
      parallel && opposite.inliers.length > floor.inliers.length ? opposite.inliers : floor.inliers;
    labels.push({ text: "Floor", position: centroid(centers, floorInliers) });
    if (parallel) {
      const ceilingInliers = floorInliers === floor.inliers ? opposite.inliers : floor.inliers;
      labels.push({ text: "Ceiling", position: centroid(centers, ceilingInliers) });
      consume(active, opposite.inliers);
    }
  }

  let wall = 1;
  for (let attempt = 0; attempt < 5 && wall <= 3; attempt += 1) {
    const plane = ransacPlane(centers, active, threshold, 200, random);
    if (!plane || plane.inliers.length < count * 0.025) break;
    const vertical = up === null || Math.abs(dot(plane.normal, up)) < 0.35;
    consume(active, plane.inliers);
    if (vertical) {
      labels.push({ text: `Wall ${wall}`, position: centroid(centers, plane.inliers) });
      wall += 1;
    }
  }

  const clusters = clusterRemaining(centers, active, voxelSize).sort((a, b) => b.length - a.length);
  const minCluster = Math.max(8, Math.floor(count * 0.01));
  let region = 1;
  for (const cluster of clusters) {
    if (cluster.length < minCluster || region > 3) break;
    labels.push({ text: `Region ${region}`, position: centroid(centers, cluster) });
    region += 1;
  }
  return { labels, up: up ? [up.x, up.y, up.z] : null };
}

function orientToward(normal: Vec3, from: readonly number[], to: readonly number[]): Vec3 {
  const aligned =
    normal.x * (to[0] - from[0]) + normal.y * (to[1] - from[1]) + normal.z * (to[2] - from[2]) >= 0;
  return aligned ? normal : { x: -normal.x, y: -normal.y, z: -normal.z };
}

function meanPoint(centers: Float32Array): [number, number, number] {
  let x = 0;
  let y = 0;
  let z = 0;
  const count = centers.length / 3;
  for (let i = 0; i < centers.length; i += 3) {
    x += centers[i];
    y += centers[i + 1];
    z += centers[i + 2];
  }
  return [x / count, y / count, z / count];
}

function ransacPlane(
  centers: Float32Array,
  active: Uint8Array,
  threshold: number,
  iterations: number,
  random: () => number,
): Plane | null {
  const pool: number[] = [];
  for (let i = 0; i < active.length; i += 1) if (active[i]) pool.push(i);
  if (pool.length < 3) return null;

  let best: Plane | null = null;
  for (let iteration = 0; iteration < iterations; iteration += 1) {
    const a = pool[(random() * pool.length) | 0] as number;
    const b = pool[(random() * pool.length) | 0] as number;
    const c = pool[(random() * pool.length) | 0] as number;
    if (a === b || b === c || a === c) continue;
    const normal = cross(sub(centers, b, a), sub(centers, c, a));
    const length = Math.hypot(normal.x, normal.y, normal.z);
    if (length < 1e-6) continue;
    const unit = { x: normal.x / length, y: normal.y / length, z: normal.z / length };
    const offset = -(
      unit.x * centers[a * 3] +
      unit.y * centers[a * 3 + 1] +
      unit.z * centers[a * 3 + 2]
    );
    const inliers: number[] = [];
    for (const index of pool) {
      const distance = Math.abs(
        unit.x * centers[index * 3] +
          unit.y * centers[index * 3 + 1] +
          unit.z * centers[index * 3 + 2] +
          offset,
      );
      if (distance < threshold) inliers.push(index);
    }
    if (best === null || inliers.length > best.inliers.length) best = { normal: unit, inliers };
  }
  return best;
}

function clusterRemaining(
  centers: Float32Array,
  active: Uint8Array,
  voxelSize: number,
): number[][] {
  const index = new Map<number, number>();
  for (let i = 0; i < active.length; i += 1) {
    if (!active[i]) continue;
    index.set(gridKey(centers[i * 3], centers[i * 3 + 1], centers[i * 3 + 2], voxelSize), i);
  }
  const visited = new Set<number>();
  const clusters: number[][] = [];
  for (const key of index.keys()) {
    if (visited.has(key)) continue;
    const cluster: number[] = [];
    const queue = [key];
    visited.add(key);
    while (queue.length > 0) {
      const current = queue.pop() as number;
      const point = index.get(current);
      if (point === undefined) continue;
      cluster.push(point);
      for (const neighbor of neighbors(current)) {
        if (index.has(neighbor) && !visited.has(neighbor)) {
          visited.add(neighbor);
          queue.push(neighbor);
        }
      }
    }
    clusters.push(cluster);
  }
  return clusters;
}

const KEY_OFFSET = 4096;
const KEY_SPAN = 8192;

function gridKey(x: number, y: number, z: number, voxelSize: number): number {
  const ix = Math.round(x / voxelSize) + KEY_OFFSET;
  const iy = Math.round(y / voxelSize) + KEY_OFFSET;
  const iz = Math.round(z / voxelSize) + KEY_OFFSET;
  return (ix * KEY_SPAN + iy) * KEY_SPAN + iz;
}

function neighbors(key: number): number[] {
  return [
    key + KEY_SPAN * KEY_SPAN,
    key - KEY_SPAN * KEY_SPAN,
    key + KEY_SPAN,
    key - KEY_SPAN,
    key + 1,
    key - 1,
  ];
}

function centroid(centers: Float32Array, indices: readonly number[]): [number, number, number] {
  let x = 0;
  let y = 0;
  let z = 0;
  for (const index of indices) {
    x += centers[index * 3];
    y += centers[index * 3 + 1];
    z += centers[index * 3 + 2];
  }
  const n = indices.length || 1;
  return [x / n, y / n, z / n];
}

function consume(active: Uint8Array, indices: readonly number[]): void {
  for (const index of indices) active[index] = 0;
}

function sub(centers: Float32Array, a: number, b: number): Vec3 {
  return {
    x: centers[a * 3] - centers[b * 3],
    y: centers[a * 3 + 1] - centers[b * 3 + 1],
    z: centers[a * 3 + 2] - centers[b * 3 + 2],
  };
}

function cross(a: Vec3, b: Vec3): Vec3 {
  return { x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x };
}

function dot(a: Vec3, b: Vec3): number {
  return a.x * b.x + a.y * b.y + a.z * b.z;
}

function seededRandom(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state += 0x6d_2b_79_f5;
    let value = state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4_294_967_296;
  };
}
