import { createHash } from "node:crypto";

import type { AgentTurnRequest, AgentTurnService } from "./agent-turn.ts";

/**
 * A small idempotency cache for mobile retries. A turn is expensive because it
 * may perform several provider calls; reconnects and repeated taps must not
 * start a second orchestration for the same client turn. The key includes all
 * client-controlled scene/pointer context and the room credential digest, so
 * a cached preview can never cross a room boundary.
 *
 * Completed entries are still only a transport optimisation: callers must use
 * the preview's authoritative base revision and CAS confirmation. A scene
 * change therefore cannot be committed through a stale cached preview.
 */
export interface AgentTurnCacheOptions {
  readonly maximumEntries?: number;
  readonly ttlMilliseconds?: number;
  readonly now?: () => number;
}

interface CacheEntry {
  readonly key: string;
  readonly expiresAt: number;
  readonly promise: Promise<unknown>;
}

const DEFAULT_MAXIMUM_ENTRIES = 64;
const DEFAULT_TTL_MILLISECONDS = 30_000;

export function createCachedAgentTurnService(
  inner: AgentTurnService,
  options: AgentTurnCacheOptions = {},
): AgentTurnService {
  const maximumEntries = options.maximumEntries ?? DEFAULT_MAXIMUM_ENTRIES;
  const ttlMilliseconds = options.ttlMilliseconds ?? DEFAULT_TTL_MILLISECONDS;
  const now = options.now ?? Date.now;
  if (
    !Number.isSafeInteger(maximumEntries) ||
    maximumEntries < 1 ||
    maximumEntries > 256 ||
    !Number.isSafeInteger(ttlMilliseconds) ||
    ttlMilliseconds < 1_000 ||
    ttlMilliseconds > 300_000
  ) {
    throw new TypeError("invalid_agent_turn_cache_options");
  }

  const entries = new Map<string, CacheEntry>();
  return {
    async submit(credential, turn, signal) {
      signal.throwIfAborted();
      const key = cacheKey(credential, turn);
      const timestamp = now();
      const existing = entries.get(key);
      if (existing !== undefined && existing.expiresAt > timestamp) {
        // Keep cancellation local to this request. The underlying operation is
        // owned by the first request and remains deduplicated for reconnects.
        return await withAbort(existing.promise, signal);
      }
      if (existing !== undefined) entries.delete(key);

      const promise = inner.submit(credential, turn, signal);
      const entry: CacheEntry = {
        key,
        expiresAt: timestamp + ttlMilliseconds,
        promise,
      };
      entries.set(key, entry);
      evictOldest(entries, maximumEntries);
      try {
        return await promise;
      } catch (error) {
        // Failures are never cached: a transient provider outage must be
        // retryable immediately and should not poison the mobile session.
        if (entries.get(key) === entry) entries.delete(key);
        throw error;
      }
    },
  };
}

function cacheKey(credential: string, turn: AgentTurnRequest): string {
  return createHash("sha256")
    .update(credential, "utf8")
    .update("\0", "utf8")
    .update(JSON.stringify(turn), "utf8")
    .digest("hex");
}

function evictOldest(entries: Map<string, CacheEntry>, maximumEntries: number): void {
  while (entries.size > maximumEntries) {
    const oldest = entries.keys().next().value;
    if (typeof oldest !== "string") return;
    entries.delete(oldest);
  }
}

async function withAbort<T>(promise: Promise<T>, signal: AbortSignal): Promise<T> {
  if (signal.aborted) throw signal.reason;
  return await new Promise<T>((resolve, reject) => {
    const cleanup = () => signal.removeEventListener("abort", abort);
    const abort = () => {
      cleanup();
      reject(signal.reason);
    };
    signal.addEventListener("abort", abort, { once: true });
    promise.then(
      (value) => {
        cleanup();
        resolve(value);
      },
      (error) => {
        cleanup();
        reject(error);
      },
    );
  });
}
