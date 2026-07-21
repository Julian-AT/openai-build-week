export interface RealtimeSubmitUserTurn {
  readonly client_turn_id: string;
  readonly utterance: string;
  readonly intent_hint: "place" | "replace" | "remove" | "restore" | null;
  readonly pointer_context_id: string | null;
  readonly client_scene_revision: number;
  readonly pending_proposal_id: string | null;
}

/**
 * Strictly validates the untrusted Realtime function arguments before forwarding
 * them. The turn carries only an opaque `pointer_context_id`; the gateway binds
 * the authoritative pointer, frame, and spatial context from durable state. A
 * client-supplied world position is rejected as an unknown property.
 */
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
    keys.some((key) => !required.includes(key)) ||
    required.some((key) => !(key in value)) ||
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
    !isNullableReference(value.pending_proposal_id)
  ) {
    throw new Error("invalid_realtime_turn");
  }
  return Object.freeze({
    client_turn_id: value.client_turn_id,
    utterance: value.utterance,
    intent_hint: value.intent_hint,
    pointer_context_id: value.pointer_context_id,
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
