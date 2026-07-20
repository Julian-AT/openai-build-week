export interface FloorPlacementPreviewInput {
  readonly assetID: string;
  readonly baseSceneRevision: number;
  readonly supportSurfaceID: string;
  readonly floorContactWorld: Readonly<{ x: number; y: number; z: number }>;
  readonly yawRadians: number;
}

export interface FloorPlacementPreview {
  readonly type: "placement_preview";
  readonly assetID: string;
  readonly baseSceneRevision: number;
  readonly supportSurfaceID: string;
  /** RF-COORD-1 column-vector transform serialized in row-major order. */
  readonly worldFromAsset: readonly number[];
}

export class PlacementPreviewInputError extends Error {
  constructor() {
    super("invalid_placement_preview");
    this.name = "PlacementPreviewInputError";
  }
}

/**
 * Creates a local-only placement projection for an already normalized,
 * floor-contact-center asset. It is deliberately revision-neutral: only the
 * transaction authority may turn this transform into a scene operation.
 */
export function createFloorPlacementPreview(
  input: FloorPlacementPreviewInput,
): FloorPlacementPreview {
  assertInput(input);
  const cosine = clean(Math.cos(input.yawRadians));
  const sine = clean(Math.sin(input.yawRadians));
  return Object.freeze({
    type: "placement_preview" as const,
    assetID: input.assetID,
    baseSceneRevision: input.baseSceneRevision,
    supportSurfaceID: input.supportSurfaceID,
    worldFromAsset: Object.freeze([
      cosine,
      0,
      sine,
      input.floorContactWorld.x,
      0,
      1,
      0,
      input.floorContactWorld.y,
      -sine,
      0,
      cosine,
      input.floorContactWorld.z,
      0,
      0,
      0,
      1,
    ]),
  });
}

function assertInput(input: FloorPlacementPreviewInput): void {
  if (
    !safeIdentifier(input.assetID) ||
    !safeIdentifier(input.supportSurfaceID) ||
    !Number.isSafeInteger(input.baseSceneRevision) ||
    input.baseSceneRevision < 0 ||
    !Number.isFinite(input.yawRadians) ||
    input.yawRadians < -Math.PI ||
    input.yawRadians > Math.PI ||
    ![input.floorContactWorld.x, input.floorContactWorld.y, input.floorContactWorld.z].every(
      Number.isFinite,
    )
  ) {
    throw new PlacementPreviewInputError();
  }
}

function safeIdentifier(value: string): boolean {
  return /^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$/u.test(value) && value.length <= 128;
}

function clean(value: number): number {
  return Math.abs(value) < Number.EPSILON ? 0 : value;
}
