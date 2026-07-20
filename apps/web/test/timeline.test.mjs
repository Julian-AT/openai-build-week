import assert from "node:assert/strict";
import { test } from "bun:test";

import { moveTimelineIndex, selectTimelineIndex } from "../src/lib/replay/timeline.ts";

const EVENTS = Object.freeze([
  Object.freeze({ eventId: "event_0" }),
  Object.freeze({ eventId: "event_1" }),
  Object.freeze({ eventId: "event_2" }),
]);

test("selection starts at zero and clamps to the verified event range", () => {
  assert.equal(selectTimelineIndex(EVENTS, 0), 0);
  assert.equal(selectTimelineIndex(EVENTS, -20), 0);
  assert.equal(selectTimelineIndex(EVENTS, 99), 2);
  assert.equal(selectTimelineIndex(EVENTS, 1.9), 1);
  assert.equal(selectTimelineIndex(EVENTS, Number.NaN), 0);
  assert.deepEqual(EVENTS.map(({ eventId }) => eventId), ["event_0", "event_1", "event_2"]);
});

test("previous and next transitions remain bounded without mutating events", () => {
  assert.equal(moveTimelineIndex(EVENTS, 0, -1), 0);
  assert.equal(moveTimelineIndex(EVENTS, 0, 1), 1);
  assert.equal(moveTimelineIndex(EVENTS, 1, 1), 2);
  assert.equal(moveTimelineIndex(EVENTS, 2, 1), 2);
  assert.equal(moveTimelineIndex(EVENTS, 2, -50), 0);
  assert.equal(moveTimelineIndex(EVENTS, 0, 50), 2);
  assert.deepEqual(EVENTS.map(({ eventId }) => eventId), ["event_0", "event_1", "event_2"]);
});

test("zero-event input produces no selectable timeline index", () => {
  assert.equal(selectTimelineIndex([], 0), null);
  assert.equal(selectTimelineIndex([], 100), null);
  assert.equal(moveTimelineIndex([], 0, 1), null);
});

test("non-finite movement cannot create an invalid index", () => {
  assert.equal(moveTimelineIndex(EVENTS, 1, Number.NaN), 1);
  assert.equal(moveTimelineIndex(EVENTS, Number.POSITIVE_INFINITY, 1), 1);
  assert.equal(moveTimelineIndex(EVENTS, Number.NEGATIVE_INFINITY, -1), 0);
});
