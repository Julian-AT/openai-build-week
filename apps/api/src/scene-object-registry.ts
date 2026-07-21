const OBJECT_ID = /^object_[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u;
const INSTANCE_ID =
  /^instance_[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u;
const SESSION_ID = /^room_[a-z0-9_]{3,120}$/u;
const ASSET_ID = /^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$/u;
const SHA256 = /^[0-9a-f]{64}$/u;
const MAX_OBJECTS_PER_SESSION = 256;

export interface SceneObjectBounds {
  readonly center: readonly [number, number, number];
  readonly halfExtents: readonly [number, number, number];
}

export interface PlacedSceneObject {
  readonly sessionID: string;
  readonly objectID: string;
  readonly instanceID: string;
  readonly assetID: string;
  readonly bounds: SceneObjectBounds;
  readonly introducedAtSceneRevision: number;
  readonly visibility: "visible" | "hidden";
  readonly source: "reframe_placement";
  readonly track?: SamTrackBinding;
}

export interface SamTrackBinding {
  readonly targetID: string;
  readonly frameID: number;
  readonly trackRevision: number;
  readonly confidence: number;
  readonly maskSHA256: string;
  readonly status: "tracked";
}

export interface SamTrackObservation {
  readonly sessionID: string;
  readonly targetID: string;
  readonly frameID: number;
  readonly trackRevision: number;
  readonly confidence: number;
  readonly maskSHA256: string;
  readonly status: "tracked" | "uncertain" | "lost";
}

export interface SceneObjectRegistryOptions {
  readonly maxObjectsPerSession?: number;
}

export class SceneObjectRegistryError extends Error {
  constructor(readonly code: SceneObjectRegistryErrorCode) {
    super(code);
    this.name = "SceneObjectRegistryError";
  }
}

export type SceneObjectRegistryErrorCode =
  | "invalid_scene_object"
  | "scene_object_limit"
  | "unknown_scene_object"
  | "scene_object_not_visible"
  | "stale_scene_object_track"
  | "unsafe_scene_object_track";

/**
 * Authoritative in-process scene-object index for deterministic target resolution.
 * It only contains objects that Reframe itself placed; model labels and unknown
 * SAM identities can never create an injectable target.
 */
export class SceneObjectRegistry {
  readonly #maxObjectsPerSession: number;
  readonly #objectsBySession = new Map<string, Map<string, PlacedSceneObject>>();

  constructor(options: SceneObjectRegistryOptions = {}) {
    this.#maxObjectsPerSession = options.maxObjectsPerSession ?? MAX_OBJECTS_PER_SESSION;
    if (
      !Number.isSafeInteger(this.#maxObjectsPerSession) ||
      this.#maxObjectsPerSession < 1 ||
      this.#maxObjectsPerSession > MAX_OBJECTS_PER_SESSION
    ) {
      throw new SceneObjectRegistryError("invalid_scene_object");
    }
  }

  registerPlacedObject(input: {
    readonly sessionID: string;
    readonly objectID: string;
    readonly instanceID: string;
    readonly assetID: string;
    readonly bounds: SceneObjectBounds;
    readonly introducedAtSceneRevision: number;
  }): PlacedSceneObject {
    validateSessionID(input.sessionID);
    validateObjectID(input.objectID);
    validateInstanceID(input.instanceID);
    validateAssetID(input.assetID);
    validateRevision(input.introducedAtSceneRevision);
    const bounds = validateBounds(input.bounds);
    const objects = this.#objectsBySession.get(input.sessionID) ?? new Map();
    if (objects.size >= this.#maxObjectsPerSession && !objects.has(input.objectID)) {
      throw new SceneObjectRegistryError("scene_object_limit");
    }
    const existing = objects.get(input.objectID);
    if (existing !== undefined) {
      if (
        existing.instanceID !== input.instanceID ||
        existing.assetID !== input.assetID ||
        existing.introducedAtSceneRevision !== input.introducedAtSceneRevision ||
        !sameBounds(existing.bounds, bounds)
      ) {
        throw new SceneObjectRegistryError("invalid_scene_object");
      }
      return existing;
    }
    const record: PlacedSceneObject = Object.freeze({
      sessionID: input.sessionID,
      objectID: input.objectID,
      instanceID: input.instanceID,
      assetID: input.assetID,
      bounds,
      introducedAtSceneRevision: input.introducedAtSceneRevision,
      visibility: "visible",
      source: "reframe_placement",
    });
    objects.set(input.objectID, record);
    this.#objectsBySession.set(input.sessionID, objects);
    return record;
  }

  setVisibility(sessionID: string, objectID: string, visibility: "visible" | "hidden"): void {
    const object = this.requireObject(sessionID, objectID);
    const objects = this.#objectsBySession.get(sessionID);
    if (!objects) throw new SceneObjectRegistryError("unknown_scene_object");
    objects.set(objectID, Object.freeze({ ...object, visibility }));
  }

  resolveTarget(input: {
    readonly sessionID: string;
    readonly targetID: string;
    readonly sceneRevision: number;
  }): PlacedSceneObject {
    validateSessionID(input.sessionID);
    validateObjectID(input.targetID);
    validateRevision(input.sceneRevision);
    const object = this.requireObject(input.sessionID, input.targetID);
    if (object.introducedAtSceneRevision > input.sceneRevision) {
      throw new SceneObjectRegistryError("unknown_scene_object");
    }
    if (object.visibility !== "visible") {
      throw new SceneObjectRegistryError("scene_object_not_visible");
    }
    return object;
  }

  /** Resolves a pointer only inside an authoritative object's conservative AABB. */
  resolvePointer(input: {
    readonly sessionID: string;
    readonly sceneRevision: number;
    readonly worldPoint: readonly [number, number, number];
    readonly maxDistanceM?: number;
  }): PlacedSceneObject | undefined {
    validateSessionID(input.sessionID);
    validateRevision(input.sceneRevision);
    const point = validatePoint(input.worldPoint);
    const maxDistance = input.maxDistanceM ?? 0;
    if (!Number.isFinite(maxDistance) || maxDistance < 0 || maxDistance > 2) {
      throw new SceneObjectRegistryError("invalid_scene_object");
    }
    const objects = this.#objectsBySession.get(input.sessionID);
    if (!objects) return undefined;
    return [...objects.values()]
      .filter(
        (object) =>
          object.visibility === "visible" &&
          object.introducedAtSceneRevision <= input.sceneRevision &&
          insideExpandedBounds(point, object.bounds, maxDistance),
      )
      .sort((left, right) => {
        const leftDistance = distanceSquared(point, left.bounds.center);
        const rightDistance = distanceSquared(point, right.bounds.center);
        return leftDistance - rightDistance || left.objectID.localeCompare(right.objectID);
      })[0];
  }

  /** Binds a validated SAM observation to an existing Reframe object only. */
  bindSamTrack(observation: SamTrackObservation): PlacedSceneObject {
    validateSessionID(observation.sessionID);
    validateObjectID(observation.targetID);
    if (
      !Number.isSafeInteger(observation.frameID) ||
      observation.frameID < 0 ||
      !Number.isSafeInteger(observation.trackRevision) ||
      observation.trackRevision < 1 ||
      !Number.isFinite(observation.confidence) ||
      observation.confidence < 0.5 ||
      observation.confidence > 1 ||
      observation.status !== "tracked" ||
      !SHA256.test(observation.maskSHA256)
    ) {
      throw new SceneObjectRegistryError("unsafe_scene_object_track");
    }
    const current = this.requireObject(observation.sessionID, observation.targetID);
    if (current.visibility !== "visible") {
      throw new SceneObjectRegistryError("scene_object_not_visible");
    }
    if (
      current.track !== undefined &&
      (observation.frameID <= current.track.frameID ||
        observation.trackRevision <= current.track.trackRevision)
    ) {
      throw new SceneObjectRegistryError("stale_scene_object_track");
    }
    const objects = this.#objectsBySession.get(observation.sessionID);
    if (!objects) throw new SceneObjectRegistryError("unknown_scene_object");
    const next = Object.freeze({
      ...current,
      track: Object.freeze({
        targetID: observation.targetID,
        frameID: observation.frameID,
        trackRevision: observation.trackRevision,
        confidence: observation.confidence,
        maskSHA256: observation.maskSHA256,
        status: "tracked" as const,
      }),
    });
    objects.set(observation.targetID, next);
    return next;
  }

  private requireObject(sessionID: string, objectID: string): PlacedSceneObject {
    const object = this.#objectsBySession.get(sessionID)?.get(objectID);
    if (object === undefined) throw new SceneObjectRegistryError("unknown_scene_object");
    return object;
  }
}

export function objectIDForInstance(instanceID: string): string {
  validateInstanceID(instanceID);
  return `object_${instanceID.slice("instance_".length)}`;
}

function validateSessionID(value: string): void {
  if (!SESSION_ID.test(value)) throw new SceneObjectRegistryError("invalid_scene_object");
}

function validateObjectID(value: string): void {
  if (!OBJECT_ID.test(value)) throw new SceneObjectRegistryError("invalid_scene_object");
}

function validateInstanceID(value: string): void {
  if (!INSTANCE_ID.test(value)) throw new SceneObjectRegistryError("invalid_scene_object");
}

function validateAssetID(value: string): void {
  if (!ASSET_ID.test(value) || value.length > 128) {
    throw new SceneObjectRegistryError("invalid_scene_object");
  }
}

function validateRevision(value: number): void {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new SceneObjectRegistryError("invalid_scene_object");
  }
}

function validateBounds(bounds: SceneObjectBounds): SceneObjectBounds {
  if (
    !Array.isArray(bounds.center) ||
    bounds.center.length !== 3 ||
    !Array.isArray(bounds.halfExtents) ||
    bounds.halfExtents.length !== 3 ||
    !bounds.center.every((value) => Number.isFinite(value) && Math.abs(value) <= 1_000) ||
    !bounds.halfExtents.every((value) => Number.isFinite(value) && value > 0 && value <= 100)
  ) {
    throw new SceneObjectRegistryError("invalid_scene_object");
  }
  return Object.freeze({
    center: Object.freeze([...bounds.center] as [number, number, number]),
    halfExtents: Object.freeze([...bounds.halfExtents] as [number, number, number]),
  });
}

function validatePoint(
  value: readonly [number, number, number],
): readonly [number, number, number] {
  if (!Array.isArray(value) || value.length !== 3 || !value.every(Number.isFinite)) {
    throw new SceneObjectRegistryError("invalid_scene_object");
  }
  return value;
}

function insideExpandedBounds(
  point: readonly [number, number, number],
  bounds: SceneObjectBounds,
  expansion: number,
): boolean {
  const [pointX, pointY, pointZ] = point;
  const [centerX, centerY, centerZ] = bounds.center;
  const [extentX, extentY, extentZ] = bounds.halfExtents;
  return (
    Math.abs(pointX - centerX) <= extentX + expansion &&
    Math.abs(pointY - centerY) <= extentY + expansion &&
    Math.abs(pointZ - centerZ) <= extentZ + expansion
  );
}

function distanceSquared(
  left: readonly [number, number, number],
  right: readonly [number, number, number],
): number {
  const [leftX, leftY, leftZ] = left;
  const [rightX, rightY, rightZ] = right;
  return (leftX - rightX) ** 2 + (leftY - rightY) ** 2 + (leftZ - rightZ) ** 2;
}

function sameBounds(left: SceneObjectBounds, right: SceneObjectBounds): boolean {
  return (
    left.center.every((value, index) => value === right.center[index]) &&
    left.halfExtents.every((value, index) => value === right.halfExtents[index])
  );
}
