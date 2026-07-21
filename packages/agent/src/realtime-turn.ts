export interface RealtimeSubmitUserTurn {
  readonly client_turn_id: string;
  readonly utterance: string;
  readonly intent_hint: "place" | "replace" | "remove" | "restore" | null;
  readonly pointer_context_id: string | null;
  readonly pointer_context?: {
    readonly world_position: { readonly x: number; readonly y: number; readonly z: number };
    readonly surface_id: string | null;
  } | null;
  readonly client_scene_revision: number;
  readonly pending_proposal_id: string | null;
}

/** Strictly validates the untrusted Realtime function arguments before forwarding them. */
export function parseRealtimeSubmitUserTurn(value: unknown): RealtimeSubmitUserTurn {
  if (!isRecord(value)) throw new Error("invalid_realtime_turn");
  const keys = Object.keys(value);
  const required = [
    "client_turn_id",
    "utterance",
    "intent_hint",
    "pointer_context_id",
    "client_scene_revision",
    "pending_proposal_id",
  ];
  if (
    keys.some((key) => !required.includes(key) && key !== "pointer_context") ||
    required.some((key) => !(key in value)) ||
    keys.length > required.length + 1 ||
    !isOpaqueReference(value.client_turn_id) ||
    !isNormalizedUtterance(value.utterance) ||
    !(
      value.intent_hint === null ||
      value.intent_hint === "place" ||
      value.intent_hint === "replace" ||
      value.intent_hint === "remove" ||
      value.intent_hint === "restore"
    ) ||
    !isNullableReference(value.pointer_context_id) ||
    !Number.isSafeInteger(value.client_scene_revision) ||
    (value.client_scene_revision as number) < 0 ||
    !isNullableReference(value.pending_proposal_id) ||
    ("pointer_context" in value && !isNullablePointerContext(value.pointer_context))
  ) {
    throw new Error("invalid_realtime_turn");
  }
  const pointerContext = "pointer_context" in value ? value.pointer_context : undefined;
  return Object.freeze({
    client_turn_id: value.client_turn_id,
    utterance: value.utterance,
    intent_hint: value.intent_hint,
    pointer_context_id: value.pointer_context_id,
    ...(pointerContext === undefined ? {} : { pointer_context: pointerContext }),
    client_scene_revision: value.client_scene_revision,
    pending_proposal_id: value.pending_proposal_id,
  }) as RealtimeSubmitUserTurn;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isOpaqueReference(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z][A-Za-z0-9_-]{0,127}$/u.test(value);
}

function isNullableReference(value: unknown): value is string | null {
  return value === null || isOpaqueReference(value);
}

function isNormalizedUtterance(value: unknown): value is string {
  if (
    typeof value !== "string" ||
    value.length < 1 ||
    value.length > 2_000 ||
    value.trim() !== value
  )
    return false;
  return ![...value].some(
    (character) => character.charCodeAt(0) <= 31 || character.charCodeAt(0) === 127,
  );
}

function isNullablePointerContext(value: unknown): boolean {
  if (value === null) return true;
  if (!isRecord(value) || !hasExactKeys(value, ["world_position", "surface_id"])) return false;
  const world = value.world_position;
  return (
    isRecord(world) &&
    hasExactKeys(world, ["x", "y", "z"]) &&
    [world.x, world.y, world.z].every(
      (component) => typeof component === "number" && Number.isFinite(component),
    ) &&
    isNullableReference(value.surface_id)
  );
}

function hasExactKeys(value: Record<string, unknown>, keys: readonly string[]): boolean {
  return Object.keys(value).length === keys.length && keys.every((key) => key in value);
}
