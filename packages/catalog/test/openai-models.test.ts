import { test } from "bun:test";
import assert from "node:assert/strict";

import {
  CATALOG_DESCRIPTOR_MODEL,
  CATALOG_EMBEDDING_MODEL,
  SEMANTIC_VECTOR_SIZE,
} from "../src/index.ts";

test("uses the verified GPT-5.6 Sol and 1,024-dimensional embedding model contract", () => {
  assert.equal(CATALOG_DESCRIPTOR_MODEL, "gpt-5.6-sol");
  assert.equal(CATALOG_EMBEDDING_MODEL, "text-embedding-3-small");
  assert.equal(SEMANTIC_VECTOR_SIZE, 1_024);
});
