import { test } from "bun:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { createFilesystemAssetDeliveryService } from "../src/asset-delivery-service.ts";
import { createDurableRoomSessionStore } from "../src/durable-session-store.ts";
import { createGatewayApp } from "../src/server.ts";

test("asset delivery returns only a verified prepared USDZ", async () => {
  const root = await mkdtemp(join(tmpdir(), "reframe-asset-delivery-"));
  try {
    const assetID = "ikea-us-40541421-d74d34f0a861";
    const bytes = new Uint8Array([0x50, 0x4b, 0x03, 0x04, 0x00]);
    const sha256 = createHash("sha256").update(bytes).digest("hex");
    const derivationID = "a".repeat(64);
    const assetDirectory = join(root, "catalog", "prepared", assetID);
    const derivativeDirectory = join(root, "catalog", "derived", "sha256");
    await mkdir(assetDirectory, { recursive: true });
    await mkdir(derivativeDirectory, { recursive: true });
    await writeFile(join(derivativeDirectory, sha256), bytes);
    await writeFile(
      join(assetDirectory, `${derivationID}.json`),
      JSON.stringify({
        derivationID,
        source: { storageKey: `sha256/${"b".repeat(64)}`, sha256: "b".repeat(64), byteLength: 1 },
        processor: { configurationDigest: "c".repeat(64), revision: "test" },
        preview: {
          storageKey: `sha256/${"d".repeat(64)}`,
          sha256: "d".repeat(64),
          byteLength: 1,
          validated: true,
          mediaType: "image/png",
          width: 1,
          height: 1,
        },
        asset: {
          assetID,
          authorization: { status: "authorized", reference: "operator-test" },
          category: "side_table",
          dimensionsM: { width: 1, height: 1, depth: 1 },
          supportType: "floor",
          normalization: { units: "meters", origin: "floor-contact-center", forwardAxis: "+z" },
          derivatives: {
            glb: {
              storageKey: `sha256/${"e".repeat(64)}`,
              sha256: "e".repeat(64),
              byteLength: 1,
              validated: true,
            },
            usdz: {
              storageKey: `sha256/${sha256}`,
              sha256,
              byteLength: bytes.byteLength,
              validated: true,
            },
            collision: {
              storageKey: `sha256/${"f".repeat(64)}`,
              sha256: "f".repeat(64),
              byteLength: 1,
              validated: true,
              representation: "aabb",
            },
          },
          cacheProfiles: ["ios-primary"],
        },
      }),
    );

    const service = createFilesystemAssetDeliveryService({
      dataDirectory: root,
      cacheProfile: "ios-primary",
    });
    const delivery = await service.deliver(assetID);
    assert.equal(delivery.assetID, assetID);
    assert.equal(delivery.sha256, sha256);
    assert.deepEqual([...delivery.bytes], [...bytes]);

    await writeFile(join(derivativeDirectory, sha256), new Uint8Array([0x00]));
    await assert.rejects(service.deliver(assetID), /asset_hash_mismatch/u);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("asset delivery route requires a room credential and exposes immutable hash facts", async () => {
  const root = await mkdtemp(join(tmpdir(), "reframe-asset-route-"));
  const store = await createDurableRoomSessionStore({
    dataDirectory: root,
    signingSecret: "route-test-signing-secret-0123456789abcdef",
  });
  try {
    const created = await store.createSession({
      sessionID: "room_asset_route",
      expiresAtMilliseconds: Date.now() + 60_000,
      allowedPaths: ["scene"],
    });
    const bytes = new Uint8Array([0x50, 0x4b, 0x03, 0x04]);
    const sha256 = createHash("sha256").update(bytes).digest("hex");
    const app = createGatewayApp({
      gatewayToken: "gateway-token",
      durableSessionStore: store,
      assetDeliveryService: {
        deliver: async () => ({
          assetID: "ikea-us-40541421-d74d34f0a861",
          derivative: "usdz",
          sha256,
          byteLength: bytes.byteLength,
          bytes,
        }),
      },
    });
    const response = await app.request("/v1/assets/ikea-us-40541421-d74d34f0a861/usdz", {
      headers: { authorization: `Bearer ${created.credential}` },
    });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("x-content-sha256"), sha256);
    assert.deepEqual([...new Uint8Array(await response.arrayBuffer())], [...bytes]);
    const unauthorized = await app.request("/v1/assets/ikea-us-40541421-d74d34f0a861/usdz", {
      headers: { authorization: "Bearer wrong-room" },
    });
    assert.equal(unauthorized.status, 401);
  } finally {
    await store.close();
    await rm(root, { recursive: true, force: true });
  }
});
