import type {
  AcquisitionDownloadRequest,
  AcquisitionDownloadResponse,
  AcquisitionTransport,
} from "./acquisition.ts";

const IKEA_ASSET_ORIGIN = "https://web-api.ikea.com";

type IkeaFetch = (
  input: Parameters<typeof globalThis.fetch>[0],
  init?: Parameters<typeof globalThis.fetch>[1],
) => ReturnType<typeof globalThis.fetch>;

export interface IkeaGLBFetchTransportOptions {
  fetch?: IkeaFetch;
}

/** Bounded HTTPS transport for raw IKEA GLBs; parsing remains in quarantine. */
export function createIkeaGLBFetchTransport(
  options: IkeaGLBFetchTransportOptions = {},
): AcquisitionTransport {
  const fetchImplementation = options.fetch ?? globalThis.fetch;
  return {
    download: async (request) => downloadGLB(fetchImplementation, request),
  };
}

async function downloadGLB(
  fetchImplementation: IkeaFetch,
  request: AcquisitionDownloadRequest,
): Promise<AcquisitionDownloadResponse> {
  if (!isAllowedIkeaGLBURL(request.sourceURL)) throw new Error("invalid_ikea_glb_url");
  if (!Number.isSafeInteger(request.offset) || request.offset < 0) {
    throw new Error("invalid_ikea_glb_offset");
  }
  if (!Number.isSafeInteger(request.maxResponseBytes) || request.maxResponseBytes < 1) {
    throw new Error("invalid_ikea_glb_response_limit");
  }
  const response = await fetchImplementation(request.sourceURL, {
    headers: {
      accept: "model/gltf-binary",
      "user-agent": "ReframeCatalog/1.0 (+catalog-source)",
      ...(request.offset === 0 ? {} : { range: `bytes=${request.offset}-` }),
      ...(request.ifRangeETag === undefined ? {} : { "if-range": request.ifRangeETag }),
    },
    redirect: "error",
  });
  if (!isAllowedIkeaGLBURL(response.url || request.sourceURL)) {
    throw new Error("invalid_ikea_glb_response_origin");
  }
  const retryAfterMs = retryAfter(response.headers.get("retry-after"));
  if (response.status !== 200 && response.status !== 206) {
    return {
      status: response.status,
      bytes: new Uint8Array(),
      ...(retryAfterMs === undefined ? {} : { retryAfterMs }),
    };
  }
  const contentType = response.headers.get("content-type")?.toLowerCase() ?? "";
  if (!contentType.startsWith("model/gltf-binary"))
    throw new Error("invalid_ikea_glb_content_type");
  const declaredLength = positiveHeaderInteger(response.headers.get("content-length"));
  if (declaredLength !== undefined && declaredLength > request.maxResponseBytes) {
    throw new Error("ikea_glb_response_too_large");
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.byteLength === 0 || bytes.byteLength > request.maxResponseBytes) {
    throw new Error("ikea_glb_response_too_large");
  }
  if (declaredLength !== undefined && bytes.byteLength !== declaredLength) {
    throw new Error("ikea_glb_content_length_mismatch");
  }
  const etag = response.headers.get("etag") ?? undefined;
  if (response.status === 200) {
    return {
      status: 200,
      bytes,
      ...(etag === undefined ? {} : { etag }),
      totalBytes: bytes.byteLength,
    };
  }
  const range = parseContentRange(response.headers.get("content-range"));
  if (range.length !== bytes.byteLength) throw new Error("ikea_glb_content_range_mismatch");
  return {
    status: 206,
    bytes,
    ...(etag === undefined ? {} : { etag }),
    rangeStart: range.start,
    totalBytes: range.total,
  };
}

function isAllowedIkeaGLBURL(value: string): boolean {
  try {
    const url = new URL(value);
    return (
      url.origin === IKEA_ASSET_ORIGIN &&
      url.protocol === "https:" &&
      url.username === "" &&
      url.password === "" &&
      url.pathname.endsWith(".glb")
    );
  } catch {
    return false;
  }
}

function positiveHeaderInteger(value: string | null): number | undefined {
  if (value === null) return undefined;
  if (!/^\d+$/u.test(value)) throw new Error("invalid_ikea_glb_content_length");
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0)
    throw new Error("invalid_ikea_glb_content_length");
  return parsed;
}

function parseContentRange(value: string | null): { start: number; length: number; total: number } {
  const match = value?.match(/^bytes (\d+)-(\d+)\/(\d+)$/u);
  if (match === null || match === undefined) throw new Error("invalid_ikea_glb_content_range");
  const start = Number(match[1]);
  const end = Number(match[2]);
  const total = Number(match[3]);
  if (
    !Number.isSafeInteger(start) ||
    !Number.isSafeInteger(end) ||
    !Number.isSafeInteger(total) ||
    start < 0 ||
    end < start ||
    total <= end
  ) {
    throw new Error("invalid_ikea_glb_content_range");
  }
  return { start, length: end - start + 1, total };
}

function retryAfter(value: string | null): number | undefined {
  if (value === null) return undefined;
  if (!/^\d+$/u.test(value)) return undefined;
  const seconds = Number(value);
  if (!Number.isSafeInteger(seconds) || seconds < 0 || seconds > 300) return undefined;
  return seconds * 1_000;
}
