import { test } from "bun:test";
import assert from "node:assert/strict";

import {
  runIkeaIndexedSmokeFromEnvironment,
  runIkeaPreparedSmokeFromEnvironment,
  runIkeaSourceSmokeFromEnvironment,
} from "../src/source-smoke.ts";

test("the source smoke command requires an explicitly configured persistent volume and product", async () => {
  await assert.rejects(runIkeaSourceSmokeFromEnvironment({}), /missing_reframe_data_dir/);
  await assert.rejects(
    runIkeaSourceSmokeFromEnvironment({ REFRAME_DATA_DIR: "/tmp/reframe-catalog" }),
    /missing_reframe_ikea_smoke_product_url/,
  );
});

test("the indexed smoke command rejects missing OpenAI credentials before source I/O", async () => {
  await assert.rejects(
    runIkeaIndexedSmokeFromEnvironment({
      REFRAME_DATA_DIR: "/tmp/reframe-catalog",
      REFRAME_IKEA_SMOKE_PRODUCT_URL:
        "https://www.ikea.com/us/en/p/holmerud-side-table-oak-effect-40541421/",
      REFRAME_IKEA_SMOKE_WIDTH_M: "0.8",
      REFRAME_IKEA_SMOKE_HEIGHT_M: "0.52",
      REFRAME_IKEA_SMOKE_DEPTH_M: "0.31",
      REFRAME_IKEA_SMOKE_CATEGORY: "side_table",
      REFRAME_IKEA_SMOKE_SUPPORT_TYPE: "floor",
      REFRAME_BLENDER_PATH: "/tools/blender",
      REFRAME_USDZIP_PATH: "/tools/usdzip",
      REFRAME_USDCHECKER_PATH: "/tools/usdchecker",
      REFRAME_ASSET_PROCESSOR_REVISION: "blender-5.2.0",
      QDRANT_URL: "http://127.0.0.1:6333",
      REFRAME_IKEA_SMOKE_SEARCH_QUERY: "light oak side table",
      REFRAME_IKEA_SMOKE_CACHE_PROFILE: "ios-primary",
    }),
    /missing_reframe_openai_api_key/,
  );
});

test("the prepared smoke command requires an explicit pinned processor configuration", async () => {
  await assert.rejects(
    runIkeaPreparedSmokeFromEnvironment({
      REFRAME_DATA_DIR: "/tmp/reframe-catalog",
      REFRAME_IKEA_SMOKE_PRODUCT_URL:
        "https://www.ikea.com/us/en/p/holmerud-side-table-oak-effect-40541421/",
      REFRAME_IKEA_SMOKE_WIDTH_M: "0.8",
      REFRAME_IKEA_SMOKE_HEIGHT_M: "0.52",
      REFRAME_IKEA_SMOKE_DEPTH_M: "0.31",
      REFRAME_IKEA_SMOKE_CATEGORY: "side_table",
      REFRAME_IKEA_SMOKE_SUPPORT_TYPE: "floor",
      REFRAME_BLENDER_PATH: "/tools/blender",
      REFRAME_USDZIP_PATH: "/tools/usdzip",
      REFRAME_USDCHECKER_PATH: "/tools/usdchecker",
    }),
    /missing_reframe_asset_processor_revision/,
  );
});
