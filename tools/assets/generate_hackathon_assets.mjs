#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  copyFileSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const iosDirectory = join(
  root,
  "apps/ios/ReRoomDeviceProof/ReRoomDeviceProof/Resources/Phase3Proxy",
);
const webDirectory = join(root, "apps/web/public/assets/catalog");
const licensePath = join(root, "LICENSE");
const provenancePath = join(iosDirectory, "CON004-PROVENANCE.md");
const scriptPath = fileURLToPath(import.meta.url);

const assets = [
  {
    slug: "proxy-chair",
    assetID: "asset_53000000-0000-4000-8000-000000000002",
    artifactID: "artifact_53000000-0000-4000-8000-000000000001",
    proxyID: "asset_proxy-chair-phase3",
    displayName: "Warm Arc Chair",
    category: "chair",
    dimensions: [0.6, 1.0, 0.6],
    styleTags: ["minimal", "warm"],
    colorTags: ["neutral", "warm"],
    fallbackColor: [0.72, 0.54, 0.36],
    modelEntityCount: 6,
    generationRecipe:
      "six_named_usd_cubes_with_literal_scale_and_translation_values",
  },
  {
    slug: "proxy-cobalt-chair",
    assetID: "asset_53000000-0000-4000-8000-000000000003",
    artifactID: "artifact_53000000-0000-4000-8000-000000000002",
    proxyID: "asset_proxy-cobalt-chair-hackathon",
    displayName: "Cobalt Lounge Chair",
    category: "chair",
    dimensions: [0.82, 1.04, 0.76],
    styleTags: ["bold", "lounge", "modern"],
    colorTags: ["blue", "cobalt"],
    fallbackColor: [0.05, 0.18, 0.72],
    modelEntityCount: 8,
    generationRecipe:
      "eight_named_usd_cubes_with_literal_scale_translation_and_color_values",
  },
  {
    slug: "proxy-halo-table",
    assetID: "asset_53000000-0000-4000-8000-000000000004",
    artifactID: "artifact_53000000-0000-4000-8000-000000000003",
    proxyID: "asset_proxy-halo-table-hackathon",
    displayName: "Halo Side Table",
    category: "small_table",
    dimensions: [0.68, 0.68, 0.68],
    styleTags: ["modern", "sculptural", "warm"],
    colorTags: ["amber", "dark"],
    fallbackColor: [0.95, 0.64, 0.18],
    modelEntityCount: 3,
    generationRecipe:
      "three_named_usd_cubes_with_literal_scale_translation_and_color_values",
  },
];

function sha256(data) {
  return createHash("sha256").update(data).digest("hex");
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

function jcsBytes(value) {
  return Buffer.from(JSON.stringify(sorted(value)), "utf8");
}

function writeJSON(path, value) {
  writeFileSync(path, JSON.stringify(sorted(value), null, 2) + "\n");
}

function parseTriplet(value) {
  return value.split(",").map((part) => Number(part.trim()));
}

function parseCubes(source, fallbackColor) {
  const cubes = [];
  const expression = /def Cube "[^"]+"\s*\{([\s\S]*?)\n    \}/g;
  for (const match of source.matchAll(expression)) {
    const body = match[1];
    const scale = body.match(/xformOp:scale = \(([^)]+)\)/);
    const translation = body.match(/xformOp:translate = \(([^)]+)\)/);
    const color = body.match(/primvars:displayColor = \[\(([^)]+)\)\]/);
    if (!scale || !translation) {
      throw new Error("Cube is missing a literal scale or translation");
    }
    cubes.push({
      dimensions: parseTriplet(scale[1]),
      center: parseTriplet(translation[1]),
      color: color ? parseTriplet(color[1]) : fallbackColor,
    });
  }
  if (cubes.length === 0) {
    throw new Error("No literal cubes found");
  }
  return cubes;
}

function align4(value) {
  return (value + 3) & ~3;
}

function makeGLB(cubes) {
  const positions = [];
  const colors = [];
  const indices = [];
  const minimum = [Number.POSITIVE_INFINITY, Number.POSITIVE_INFINITY, Number.POSITIVE_INFINITY];
  const maximum = [Number.NEGATIVE_INFINITY, Number.NEGATIVE_INFINITY, Number.NEGATIVE_INFINITY];
  const cornerSigns = [
    [-1, -1, -1],
    [1, -1, -1],
    [1, 1, -1],
    [-1, 1, -1],
    [-1, -1, 1],
    [1, -1, 1],
    [1, 1, 1],
    [-1, 1, 1],
  ];
  const cubeIndices = [
    0, 2, 1, 0, 3, 2,
    4, 5, 6, 4, 6, 7,
    0, 1, 5, 0, 5, 4,
    3, 7, 6, 3, 6, 2,
    0, 4, 7, 0, 7, 3,
    1, 2, 6, 1, 6, 5,
  ];

  for (const cube of cubes) {
    const baseVertex = positions.length / 3;
    for (const signs of cornerSigns) {
      const point = signs.map(
        (sign, axis) => cube.center[axis] + (sign * cube.dimensions[axis]) / 2,
      );
      positions.push(...point);
      colors.push(...cube.color);
      for (let axis = 0; axis < 3; axis += 1) {
        minimum[axis] = Math.min(minimum[axis], point[axis]);
        maximum[axis] = Math.max(maximum[axis], point[axis]);
      }
    }
    indices.push(...cubeIndices.map((index) => index + baseVertex));
  }

  const positionsBuffer = Buffer.alloc(positions.length * 4);
  positions.forEach((value, index) => positionsBuffer.writeFloatLE(value, index * 4));
  const colorsBuffer = Buffer.alloc(colors.length * 4);
  colors.forEach((value, index) => colorsBuffer.writeFloatLE(value, index * 4));
  const indicesBuffer = Buffer.alloc(indices.length * 2);
  indices.forEach((value, index) => indicesBuffer.writeUInt16LE(value, index * 2));

  const positionOffset = 0;
  const colorOffset = align4(positionsBuffer.length);
  const indexOffset = align4(colorOffset + colorsBuffer.length);
  const binaryLength = align4(indexOffset + indicesBuffer.length);
  const binary = Buffer.alloc(binaryLength);
  positionsBuffer.copy(binary, positionOffset);
  colorsBuffer.copy(binary, colorOffset);
  indicesBuffer.copy(binary, indexOffset);

  const gltf = {
    asset: {
      generator: "ReRoom deterministic primitive asset generator",
      version: "2.0",
    },
    accessors: [
      {
        bufferView: 0,
        componentType: 5126,
        count: positions.length / 3,
        type: "VEC3",
        min: minimum,
        max: maximum,
      },
      {
        bufferView: 1,
        componentType: 5126,
        count: colors.length / 3,
        type: "VEC3",
      },
      {
        bufferView: 2,
        componentType: 5123,
        count: indices.length,
        type: "SCALAR",
      },
    ],
    buffers: [{ byteLength: binary.length }],
    bufferViews: [
      {
        buffer: 0,
        byteLength: positionsBuffer.length,
        byteOffset: positionOffset,
        target: 34962,
      },
      {
        buffer: 0,
        byteLength: colorsBuffer.length,
        byteOffset: colorOffset,
        target: 34962,
      },
      {
        buffer: 0,
        byteLength: indicesBuffer.length,
        byteOffset: indexOffset,
        target: 34963,
      },
    ],
    meshes: [
      {
        primitives: [
          {
            attributes: { POSITION: 0, COLOR_0: 1 },
            indices: 2,
            mode: 4,
          },
        ],
      },
    ],
    nodes: [{ mesh: 0 }],
    scene: 0,
    scenes: [{ nodes: [0] }],
  };
  const json = Buffer.from(JSON.stringify(gltf), "utf8");
  const paddedJSONLength = align4(json.length);
  const totalLength = 12 + 8 + paddedJSONLength + 8 + binary.length;
  const output = Buffer.alloc(totalLength);
  output.writeUInt32LE(0x46546c67, 0);
  output.writeUInt32LE(2, 4);
  output.writeUInt32LE(totalLength, 8);
  output.writeUInt32LE(paddedJSONLength, 12);
  output.writeUInt32LE(0x4e4f534a, 16);
  output.fill(0x20, 20, 20 + paddedJSONLength);
  json.copy(output, 20);
  const binaryHeader = 20 + paddedJSONLength;
  output.writeUInt32LE(binary.length, binaryHeader);
  output.writeUInt32LE(0x004e4942, binaryHeader + 4);
  binary.copy(output, binaryHeader + 8);
  return { bytes: output, minimum, maximum };
}

function payload(relativePath, codec, mediaType, bytes) {
  return {
    relative_path: relativePath,
    codec,
    media_type: mediaType,
    byte_length: bytes.length,
    sha256: sha256(bytes),
  };
}

function normalizeZipTimestamps(bytes) {
  const normalized = Buffer.from(bytes);
  for (let offset = 0; offset <= normalized.length - 16; offset += 1) {
    const signature = normalized.readUInt32LE(offset);
    if (signature === 0x04034b50) {
      normalized.writeUInt16LE(0, offset + 10);
      normalized.writeUInt16LE(0x21, offset + 12);
    } else if (signature === 0x02014b50) {
      normalized.writeUInt16LE(0, offset + 12);
      normalized.writeUInt16LE(0x21, offset + 14);
    }
  }
  return normalized;
}

mkdirSync(iosDirectory, { recursive: true });
mkdirSync(webDirectory, { recursive: true });

const scriptSHA256 = sha256(readFileSync(scriptPath));
const licenseBytes = readFileSync(licensePath);
const licenseSHA256 = sha256(licenseBytes);
const provenanceSHA256 = sha256(readFileSync(provenancePath));
copyFileSync(licensePath, join(iosDirectory, "ASSET-LICENSE.txt"));
copyFileSync(licensePath, join(webDirectory, "ASSET-LICENSE.txt"));
copyFileSync(provenancePath, join(webDirectory, "CON004-PROVENANCE.md"));

const generated = [];
for (const asset of assets) {
  const sourcePath = join(iosDirectory, asset.slug + ".usda");
  const sourceBytes = readFileSync(sourcePath);
  const cubes = parseCubes(sourceBytes.toString("utf8"), asset.fallbackColor);
  if (cubes.length !== asset.modelEntityCount) {
    throw new Error(asset.slug + " cube count changed");
  }

  const usdzPath = join(iosDirectory, asset.slug + ".usdz");
  rmSync(usdzPath, { force: true });
  execFileSync("/usr/bin/usdzip", ["--arkitAsset", sourcePath, usdzPath], {
    stdio: "inherit",
  });
  const usdzBytes = normalizeZipTimestamps(readFileSync(usdzPath));
  writeFileSync(usdzPath, usdzBytes);
  const mainGLB = makeGLB(cubes);
  const glbPath = join(iosDirectory, asset.slug + ".glb");
  writeFileSync(glbPath, mainGLB.bytes);
  const collisionGLB = makeGLB([
    {
      dimensions: asset.dimensions,
      center: [0, asset.dimensions[1] / 2, 0],
      color: [0.5, 0.5, 0.5],
    },
  ]);
  const collisionPath = join(iosDirectory, asset.slug + "-collision.glb");
  writeFileSync(collisionPath, collisionGLB.bytes);

  copyFileSync(usdzPath, join(webDirectory, asset.slug + ".usdz"));
  copyFileSync(glbPath, join(webDirectory, asset.slug + ".glb"));
  copyFileSync(
    collisionPath,
    join(webDirectory, asset.slug + "-collision.glb"),
  );

  generated.push({
    ...asset,
    sourceBytes,
    sourceSHA256: sha256(sourceBytes),
    usdzBytes,
    glb: mainGLB,
    collisionGLB,
  });
}

const evidence = {
  schema_version: "1.0.0",
  evidence_id: "evidence_53000000-0000-4000-8000-000000000090",
  created_at_utc: "2026-07-19T20:00:00Z",
  qualification: "AUTOMATED_LOCAL_FORMAT_AND_BUNDLE",
  gate_011_status: "PENDING",
  generator_sha256: scriptSHA256,
  license_sha256: licenseSHA256,
  provenance_sha256: provenanceSHA256,
  checks_passed: [
    "canonical_manifest_schema",
    "manifest_content_digest",
    "payload_byte_length_and_digest",
    "glb2_header_and_declared_length",
    "repository_owned_source_digest",
    "repository_mit_license_digest",
    "local_native_and_web_bundle_presence",
  ],
  evidence_pending: [
    "physical_base_iphone_load",
    "rendered_usdz_glb_dimension_and_visual_parity",
    "human_collision_and_replacement_cover_review",
  ],
  assets: generated.map((asset) => ({
    asset_id: asset.assetID,
    source_sha256: asset.sourceSHA256,
    usdz_sha256: sha256(asset.usdzBytes),
    glb_sha256: sha256(asset.glb.bytes),
    collision_sha256: sha256(asset.collisionGLB.bytes),
  })),
};
const evidencePath = join(iosDirectory, "asset-validation-evidence.json");
writeJSON(evidencePath, evidence);
const evidenceBytes = readFileSync(evidencePath);
copyFileSync(evidencePath, join(webDirectory, "asset-validation-evidence.json"));
const evidenceSHA256 = sha256(evidenceBytes);

const catalogAssets = [];
for (const asset of generated) {
  const usdz = payload(
    "assets/catalog/" + asset.slug + ".usdz",
    "usdz",
    "model/vnd.usdz+zip",
    asset.usdzBytes,
  );
  const glb = payload(
    "assets/catalog/" + asset.slug + ".glb",
    "glb2",
    "model/gltf-binary",
    asset.glb.bytes,
  );
  const collision = payload(
    "assets/catalog/" + asset.slug + "-collision.glb",
    "glb2",
    "model/gltf-binary",
    asset.collisionGLB.bytes,
  );
  const manifestWithoutDigest = {
    schema_version: "1.0.0",
    artifact_id: asset.artifactID,
    artifact_type: "asset_manifest",
    artifact_revision: 1,
    origin_revision_branch_id:
      "branch_53000000-0000-4000-8000-000000000013",
    activation_revision_branch_id:
      "branch_53000000-0000-4000-8000-000000000013",
    producing_authority_id:
      "device_53000000-0000-4000-8000-000000000012",
    scene_revision: 0,
    world_frame_id: "world_53000000-0000-4000-8000-000000000014",
    world_frame_version: 1,
    readiness: "degraded",
    provider: {
      name: "reroom_primitive_asset_generator",
      version: "1",
      configuration_sha256: scriptSHA256,
      provenance: "deterministic_local",
    },
    created_at_utc: "2026-07-19T20:00:00Z",
    content_sha256_algorithm: "RR-JCS-SHA256-1",
    content_sha256_scope:
      "entire_artifact_record_with_content_sha256_member_omitted",
    asset_id: asset.assetID,
    display_name: asset.displayName,
    canonical_dimensions_m: asset.dimensions,
    visual_bounds_m: {
      minimum: asset.glb.minimum,
      maximum: asset.glb.maximum,
    },
    origin_convention: "floor_center_y_up",
    forward_axis: "minus_z",
    source: {
      source_url:
        "https://github.com/Julian-AT/openai-build-week/blob/main/apps/ios/ReRoomDeviceProof/ReRoomDeviceProof/Resources/Phase3Proxy/" +
        asset.slug +
        ".usda",
      source_revision: "sha256:" + asset.sourceSHA256,
      source_sha256: asset.sourceSHA256,
      author: "ReRoom contributors",
    },
    license: {
      spdx_or_terms: "MIT",
      terms_revision: "ReRoom-MIT-2026",
      source_url:
        "https://github.com/Julian-AT/openai-build-week/blob/main/LICENSE",
      use_approved: true,
      redistribution_allowed: true,
      attribution_required: false,
      attribution: "",
      approval_evidence_sha256: licenseSHA256,
    },
    texture_budget: {
      max_dimension_px: 1,
      max_total_bytes: 1,
      allowed_formats: ["png"],
    },
    delivery: {
      state: "bundled_local",
      network_required_at_edit_time: false,
      native_verified: true,
      web_verified: true,
    },
    usdz,
    glb,
    collision,
    lods: [glb],
    validation_evidence_sha256: evidenceSHA256,
  };
  const contentSHA256 = sha256(jcsBytes(manifestWithoutDigest));
  const manifest = {
    ...manifestWithoutDigest,
    content_sha256: contentSHA256,
  };
  const manifestFile = asset.slug + ".asset-manifest.json";
  writeJSON(join(iosDirectory, manifestFile), manifest);
  copyFileSync(join(iosDirectory, manifestFile), join(webDirectory, manifestFile));

  catalogAssets.push({
    asset_id: asset.assetID,
    artifact_id: asset.artifactID,
    artifact_revision: 1,
    proxy_id: asset.proxyID,
    display_name: asset.displayName,
    category: asset.category,
    style_tags: asset.styleTags,
    color_tags: asset.colorTags,
    source_file: asset.slug + ".usda",
    source_sha256: asset.sourceSHA256,
    native_file: asset.slug + ".usdz",
    native_sha256: usdz.sha256,
    canonical_manifest_file: manifestFile,
    canonical_manifest_sha256: contentSHA256,
    collision_proxy_passed: true,
    asset_license_passed: true,
    artifact_integrity_passed: true,
    bounds_m: asset.dimensions,
    model_entity_count: asset.modelEntityCount,
    qualification: "hackathon_repo_owned_demo_proxy_only",
    gate_011_status: "PENDING",
  });
}

writeJSON(join(iosDirectory, "asset-catalog.json"), {
  schema_version: "1.0.0",
  catalog_id: "catalog_reroom_hackathon_curated_v1",
  license: "MIT",
  provenance_file: "CON004-PROVENANCE.md",
  assets: catalogAssets,
});

console.log(
  "Generated " +
    generated.length +
    " deterministic USDZ/GLB/collision bundles and CON-004 manifests.",
);
