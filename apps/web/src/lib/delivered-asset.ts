import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";

export interface DeliveredAssetDescriptor {
  readonly assetID: string;
  readonly derivative: "glb" | "usdz";
  readonly sha256: string;
  readonly byteLength: number;
}

export interface RemoteDeliveredAsset extends DeliveredAssetDescriptor {
  readonly url: string;
}

export class DeliveredAssetError extends Error {
  constructor(
    readonly code:
      | "invalid_descriptor"
      | "download_failed"
      | "byte_length_mismatch"
      | "hash_mismatch",
  ) {
    super(code);
    this.name = "DeliveredAssetError";
  }
}

/**
 * Checks an immutable delivery before a renderer can parse it. URLs are only
 * transport locations; the content-addressed descriptor remains authoritative.
 */
export async function verifyDeliveredAsset(
  descriptor: DeliveredAssetDescriptor,
  bytes: ArrayBuffer,
): Promise<ArrayBuffer> {
  assertDescriptor(descriptor);
  if (bytes.byteLength !== descriptor.byteLength)
    throw new DeliveredAssetError("byte_length_mismatch");
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  if (hex(new Uint8Array(digest)) !== descriptor.sha256)
    throw new DeliveredAssetError("hash_mismatch");
  return bytes;
}

export async function fetchVerifiedAsset(
  delivery: RemoteDeliveredAsset,
  signal?: AbortSignal,
): Promise<ArrayBuffer> {
  assertDescriptor(delivery);
  const url = deliveryURL(delivery.url);
  let response: Response;
  try {
    response = await fetch(url, {
      method: "GET",
      signal,
      credentials: "include",
      cache: "no-store",
    });
  } catch {
    throw new DeliveredAssetError("download_failed");
  }
  if (!response.ok) throw new DeliveredAssetError("download_failed");
  return await verifyDeliveredAsset(delivery, await response.arrayBuffer());
}

/** Loads a verified normalized GLB using the production Three.js loader. */
export async function loadVerifiedGLB(
  delivery: RemoteDeliveredAsset & { readonly derivative: "glb" },
  signal?: AbortSignal,
) {
  const bytes = await fetchVerifiedAsset(delivery, signal);
  return await new GLTFLoader().parseAsync(bytes, new URL(".", delivery.url).href);
}

function assertDescriptor(descriptor: DeliveredAssetDescriptor): void {
  if (
    !/^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$/u.test(descriptor.assetID) ||
    descriptor.assetID.length > 128 ||
    !/^[a-f0-9]{64}$/u.test(descriptor.sha256) ||
    !Number.isSafeInteger(descriptor.byteLength) ||
    descriptor.byteLength <= 0
  ) {
    throw new DeliveredAssetError("invalid_descriptor");
  }
}

function deliveryURL(value: string): URL {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new DeliveredAssetError("invalid_descriptor");
  }
  if (
    (url.protocol !== "https:" && url.protocol !== "http:") ||
    url.username.length > 0 ||
    url.password.length > 0
  ) {
    throw new DeliveredAssetError("invalid_descriptor");
  }
  return url;
}

function hex(bytes: Uint8Array): string {
  return [...bytes].map((value) => value.toString(16).padStart(2, "0")).join("");
}
