import {
  type AssetSupportType,
  createCatalogRetriever,
  createOpenAICatalogQueryVectorizer,
  QdrantCatalogStore,
} from "@reframe/catalog";

import type { AgentTurnRequest } from "./agent-turn.ts";
import {
  createLivePlacementAgentTurnService,
  type LivePlacementPreview,
  type LivePlacementScope,
} from "./live-placement-agent.ts";

export interface LivePlacementAgentSmokeConfiguration {
  readonly apiKey: string;
  readonly qdrantURL: string;
  readonly qdrantAPIKey: string;
  readonly credential: string;
  readonly context: {
    readonly sessionID: string;
    readonly sceneRevision: number;
    readonly pointerContextID: string | null;
  };
  readonly scope: LivePlacementScope;
  readonly floorContactRF: Readonly<{ x: number; y: number; z: number }>;
  readonly yawRadians: number;
  readonly turn: AgentTurnRequest;
}

/** Runs the live OpenAI + embedding + Qdrant placement proof with explicit server-only config. */
export async function runLivePlacementAgentSmokeFromEnvironment(
  environment: Record<string, string | undefined>,
  signal: AbortSignal = new AbortController().signal,
): Promise<LivePlacementPreview> {
  const configuration = parseLivePlacementAgentSmokeEnvironment(environment);
  const catalog = createCatalogRetriever({
    vectorizer: createOpenAICatalogQueryVectorizer({ apiKey: configuration.apiKey }),
    store: new QdrantCatalogStore({
      url: configuration.qdrantURL,
      apiKey: configuration.qdrantAPIKey,
    }),
  });
  const service = createLivePlacementAgentTurnService({
    credential: configuration.credential,
    context: configuration.context,
    catalog,
    scope: configuration.scope,
    floorContactRF: configuration.floorContactRF,
    yawRadians: configuration.yawRadians,
    apiKey: configuration.apiKey,
  });
  return await service.submit(configuration.credential, configuration.turn, signal);
}

export function parseLivePlacementAgentSmokeEnvironment(
  environment: Record<string, string | undefined>,
): LivePlacementAgentSmokeConfiguration {
  const apiKey = required(environment.OPENAI_API_KEY, "openai_api_key");
  const qdrantURL = qdrantURLFrom(environment);
  const qdrantAPIKey = required(environment.QDRANT_API_KEY, "qdrant_api_key");
  const credential = required(environment.REFRAME_AGENT_SMOKE_CREDENTIAL, "agent_smoke_credential");
  if (credential.length < 8 || credential.length > 512 || credential.trim() !== credential) {
    throw new Error("invalid_agent_smoke_credential");
  }
  const sessionID = identifier(
    required(environment.REFRAME_AGENT_SMOKE_SESSION_ID, "agent_smoke_session_id"),
    "agent_smoke_session_id",
  );
  const pointerContextID = nullableIdentifier(environment.REFRAME_AGENT_SMOKE_POINTER_CONTEXT_ID);
  const sceneRevision = nonnegativeInteger(
    environment.REFRAME_AGENT_SMOKE_SCENE_REVISION,
    "agent_smoke_scene_revision",
  );
  const scope = Object.freeze({
    category: identifier(
      required(environment.REFRAME_AGENT_SMOKE_CATEGORY, "agent_smoke_category"),
      "agent_smoke_category",
    ),
    maxDimensionsM: Object.freeze({
      width: meter(environment.REFRAME_AGENT_SMOKE_MAX_WIDTH_M, "agent_smoke_max_width_m"),
      height: meter(environment.REFRAME_AGENT_SMOKE_MAX_HEIGHT_M, "agent_smoke_max_height_m"),
      depth: meter(environment.REFRAME_AGENT_SMOKE_MAX_DEPTH_M, "agent_smoke_max_depth_m"),
    }),
    supportType: supportType(environment.REFRAME_AGENT_SMOKE_SUPPORT_TYPE),
    cacheProfile: identifier(
      required(environment.REFRAME_AGENT_SMOKE_CACHE_PROFILE, "agent_smoke_cache_profile"),
      "agent_smoke_cache_profile",
    ),
  } satisfies LivePlacementScope);
  const turn = Object.freeze({
    client_turn_id: identifier(
      required(environment.REFRAME_AGENT_SMOKE_TURN_ID, "agent_smoke_turn_id"),
      "agent_smoke_turn_id",
    ),
    utterance: utterance(
      required(environment.REFRAME_AGENT_SMOKE_UTTERANCE, "agent_smoke_utterance"),
    ),
    intent_hint: "place" as const,
    pointer_context_id: pointerContextID,
    client_scene_revision: sceneRevision,
    pending_proposal_id: null,
  });
  return Object.freeze({
    apiKey,
    qdrantURL,
    qdrantAPIKey,
    credential,
    context: Object.freeze({ sessionID, sceneRevision, pointerContextID }),
    scope,
    floorContactRF: Object.freeze({
      x: finite(environment.REFRAME_AGENT_SMOKE_FLOOR_X_M, "agent_smoke_floor_x_m"),
      y: finite(environment.REFRAME_AGENT_SMOKE_FLOOR_Y_M, "agent_smoke_floor_y_m"),
      z: finite(environment.REFRAME_AGENT_SMOKE_FLOOR_Z_M, "agent_smoke_floor_z_m"),
    }),
    yawRadians: yaw(environment.REFRAME_AGENT_SMOKE_YAW_RADIANS),
    turn,
  });
}

function qdrantURLFrom(environment: Record<string, string | undefined>): string {
  const value = required(environment.REFRAME_QDRANT_URL ?? environment.QDRANT_URL, "qdrant_url");
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Error("invalid_qdrant_url");
  }
  if (
    (url.protocol !== "http:" && url.protocol !== "https:") ||
    url.username !== "" ||
    url.password !== ""
  ) {
    throw new Error("invalid_qdrant_url");
  }
  return url.toString();
}

function required(value: string | undefined, name: string): string {
  const normalized = value?.trim();
  if (normalized === undefined || normalized.length === 0) throw new Error(`missing_${name}`);
  return normalized;
}

function identifier(value: string, name: string): string {
  if (!/^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$/u.test(value) || value.length > 128) {
    throw new Error(`invalid_${name}`);
  }
  return value;
}

function nullableIdentifier(value: string | undefined): string | null {
  const normalized = value?.trim();
  if (normalized === undefined || normalized.length === 0) return null;
  return identifier(normalized, "agent_smoke_pointer_context_id");
}

function nonnegativeInteger(value: string | undefined, name: string): number {
  const parsed = Number(required(value, name));
  if (!Number.isSafeInteger(parsed) || parsed < 0) throw new Error(`invalid_${name}`);
  return parsed;
}

function meter(value: string | undefined, name: string): number {
  const parsed = finite(value, name);
  if (parsed <= 0 || parsed >= 100) throw new Error(`invalid_${name}`);
  return parsed;
}

function finite(value: string | undefined, name: string): number {
  const parsed = Number(required(value, name));
  if (!Number.isFinite(parsed)) throw new Error(`invalid_${name}`);
  return parsed;
}

function yaw(value: string | undefined): number {
  const parsed = finite(value, "agent_smoke_yaw_radians");
  if (parsed < -Math.PI || parsed > Math.PI) throw new Error("invalid_agent_smoke_yaw_radians");
  return parsed;
}

function supportType(value: string | undefined): AssetSupportType {
  const normalized = required(value, "agent_smoke_support_type");
  if (
    !(["floor", "surface", "wall", "ceiling"] as const).includes(normalized as AssetSupportType)
  ) {
    throw new Error("invalid_agent_smoke_support_type");
  }
  return normalized as AssetSupportType;
}

function utterance(value: string): string {
  if (value.length > 2_000 || hasControlCharacter(value) || value.trim() !== value) {
    throw new Error("invalid_agent_smoke_utterance");
  }
  return value;
}

function hasControlCharacter(value: string): boolean {
  for (let index = 0; index < value.length; index += 1) {
    const codePoint = value.charCodeAt(index);
    if (codePoint <= 31 || codePoint === 127) return true;
  }
  return false;
}
