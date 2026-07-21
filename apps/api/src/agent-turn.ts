import { ProtocolError } from "./protocol.ts";

export const AGENT_TURN_INTENT_HINTS = ["place", "replace", "remove", "restore"] as const;

export type AgentTurnIntentHint = (typeof AGENT_TURN_INTENT_HINTS)[number];

export interface AgentTurnRequest {
  readonly client_turn_id: string;
  readonly utterance: string;
  readonly intent_hint: AgentTurnIntentHint | null;
  readonly pointer_context_id: string | null;
  readonly client_scene_revision: number;
  readonly pending_proposal_id: string | null;
}

export interface AgentTurnService {
  submit(credential: string, turn: AgentTurnRequest, signal: AbortSignal): Promise<unknown>;
}

/** Parses the untrusted typed-turn envelope; unknown keys are rejected. */
export function parseAgentTurnRequest(value: unknown): AgentTurnRequest {
  const keys = [
    "client_turn_id",
    "utterance",
    "intent_hint",
    "pointer_context_id",
    "client_scene_revision",
    "pending_proposal_id",
  ];
  if (
    !isExactRecord(value, keys) ||
    !isOpaqueReference(value.client_turn_id) ||
    !isNormalizedUtterance(value.utterance) ||
    !(
      value.intent_hint === null ||
      AGENT_TURN_INTENT_HINTS.includes(value.intent_hint as AgentTurnIntentHint)
    ) ||
    !isNullableReference(value.pointer_context_id) ||
    !Number.isSafeInteger(value.client_scene_revision) ||
    (value.client_scene_revision as number) < 0 ||
    !isNullableReference(value.pending_proposal_id)
  ) {
    throw new ProtocolError("invalid_request");
  }

  return Object.freeze({
    client_turn_id: value.client_turn_id,
    utterance: value.utterance,
    intent_hint: value.intent_hint as AgentTurnIntentHint | null,
    pointer_context_id: value.pointer_context_id,
    client_scene_revision: value.client_scene_revision as number,
    pending_proposal_id: value.pending_proposal_id,
  });
}

function isExactRecord(value: unknown, keys: readonly string[]): value is Record<string, unknown> {
  return (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value) &&
    Object.keys(value).length === keys.length &&
    keys.every((key) => key in value)
  );
}

function isNullableReference(value: unknown): value is string | null {
  return value === null || isOpaqueReference(value);
}

function isOpaqueReference(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z][A-Za-z0-9_-]{0,127}$/u.test(value);
}

function isNormalizedUtterance(value: unknown): value is string {
  return (
    typeof value === "string" &&
    value.length >= 1 &&
    value.length <= 2_000 &&
    value.trim() === value &&
    !hasControlCharacter(value)
  );
}

function hasControlCharacter(value: string): boolean {
  for (let index = 0; index < value.length; index += 1) {
    const codePoint = value.charCodeAt(index);
    if (codePoint <= 31 || codePoint === 127) return true;
  }
  return false;
}
