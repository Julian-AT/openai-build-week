export type GpuWorkKind =
  | "target_semantics"
  | "live_depth"
  | "tsdf_extraction"
  | "reveal_generation"
  | "dense_background"
  | "naming_contact_sheet"
  | "b0_batch"
  | "b1_polish";

export type GpuWorkResult =
  | { readonly status: "completed" }
  | { readonly status: "cancelled" }
  | { readonly status: "failed" }
  | { readonly status: "dropped"; readonly reason: "superseded" | "queue_full" | "mode_a_active" };

export interface GpuWorkRequest {
  readonly id: string;
  readonly kind: GpuWorkKind;
  readonly run: (signal: AbortSignal) => Promise<void>;
  readonly signal?: AbortSignal;
}

export interface GpuLaneCoordinatorOptions {
  readonly modeAActive?: () => boolean;
}

interface QueuedWork {
  readonly request: GpuWorkRequest;
  readonly controller: AbortController;
  readonly sequence: number;
  readonly settle: (result: GpuWorkResult) => void;
  readonly removeAbortListener: () => void;
}

const PRIORITY: Readonly<Record<GpuWorkKind, number>> = {
  target_semantics: 1,
  live_depth: 2,
  tsdf_extraction: 3,
  reveal_generation: 4,
  dense_background: 5,
  naming_contact_sheet: 6,
  b0_batch: 7,
  b1_polish: 8,
};
const MAX_PENDING_WORK = 7;

/**
 * The gateway owns this single-process admission coordinator. It intentionally
 * serializes GPU-heavy starts on an 8 GB device; a running kernel is allowed to
 * finish, then the highest priority pending job proceeds. Live depth keeps one
 * newest pending frame instead of becoming a latency backlog.
 */
export class GpuLaneCoordinator {
  readonly #modeAActive: () => boolean;
  readonly #pending: QueuedWork[] = [];
  #active: QueuedWork | undefined;
  #nextSequence = 0;
  #pumpScheduled = false;

  constructor(options: GpuLaneCoordinatorOptions = {}) {
    this.#modeAActive = options.modeAActive ?? (() => false);
  }

  submit(request: GpuWorkRequest): Promise<GpuWorkResult> {
    if (!isValidID(request.id)) throw new Error("invalid_gpu_work_id");
    if (request.kind === "b1_polish" && this.#modeAActive()) {
      return Promise.resolve({ status: "dropped", reason: "mode_a_active" });
    }
    if (request.signal?.aborted) return Promise.resolve({ status: "cancelled" });

    return new Promise<GpuWorkResult>((settle) => {
      const controller = new AbortController();
      let work: QueuedWork;
      const abort = () => this.#cancel(work);
      const removeAbortListener = () => request.signal?.removeEventListener("abort", abort);
      work = {
        request,
        controller,
        sequence: this.#nextSequence++,
        settle,
        removeAbortListener,
      };
      request.signal?.addEventListener("abort", abort, { once: true });

      this.#replaceStaleLiveDepth(work);
      if (this.#pending.length >= MAX_PENDING_WORK) {
        work.removeAbortListener();
        settle({ status: "dropped", reason: "queue_full" });
        return;
      }
      this.#pending.push(work);
      this.#schedulePump();
    });
  }

  #replaceStaleLiveDepth(incoming: QueuedWork): void {
    if (incoming.request.kind !== "live_depth") return;
    const staleIndex = this.#pending.findIndex((work) => work.request.kind === "live_depth");
    if (staleIndex < 0) return;
    const [stale] = this.#pending.splice(staleIndex, 1);
    if (stale === undefined) throw new Error("missing_pending_gpu_work");
    stale.removeAbortListener();
    stale.controller.abort();
    stale.settle({ status: "dropped", reason: "superseded" });
  }

  #cancel(work: QueuedWork): void {
    const pendingIndex = this.#pending.indexOf(work);
    if (pendingIndex >= 0) {
      this.#pending.splice(pendingIndex, 1);
      work.removeAbortListener();
      work.controller.abort();
      work.settle({ status: "cancelled" });
      return;
    }
    if (this.#active === work) work.controller.abort();
  }

  #schedulePump(): void {
    if (this.#pumpScheduled) return;
    this.#pumpScheduled = true;
    queueMicrotask(() => {
      this.#pumpScheduled = false;
      void this.#pump();
    });
  }

  async #pump(): Promise<void> {
    if (this.#active !== undefined) return;
    const next = this.#takeHighestPriority();
    if (next === undefined) return;
    if (next.controller.signal.aborted) {
      next.removeAbortListener();
      next.settle({ status: "cancelled" });
      this.#schedulePump();
      return;
    }
    this.#active = next;
    try {
      await next.request.run(next.controller.signal);
      next.settle(
        next.controller.signal.aborted ? { status: "cancelled" } : { status: "completed" },
      );
    } catch {
      next.settle(next.controller.signal.aborted ? { status: "cancelled" } : { status: "failed" });
    } finally {
      next.removeAbortListener();
      this.#active = undefined;
      this.#schedulePump();
    }
  }

  #takeHighestPriority(): QueuedWork | undefined {
    if (this.#pending.length === 0) return undefined;
    let selectedIndex = 0;
    for (let index = 1; index < this.#pending.length; index += 1) {
      const candidate = this.#pending[index];
      const selected = this.#pending[selectedIndex];
      if (candidate === undefined || selected === undefined) continue;
      if (
        PRIORITY[candidate.request.kind] < PRIORITY[selected.request.kind] ||
        (PRIORITY[candidate.request.kind] === PRIORITY[selected.request.kind] &&
          candidate.sequence < selected.sequence)
      ) {
        selectedIndex = index;
      }
    }
    return this.#pending.splice(selectedIndex, 1)[0];
  }
}

function isValidID(value: string): boolean {
  return /^[a-z][a-z0-9_-]{2,127}$/u.test(value);
}
