import {
  type AssetSupportType,
  type CatalogRetriever,
  createCatalogRetriever,
  createOpenAICatalogQueryVectorizer,
  QdrantCatalogStore,
} from "@reframe/catalog";

import type { AgentTurnRequest, AgentTurnService } from "./agent-turn.ts";
import type { DurableEditTransactionService } from "./durable-edit-transaction-service.ts";
import type { DurableRoomSessionStore } from "./durable-session-store.ts";
import type { KnownTargetRegistry } from "./known-target-registry.ts";
import {
  createLivePlacementAgentTurnService,
  type LivePlacementScope,
} from "./live-placement-agent.ts";

export interface RoomAgentServiceOptions {
  readonly openAIAPIKey: string;
  readonly qdrantURL: string;
  readonly qdrantAPIKey?: string;
  readonly sessionStore: DurableRoomSessionStore;
  readonly editTransactionService?: DurableEditTransactionService;
  readonly category: string;
  readonly maxDimensionsM: {
    readonly width: number;
    readonly height: number;
    readonly depth: number;
  };
  readonly supportType: AssetSupportType;
  readonly cacheProfile: string;
  readonly floorContactRF: { readonly x: number; readonly y: number; readonly z: number };
  readonly yawRadians: number;
  readonly targetRegistry?: KnownTargetRegistry;
}

/**
 * Creates the opt-in live placement service. Each request first validates the
 * room-scoped credential, then builds a preview authority for that room. The
 * model still has no mutation tools; deterministic placement staging and any
 * later CAS commit stay behind the durable edit service.
 */
export function createRoomAgentTurnService(options: RoomAgentServiceOptions): AgentTurnService {
  const catalog = createCatalogRetriever({
    vectorizer: createOpenAICatalogQueryVectorizer({ apiKey: options.openAIAPIKey }),
    store: new QdrantCatalogStore({
      url: options.qdrantURL,
      ...(options.qdrantAPIKey === undefined ? {} : { apiKey: options.qdrantAPIKey }),
    }),
  });
  return createRoomAgentTurnServiceWithCatalog(options, catalog);
}

export function createRoomAgentTurnServiceWithCatalog(
  options: RoomAgentServiceOptions,
  catalog: CatalogRetriever,
): AgentTurnService {
  const scope: LivePlacementScope = Object.freeze({
    category: options.category,
    maxDimensionsM: Object.freeze(options.maxDimensionsM),
    supportType: options.supportType,
    cacheProfile: options.cacheProfile,
  });
  return {
    async submit(
      credential: string,
      turn: AgentTurnRequest,
      signal: AbortSignal,
    ): Promise<unknown> {
      let sessionID: string | undefined;
      await options.sessionStore.withAuthorizedScene(credential, (authorizedSessionID) => {
        sessionID = authorizedSessionID;
      });
      if (sessionID === undefined) throw new Error("invalid_room_credential");
      const sceneRevision =
        options.editTransactionService === undefined
          ? 0
          : (await options.editTransactionService.readScene(credential)).scene_revision;
      const service = createLivePlacementAgentTurnService({
        credential,
        context: Object.freeze({
          sessionID,
          sceneRevision,
          pointerContextID: turn.pointer_context_id,
        }),
        catalog,
        scope,
        floorContactRF: turn.pointer_context?.world_position ?? options.floorContactRF,
        yawRadians: options.yawRadians,
        ...(options.targetRegistry === undefined ? {} : { targetRegistry: options.targetRegistry }),
        apiKey: options.openAIAPIKey,
      });
      const preview = await service.submit(credential, turn, signal);
      if (preview.intent.operation === "replace") {
        const replacement = preview.replacement;
        if (replacement === undefined || preview.intent.target_id === undefined) {
          throw new Error("replacement_staging_metadata_missing");
        }
        await options.editTransactionService?.stageValidatedReplacement(credential, {
          sessionID,
          proposalID: preview.proposal_id,
          baseSceneRevision: preview.base_scene_revision,
          targetID: preview.intent.target_id,
          assetID: preview.intent.asset_id,
          replacementInstanceID: replacement.instance_id,
          revealBundleID: replacement.reveal_bundle_id,
          worldFromAsset: preview.world_from_asset,
        });
        const { replacement: _replacement, ...publicPreview } = preview;
        return publicPreview;
      } else {
        await options.editTransactionService?.stagePlacementPreview(credential, {
          proposalID: preview.proposal_id,
          baseSceneRevision: preview.base_scene_revision,
          assetID: preview.intent.asset_id,
          worldFromAsset: preview.world_from_asset,
        });
      }
      return preview;
    },
  };
}
