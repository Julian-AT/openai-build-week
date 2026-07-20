import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "bun:test";

import { CURATED_CATALOG } from "../src/catalog.ts";
import { PROPOSAL_MODEL } from "../src/proposal-service.ts";
import { INGRESS_SOURCES } from "../src/protocol.ts";

test("CON-006 is closed and aligned with the gateway-owned model and catalog", async () => {
  const schemaURL = new URL("../../../docs/contracts/semantic-proposal.schema.json", import.meta.url);
  const schema = JSON.parse(await readFile(schemaURL, "utf8")) as Record<string, unknown>;

  assert.equal(schema.$schema, "https://json-schema.org/draft/2020-12/schema");
  assert.equal(schema.$id, "urn:reroom:schema:semantic-proposal:1");
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.required, [
    "schema_version",
    "envelope_id",
    "created_at_utc",
    "request_context",
    "ingress_source",
    "semantic_model",
    "status",
    "intent",
    "explanation",
    "clarification",
  ]);

  const properties = schema.properties as Record<string, Record<string, unknown>>;
  assert.deepEqual(properties.ingress_source?.enum, INGRESS_SOURCES);
  const definitions = schema.$defs as Record<string, Record<string, unknown>>;
  const modelProperties = definitions.semanticModel?.properties as Record<
    string,
    Record<string, unknown>
  >;
  assert.equal(modelProperties.model?.const, PROPOSAL_MODEL);
  const catalogProperties = definitions.catalogArguments?.properties as Record<
    string,
    Record<string, unknown>
  >;
  assert.deepEqual(
    catalogProperties.asset_id?.enum,
    CURATED_CATALOG.map((asset) => asset.asset_id),
  );
});
