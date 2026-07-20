import { expect, test } from "bun:test";

import { evaluateReplacementCover } from "../src/index.ts";

test("accepts opaque asset coverage without requiring a reveal", () => {
  const result = evaluateReplacementCover([
    { targetPixels: 1_000, opaqueCoveredPixels: 990, compositeCoveredPixels: 990, largestUncoveredComponentPixels: 5 },
    { targetPixels: 1_000, opaqueCoveredPixels: 985, compositeCoveredPixels: 985, largestUncoveredComponentPixels: 8 },
    { targetPixels: 1_000, opaqueCoveredPixels: 995, compositeCoveredPixels: 995, largestUncoveredComponentPixels: 3 },
    { targetPixels: 1_000, opaqueCoveredPixels: 980, compositeCoveredPixels: 980, largestUncoveredComponentPixels: 10 },
    { targetPixels: 1_000, opaqueCoveredPixels: 990, compositeCoveredPixels: 990, largestUncoveredComponentPixels: 5 },
    { targetPixels: 1_000, opaqueCoveredPixels: 985, compositeCoveredPixels: 985, largestUncoveredComponentPixels: 8 },
    { targetPixels: 1_000, opaqueCoveredPixels: 995, compositeCoveredPixels: 995, largestUncoveredComponentPixels: 3 },
    { targetPixels: 1_000, opaqueCoveredPixels: 980, compositeCoveredPixels: 980, largestUncoveredComponentPixels: 10 },
  ], false);

  expect(result.decision).toBe("asset_only");
  expect(result.requiresReveal).toBeFalse();
});

test("accepts a thin asset only when a ready reveal closes the original silhouette", () => {
  const views = Array.from({ length: 8 }, () => ({
    targetPixels: 1_000,
    opaqueCoveredPixels: 700,
    compositeCoveredPixels: 998,
    largestUncoveredComponentPixels: 2,
  }));

  expect(evaluateReplacementCover(views, false).decision).toBe("rejected");
  const result = evaluateReplacementCover(views, true);
  expect(result.decision).toBe("composite");
  expect(result.requiresReveal).toBeTrue();
});
