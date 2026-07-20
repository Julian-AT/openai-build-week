export const INGRESS_SOURCES = ["typed", "vision", "voice"] as const;
export const MAX_JPEG_BYTES = 1_500_000;

export type IngressSource = (typeof INGRESS_SOURCES)[number];

export interface ProposalRequestContext {
  session_id: string;
  revision_branch_id: string;
  base_scene_revision: number;
  world_frame_id: string;
  world_frame_version: number;
  selected_object_id: string | null;
}

export interface ProposalRequest {
  prompt: string;
  image_data_url?: string;
  ingress_source: IngressSource;
  request_context: ProposalRequestContext;
}

const stableUUID = "[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}";

export function parseProposalRequest(value: unknown): ProposalRequest {
  if (!isRecord(value)) {
    throw new ProtocolError("invalid_request");
  }
  const allowedRequestKeys = new Set(["prompt", "image_data_url", "ingress_source", "request_context"]);
  if (
    !["prompt", "ingress_source", "request_context"].every((key) => key in value) ||
    !Object.keys(value).every((key) => allowedRequestKeys.has(key))
  ) {
    throw new ProtocolError("invalid_request");
  }

  const prompt = value.prompt;
  const ingressSource = value.ingress_source;
  const context = value.request_context;
  if (
    typeof prompt !== "string" ||
    prompt.length < 1 ||
    prompt.length > 2_000 ||
    prompt.trim().length < 1 ||
    prompt.trim() !== prompt ||
    !INGRESS_SOURCES.includes(ingressSource as IngressSource) ||
    !isRecord(context) ||
    !hasExactKeys(context, [
      "session_id",
      "revision_branch_id",
      "base_scene_revision",
      "world_frame_id",
      "world_frame_version",
      "selected_object_id",
    ])
  ) {
    throw new ProtocolError("invalid_request");
  }

  const selectedObjectID = context.selected_object_id;
  if (
    !matchesID(context.session_id, "session") ||
    !matchesID(context.revision_branch_id, "branch") ||
    !Number.isSafeInteger(context.base_scene_revision) ||
    (context.base_scene_revision as number) < 0 ||
    !matchesID(context.world_frame_id, "world") ||
    !Number.isSafeInteger(context.world_frame_version) ||
    (context.world_frame_version as number) < 1 ||
    !(selectedObjectID === null || matchesID(selectedObjectID, "object"))
  ) {
    throw new ProtocolError("invalid_request");
  }

  const request: ProposalRequest = {
    prompt,
    ingress_source: ingressSource as IngressSource,
    request_context: {
      session_id: context.session_id as string,
      revision_branch_id: context.revision_branch_id as string,
      base_scene_revision: context.base_scene_revision as number,
      world_frame_id: context.world_frame_id as string,
      world_frame_version: context.world_frame_version as number,
      selected_object_id: selectedObjectID as string | null,
    },
  };

  if ("image_data_url" in value) {
    if (typeof value.image_data_url !== "string" || !isValidJPEGDataURL(value.image_data_url)) {
      throw new ProtocolError("invalid_request");
    }
    request.image_data_url = value.image_data_url;
  }
  if ((ingressSource === "vision") !== (request.image_data_url !== undefined)) {
    throw new ProtocolError("invalid_request");
  }
  return request;
}

export class ProtocolError extends Error {
  readonly code: string;

  constructor(code: string) {
    super(code);
    this.code = code;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function matchesID(value: unknown, prefix: string): value is string {
  return typeof value === "string" && new RegExp(`^${prefix}_${stableUUID}$`, "u").test(value);
}

function hasExactKeys(value: Record<string, unknown>, expected: readonly string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === expected.length && expected.every((key) => key in value);
}

function isValidJPEGDataURL(value: string): boolean {
  const match = /^data:image\/jpeg;base64,([A-Za-z0-9+/]+={0,2})$/u.exec(value);
  if (!match?.[1]) {
    return false;
  }
  const encoded = match[1];
  const bytes = Buffer.from(encoded, "base64");
  return (
    bytes.length >= 4 &&
    bytes.length <= MAX_JPEG_BYTES &&
    bytes.toString("base64") === encoded &&
    bytes[0] === 0xff &&
    bytes[1] === 0xd8 &&
    bytes.at(-2) === 0xff &&
    bytes.at(-1) === 0xd9
  );
}
