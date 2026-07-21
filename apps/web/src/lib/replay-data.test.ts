import { expect, test } from "bun:test";

import { parseReplayEvents, replayEventsURL } from "./replay-data.ts";

const event = (sequence: number) => ({
  event_id: `event_00000000-0000-4000-8000-00000000000${sequence + 1}`,
  event_sequence: sequence,
  monotonic_timestamp_ns: String(sequence + 1),
  type: "tracking_changed",
  payload: { state: "tracking" },
});

test("builds an isolated room event endpoint and preserves order", () => {
  expect(replayEventsURL("https://gateway.example/", "room_demo_01")).toBe(
    "https://gateway.example/v1/sessions/room_demo_01/events",
  );
  expect(parseReplayEvents({ events: [event(0), event(1)] })).toHaveLength(2);
});

test("rejects malformed or non-monotonic replay input", () => {
  expect(() => replayEventsURL("https://gateway.example", "session_bad")).toThrow(
    "invalid_replay_session",
  );
  expect(() => parseReplayEvents({ events: [event(1), event(0)] })).toThrow(
    "non_monotonic_replay_events",
  );
  expect(() =>
    parseReplayEvents({ events: [{ ...event(0), payload: undefined, extra: true }] }),
  ).toThrow("invalid_replay_event");
});
