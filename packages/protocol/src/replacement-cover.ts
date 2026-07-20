export interface ReplacementViewCoverage {
  targetPixels: number;
  opaqueCoveredPixels: number;
  compositeCoveredPixels: number;
  largestUncoveredComponentPixels: number;
}

export interface ReplacementCoverResult {
  decision: "asset_only" | "composite" | "rejected";
  requiresReveal: boolean;
  assetCoverageMedian: number;
  assetCoverageP10: number;
  compositeCoverageMedian: number;
  compositeCoverageP10: number;
  largestUncoveredComponentFraction: number;
}

export class ReplacementCoverInputError extends Error {
  constructor() {
    super("invalid_replacement_cover_input");
    this.name = "ReplacementCoverInputError";
  }
}

export function evaluateReplacementCover(
  views: readonly ReplacementViewCoverage[],
  revealReady: boolean,
): ReplacementCoverResult {
  if (views.length < 8) throw new ReplacementCoverInputError();
  const assetCoverage: number[] = [];
  const compositeCoverage: number[] = [];
  let largestUncoveredComponentFraction = 0;
  for (const view of views) {
    assertView(view);
    assetCoverage.push(view.opaqueCoveredPixels / view.targetPixels);
    compositeCoverage.push(view.compositeCoveredPixels / view.targetPixels);
    largestUncoveredComponentFraction = Math.max(
      largestUncoveredComponentFraction,
      view.largestUncoveredComponentPixels / view.targetPixels,
    );
  }
  const assetCoverageMedian = conservativeQuantile(assetCoverage, 0.5);
  const assetCoverageP10 = conservativeQuantile(assetCoverage, 0.1);
  const compositeCoverageMedian = conservativeQuantile(compositeCoverage, 0.5);
  const compositeCoverageP10 = conservativeQuantile(compositeCoverage, 0.1);
  const assetOnly = assetCoverageMedian >= 0.98 && assetCoverageP10 >= 0.95;
  const composite =
    revealReady &&
    compositeCoverageMedian >= 0.995 &&
    compositeCoverageP10 >= 0.98 &&
    largestUncoveredComponentFraction <= 0.01;
  return {
    decision: assetOnly ? "asset_only" : composite ? "composite" : "rejected",
    requiresReveal: !assetOnly,
    assetCoverageMedian,
    assetCoverageP10,
    compositeCoverageMedian,
    compositeCoverageP10,
    largestUncoveredComponentFraction,
  };
}

function assertView(view: ReplacementViewCoverage): void {
  const values = [
    view.targetPixels,
    view.opaqueCoveredPixels,
    view.compositeCoveredPixels,
    view.largestUncoveredComponentPixels,
  ];
  if (
    !values.every((value) => Number.isSafeInteger(value) && value >= 0) ||
    view.targetPixels === 0 ||
    view.opaqueCoveredPixels > view.targetPixels ||
    view.compositeCoveredPixels < view.opaqueCoveredPixels ||
    view.compositeCoveredPixels > view.targetPixels ||
    view.largestUncoveredComponentPixels > view.targetPixels - view.compositeCoveredPixels
  ) {
    throw new ReplacementCoverInputError();
  }
}

function conservativeQuantile(values: readonly number[], quantile: number): number {
  const ordered = [...values].sort((left, right) => left - right);
  return ordered[Math.floor((ordered.length - 1) * quantile)] ?? 0;
}
