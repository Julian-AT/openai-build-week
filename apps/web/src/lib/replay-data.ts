export interface ReplayEvent {
  readonly event_id: string;
  readonly event_sequence: number;
  readonly monotonic_timestamp_ns: string;
  readonly type: string;
  readonly payload: unknown;
}

const ROOM_ID = /^room_[a-z0-9_]{3,120}$/u;
const EVENT_ID = /^event_[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u;

export function assertReplaySessionID(sessionID: string): string {
  if (!ROOM_ID.test(sessionID)) throw new Error("invalid_replay_session");
  return sessionID;
}

export function replayEventsURL(gatewayURL: string, sessionID: string): string {
  assertReplaySessionID(sessionID);
  const base = new URL(gatewayURL);
  if (base.protocol !== "https:" && base.protocol !== "http:") {
    throw new Error("invalid_replay_gateway");
  }
  return new URL(`/v1/sessions/${sessionID}/events`, base).toString();
}

export function parseReplayEvents(value: unknown): readonly ReplayEvent[] {
  if (!isRecord(value) || !Array.isArray(value.events)) throw new Error("invalid_replay_events");
  const events = value.events.map(parseReplayEvent);
  for (let index = 1; index < events.length; index += 1) {
    const current = events[index];
    const previous = events[index - 1];
    if (current === undefined || previous === undefined) throw new Error("invalid_replay_events");
    if (current.event_sequence <= previous.event_sequence) {
      throw new Error("non_monotonic_replay_events");
    }
  }
  return Object.freeze(events);
}

function parseReplayEvent(value: unknown): ReplayEvent {
  if (
    !isRecord(value) ||
    Object.keys(value).some(
      (key) =>
        !["event_id", "event_sequence", "monotonic_timestamp_ns", "type", "payload"].includes(key),
    ) ||
    typeof value.event_id !== "string" ||
    !EVENT_ID.test(value.event_id) ||
    typeof value.event_sequence !== "number" ||
    !Number.isSafeInteger(value.event_sequence) ||
    value.event_sequence < 0 ||
    typeof value.monotonic_timestamp_ns !== "string" ||
    !/^(?:0|[1-9][0-9]{0,29})$/u.test(value.monotonic_timestamp_ns) ||
    typeof value.type !== "string"
  ) {
    throw new Error("invalid_replay_event");
  }
  return Object.freeze({
    event_id: value.event_id,
    event_sequence: value.event_sequence,
    monotonic_timestamp_ns: value.monotonic_timestamp_ns,
    type: value.type,
    payload: value.payload,
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
