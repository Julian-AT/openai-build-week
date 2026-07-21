import { randomUUID, timingSafeEqual } from "node:crypto";

import {
  type AgentPlanner,
  type AgentReadToolExecutor,
  type AgentTurnInput,
  type AuthoritativeTurnContext,
  createOpenAIResponsesAgentPlanner,
  PROPOSAL_MODEL,
  REFRAME_AGENT_TOOLS,
  runBoundedAgentTurnResult,
} from "@reframe/agent";
import type { AssetSupportType, CatalogDimensionsM, CatalogRetriever } from "@reframe/catalog";
import { createFloorPlacementPreview } from "@reframe/protocol";

import {
  type CatalogSearchScope,
  createAgentReadTools,
  type SceneAgentQueries,
} from "./agent-read-tools.ts";
import type { AgentTurnRequest, AgentTurnService } from "./agent-turn.ts";
import { SessionCredentialError } from "./edit-transaction-service.ts";
import type { KnownTarget, KnownTargetRegistry } from "./known-target-registry.ts";

const MAX_EXPLANATION_LENGTH = 280;
const PROPOSAL_ID =
  /^proposal_[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u;

export interface LivePlacementScope extends CatalogSearchScope {
  readonly category: string;
  readonly maxDimensionsM: CatalogDimensionsM;
  readonly supportType: AssetSupportType;
  readonly cacheProfile: string;
}

export interface LivePlacementPreview {
  readonly type: "placement_preview";
  readonly status: "pending_confirmation";
  readonly proposal_id: string;
  readonly base_scene_revision: number;
  readonly intent: {
    readonly operation: "place" | "replace";
    readonly target_id?: string;
    readonly asset_id: string;
  };
  /** RF-COORD-1 column-vector transform serialized in row-major order. */
  readonly world_from_asset: readonly number[];
  readonly model: {
    readonly provider: "openai";
    readonly model: typeof PROPOSAL_MODEL;
    readonly response_id: string;
  };
  readonly explanation: string;
  /** Internal staging metadata; never used as model authority. */
  readonly replacement?: {
    readonly instance_id: string;
    readonly reveal_bundle_id: string;
  };
}

export interface LivePlacementAgentTurnServiceOptions {
  readonly credential: string;
  readonly context: AuthoritativeTurnContext;
  readonly catalog: CatalogRetriever;
  readonly scope: LivePlacementScope;
  readonly floorContactRF: Readonly<{ x: number; y: number; z: number }>;
  readonly yawRadians: number;
  readonly apiKey?: string;
  readonly plannerFactory?: { create(): AgentPlanner };
  readonly nextProposalID?: () => string;
  readonly targetRegistry?: KnownTargetRegistry;
  readonly nextReplacementInstanceID?: () => string;
}

export interface LivePlacementAgentTurnService extends AgentTurnService {
  submit(
    credential: string,
    turn: AgentTurnRequest,
    signal: AbortSignal,
  ): Promise<LivePlacementPreview>;
}

/**
 * A narrowly scoped integration proof: GPT may ask the five public questions,
 * but only deterministic code can bind a searched asset to a local floor
 * preview. It deliberately exposes no mutation port.
 */
export function createLivePlacementAgentTurnService(
  options: LivePlacementAgentTurnServiceOptions,
): LivePlacementAgentTurnService {
  assertOptions(options);
  const plannerFactory =
    options.plannerFactory ??
    createPlannerFactory(options.apiKey as string, options.targetRegistry !== undefined);
  const authoritativeContext = freezeContext(options.context);
  const nextProposalID = options.nextProposalID ?? (() => `proposal_${randomUUID()}`);

  return {
    async submit(credential, turn, signal) {
      signal.throwIfAborted();
      authorize(credential, options.credential);
      if (
        turn.intent_hint !== null &&
        turn.intent_hint !== "place" &&
        turn.intent_hint !== "replace"
      ) {
        throw new AgentPlacementError("agent_placement_intent_required");
      }
      if (turn.intent_hint === "replace" && options.targetRegistry === undefined) {
        throw new AgentPlacementError("replacement_target_unavailable");
      }

      const prepared = createPreparedPreviewAuthority({
        catalog: options.catalog,
        context: authoritativeContext,
        scope: options.scope,
        floorContactRF: options.floorContactRF,
        yawRadians: options.yawRadians,
        nextProposalID,
        ...(options.targetRegistry === undefined ? {} : { targetRegistry: options.targetRegistry }),
        nextReplacementInstanceID:
          options.nextReplacementInstanceID ?? (() => `instance_${randomUUID()}`),
      });
      const input: AgentTurnInput = Object.freeze({
        clientTurnID: turn.client_turn_id,
        utterance: turn.utterance,
        authoritativeContext,
      });
      const modelResult = await runBoundedAgentTurnResult(
        input,
        plannerFactory.create(),
        prepared.tools,
        signal,
      );
      return prepared.finalize(modelResult.proposal, modelResult.responseID);
    },
  };
}

export class AgentPlacementError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AgentPlacementError";
  }
}

function createPlannerFactory(
  apiKey: string,
  supportsReplacement: boolean,
): { create(): AgentPlanner } {
  if (apiKey.length === 0) throw new AgentPlacementError("missing_openai_api_key");
  return {
    create: () =>
      createOpenAIResponsesAgentPlanner({
        apiKey,
        tools: REFRAME_AGENT_TOOLS.filter((tool) =>
          [
            "search_catalog",
            "prepare_edit_preview",
            "resolve_target",
            "validate_candidate",
            "get_scene_context",
          ].includes(tool.name),
        ),
        instructions: [
          "You prepare exactly one Reframe placement or replacement preview and never commit an edit.",
          "Use only the supplied read-only or preview-only functions.",
          "For a floor placement, search_catalog with a concise user-derived query and a limit no greater than 8.",
          ...(supportsReplacement
            ? [
                "For replacement, resolve_target first, search_catalog, validate_candidate, then call prepare_edit_preview with the resolved target_id.",
              ]
            : ["Replacement is unavailable unless an authoritative target is resolved."]),
          "Choose only an asset returned by search_catalog.",
          "After a preview is prepared, respond with the required JSON. Copy its proposal_id exactly.",
          "Never invent a transform, target, revision, asset ID, URL, or a confirmation. Do not call unavailable tools.",
        ].join(" "),
        proposalSchema: LIVE_PLACEMENT_PROPOSAL_SCHEMA,
      }),
  };
}

export const LIVE_PLACEMENT_PROPOSAL_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["status", "proposal_id", "explanation"],
  properties: {
    status: { type: "string", const: "preview_ready" },
    proposal_id: { type: "string", pattern: PROPOSAL_ID.source },
    explanation: {
      type: "string",
      minLength: 1,
      maxLength: MAX_EXPLANATION_LENGTH,
      pattern: "^[^\\r\\n]+$",
    },
  },
} as const;

function createPreparedPreviewAuthority(options: {
  readonly catalog: CatalogRetriever;
  readonly context: AuthoritativeTurnContext;
  readonly scope: LivePlacementScope;
  readonly floorContactRF: Readonly<{ x: number; y: number; z: number }>;
  readonly yawRadians: number;
  readonly nextProposalID: () => string;
  readonly targetRegistry?: KnownTargetRegistry;
  readonly nextReplacementInstanceID: () => string;
}): {
  readonly tools: AgentReadToolExecutor;
  finalize(modelProposal: unknown, responseID: string | undefined): LivePlacementPreview;
} {
  const eligibleAssetIDs = new Set<string>();
  const catalogHits = new Map<string, Awaited<ReturnType<CatalogRetriever["search"]>>[number]>();
  let prepared: Omit<LivePlacementPreview, "explanation" | "model"> | undefined;
  let resolvedTarget: KnownTarget | null = null;
  const trackedCatalog: CatalogRetriever = {
    async search(request, signal) {
      // Catalog unavailability propagates as a typed error. It is never rescued
      // with a fabricated placement candidate.
      const hits = await options.catalog.search(request, signal);
      for (const hit of hits) {
        eligibleAssetIDs.add(hit.assetID);
        catalogHits.set(hit.assetID, hit);
      }
      return hits;
    },
  };
  const scene: SceneAgentQueries = {
    async getSceneContext(authority) {
      assertSameContext(authority, options.context);
      return {
        scene_revision: authority.sceneRevision,
        placement_support: "floor",
        preview_only: true,
      };
    },
    async resolveTarget(authority, request) {
      assertSameContext(authority, options.context);
      if (options.targetRegistry === undefined) {
        resolvedTarget = null;
        return { status: "unavailable" };
      }
      resolvedTarget = options.targetRegistry.resolve(authority.sessionID, request);
      return resolvedTarget === null
        ? { status: "unresolved" }
        : {
            status: "resolved",
            target_id: resolvedTarget.targetID,
            dimensions_m: resolvedTarget.dimensionsM,
          };
    },
    async catalogScope(authority, _requestedCategory) {
      assertSameContext(authority, options.context);
      return options.scope;
    },
    async validateCandidate(authority, request) {
      assertSameContext(authority, options.context);
      const target = resolveAuthoritativeTarget(request.targetID);
      if (request.targetID !== null && target === null) {
        return { valid: false, asset_id: request.assetID, reason: "target_unresolved" };
      }
      const hit = catalogHits.get(request.assetID);
      if (hit === undefined) {
        return { valid: false, asset_id: request.assetID, reason: "asset_not_searched" };
      }
      if (target !== null && !fitsTarget(hit.dimensionsM, target.dimensionsM)) {
        return {
          valid: false,
          asset_id: request.assetID,
          reason: "replacement_dimensions_exceed_target",
        };
      }
      return {
        valid: true,
        asset_id: request.assetID,
        ...(target === null ? {} : { target_id: target.targetID }),
      };
    },
    async prepareEditPreview(authority, request) {
      assertSameContext(authority, options.context);
      if (request.assetID === null || !eligibleAssetIDs.has(request.assetID)) {
        throw new AgentPlacementError("agent_preview_asset_not_eligible");
      }
      if (prepared !== undefined) throw new AgentPlacementError("agent_preview_already_prepared");
      const proposalID = options.nextProposalID();
      if (!PROPOSAL_ID.test(proposalID)) throw new AgentPlacementError("invalid_agent_proposal_id");
      if (request.intent === "replace") {
        const target =
          request.targetID === null ? null : resolveAuthoritativeTarget(request.targetID);
        const hit = catalogHits.get(request.assetID);
        if (
          target === null ||
          hit === undefined ||
          !fitsTarget(hit.dimensionsM, target.dimensionsM)
        ) {
          throw new AgentPlacementError("replacement_candidate_rejected");
        }
        const replacementInstanceID = options.nextReplacementInstanceID();
        if (!/^instance_[0-9a-f-]{36}$/u.test(replacementInstanceID)) {
          throw new AgentPlacementError("invalid_replacement_instance_id");
        }
        prepared = Object.freeze({
          type: "placement_preview" as const,
          status: "pending_confirmation" as const,
          proposal_id: proposalID,
          base_scene_revision: authority.sceneRevision,
          intent: Object.freeze({
            operation: "replace" as const,
            target_id: target.targetID,
            asset_id: request.assetID,
          }),
          world_from_asset: Object.freeze([...target.worldFromTarget]),
          replacement: Object.freeze({
            instance_id: replacementInstanceID,
            reveal_bundle_id: target.revealBundleID,
          }),
        });
        return prepared;
      }
      if (request.intent !== "place" || request.targetID !== null) {
        throw new AgentPlacementError("agent_preview_intent_not_supported");
      }
      const localPreview = createFloorPlacementPreview({
        assetID: request.assetID,
        baseSceneRevision: authority.sceneRevision,
        supportSurfaceID: "floor_support_smoke",
        floorContactWorld: options.floorContactRF,
        yawRadians: options.yawRadians,
      });
      prepared = Object.freeze({
        type: "placement_preview" as const,
        status: "pending_confirmation" as const,
        proposal_id: proposalID,
        base_scene_revision: localPreview.baseSceneRevision,
        intent: Object.freeze({ operation: "place" as const, asset_id: request.assetID }),
        world_from_asset: localPreview.worldFromAsset,
      });
      return prepared;
    },
  };

  return {
    tools: createAgentReadTools({ scene, catalog: trackedCatalog }),
    finalize(modelProposal, responseID) {
      const response = parseModelProposal(modelProposal);
      if (
        prepared === undefined ||
        response.proposalID !== prepared.proposal_id ||
        !isResponseID(responseID)
      ) {
        throw new AgentPlacementError("agent_preview_not_authoritative");
      }
      return Object.freeze({
        ...prepared,
        model: Object.freeze({
          provider: "openai" as const,
          model: PROPOSAL_MODEL,
          response_id: responseID,
        }),
        explanation: response.explanation,
      });
    },
  };

  function resolveAuthoritativeTarget(targetID: string): KnownTarget | null {
    if (options.targetRegistry === undefined || resolvedTarget === null) return null;
    return resolvedTarget.targetID === targetID ? resolvedTarget : null;
  }
}

function fitsTarget(
  candidate: CatalogDimensionsM,
  target: Readonly<{ width: number; height: number; depth: number }>,
): boolean {
  const tolerance = 1.05;
  return (
    candidate.width <= target.width * tolerance &&
    candidate.height <= target.height * tolerance &&
    candidate.depth <= target.depth * tolerance
  );
}

function parseModelProposal(value: unknown): { proposalID: string; explanation: string } {
  if (
    !isExactRecord(value, ["status", "proposal_id", "explanation"]) ||
    value.status !== "preview_ready" ||
    !isProposalID(value.proposal_id) ||
    !isExplanation(value.explanation)
  ) {
    throw new AgentPlacementError("invalid_agent_placement_proposal");
  }
  return { proposalID: value.proposal_id, explanation: value.explanation };
}

function assertOptions(options: LivePlacementAgentTurnServiceOptions): void {
  if (
    options.credential.length < 8 ||
    options.credential.trim() !== options.credential ||
    options.credential.length > 512 ||
    !validDimensions(options.scope.maxDimensionsM) ||
    !isSafeIdentifier(options.scope.category) ||
    !isSafeIdentifier(options.scope.cacheProfile) ||
    !["floor", "surface", "wall", "ceiling"].includes(options.scope.supportType) ||
    ![options.floorContactRF.x, options.floorContactRF.y, options.floorContactRF.z].every(
      Number.isFinite,
    ) ||
    !Number.isFinite(options.yawRadians) ||
    options.yawRadians < -Math.PI ||
    options.yawRadians > Math.PI ||
    (options.plannerFactory === undefined &&
      (options.apiKey === undefined || options.apiKey.length === 0))
  ) {
    throw new AgentPlacementError("invalid_live_placement_agent_options");
  }
  freezeContext(options.context);
}

function freezeContext(context: AuthoritativeTurnContext): AuthoritativeTurnContext {
  if (
    !isSafeIdentifier(context.sessionID) ||
    !Number.isSafeInteger(context.sceneRevision) ||
    context.sceneRevision < 0 ||
    !(context.pointerContextID === null || isSafeIdentifier(context.pointerContextID))
  ) {
    throw new AgentPlacementError("invalid_live_placement_context");
  }
  return Object.freeze({ ...context });
}

function assertSameContext(
  received: AuthoritativeTurnContext,
  expected: AuthoritativeTurnContext,
): void {
  if (
    received.sessionID !== expected.sessionID ||
    received.sceneRevision !== expected.sceneRevision ||
    received.pointerContextID !== expected.pointerContextID
  ) {
    throw new AgentPlacementError("agent_context_mismatch");
  }
}

function authorize(received: string, expected: string): void {
  const receivedBytes = Buffer.from(received, "utf8");
  const expectedBytes = Buffer.from(expected, "utf8");
  if (
    receivedBytes.length !== expectedBytes.length ||
    !timingSafeEqual(receivedBytes, expectedBytes)
  ) {
    throw new SessionCredentialError();
  }
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

function isProposalID(value: unknown): value is string {
  return typeof value === "string" && PROPOSAL_ID.test(value);
}

function isResponseID(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z0-9._-]{1,128}$/u.test(value);
}

function isExplanation(value: unknown): value is string {
  return (
    typeof value === "string" &&
    value.length >= 1 &&
    value.length <= MAX_EXPLANATION_LENGTH &&
    value.trim() === value &&
    !/[\r\n]/u.test(value) &&
    !/(?:[A-Za-z][A-Za-z0-9+.-]*:\/\/|www\.)/u.test(value)
  );
}

function isSafeIdentifier(value: string): boolean {
  return /^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$/u.test(value) && value.length <= 128;
}

function validDimensions(dimensions: CatalogDimensionsM): boolean {
  return [dimensions.width, dimensions.height, dimensions.depth].every(
    (value) => Number.isFinite(value) && value > 0 && value < 100,
  );
}
