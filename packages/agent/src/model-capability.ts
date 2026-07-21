export const REQUIRED_OPENAI_MODELS = ["gpt-5.6-sol", "gpt-realtime-2.1"] as const;

export type RequiredOpenAIModel = (typeof REQUIRED_OPENAI_MODELS)[number];

export interface OpenAIModelCapabilitySnapshot {
  readonly status: "ready" | "degraded";
  readonly models: Readonly<Record<RequiredOpenAIModel, boolean>>;
  readonly checkedAtMilliseconds: number;
}

export interface OpenAIModelCapabilityProbe {
  check(signal?: AbortSignal): Promise<OpenAIModelCapabilitySnapshot>;
}

type FetchImplementation = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

/**
 * Checks exact model identifiers before enabling live agent features. This is
 * intentionally a read-only `/v1/models` probe; callers must fail closed when
 * either configured identifier is unavailable instead of silently substituting.
 */
export function createOpenAIModelCapabilityProbe(options: {
  readonly apiKey: string;
  readonly fetch?: FetchImplementation;
  readonly nowMilliseconds?: () => number;
}): OpenAIModelCapabilityProbe {
  if (options.apiKey.length === 0) throw new Error("missing_openai_api_key");
  const fetchImplementation = options.fetch ?? globalThis.fetch;
  const now = options.nowMilliseconds ?? Date.now;
  return {
    async check(signal) {
      const response = await fetchImplementation("https://api.openai.com/v1/models", {
        method: "GET",
        headers: { Authorization: `Bearer ${options.apiKey}` },
        ...(signal === undefined ? {} : { signal }),
      });
      if (!response.ok) throw new Error("openai_model_capability_unavailable");
      const payload: unknown = await response.json();
      const IDs = extractModelIDs(payload);
      const models = Object.fromEntries(
        REQUIRED_OPENAI_MODELS.map((model) => [model, IDs.has(model)]),
      ) as Record<RequiredOpenAIModel, boolean>;
      return Object.freeze({
        status: Object.values(models).every(Boolean) ? "ready" : "degraded",
        models: Object.freeze(models),
        checkedAtMilliseconds: now(),
      });
    },
  };
}

function extractModelIDs(value: unknown): Set<string> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("invalid_openai_model_capability_response");
  }
  const data = (value as { data?: unknown }).data;
  if (!Array.isArray(data)) throw new Error("invalid_openai_model_capability_response");
  const ids = new Set<string>();
  for (const item of data) {
    if (typeof item !== "object" || item === null || Array.isArray(item)) continue;
    const id = (item as { id?: unknown }).id;
    if (typeof id === "string") ids.add(id);
  }
  return ids;
}
