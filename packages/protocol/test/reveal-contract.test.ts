import { expect, test } from "bun:test";

import schema from "../schemas/edit-artifacts.schema.json";
import sceneSchema from "../schemas/scene-state.schema.json";
import transactionSchema from "../schemas/transaction.schema.json";

test("reveal readiness is automatic and layers carry render and texel provenance contracts", () => {
  const definitions = schema.$defs as Record<string, any>;
  const quality = definitions.revealBundle.allOf[1].properties.quality;
  const qualityRequired = quality.required as string[];

  expect(qualityRequired).not.toContain("fixture_id");
  expect(qualityRequired).not.toContain("evidence_record_sha256");
  expect(qualityRequired).not.toContain("human_visual_votes_pass");
  expect(qualityRequired).not.toContain("human_visual_votes_total");
  expect(qualityRequired).toContain("metric_version");
  expect(qualityRequired).toContain("automated_decision");

  const layer = definitions.revealLayer;
  expect(layer.required).toContain("provenance_map");
  expect(layer.required).toContain("rendering");
  expect(layer.properties.rendering.required).toEqual([
    "color_space",
    "alpha_mode",
    "edge_feather_m",
  ]);

  const bundle = definitions.revealBundle.allOf[1];
  expect(bundle.required).toContain("outside_envelope_behavior");
  expect(bundle.properties.outside_envelope_behavior.const).toBe("show_unmodified_camera");
});

test("canonical scene and transaction revisions are gateway-owned", () => {
  for (const candidate of [sceneSchema, transactionSchema]) {
    const authority = (candidate.$defs as Record<string, any>).revisionAuthority;
    expect(authority.oneOf).toBeUndefined();
    expect(authority.properties.kind.const).toBe("gateway");
    expect(authority.properties.authority_id.pattern).toStartWith("^gateway_");
  }
});
