import {
  type AgentReadToolExecutor,
  type AgentToolCall,
  AgentToolPolicyError,
  type AuthoritativeTurnContext,
} from "@reframe/agent";
import type { AssetSupportType, CatalogDimensionsM, CatalogRetriever } from "@reframe/catalog";

type DetailLevel = "summary" | "detailed";
type EditIntent = "place" | "replace" | "remove" | "restore";

export interface AgentConstraint {
  readonly kind: string;
  readonly value: string | number | boolean;
}

export interface CatalogSearchScope {
  readonly category: string;
  readonly maxDimensionsM: CatalogDimensionsM;
  readonly supportType: AssetSupportType;
  readonly cacheProfile: string;
}

export interface SceneAgentQueries {
  getSceneContext(
    authority: AuthoritativeTurnContext,
    request: { readonly region: string | null; readonly detailLevel: DetailLevel },
    signal: AbortSignal,
  ): Promise<unknown>;
  resolveTarget(
    authority: AuthoritativeTurnContext,
    request: {
      readonly pointerContextID: string | null;
      readonly languageReference: string | null;
    },
    signal: AbortSignal,
  ): Promise<unknown>;
  catalogScope(
    authority: AuthoritativeTurnContext,
    requestedCategory: string | null,
    signal: AbortSignal,
  ): Promise<CatalogSearchScope>;
  validateCandidate(
    authority: AuthoritativeTurnContext,
    request: {
      readonly targetID: string;
      readonly assetID: string;
      readonly constraints: readonly AgentConstraint[];
    },
    signal: AbortSignal,
  ): Promise<unknown>;
  prepareEditPreview(
    authority: AuthoritativeTurnContext,
    request: {
      readonly intent: EditIntent;
      readonly targetID: string | null;
      readonly assetID: string | null;
      readonly constraints: readonly AgentConstraint[];
    },
    signal: AbortSignal,
  ): Promise<unknown>;
}

export function createAgentReadTools(options: {
  scene: SceneAgentQueries;
  catalog: CatalogRetriever;
}): AgentReadToolExecutor {
  return {
    async execute(call, authority, signal) {
      signal.throwIfAborted();
      switch (call.name) {
        case "get_scene_context":
          return await executeGetScene(call, authority, signal, options.scene);
        case "resolve_target":
          return await executeResolveTarget(call, authority, signal, options.scene);
        case "search_catalog":
          return await executeCatalogSearch(call, authority, signal, options);
        case "validate_candidate":
          return await executeValidateCandidate(call, authority, signal, options.scene);
        case "prepare_edit_preview":
          return await executePreparePreview(call, authority, signal, options.scene);
      }
    },
  };
}

async function executeGetScene(
  call: AgentToolCall,
  authority: AuthoritativeTurnContext,
  signal: AbortSignal,
  scene: SceneAgentQueries,
): Promise<unknown> {
  const args = exactArguments(call.arguments, ["region", "detail_level"]);
  if (
    !isNullableBoundedString(args.region, 128) ||
    (args.detail_level !== "summary" && args.detail_level !== "detailed")
  ) {
    invalidArguments();
  }
  return await scene.getSceneContext(
    authority,
    { region: args.region, detailLevel: args.detail_level },
    signal,
  );
}

async function executeResolveTarget(
  call: AgentToolCall,
  authority: AuthoritativeTurnContext,
  signal: AbortSignal,
  scene: SceneAgentQueries,
): Promise<unknown> {
  const args = exactArguments(call.arguments, ["pointer_context_id", "language_reference"]);
  if (
    !isNullableOpaqueReference(args.pointer_context_id) ||
    !isNullableBoundedString(args.language_reference, 500)
  ) {
    invalidArguments();
  }
  return await scene.resolveTarget(
    authority,
    {
      pointerContextID: authority.pointerContextID,
      languageReference: args.language_reference,
    },
    signal,
  );
}

async function executeCatalogSearch(
  call: AgentToolCall,
  authority: AuthoritativeTurnContext,
  signal: AbortSignal,
  options: { scene: SceneAgentQueries; catalog: CatalogRetriever },
): Promise<unknown> {
  const args = exactArguments(call.arguments, [
    "query",
    "category",
    "style",
    "color",
    "material",
    "limit",
  ]);
  if (
    !isBoundedString(args.query, 1, 500) ||
    !isNullableBoundedString(args.category, 64) ||
    !isNullableBoundedString(args.style, 128) ||
    !isNullableBoundedString(args.color, 128) ||
    !isNullableBoundedString(args.material, 128) ||
    !Number.isSafeInteger(args.limit) ||
    (args.limit as number) < 1 ||
    (args.limit as number) > 8
  ) {
    invalidArguments();
  }
  const scope = await options.scene.catalogScope(authority, args.category, signal);
  signal.throwIfAborted();
  const query = semanticCatalogQuery(args.query, {
    style: args.style,
    color: args.color,
    material: args.material,
  });
  const candidates = await options.catalog.search(
    { query, ...scope, limit: args.limit as number },
    signal,
  );
  return { candidates };
}

async function executeValidateCandidate(
  call: AgentToolCall,
  authority: AuthoritativeTurnContext,
  signal: AbortSignal,
  scene: SceneAgentQueries,
): Promise<unknown> {
  const args = exactArguments(call.arguments, ["target_id", "asset_id", "constraints"]);
  const constraints = parseConstraints(args.constraints);
  if (!isOpaqueReference(args.target_id) || !isOpaqueReference(args.asset_id)) {
    invalidArguments();
  }
  return await scene.validateCandidate(
    authority,
    { targetID: args.target_id, assetID: args.asset_id, constraints },
    signal,
  );
}

async function executePreparePreview(
  call: AgentToolCall,
  authority: AuthoritativeTurnContext,
  signal: AbortSignal,
  scene: SceneAgentQueries,
): Promise<unknown> {
  const args = exactArguments(call.arguments, ["intent", "target_id", "asset_id", "constraints"]);
  const constraints = parseConstraints(args.constraints);
  if (
    !isEditIntent(args.intent) ||
    !isNullableOpaqueReference(args.target_id) ||
    !isNullableOpaqueReference(args.asset_id) ||
    !validIntentReferences(args.intent, args.target_id, args.asset_id)
  ) {
    invalidArguments();
  }
  return await scene.prepareEditPreview(
    authority,
    {
      intent: args.intent,
      targetID: args.target_id,
      assetID: args.asset_id,
      constraints,
    },
    signal,
  );
}

function exactArguments(value: unknown, keys: readonly string[]): Record<string, unknown> {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value) ||
    Object.keys(value).length !== keys.length ||
    !keys.every((key) => key in value)
  ) {
    invalidArguments();
  }
  return value as Record<string, unknown>;
}

function parseConstraints(value: unknown): readonly AgentConstraint[] {
  if (!Array.isArray(value) || value.length > 16) invalidArguments();
  return Object.freeze(
    value.map((entry) => {
      const constraint = exactArguments(entry, ["kind", "value"]);
      if (
        !isBoundedString(constraint.kind, 1, 64) ||
        !["string", "number", "boolean"].includes(typeof constraint.value) ||
        (typeof constraint.value === "number" && !Number.isFinite(constraint.value))
      ) {
        invalidArguments();
      }
      return Object.freeze({
        kind: constraint.kind,
        value: constraint.value as string | number | boolean,
      });
    }),
  );
}

function semanticCatalogQuery(
  query: string,
  facets: Record<"style" | "color" | "material", string | null>,
): string {
  const parts = [query];
  for (const key of ["style", "color", "material"] as const) {
    const value = facets[key];
    if (value !== null) parts.push(`${key}: ${value}`);
  }
  return parts.join("; ");
}

function validIntentReferences(
  intent: EditIntent,
  targetID: string | null,
  assetID: string | null,
): boolean {
  if (intent === "place") return targetID === null && assetID !== null;
  if (intent === "replace") return targetID !== null && assetID !== null;
  if (intent === "remove") return targetID !== null && assetID === null;
  return targetID === null && assetID === null;
}

function isEditIntent(value: unknown): value is EditIntent {
  return ["place", "replace", "remove", "restore"].includes(value as string);
}

function isNullableOpaqueReference(value: unknown): value is string | null {
  return value === null || isOpaqueReference(value);
}

function isOpaqueReference(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z][A-Za-z0-9_-]{0,127}$/u.test(value);
}

function isNullableBoundedString(value: unknown, maximum: number): value is string | null {
  return value === null || isBoundedString(value, 1, maximum);
}

function isBoundedString(value: unknown, minimum: number, maximum: number): value is string {
  return (
    typeof value === "string" &&
    value.length >= minimum &&
    value.length <= maximum &&
    value.trim() === value
  );
}

function invalidArguments(): never {
  throw new AgentToolPolicyError("invalid_agent_tool_arguments");
}
