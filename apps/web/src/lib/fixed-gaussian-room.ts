export interface FixedGaussianRoomModel {
  readonly id: "reframe-fixed-room-v1";
  readonly coordinateSystem: {
    readonly handedness: "right";
    readonly upAxis: "+Y";
    readonly units: "metres";
  };
  readonly splatCount: number;
  readonly positions: Float32Array;
  readonly colors: Float32Array;
  readonly radii: Float32Array;
  readonly bounds: {
    readonly min: readonly [number, number, number];
    readonly max: readonly [number, number, number];
  };
}

type Vector3 = readonly [number, number, number];

interface GridOptions {
  readonly origin: Vector3;
  readonly u: Vector3;
  readonly v: Vector3;
  readonly columns: number;
  readonly rows: number;
  readonly color: Vector3;
  readonly radius: number;
  readonly positionJitter?: number;
  readonly colorJitter?: number;
}

/**
 * Creates the one decorative room model used behind the web landing surface.
 * It is a deterministic presentation asset, never canonical scene or replay data.
 */
export function createFixedGaussianRoom(): FixedGaussianRoomModel {
  const random = createSeededRandom(0x5246_524d);
  const positions: number[] = [];
  const colors: number[] = [];
  const radii: number[] = [];

  const addSplat = (position: Vector3, color: Vector3, radius: number, jitter = 0.025) => {
    positions.push(position[0], position[1], position[2]);
    colors.push(
      clamp01(color[0] + centeredRandom(random) * jitter),
      clamp01(color[1] + centeredRandom(random) * jitter),
      clamp01(color[2] + centeredRandom(random) * jitter),
    );
    radii.push(radius);
  };

  const addGrid = (options: GridOptions) => {
    const positionJitter = options.positionJitter ?? 0.012;
    for (let row = 0; row < options.rows; row += 1) {
      for (let column = 0; column < options.columns; column += 1) {
        const across = options.columns === 1 ? 0.5 : column / (options.columns - 1);
        const up = options.rows === 1 ? 0.5 : row / (options.rows - 1);
        const jitter = centeredRandom(random) * positionJitter;
        addSplat(
          [
            options.origin[0] + options.u[0] * across + options.v[0] * up + jitter,
            options.origin[1] + options.u[1] * across + options.v[1] * up + jitter * 0.25,
            options.origin[2] + options.u[2] * across + options.v[2] * up + jitter,
          ],
          options.color,
          options.radius * (0.86 + random() * 0.28),
          options.colorJitter,
        );
      }
    }
  };

  // Architectural shell: a staged room with a warm floor, rear wall, and side wall.
  addGrid({
    origin: [-3.8, 0, -4.75],
    u: [7.6, 0, 0],
    v: [0, 0, 5.45],
    columns: 52,
    rows: 46,
    color: [0.28, 0.25, 0.2],
    radius: 0.025,
    colorJitter: 0.035,
  });
  addGrid({
    origin: [-3.8, 0, -4.75],
    u: [7.6, 0, 0],
    v: [0, 3.4, 0],
    columns: 52,
    rows: 38,
    color: [0.37, 0.39, 0.35],
    radius: 0.022,
    colorJitter: 0.025,
  });
  addGrid({
    origin: [-3.8, 0, -4.75],
    u: [0, 0, 5.45],
    v: [0, 3.4, 0],
    columns: 36,
    rows: 38,
    color: [0.2, 0.23, 0.2],
    radius: 0.024,
    colorJitter: 0.025,
  });

  // A woven rug gives the foreground depth without becoming interaction state.
  addGrid({
    origin: [-1.85, 0.014, -3.62],
    u: [3.7, 0, 0],
    v: [0, 0, 2.55],
    columns: 36,
    rows: 22,
    color: [0.34, 0.29, 0.18],
    radius: 0.024,
    positionJitter: 0.018,
    colorJitter: 0.045,
  });

  // The fixed furniture silhouette is assembled from soft cuboid surfaces.
  addGrid({
    origin: [0.15, 0.2, -4.36],
    u: [2.55, 0, 0],
    v: [0, 1.22, 0.12],
    columns: 34,
    rows: 17,
    color: [0.46, 0.28, 0.19],
    radius: 0.032,
    positionJitter: 0.025,
    colorJitter: 0.04,
  });
  addGrid({
    origin: [0.2, 0.46, -4.18],
    u: [2.45, 0, 0],
    v: [0, 0, 0.82],
    columns: 32,
    rows: 12,
    color: [0.5, 0.31, 0.2],
    radius: 0.034,
    positionJitter: 0.025,
    colorJitter: 0.04,
  });
  addGrid({
    origin: [0.03, 0.18, -4.24],
    u: [0.3, 0.82, 0],
    v: [0, 0, 0.75],
    columns: 9,
    rows: 11,
    color: [0.4, 0.23, 0.16],
    radius: 0.035,
    colorJitter: 0.035,
  });
  addGrid({
    origin: [2.52, 0.18, -4.24],
    u: [0.3, 0.82, 0],
    v: [0, 0, 0.75],
    columns: 9,
    rows: 11,
    color: [0.4, 0.23, 0.16],
    radius: 0.035,
    colorJitter: 0.035,
  });

  // Window, side table, and plant create recognizable room landmarks.
  addGrid({
    origin: [-2.95, 1.35, -4.73],
    u: [1.52, 0, 0],
    v: [0, 1.35, 0],
    columns: 23,
    rows: 20,
    color: [0.66, 0.73, 0.64],
    radius: 0.022,
    positionJitter: 0.006,
    colorJitter: 0.025,
  });
  addGrid({
    origin: [-2.65, 0.48, -3.65],
    u: [0.82, 0, 0],
    v: [0, 0, 0.7],
    columns: 16,
    rows: 13,
    color: [0.16, 0.12, 0.09],
    radius: 0.028,
    colorJitter: 0.025,
  });
  addGrid({
    origin: [-2.47, 0.04, -3.48],
    u: [0, 0.46, 0],
    v: [0.46, 0, 0],
    columns: 8,
    rows: 10,
    color: [0.13, 0.1, 0.08],
    radius: 0.022,
    colorJitter: 0.02,
  });
  addEllipsoidShell(
    addSplat,
    random,
    [-2.22, 1.04, -3.38],
    [0.52, 0.7, 0.42],
    360,
    [0.27, 0.48, 0.23],
    0.031,
  );

  const bounds = calculateBounds(positions);
  return {
    id: "reframe-fixed-room-v1",
    coordinateSystem: { handedness: "right", upAxis: "+Y", units: "metres" },
    splatCount: radii.length,
    positions: new Float32Array(positions),
    colors: new Float32Array(colors),
    radii: new Float32Array(radii),
    bounds,
  };
}

function addEllipsoidShell(
  addSplat: (position: Vector3, color: Vector3, radius: number, jitter?: number) => void,
  random: () => number,
  center: Vector3,
  extent: Vector3,
  count: number,
  color: Vector3,
  radius: number,
) {
  for (let index = 0; index < count; index += 1) {
    const y = 1 - 2 * ((index + 0.5) / count);
    const radial = Math.sqrt(Math.max(0, 1 - y * y));
    const angle = Math.PI * (3 - Math.sqrt(5)) * index + centeredRandom(random) * 0.08;
    addSplat(
      [
        center[0] + Math.cos(angle) * radial * extent[0],
        center[1] + y * extent[1],
        center[2] + Math.sin(angle) * radial * extent[2],
      ],
      color,
      radius * (0.88 + random() * 0.24),
      0.055,
    );
  }
}

function calculateBounds(values: readonly number[]): {
  readonly min: readonly [number, number, number];
  readonly max: readonly [number, number, number];
} {
  const min: [number, number, number] = [
    Number.POSITIVE_INFINITY,
    Number.POSITIVE_INFINITY,
    Number.POSITIVE_INFINITY,
  ];
  const max: [number, number, number] = [
    Number.NEGATIVE_INFINITY,
    Number.NEGATIVE_INFINITY,
    Number.NEGATIVE_INFINITY,
  ];
  for (let index = 0; index < values.length; index += 3) {
    for (let axis = 0; axis < 3; axis += 1) {
      min[axis] = Math.min(min[axis], values[index + axis] ?? min[axis]);
      max[axis] = Math.max(max[axis], values[index + axis] ?? max[axis]);
    }
  }
  return { min, max };
}

function createSeededRandom(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state += 0x6d2b_79f5;
    let value = state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4_294_967_296;
  };
}

function centeredRandom(random: () => number): number {
  return random() - 0.5;
}

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}
