import { expect, test } from "bun:test";

import schema from "../schemas/edit-artifacts.schema.json";
import sceneSchema from "../schemas/scene-state.schema.json";
import transactionSchema from "../schemas/transaction.schema.json";

interface SchemaNode {
  allOf: SchemaNode[];
  properties: Record<string, SchemaNode>;
  required: string[];
  const?: string;
  pattern?: string;
  oneOf?: unknown;
}

test("reveal readiness is automatic and layers carry render and texel provenance contracts", () => {
  const definitions = schema.$defs as unknown as Record<string, SchemaNode>;
  const revealBundle = definitions.revealBundle;
  if (revealBundle === undefined) throw new Error("missing reveal bundle schema");
  const quality = revealBundle.allOf[1]?.properties.quality;
  if (quality === undefined) throw new Error("missing reveal quality schema");
  const qualityRequired = quality.required;

  expect(qualityRequired).not.toContain("fixture_id");
  expect(qualityRequired).not.toContain("evidence_record_sha256");
  expect(qualityRequired).not.toContain("human_visual_votes_pass");
  expect(qualityRequired).not.toContain("human_visual_votes_total");
  expect(qualityRequired).toContain("metric_version");
  expect(qualityRequired).toContain("automated_decision");

  const layer = definitions.revealLayer;
  if (layer === undefined) throw new Error("missing reveal layer schema");
  expect(layer.required).toContain("provenance_map");
  expect(layer.required).toContain("rendering");
  expect(requireProperty(layer, "rendering").required).toEqual([
    "color_space",
    "alpha_mode",
    "edge_feather_m",
  ]);

  const bundle = revealBundle.allOf[1];
  if (bundle === undefined) throw new Error("missing reveal bundle schema");
  expect(bundle.required).toContain("outside_envelope_behavior");
  expect(requireProperty(bundle, "outside_envelope_behavior").const).toBe("show_unmodified_camera");
});

test("canonical scene and transaction revisions are gateway-owned", () => {
  for (const candidate of [sceneSchema, transactionSchema]) {
    const authority = candidate.$defs.revisionAuthority as unknown as SchemaNode;
    expect(authority.oneOf).toBeUndefined();
    expect(requireProperty(authority, "kind").const).toBe("gateway");
    expect(requireProperty(authority, "authority_id").pattern).toStartWith("^gateway_");
  }
});

function requireProperty(node: SchemaNode, name: string): SchemaNode {
  const property = node.properties[name];
  if (property === undefined) throw new Error(`missing schema property: ${name}`);
  return property;
}
