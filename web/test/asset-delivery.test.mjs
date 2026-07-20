import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

const REPO_ROOT = path.resolve(import.meta.dirname, "../..");
const ASSET_ROOT = path.join(REPO_ROOT, "web/public/assets/catalog");
const IOS_ROOT = path.join(
  REPO_ROOT,
  "ios/ReRoomDeviceProof/ReRoomDeviceProof/Resources/Phase3Proxy",
);
const CATALOG_PATH = path.join(IOS_ROOT, "asset-catalog.json");
const MANIFEST_KEYS = [
  "activation_revision_branch_id",
  "artifact_id",
  "artifact_revision",
  "artifact_type",
  "asset_id",
  "canonical_dimensions_m",
  "collision",
  "content_sha256",
  "content_sha256_algorithm",
  "content_sha256_scope",
  "created_at_utc",
  "delivery",
  "display_name",
  "forward_axis",
  "glb",
  "license",
  "lods",
  "origin_convention",
  "origin_revision_branch_id",
  "producing_authority_id",
  "provider",
  "readiness",
  "scene_revision",
  "schema_version",
  "source",
  "texture_budget",
  "usdz",
  "validation_evidence_sha256",
  "visual_bounds_m",
  "world_frame_id",
  "world_frame_version",
].sort();

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function sorted(value) {
  if (Array.isArray(value)) {
    return value.map(sorted);
  }
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, sorted(value[key])]),
    );
  }
  return value;
}

async function readJSON(filePath) {
  return JSON.parse(await readFile(filePath, "utf8"));
}

function assertGLB(bytes) {
  assert.ok(bytes.length >= 20);
  assert.equal(bytes.readUInt32LE(0), 0x46546c67);
  assert.equal(bytes.readUInt32LE(4), 2);
  assert.equal(bytes.readUInt32LE(8), bytes.length);
}

async function assertPayload(payload) {
  const relativePath = payload.relative_path.replace(/^assets\/catalog\//, "");
  const bytes = await readFile(path.join(ASSET_ROOT, relativePath));
  const nativeBytes = await readFile(path.join(IOS_ROOT, relativePath));
  assert.deepEqual(bytes, nativeBytes);
  assert.equal(bytes.length, payload.byte_length);
  assert.equal(sha256(bytes), payload.sha256);
  if (payload.codec === "glb2") {
    assertGLB(bytes);
  }
  if (payload.codec === "usdz") {
    assert.deepEqual([...bytes.subarray(0, 4)], [0x50, 0x4b, 0x03, 0x04]);
  }
}

test("web catalog ships digest-bound CON-004 derivatives without edit-time network", async () => {
  const catalog = await readJSON(CATALOG_PATH);
  const licenseBytes = await readFile(path.join(ASSET_ROOT, "ASSET-LICENSE.txt"));
  const evidenceBytes = await readFile(
    path.join(ASSET_ROOT, "asset-validation-evidence.json"),
  );
  const provenanceBytes = await readFile(
    path.join(ASSET_ROOT, "CON004-PROVENANCE.md"),
  );
  assert.deepEqual(
    licenseBytes,
    await readFile(path.join(IOS_ROOT, "ASSET-LICENSE.txt")),
  );
  assert.deepEqual(
    evidenceBytes,
    await readFile(path.join(IOS_ROOT, "asset-validation-evidence.json")),
  );
  assert.deepEqual(
    provenanceBytes,
    await readFile(path.join(IOS_ROOT, "CON004-PROVENANCE.md")),
  );
  const evidence = JSON.parse(evidenceBytes.toString("utf8"));
  assert.equal(evidence.qualification, "AUTOMATED_LOCAL_FORMAT_AND_BUNDLE");
  assert.equal(evidence.gate_011_status, "PENDING");
  assert.equal(evidence.license_sha256, sha256(licenseBytes));
  assert.equal(evidence.provenance_sha256, sha256(provenanceBytes));
  assert.equal(catalog.assets.length, 3);

  for (const asset of catalog.assets) {
    const manifestPath = path.join(ASSET_ROOT, asset.canonical_manifest_file);
    const manifestBytes = await readFile(manifestPath);
    assert.deepEqual(
      manifestBytes,
      await readFile(path.join(IOS_ROOT, asset.canonical_manifest_file)),
    );
    const manifest = JSON.parse(manifestBytes.toString("utf8"));
    assert.deepEqual(Object.keys(manifest).sort(), MANIFEST_KEYS);
    const { content_sha256: declaredDigest, ...unsigned } = manifest;
    assert.equal(
      sha256(Buffer.from(JSON.stringify(sorted(unsigned)), "utf8")),
      declaredDigest,
    );
    assert.equal(declaredDigest, asset.canonical_manifest_sha256);
    assert.equal(manifest.asset_id, asset.asset_id);
    assert.equal(manifest.artifact_id, asset.artifact_id);
    assert.equal(manifest.artifact_type, "asset_manifest");
    assert.match(manifest.asset_id, /^asset_[0-9a-f-]{36}$/);
    assert.equal(manifest.content_sha256_algorithm, "RR-JCS-SHA256-1");
    assert.equal(
      manifest.content_sha256_scope,
      "entire_artifact_record_with_content_sha256_member_omitted",
    );
    assert.equal(manifest.readiness, "degraded");
    assert.equal(manifest.origin_convention, "floor_center_y_up");
    assert.equal(manifest.forward_axis, "minus_z");
    assert.equal(manifest.canonical_dimensions_m.length, 3);
    assert.ok(manifest.canonical_dimensions_m.every((value) => value > 0));
    assert.deepEqual(manifest.delivery, {
      state: "bundled_local",
      network_required_at_edit_time: false,
      native_verified: true,
      web_verified: true,
    });
    assert.equal(manifest.license.spdx_or_terms, "MIT");
    assert.equal(manifest.license.use_approved, true);
    assert.equal(manifest.license.redistribution_allowed, true);
    assert.equal(
      manifest.license.approval_evidence_sha256,
      sha256(licenseBytes),
    );
    assert.equal(manifest.validation_evidence_sha256, sha256(evidenceBytes));
    assert.equal(manifest.provider.configuration_sha256, evidence.generator_sha256);

    await assertPayload(manifest.usdz);
    await assertPayload(manifest.glb);
    await assertPayload(manifest.collision);
    for (const lod of manifest.lods) {
      await assertPayload(lod);
    }
  }
});
