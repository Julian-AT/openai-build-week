import { test } from "bun:test";
import assert from "node:assert/strict";

import { runIkeaSourceSmokeFromEnvironment } from "../src/source-smoke.ts";

test("the source smoke command requires an explicitly configured persistent volume and product", async () => {
  await assert.rejects(runIkeaSourceSmokeFromEnvironment({}), /missing_reframe_data_dir/);
  await assert.rejects(
    runIkeaSourceSmokeFromEnvironment({ REFRAME_DATA_DIR: "/tmp/reframe-catalog" }),
    /missing_reframe_ikea_smoke_product_url/,
  );
});
