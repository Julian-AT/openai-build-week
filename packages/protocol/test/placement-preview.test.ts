import { expect, test } from "bun:test";

import { createFloorPlacementPreview } from "../src/index.ts";

test("creates a revision-neutral floor-contact-center placement transform", () => {
  expect(
    createFloorPlacementPreview({
      assetID: "ikea-us-40541421-d74d34f0a861",
      baseSceneRevision: 7,
      supportSurfaceID: "arkit_plane_floor",
      floorContactWorld: { x: 1.25, y: 0, z: -2.5 },
      yawRadians: Math.PI / 2,
    }),
  ).toEqual({
    type: "placement_preview",
    assetID: "ikea-us-40541421-d74d34f0a861",
    baseSceneRevision: 7,
    supportSurfaceID: "arkit_plane_floor",
    worldFromAsset: [0, 0, 1, 1.25, 0, 1, 0, 0, -1, 0, 0, -2.5, 0, 0, 0, 1],
  });
});
