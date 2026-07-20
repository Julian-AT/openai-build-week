import { createHash } from "node:crypto";
import {
  type AcquisitionContentStore,
  type AcquisitionResult,
  type AcquisitionStateStore,
  type AcquisitionTransport,
  acquireCatalogBinary,
} from "./acquisition.ts";
import { validateGLB } from "./asset-validator.ts";
import type { CatalogOperationDiscovery, CatalogSource } from "./catalog-operation.ts";
import type { CatalogRunCheckpoint } from "./catalog-run-store.ts";
import {
  assertIkeaSourceAuthorization,
  type IkeaSourceAuthorization,
} from "./ikea-authorization.ts";
import type { AssetSupportType, CatalogDimensionsM, CatalogProduct } from "./types.ts";

const IKEA_ORIGIN = "https://www.ikea.com";
const IKEA_ASSET_ORIGIN = "https://web-api.ikea.com";
const PRODUCT_PATH = /^\/us\/en\/p\/[a-z0-9-]+\/$/u;
export const IKEA_HTML_PARSER_REVISION = "ikea-html-v1";

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

export interface IkeaUSCatalogSourceOptions extends IkeaSourceOptions {
  /** Sustained per-origin request ceiling, shared by sitemap and product page observation. */
  requestsPerMinute: number;
  maxAttempts?: number;
  retryBaseMs?: number;
  maxProducts?: number;
  sleep?: (milliseconds: number) => Promise<void>;
  now?: () => number;
}

export interface IkeaProductResponseValidators {
  etag?: string;
  lastModified?: string;
}

export interface IkeaRawProductRecord {
  parserRevision: typeof IKEA_HTML_PARSER_REVISION;
  productURL: string;
  responseValidators: IkeaProductResponseValidators;
  /** Raw page bytes decoded as UTF-8. This is untrusted data, retained by the catalog run store by hash. */
  pageHTML: string;
}

/** Source facts remain separate from normalized processor facts and model-derived enrichment. */
export interface IkeaProductSourceFacts {
  rawCategory?: string;
  dimensionsM?: CatalogDimensionsM;
  category?: string;
  supportType?: AssetSupportType;
}

export interface IkeaCatalogDiscovery extends Omit<CatalogOperationDiscovery, "rawRecord"> {
  rawRecord: IkeaRawProductRecord;
  product: CatalogProduct;
  sourceFacts: IkeaProductSourceFacts;
}

export interface IkeaCatalogSource extends CatalogSource<IkeaCatalogDiscovery> {
  discover(context: {
    profile: "smoke" | "full" | "incremental";
    checkpoint: CatalogRunCheckpoint | undefined;
    signal: AbortSignal | undefined;
  }): AsyncIterable<IkeaCatalogDiscovery>;
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
  const productSitemap = new RegExp(
    `/sitemaps/prod-${escapeRegExp(language)}-${escapeRegExp(market.toUpperCase())}(?:_|\\.)`,
    "iu",
  );
  return {
    sitemapURLs: urls
      .filter(
        (url) => (url.includes(localeSegment) && url.endsWith(".xml")) || productSitemap.test(url),
      )
      .sort(),
    productURLs: urls.filter(isAllowedProductURL).sort(),
  };
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&");
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

/**
 * Extracts permitted source facts only. A missing or ambiguous dimension/class
 * is represented as absent so callers can retain discovery without guessing
 * eligibility.
 */
export function extractIkeaProductSourceFacts(
  html: string,
  productName: string,
): IkeaProductSourceFacts {
  const rawCategory = extractIkeaCategory(html);
  const dimensionsM = extractIkeaDimensions(html);
  const classification = classifyIkeaProduct(productName);
  return {
    ...(rawCategory === undefined ? {} : { rawCategory }),
    ...(dimensionsM === undefined ? {} : { dimensionsM }),
    ...(classification === undefined ? {} : classification),
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

/**
 * Authorized, restart-aware discovery adapter. It returns immutable records to
 * the catalog operation and has no path to Qdrant, derivatives, or delivery.
 */
export function createIkeaUSCatalogSource(options: IkeaUSCatalogSourceOptions): IkeaCatalogSource {
  const authorization = options.authorization;
  if (authorization === undefined) throw new Error("missing_ikea_authorization");
  assertIkeaSourceAuthorization(authorization);
  const concurrency = Math.max(1, Math.min(options.concurrency ?? 4, 12));
  const requestsPerMinute = options.requestsPerMinute;
  if (!Number.isSafeInteger(requestsPerMinute) || requestsPerMinute < 1 || requestsPerMinute > 600)
    throw new Error("invalid_ikea_requests_per_minute");
  const maxAttempts = options.maxAttempts ?? 3;
  if (!Number.isSafeInteger(maxAttempts) || maxAttempts < 1 || maxAttempts > 8)
    throw new Error("invalid_ikea_source_max_attempts");
  const retryBaseMs = options.retryBaseMs ?? 500;
  if (!Number.isSafeInteger(retryBaseMs) || retryBaseMs < 50 || retryBaseMs > 60_000)
    throw new Error("invalid_ikea_source_retry_base_ms");
  if (
    options.maxProducts !== undefined &&
    (!Number.isSafeInteger(options.maxProducts) ||
      options.maxProducts < 1 ||
      options.maxProducts > 100_000)
  ) {
    throw new Error("invalid_ikea_source_max_products");
  }
  const fetchImplementation = options.fetch ?? globalThis.fetch;
  const sleep = options.sleep ?? ((milliseconds: number) => Bun.sleep(milliseconds));
  const now = options.now ?? Date.now;
  const rateLimit = createRateLimiter(requestsPerMinute, now, sleep);

  return {
    discover: async function* ({ checkpoint, signal }) {
      assertIkeaSourceAuthorization(authorization);
      if (checkpoint !== undefined) validateIkeaCheckpoint(checkpoint);
      throwIfAborted(signal);
      const productURLs = await discoverIkeaUSProductURLs({
        fetch: fetchImplementation,
        rateLimit,
        maxAttempts,
        retryBaseMs,
        sleep,
        signal,
      });
      const startAfter = checkpoint?.cursor;
      const queue = productURLs.filter((url) => startAfter === undefined || url > startAfter);
      const bounded =
        options.maxProducts === undefined ? queue : queue.slice(0, options.maxProducts);
      const categories = new Set<string>();
      for (let offset = 0; offset < bounded.length; offset += concurrency) {
        throwIfAborted(signal);
        const batch = bounded.slice(offset, offset + concurrency);
        const pages = await Promise.all(
          batch.map(async (productURL) => {
            const response = await fetchIkeaText({
              fetch: fetchImplementation,
              url: productURL,
              accept: "text/html",
              rateLimit,
              maxAttempts,
              retryBaseMs,
              sleep,
              signal,
            });
            return { productURL, ...response };
          }),
        );
        for (const page of pages) {
          throwIfAborted(signal);
          const product = extractIkeaProduct(page.text, page.productURL);
          const facts = extractIkeaProductSourceFacts(page.text, product.name);
          const categoryPage =
            facts.rawCategory !== undefined && !categories.has(facts.rawCategory);
          if (facts.rawCategory !== undefined) categories.add(facts.rawCategory);
          const variantIDs = product.assetURLs.map(
            (assetURL) =>
              `${product.id}-${createHash("sha256").update(assetURL).digest("hex").slice(0, 12)}`,
          );
          yield {
            cursor: page.productURL,
            sourceProductID: product.sourceProductID,
            canonicalProductID: product.id,
            variantIDs,
            categoryPage,
            productHasModelReference: product.assetURLs.length > 0,
            modelURLsObserved: product.assetURLs.length,
            rawRecord: {
              parserRevision: IKEA_HTML_PARSER_REVISION,
              productURL: page.productURL,
              responseValidators: page.validators,
              pageHTML: page.text,
            },
            product,
            sourceFacts: facts,
          };
        }
      }
    },
  };
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

async function discoverIkeaUSProductURLs(options: {
  fetch: IkeaFetch;
  rateLimit: () => Promise<void>;
  maxAttempts: number;
  retryBaseMs: number;
  sleep: (milliseconds: number) => Promise<void>;
  signal: AbortSignal | undefined;
}): Promise<string[]> {
  const pending = [`${IKEA_ORIGIN}/sitemaps/sitemap.xml`];
  const visited = new Set<string>();
  const productURLs = new Set<string>();
  while (pending.length > 0) {
    const sitemapURL = pending.shift();
    if (sitemapURL === undefined || visited.has(sitemapURL)) continue;
    visited.add(sitemapURL);
    const response = await fetchIkeaText({
      ...options,
      url: sitemapURL,
      accept: "application/xml",
    });
    const parsed = parseSitemap(response.text);
    for (const child of parsed.sitemapURLs) {
      if (!visited.has(child)) pending.push(child);
    }
    for (const productURL of parsed.productURLs) productURLs.add(productURL);
  }
  if (productURLs.size === 0) throw new Error("ikea_selector_drift_no_product_frontier");
  return [...productURLs].sort();
}

async function fetchIkeaText(options: {
  fetch: IkeaFetch;
  url: string;
  accept: string;
  rateLimit: () => Promise<void>;
  maxAttempts: number;
  retryBaseMs: number;
  sleep: (milliseconds: number) => Promise<void>;
  signal: AbortSignal | undefined;
}): Promise<{ text: string; validators: IkeaProductResponseValidators }> {
  for (let attempt = 1; attempt <= options.maxAttempts; attempt += 1) {
    throwIfAborted(options.signal);
    try {
      await options.rateLimit();
      const response = await options.fetch(options.url, {
        headers: { accept: options.accept, "user-agent": "ReframeCatalog/1.0 (+catalog-sync)" },
        redirect: "follow",
        ...(options.signal === undefined ? {} : { signal: options.signal }),
      });
      if (!response.ok || new URL(response.url || options.url).origin !== IKEA_ORIGIN) {
        if (response.status === 429 || response.status >= 500)
          throw new Error("ikea_source_retryable");
        throw new Error("ikea_source_failure");
      }
      const bytes = new Uint8Array(await response.arrayBuffer());
      if (bytes.byteLength > 8_000_000) throw new Error("ikea_source_too_large");
      const etag = validValidator(response.headers.get("etag"));
      const lastModified = validValidator(response.headers.get("last-modified"));
      return {
        text: new TextDecoder("utf-8", { fatal: true }).decode(bytes),
        validators: {
          ...(etag === undefined ? {} : { etag }),
          ...(lastModified === undefined ? {} : { lastModified }),
        },
      };
    } catch (error) {
      if (attempt === options.maxAttempts || !isRetryableIkeaError(error)) throw error;
      const jitter = deterministicJitter(options.url, attempt, options.retryBaseMs);
      await options.sleep(options.retryBaseMs * 2 ** (attempt - 1) + jitter);
    }
  }
  throw new Error("ikea_source_retry_exhausted");
}

function createRateLimiter(
  requestsPerMinute: number,
  now: () => number,
  sleep: (milliseconds: number) => Promise<void>,
): () => Promise<void> {
  const intervalMs = Math.ceil(60_000 / requestsPerMinute);
  let nextRequestAtMs = 0;
  return async () => {
    const current = now();
    const scheduled = Math.max(current, nextRequestAtMs);
    nextRequestAtMs = scheduled + intervalMs;
    if (scheduled > current) await sleep(scheduled - current);
  };
}

function deterministicJitter(url: string, attempt: number, baseRetryMs: number): number {
  const value = createHash("sha256").update(`${url}:${attempt}`).digest()[0] ?? 0;
  return value % Math.max(1, Math.floor(baseRetryMs / 4));
}

function isRetryableIkeaError(error: unknown): boolean {
  return error instanceof Error && error.message === "ikea_source_retryable";
}

function validValidator(value: string | null): string | undefined {
  if (value === null || value.length === 0 || value.length > 1_024 || /[\r\n]/u.test(value))
    return undefined;
  return value;
}

function validateIkeaCheckpoint(checkpoint: CatalogRunCheckpoint): void {
  if (
    checkpoint.source !== "ikea-us" ||
    checkpoint.market !== "us" ||
    checkpoint.locale !== "en-US" ||
    checkpoint.parserRevision !== IKEA_HTML_PARSER_REVISION
  ) {
    throw new Error("ikea_frontier_checkpoint_mismatch");
  }
}

function extractIkeaCategory(html: string): string | undefined {
  const category = /"category"\s*:\s*"([0-9]{1,20})"/u.exec(html)?.[1];
  return category;
}

function extractIkeaDimensions(html: string): CatalogDimensionsM | undefined {
  const text = decodeHTML(html)
    .replace(/<[^>]*>/gu, " ")
    .replace(/\s+/gu, " ")
    .trim();
  const measurements = [
    ...text.matchAll(/\b(Width|Height|Length|Depth)\s*:\s*([0-9]+(?:\s+(?:[¼½¾]|\d+\/\d+))?)/giu),
  ]
    .map((match) => ({
      label: (match[1] ?? "").toLowerCase(),
      inches: parseInches(match[2] ?? ""),
    }))
    .filter(
      (measurement): measurement is { label: string; inches: number } =>
        measurement.inches !== undefined,
    );
  const candidates: Array<Record<string, number>> = [];
  let candidate: Record<string, number> = {};
  for (const measurement of measurements) {
    if (candidate[measurement.label] !== undefined) {
      candidates.push(candidate);
      candidate = {};
    }
    candidate[measurement.label] = measurement.inches;
  }
  candidates.push(candidate);
  const dimensions = candidates
    .map((values) => {
      const height = values.height;
      const width = values.length ?? values.width;
      const depth = values.depth ?? (values.length === undefined ? undefined : values.width);
      if (height === undefined || width === undefined || depth === undefined) return undefined;
      const dimensionsM = {
        width: inchesToMeters(width),
        height: inchesToMeters(height),
        depth: inchesToMeters(depth),
      };
      return Object.values(dimensionsM).every(
        (value) => Number.isFinite(value) && value > 0 && value < 100,
      )
        ? dimensionsM
        : undefined;
    })
    .filter((value): value is CatalogDimensionsM => value !== undefined)
    .sort(
      (left, right) =>
        right.width * right.height * right.depth - left.width * left.height * left.depth,
    );
  return dimensions[0];
}

function inchesToMeters(inches: number): number {
  return Number((inches * 0.0254).toFixed(5));
}

function parseInches(value: string): number | undefined {
  const normalized = value.trim();
  const [wholePart, fractionPart] = normalized.split(/\s+/u);
  const whole = Number(wholePart);
  if (!Number.isFinite(whole) || whole < 0) return undefined;
  if (fractionPart === undefined) return whole;
  const fractions: Record<string, number> = { "¼": 0.25, "½": 0.5, "¾": 0.75 };
  if (fractions[fractionPart] !== undefined) return whole + fractions[fractionPart];
  const fraction = /^(\d+)\/(\d+)$/u.exec(fractionPart);
  if (fraction === null) return undefined;
  const numerator = Number(fraction[1]);
  const denominator = Number(fraction[2]);
  if (!Number.isSafeInteger(numerator) || !Number.isSafeInteger(denominator) || denominator === 0)
    return undefined;
  return whole + numerator / denominator;
}

function classifyIkeaProduct(
  name: string,
): { category: string; supportType: AssetSupportType } | undefined {
  const normalized = name.toLowerCase();
  const category = /side table|bedside table|end table/u.test(normalized)
    ? "side_table"
    : /coffee table/u.test(normalized)
      ? "coffee_table"
      : /table/u.test(normalized)
        ? "table"
        : /chair|stool/u.test(normalized)
          ? "chair"
          : /sofa|armchair/u.test(normalized)
            ? "sofa"
            : /cabinet|shelf|shelving|bookcase|wardrobe|storage/u.test(normalized)
              ? "storage"
              : /bed/u.test(normalized)
                ? "bed"
                : /floor lamp|lamp/u.test(normalized)
                  ? "lamp"
                  : /rug/u.test(normalized)
                    ? "rug"
                    : undefined;
  return category === undefined ? undefined : { category, supportType: "floor" };
}

function throwIfAborted(signal: AbortSignal | undefined): void {
  if (signal?.aborted) throw new Error("ikea_source_cancelled");
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

function decodeHTML(value: string): string {
  return decodeXML(value)
    .replaceAll("&quot;", '"')
    .replaceAll("&#34;", '"')
    .replaceAll("&nbsp;", " ")
    .replaceAll("&#160;", " ");
}
