import { expect, test } from "bun:test";

import { fetchVerifiedAsset, verifyDeliveredAsset } from "./delivered-asset.ts";

test("accepts a GLB only when bytes match its delivery hash and length", async () => {
  const bytes = new TextEncoder().encode("reframe-delivery").buffer;
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const sha256 = [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");

  await expect(
    verifyDeliveredAsset(
      {
        assetID: "ikea-us-40541421-d74d34f0a861",
        derivative: "glb",
        sha256,
        byteLength: bytes.byteLength,
      },
      bytes,
    ),
  ).resolves.toEqual(bytes);
});

test("rejects an untrusted delivery location before issuing a network request", async () => {
  await expect(
    fetchVerifiedAsset({
      assetID: "ikea-us-40541421-d74d34f0a861",
      derivative: "glb",
      sha256: "a".repeat(64),
      byteLength: 1,
      url: "not-a-url",
    }),
  ).rejects.toMatchObject({ code: "invalid_descriptor" });
});
