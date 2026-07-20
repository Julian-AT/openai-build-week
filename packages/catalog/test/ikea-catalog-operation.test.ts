import { test } from "bun:test";
import assert from "node:assert/strict";

import { runIkeaCatalogOperationFromEnvironment } from "../src/index.ts";

test("the full IKEA operation requires an explicit persistent frontier configuration before source I/O", async () => {
  await assert.rejects(
    runIkeaCatalogOperationFromEnvironment({}),
    /missing_reframe_catalog_profile/,
  );
  await assert.rejects(
    runIkeaCatalogOperationFromEnvironment({ REFRAME_CATALOG_PROFILE: "full" }),
    /missing_reframe_data_dir/,
  );
  await assert.rejects(
    runIkeaCatalogOperationFromEnvironment({
      REFRAME_CATALOG_PROFILE: "full",
      REFRAME_DATA_DIR: "/tmp/reframe-catalog",
    }),
    /missing_reframe_catalog_frontier_revision/,
  );
});
