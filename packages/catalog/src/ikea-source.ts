import { createHash } from "node:crypto";
import {
  type AcquisitionContentStore,
  type AcquisitionResult,
  type AcquisitionStateStore,
  type AcquisitionTransport,
  acquireCatalogBinary,
} from "./acquisition.ts";
import { validateGLB } from "./asset-validator.ts";
import {
  assertIkeaSourceAuthorization,
  type IkeaSourceAuthorization,
} from "./ikea-authorization.ts";
import type { CatalogProduct } from "./types.ts";

const IKEA_ORIGIN = "https://www.ikea.com";
const IKEA_ASSET_ORIGIN = "https://web-api.ikea.com";
const PRODUCT_PATH = /^\/us\/en\/p\/[a-z0-9-]+\/$/u;

type IkeaFetch = (
  input: Parameters<typeof globalThis.fetch>[0],
  init?: Parameters<typeof globalThis.fetch>[1],
) => ReturnType<typeof globalThis.fetch>;

export interface SitemapResult {
  sitemapURLs: string[];
  productURLs: string[];
}

export interface IkeaSourceOptions {
  fetch?: IkeaFetch;
  concurrency?: number;
  authorization?: IkeaSourceAuthorization;
}

export interface FetchIkeaUSProductOptions {
  authorization: IkeaSourceAuthorization;
  productURL: string;
  fetch?: IkeaFetch;
}

export interface IkeaUSSourceSmokeOptions extends FetchIkeaUSProductOptions {
  state: AcquisitionStateStore;
  content: AcquisitionContentStore;
  transport: AcquisitionTransport;
  nowMs: number;
  maxAttempts?: number;
  baseRetryMs?: number;
  maxResponseBytes?: number;
  maxAssetBytes?: number;
}

export interface IkeaUSSourceSmokeResult {
  product: CatalogProduct;
  sourceGLBURL: string;
  acquisition: AcquisitionResult;
}

export function parseSitemap(xml: string, market = "us", language = "en"): SitemapResult {
  const urls = [...xml.matchAll(/<loc>\s*([^<]+?)\s*<\/loc>/giu)]
    .map((match) => decodeXML(match[1] ?? ""))
    .filter((value) => value.length > 0);
  const localeSegment = `/${market}/${language}/`;
  return {
    sitemapURLs: urls.filter((url) => url.includes(localeSegment) && url.endsWith(".xml")).sort(),
    productURLs: urls.filter(isAllowedProductURL).sort(),
  };
}

export function extractIkeaProduct(html: string, productURL: string): CatalogProduct {
  if (!isAllowedProductURL(productURL)) throw new Error("invalid_ikea_product_url");
  const product = findProductJSONLD(html);
  const sourceProductID = requireString(product.sku, "missing_product_id").replace(/\D/gu, "");
  if (!/^\d{8}$/u.test(sourceProductID)) throw new Error("invalid_product_id");
  const name = requireString(product.name, "missing_product_name");
  const description = typeof product.description === "string" ? cleanText(product.description) : "";
  const imageURLs = normalizeStringList(product.image).filter(isAllowedImageURL);
  const assetURLs = extractGLBURLs(html);
  const price = extractPrice(product.offers);
  return {
    id: `ikea-us-${sourceProductID}`,
    source: "ikea-us",
    sourceProductID,
    locale: "en-US",
    name,
    description,
    productURL,
    imageURLs,
    assetURLs,
    ...(price === undefined ? {} : { price }),
    searchableText: [name, description].filter((value) => value.length > 0).join(". "),
  };
}

export function extractGLBURLs(html: string): string[] {
  const normalized = html.replaceAll("\\/", "/").replaceAll("\\u002F", "/");
  const matches =
    normalized.match(/https:\/\/web-api\.ikea\.com\/[^\s"'<>]+?\.glb(?:\?[^\s"'<>]*)?/giu) ?? [];
  return [...new Set(matches.map((value) => value.replaceAll("&amp;", "&")))]
    .filter((value) => {
      try {
        return new URL(value).origin === IKEA_ASSET_ORIGIN;
      } catch {
        return false;
      }
    })
    .sort();
}

/** Reads exactly one authorized US-English product page without widening a frontier. */
export async function fetchIkeaUSProduct(
  options: FetchIkeaUSProductOptions,
): Promise<CatalogProduct> {
  assertIkeaSourceAuthorization(options.authorization);
  if (!isAllowedProductURL(options.productURL)) throw new Error("invalid_ikea_product_url");
  const fetchImplementation = options.fetch ?? globalThis.fetch;
  return extractIkeaProduct(
    await fetchText(fetchImplementation, options.productURL, "text/html"),
    options.productURL,
  );
}

/**
 * Bounded first leg of the live source spine. It does not parse or index the
 * GLB; it persists only an immutable source object or a resumable checkpoint.
 */
export async function runIkeaUSSourceSmoke(
  options: IkeaUSSourceSmokeOptions,
): Promise<IkeaUSSourceSmokeResult> {
  const product = await fetchIkeaUSProduct(options);
  const sourceGLBURL = selectSmokeGLB(product.assetURLs);
  const suffix = createHash("sha256").update(sourceGLBURL).digest("hex").slice(0, 12);
  const acquisition = await acquireCatalogBinary({
    acquisitionID: `${product.id}-source-${suffix}`,
    sourceURL: sourceGLBURL,
    state: options.state,
    content: options.content,
    transport: options.transport,
    nowMs: options.nowMs,
    ...(options.maxAttempts === undefined ? {} : { maxAttempts: options.maxAttempts }),
    ...(options.baseRetryMs === undefined ? {} : { baseRetryMs: options.baseRetryMs }),
    ...(options.maxResponseBytes === undefined
      ? {}
      : { maxResponseBytes: options.maxResponseBytes }),
    ...(options.maxAssetBytes === undefined ? {} : { maxAssetBytes: options.maxAssetBytes }),
    validateCompletedContent: validateGLB,
  });
  return { product, sourceGLBURL, acquisition };
}

export async function* crawlIkeaUSProducts(
  options: IkeaSourceOptions = {},
): AsyncGenerator<CatalogProduct> {
  if (options.authorization === undefined) throw new Error("missing_ikea_authorization");
  assertIkeaSourceAuthorization(options.authorization);
  const fetchImplementation = options.fetch ?? globalThis.fetch;
  const concurrency = Math.max(1, Math.min(options.concurrency ?? 6, 12));
  const pendingSitemaps = [`${IKEA_ORIGIN}/sitemaps/sitemap.xml`];
  const visitedSitemaps = new Set<string>();
  const productURLs = new Set<string>();

  while (pendingSitemaps.length > 0) {
    const sitemapURL = pendingSitemaps.shift();
    if (sitemapURL === undefined || visitedSitemaps.has(sitemapURL)) continue;
    visitedSitemaps.add(sitemapURL);
    const xml = await fetchText(fetchImplementation, sitemapURL, "application/xml");
    const parsed = parseSitemap(xml);
    for (const child of parsed.sitemapURLs) {
      if (!visitedSitemaps.has(child)) pendingSitemaps.push(child);
    }
    for (const productURL of parsed.productURLs) productURLs.add(productURL);
  }

  const queue = [...productURLs].sort();
  for (let offset = 0; offset < queue.length; offset += concurrency) {
    const batch = queue.slice(offset, offset + concurrency);
    const products = await Promise.all(
      batch.map(async (url) =>
        extractIkeaProduct(await fetchText(fetchImplementation, url, "text/html"), url),
      ),
    );
    for (const product of products) yield product;
  }
}

async function fetchText(
  fetchImplementation: IkeaFetch,
  url: string,
  accept: string,
): Promise<string> {
  const response = await fetchImplementation(url, {
    headers: { accept, "user-agent": "ReframeCatalog/1.0 (+catalog-sync)" },
    redirect: "follow",
  });
  if (!response.ok || new URL(response.url || url).origin !== IKEA_ORIGIN) {
    throw new Error("ikea_source_failure");
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.byteLength > 8_000_000) throw new Error("ikea_source_too_large");
  return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}

function findProductJSONLD(html: string): Record<string, unknown> {
  const scripts = [
    ...html.matchAll(
      /<script\b[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/giu,
    ),
  ];
  for (const match of scripts) {
    try {
      const value = JSON.parse(match[1] ?? "null") as unknown;
      for (const candidate of flattenJSONLD(value)) {
        if (candidate["@type"] === "Product") return candidate;
      }
    } catch {}
  }
  throw new Error("missing_product_metadata");
}

function flattenJSONLD(value: unknown): Record<string, unknown>[] {
  if (Array.isArray(value)) return value.flatMap(flattenJSONLD);
  if (typeof value !== "object" || value === null) return [];
  const record = value as Record<string, unknown>;
  return [record, ...flattenJSONLD(record["@graph"])];
}

function extractPrice(value: unknown): { amount: number; currency: string } | undefined {
  const offer = Array.isArray(value) ? value[0] : value;
  if (typeof offer !== "object" || offer === null) return undefined;
  const record = offer as Record<string, unknown>;
  const amount = Number(record.price);
  const currency = record.priceCurrency;
  if (
    !Number.isFinite(amount) ||
    amount < 0 ||
    typeof currency !== "string" ||
    !/^[A-Z]{3}$/u.test(currency)
  ) {
    return undefined;
  }
  return { amount, currency };
}

function isAllowedProductURL(value: string): boolean {
  try {
    const url = new URL(value);
    return url.origin === IKEA_ORIGIN && url.search === "" && PRODUCT_PATH.test(url.pathname);
  } catch {
    return false;
  }
}

function isAllowedImageURL(value: string): boolean {
  try {
    return new URL(value).origin === IKEA_ORIGIN;
  } catch {
    return false;
  }
}

function selectSmokeGLB(assetURLs: readonly string[]): string {
  const selected = [...assetURLs].sort((left, right) => {
    const rankDifference = glbQualityRank(left) - glbQualityRank(right);
    return rankDifference === 0 ? left.localeCompare(right) : rankDifference;
  })[0];
  if (selected === undefined || !isAllowedGLBURL(selected))
    throw new Error("missing_ikea_glb_asset");
  return selected;
}

function glbQualityRank(url: string): number {
  if (url.includes("/rqp3/glb_draco/")) return 0;
  if (url.includes("/rqp3/glb/")) return 1;
  if (url.includes("/rqp2/glb_draco/")) return 2;
  if (url.includes("/rqp2/glb/")) return 3;
  if (url.includes("/rqp1/glb_draco/")) return 4;
  if (url.includes("/rqp1/glb/")) return 5;
  return 6;
}

function isAllowedGLBURL(value: string): boolean {
  try {
    const url = new URL(value);
    return (
      url.protocol === "https:" &&
      url.origin === IKEA_ASSET_ORIGIN &&
      url.username === "" &&
      url.password === "" &&
      url.pathname.endsWith(".glb")
    );
  } catch {
    return false;
  }
}

function normalizeStringList(value: unknown): string[] {
  const values = Array.isArray(value) ? value : [value];
  return [...new Set(values.filter((item): item is string => typeof item === "string"))].sort();
}

function requireString(value: unknown, error: string): string {
  if (typeof value !== "string" || cleanText(value).length === 0) throw new Error(error);
  return cleanText(value);
}

function cleanText(value: string): string {
  return value.replace(/\s+/gu, " ").trim();
}

function decodeXML(value: string): string {
  return value.replaceAll("&amp;", "&").replaceAll("&lt;", "<").replaceAll("&gt;", ">");
}
