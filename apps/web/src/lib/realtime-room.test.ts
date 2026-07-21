import { expect, test } from "bun:test";

import { forwardRealtimeTurn } from "./realtime-room.ts";

const gatewayURL = new URL("https://gateway.example.test");
const validArguments = JSON.stringify({
  client_turn_id: "turn_browser_1",
  utterance: "Replace this chair",
  intent_hint: "replace",
  pointer_context_id: "pointer_1",
  client_scene_revision: 4,
  pending_proposal_id: null,
});

test("forwards a validated Realtime turn to the non-mutating gateway route", async () => {
  const events: unknown[] = [];
  let requestURL = "";
  let requestInit: RequestInit | undefined;
  await forwardRealtimeTurn({
    gatewayURL,
    roomCredential: "room-token",
    connection: { sendEvent: (event) => events.push(event) },
    callID: "call_1",
    argumentsJSON: validArguments,
    fetch: async (input, init) => {
      requestURL = String(input);
      requestInit = init;
      return Response.json({ status: "preview_ready", proposal_id: "proposal_1" });
    },
  });

  expect(requestURL).toBe("https://gateway.example.test/v1/turns");
  expect(requestInit?.method).toBe("POST");
  expect(requestInit?.headers).toEqual({
    Authorization: "Bearer room-token",
    "Content-Type": "application/json",
  });
  expect(JSON.parse(String(requestInit?.body))).toEqual(JSON.parse(validArguments));
  expect(events).toEqual([
    {
      type: "conversation.item.create",
      item: {
        type: "function_call_output",
        call_id: "call_1",
        output: JSON.stringify({
          status: "accepted",
          result: { status: "preview_ready", proposal_id: "proposal_1" },
        }),
      },
    },
    { type: "response.create" },
  ]);
});

test("never forwards malformed or mutation-shaped Realtime arguments", async () => {
  let requested = false;
  const events: unknown[] = [];
  await forwardRealtimeTurn({
    gatewayURL,
    roomCredential: "room-token",
    connection: { sendEvent: (event) => events.push(event) },
    callID: "call_2",
    argumentsJSON: JSON.stringify({ ...JSON.parse(validArguments), commit: true }),
    fetch: async () => {
      requested = true;
      return Response.json({});
    },
  });
  expect(requested).toBeFalse();
  expect(events).toEqual([
    {
      type: "conversation.item.create",
      item: {
        type: "function_call_output",
        call_id: "call_2",
        output: JSON.stringify({ status: "error", code: "invalid_turn" }),
      },
    },
    { type: "response.create" },
  ]);
});
