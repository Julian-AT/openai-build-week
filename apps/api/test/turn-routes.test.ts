import { test } from "bun:test";
import assert from "node:assert/strict";

import type { AgentTurnRequest, AgentTurnService } from "../src/agent-turn.ts";
import { SessionCredentialError } from "../src/edit-transaction-service.ts";
import { createGatewayApp } from "../src/server.ts";

const validTurn: AgentTurnRequest = {
  client_turn_id: "turn_019",
  utterance: "Replace this chair with something warmer.",
  intent_hint: "replace",
  pointer_context_id: "ptr_842_01",
  client_scene_revision: 4,
  pending_proposal_id: null,
};

test("POST /v1/turns passes a closed turn and separate scoped authority", async () => {
  let receivedCredential: string | undefined;
  let receivedTurn: AgentTurnRequest | undefined;
  let receivedSignal: AbortSignal | undefined;
  const expected = {
    status: "preview_ready",
    preview_id: "preview_10000000-0000-4000-8000-000000000001",
  };
  const service: AgentTurnService = {
    submit: async (credential, turn, signal) => {
      receivedCredential = credential;
      receivedTurn = turn;
      receivedSignal = signal;
      return expected;
    },
  };
  const app = createGatewayApp({ gatewayToken: "gateway-token", agentTurnService: service });

  const response = await app.request("/v1/turns", {
    method: "POST",
    headers: {
      authorization: "Bearer scoped-room-token",
      "content-type": "application/json",
    },
    body: JSON.stringify(validTurn),
  });

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), expected);
  assert.equal(receivedCredential, "scoped-room-token");
  assert.deepEqual(receivedTurn, validTurn);
  assert.equal(receivedSignal instanceof AbortSignal, true);
});

test("POST /v1/turns rejects a client-supplied pointer_context world position", async () => {
  let calls = 0;
  const service: AgentTurnService = {
    submit: async () => {
      calls += 1;
      return { status: "preview_ready" };
    },
  };
  const app = createGatewayApp({ gatewayToken: "gateway-token", agentTurnService: service });

  const response = await app.request("/v1/turns", {
    method: "POST",
    headers: {
      authorization: "Bearer scoped-room-token",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      ...validTurn,
      pointer_context: {
        world_position: { x: 0.12, y: -0.84, z: -1.4 },
        surface_id: "plane_floor_01",
      },
    }),
  });

  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: "invalid_request" });
  assert.equal(calls, 0);
});

test("POST /v1/turns rejects client-injected authority and mutation fields", async () => {
  let calls = 0;
  const service: AgentTurnService = {
    submit: async () => {
      calls += 1;
      return {};
    },
  };
  const app = createGatewayApp({ gatewayToken: "gateway-token", agentTurnService: service });
  const injectedFields = [
    ["session_id", "session_attacker"],
    ["world_frame_id", "world_attacker"],
    ["operations", [{ op: "commit" }]],
    ["transform", new Array(16).fill(1)],
    ["commit", true],
  ] as const;

  for (const [field, value] of injectedFields) {
    const response = await app.request("/v1/turns", {
      method: "POST",
      headers: {
        authorization: "Bearer scoped-room-token",
        "content-type": "application/json",
      },
      body: JSON.stringify({ ...validTurn, [field]: value }),
    });
    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), { error: "invalid_request" });
  }
  assert.equal(calls, 0);
});

test("POST /v1/turns validates the complete submit_user_turn envelope", async () => {
  let calls = 0;
  const service: AgentTurnService = {
    submit: async () => {
      calls += 1;
      return {};
    },
  };
  const app = createGatewayApp({ gatewayToken: "gateway-token", agentTurnService: service });
  const invalidTurns = [
    { ...validTurn, utterance: "  " },
    { ...validTurn, utterance: " padded" },
    { ...validTurn, intent_hint: "commit" },
    { ...validTurn, pointer_context_id: "" },
    { ...validTurn, client_scene_revision: -1 },
    { ...validTurn, pending_proposal_id: "bad reference!" },
    { ...validTurn, client_turn_id: "" },
  ];

  for (const body of invalidTurns) {
    const response = await app.request("/v1/turns", {
      method: "POST",
      headers: {
        authorization: "Bearer scoped-room-token",
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    });
    assert.equal(response.status, 400);
    assert.deepEqual(await response.json(), { error: "invalid_request" });
  }
  assert.equal(calls, 0);
});

test("POST /v1/turns requires a configured service and scoped credential", async () => {
  const app = createGatewayApp({ gatewayToken: "gateway-token" });
  const noCredential = await app.request("/v1/turns", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(validTurn),
  });
  assert.equal(noCredential.status, 401);

  const unavailable = await app.request("/v1/turns", {
    method: "POST",
    headers: {
      authorization: "Bearer scoped-room-token",
      "content-type": "application/json",
    },
    body: JSON.stringify(validTurn),
  });
  assert.equal(unavailable.status, 503);
  assert.deepEqual(await unavailable.json(), { error: "service_unavailable" });
});

test("POST /v1/turns maps invalid session credentials without exposing authority details", async () => {
  const service: AgentTurnService = {
    submit: async () => {
      throw new SessionCredentialError();
    },
  };
  const app = createGatewayApp({ gatewayToken: "gateway-token", agentTurnService: service });
  const response = await app.request("/v1/turns", {
    method: "POST",
    headers: {
      authorization: "Bearer wrong-room-token",
      "content-type": "application/json",
    },
    body: JSON.stringify(validTurn),
  });

  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), { error: "unauthorized" });
});

test("POST /v1/turns cancels timed-out orchestration and redacts failures", async () => {
  let observedAbort = false;
  const timeoutService: AgentTurnService = {
    submit: async (_credential, _turn, signal) =>
      await new Promise((_resolve, reject) => {
        signal.addEventListener(
          "abort",
          () => {
            observedAbort = true;
            reject(signal.reason);
          },
          { once: true },
        );
      }),
  };
  const request = (service: AgentTurnService) =>
    createGatewayApp({
      gatewayToken: "gateway-token",
      agentTurnService: service,
      requestTimeoutMilliseconds: 5,
    }).request("/v1/turns", {
      method: "POST",
      headers: {
        authorization: "Bearer scoped-room-token",
        "content-type": "application/json",
      },
      body: JSON.stringify(validTurn),
    });

  const timedOut = await request(timeoutService);
  assert.equal(timedOut.status, 504);
  assert.deepEqual(await timedOut.json(), { error: "upstream_timeout" });
  assert.equal(observedAbort, true);

  const failed = await request({
    submit: async () => {
      throw new Error("sk-private session prompt image");
    },
  });
  assert.equal(failed.status, 502);
  const body = JSON.stringify(await failed.json());
  assert.equal(body, '{"error":"upstream_failure"}');
  assert.doesNotMatch(body, /private|session|prompt|image/iu);
});
