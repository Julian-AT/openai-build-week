import { createHash } from "node:crypto";

export type AgentTraceEvent =
  | {
      readonly type: "turn_started";
      readonly clientTurnID: string;
      readonly sessionID: string;
      readonly sceneRevision: number;
    }
  | {
      readonly type: "tool_call";
      readonly name: string;
      readonly callID: string;
    }
  | {
      readonly type: "tool_result";
      readonly name: string;
      readonly callID: string;
      readonly outputBytes: number;
    }
  | {
      readonly type: "proposal";
      readonly responseID: string | null;
    }
  | {
      readonly type: "failure";
      readonly code: string;
    };

/** A sink receives only structured, redacted agent facts — never prompts or room data. */
export type AgentTraceSink = (event: Readonly<RedactedAgentTraceEvent>) => void;

interface TraceInput {
  readonly type: AgentTraceEvent["type"];
  readonly clientTurnID?: string;
  readonly sessionID?: string;
  readonly sceneRevision?: number;
  readonly name?: string;
  readonly callID?: string;
  readonly responseID?: string | null;
  readonly outputBytes?: number;
  readonly code?: string;
}

export interface RedactedAgentTraceEvent {
  readonly type: AgentTraceEvent["type"];
  readonly requestID: string;
  readonly sessionIDHash?: string;
  readonly clientTurnIDHash?: string;
  readonly sceneRevision?: number;
  readonly toolName?: string;
  readonly callIDHash?: string;
  readonly responseIDHash?: string;
  readonly outputBytes?: number;
  readonly code?: string;
}

export function createRedactedTraceSink(
  requestID: string,
  sink: (event: RedactedAgentTraceEvent) => void,
): (event: TraceInput) => void {
  if (!/^[A-Za-z0-9._-]{1,128}$/u.test(requestID)) throw new Error("invalid_trace_request_id");
  return (event) => {
    const redacted: RedactedAgentTraceEvent = {
      type: event.type,
      requestID,
      ...(event.sessionID === undefined ? {} : { sessionIDHash: hash(event.sessionID) }),
      ...(event.clientTurnID === undefined ? {} : { clientTurnIDHash: hash(event.clientTurnID) }),
      ...(event.sceneRevision === undefined ? {} : { sceneRevision: event.sceneRevision }),
      ...(event.name === undefined ? {} : { toolName: event.name }),
      ...(event.callID === undefined ? {} : { callIDHash: hash(event.callID) }),
      ...(event.responseID === undefined || event.responseID === null
        ? {}
        : { responseIDHash: hash(event.responseID) }),
      ...(event.outputBytes === undefined ? {} : { outputBytes: event.outputBytes }),
      ...(event.code === undefined ? {} : { code: event.code }),
    };
    sink(Object.freeze(redacted));
  };
}

function hash(value: string): string {
  return createHash("sha256").update(value).digest("hex").slice(0, 16);
}
