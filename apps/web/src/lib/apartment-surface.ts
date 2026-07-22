export interface SurfaceMesh {
  readonly positions: Float32Array;
  readonly indices: Uint32Array;
  /** Occupied-cell world centres, reused for geometry-derived labelling. */
  readonly centers: Float32Array;
  readonly cellSize: number;
}

/**
 * Reconstructs a smooth surface mesh from a point cloud: the points are binned
 * into an occupancy grid, dilated into a thin closed shell, and polygonised with
 * naive Surface Nets. The result is a continuous isosurface (not voxel cubes)
 * that shades smoothly once vertex normals are computed.
 */
export function reconstructSurface(points: Float32Array, resolution: number): SurfaceMesh {
  const count = Math.floor(points.length / 3);
  if (count === 0 || resolution < 4) {
    return {
      positions: new Float32Array(),
      indices: new Uint32Array(),
      centers: new Float32Array(),
      cellSize: 1,
    };
  }

  let minX = Infinity;
  let minY = Infinity;
  let minZ = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  let maxZ = -Infinity;
  for (let i = 0; i < points.length; i += 3) {
    minX = Math.min(minX, points[i]);
    minY = Math.min(minY, points[i + 1]);
    minZ = Math.min(minZ, points[i + 2]);
    maxX = Math.max(maxX, points[i]);
    maxY = Math.max(maxY, points[i + 1]);
    maxZ = Math.max(maxZ, points[i + 2]);
  }

  const cell = Math.max(maxX - minX, maxY - minY, maxZ - minZ) / resolution || 1;
  const pad = 2;
  const nx = Math.ceil((maxX - minX) / cell) + 2 * pad;
  const ny = Math.ceil((maxY - minY) / cell) + 2 * pad;
  const nz = Math.ceil((maxZ - minZ) / cell) + 2 * pad;
  const originX = minX - pad * cell;
  const originY = minY - pad * cell;
  const originZ = minZ - pad * cell;

  const occupied = new Uint8Array(nx * ny * nz);
  const centerList: number[] = [];
  for (let i = 0; i < points.length; i += 3) {
    const gx = Math.round((points[i] - originX) / cell);
    const gy = Math.round((points[i + 1] - originY) / cell);
    const gz = Math.round((points[i + 2] - originZ) / cell);
    if (gx < 0 || gy < 0 || gz < 0 || gx >= nx || gy >= ny || gz >= nz) continue;
    const key = gx + gy * nx + gz * nx * ny;
    if (occupied[key] === 0) {
      occupied[key] = 1;
      centerList.push(originX + gx * cell, originY + gy * cell, originZ + gz * cell);
    }
  }

  const field = dilateToField(occupied, nx, ny, nz);
  const raw = surfaceNets(field, [nx, ny, nz]);

  const positions = new Float32Array(raw.vertices.length * 3);
  for (let i = 0; i < raw.vertices.length; i += 1) {
    const v = raw.vertices[i];
    positions[i * 3] = originX + v[0] * cell;
    positions[i * 3 + 1] = originY + v[1] * cell;
    positions[i * 3 + 2] = originZ + v[2] * cell;
  }

  const indices = new Uint32Array(raw.cells.length * 6);
  for (let i = 0; i < raw.cells.length; i += 1) {
    const q = raw.cells[i];
    const o = i * 6;
    indices[o] = q[0];
    indices[o + 1] = q[1];
    indices[o + 2] = q[2];
    indices[o + 3] = q[0];
    indices[o + 4] = q[2];
    indices[o + 5] = q[3];
  }

  return { positions, indices, centers: new Float32Array(centerList), cellSize: cell };
}

function dilateToField(occupied: Uint8Array, nx: number, ny: number, nz: number): Float32Array {
  const field = new Float32Array(nx * ny * nz).fill(1);
  const nxy = nx * ny;
  for (let z = 0; z < nz; z += 1) {
    for (let y = 0; y < ny; y += 1) {
      for (let x = 0; x < nx; x += 1) {
        const key = x + y * nx + z * nxy;
        if (occupied[key] === 0) continue;
        field[key] = -1;
        if (x > 0) field[key - 1] = -1;
        if (x < nx - 1) field[key + 1] = -1;
        if (y > 0) field[key - nx] = -1;
        if (y < ny - 1) field[key + nx] = -1;
        if (z > 0) field[key - nxy] = -1;
        if (z < nz - 1) field[key + nxy] = -1;
      }
    }
  }
  return field;
}

interface RawSurface {
  readonly vertices: number[][];
  readonly cells: number[][];
}

const CUBE_EDGES = new Int32Array(24);
const EDGE_TABLE = new Int32Array(256);
(() => {
  let k = 0;
  for (let i = 0; i < 8; i += 1) {
    for (let j = 1; j <= 4; j <<= 1) {
      const p = i ^ j;
      if (i <= p) {
        CUBE_EDGES[k] = i;
        CUBE_EDGES[k + 1] = p;
        k += 2;
      }
    }
  }
  for (let i = 0; i < 256; i += 1) {
    let em = 0;
    for (let j = 0; j < 24; j += 2) {
      const a = (i & (1 << CUBE_EDGES[j])) !== 0;
      const b = (i & (1 << CUBE_EDGES[j + 1])) !== 0;
      em |= a !== b ? 1 << (j >> 1) : 0;
    }
    EDGE_TABLE[i] = em;
  }
})();

function surfaceNets(data: Float32Array, dims: readonly [number, number, number]): RawSurface {
  const vertices: number[][] = [];
  const cells: number[][] = [];
  const x = [0, 0, 0];
  const R = [1, dims[0] + 1, (dims[0] + 1) * (dims[1] + 1)];
  const grid = new Float32Array(8);
  const buffer = new Int32Array((dims[0] + 1) * (dims[1] + 1) * 2);
  let bufNo = 1;
  let n = 0;

  for (x[2] = 0; x[2] < dims[2] - 1; x[2] += 1, n += dims[0], bufNo ^= 1, R[2] = -R[2]) {
    let m = 1 + (dims[0] + 1) * (1 + bufNo * (dims[1] + 1));
    for (x[1] = 0; x[1] < dims[1] - 1; x[1] += 1, n += 1, m += 2) {
      for (x[0] = 0; x[0] < dims[0] - 1; x[0] += 1, n += 1, m += 1) {
        let mask = 0;
        let g = 0;
        let idx = n;
        for (let k = 0; k < 2; k += 1, idx += dims[0] * (dims[1] - 2)) {
          for (let j = 0; j < 2; j += 1, idx += dims[0] - 2) {
            for (let i = 0; i < 2; i += 1, g += 1, idx += 1) {
              const p = data[idx];
              grid[g] = p;
              mask |= p < 0 ? 1 << g : 0;
            }
          }
        }
        if (mask === 0 || mask === 0xff) continue;
        const edgeMask = EDGE_TABLE[mask];
        const v = [0, 0, 0];
        let edges = 0;
        for (let i = 0; i < 12; i += 1) {
          if (!(edgeMask & (1 << i))) continue;
          edges += 1;
          const e0 = CUBE_EDGES[i << 1];
          const e1 = CUBE_EDGES[(i << 1) + 1];
          const g0 = grid[e0];
          const g1 = grid[e1];
          let t = g0 - g1;
          if (Math.abs(t) > 1e-6) t = g0 / t;
          else continue;
          for (let j = 0, kk = 1; j < 3; j += 1, kk <<= 1) {
            const a = e0 & kk;
            const b = e1 & kk;
            if (a !== b) v[j] += a ? 1 - t : t;
            else v[j] += a ? 1 : 0;
          }
        }
        const s = 1 / edges;
        for (let i = 0; i < 3; i += 1) v[i] = x[i] + s * v[i];
        buffer[m] = vertices.length;
        vertices.push(v);
        for (let i = 0; i < 3; i += 1) {
          if (!(edgeMask & (1 << i))) continue;
          const iu = (i + 1) % 3;
          const iv = (i + 2) % 3;
          if (x[iu] === 0 || x[iv] === 0) continue;
          const du = R[iu];
          const dv = R[iv];
          if (mask & 1) {
            cells.push([buffer[m], buffer[m - du], buffer[m - du - dv], buffer[m - dv]]);
          } else {
            cells.push([buffer[m], buffer[m - dv], buffer[m - du - dv], buffer[m - du]]);
          }
        }
      }
    }
  }
  return { vertices, cells };
}
