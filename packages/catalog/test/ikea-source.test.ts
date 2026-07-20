import { test } from "bun:test";
import assert from "node:assert/strict";

import {
  crawlIkeaUSProducts,
  extractIkeaProduct,
  fetchIkeaUSProduct,
  parseSitemap,
  REFRAME_IKEA_US_AUTHORIZATION,
  runIkeaUSSourceSmoke,
} from "../src/index.ts";

test("the IKEA source discovers product pages from sitemap indexes", () => {
  const xml = `<?xml version="1.0"?><sitemapindex>
    <sitemap><loc>https://www.ikea.com/sitemaps/us/en/products.xml</loc></sitemap>
    <sitemap><loc>https://www.ikea.com/sitemaps/de/de/products.xml</loc></sitemap>
  </sitemapindex>`;

  assert.deepEqual(parseSitemap(xml, "us", "en"), {
    sitemapURLs: ["https://www.ikea.com/sitemaps/us/en/products.xml"],
    productURLs: [],
  });
});

test("the IKEA source extracts stable product metadata and every GLB variant", () => {
  const html = `<html><head>
    <script type="application/ld+json">{
      "@type":"Product","name":"KALLAX shelf unit","sku":"99017186",
      "description":"A practical white shelf.","image":["https://www.ikea.com/image.jpg"],
      "brand":{"name":"IKEA"},"offers":{"price":"199.99","priceCurrency":"USD"}
    }</script>
  </head><body>
    <script>{"model":"https://web-api.ikea.com/dimma/assets/99017186/simple.glb?cn=pip",
      "draco":"https:\\/\\/web-api.ikea.com\\/dimma\\/assets\\/99017186\\/simple-draco.glb?cn=pip"}</script>
  </body></html>`;

  assert.deepEqual(
    extractIkeaProduct(html, "https://www.ikea.com/us/en/p/kallax-white-s99017186/"),
    {
      id: "ikea-us-99017186",
      source: "ikea-us",
      sourceProductID: "99017186",
      locale: "en-US",
      name: "KALLAX shelf unit",
      description: "A practical white shelf.",
      productURL: "https://www.ikea.com/us/en/p/kallax-white-s99017186/",
      imageURLs: ["https://www.ikea.com/image.jpg"],
      assetURLs: [
        "https://web-api.ikea.com/dimma/assets/99017186/simple-draco.glb?cn=pip",
        "https://web-api.ikea.com/dimma/assets/99017186/simple.glb?cn=pip",
      ],
      price: { amount: 199.99, currency: "USD" },
      searchableText: "KALLAX shelf unit. A practical white shelf.",
    },
  );
});

test("the IKEA crawler rejects a disabled source policy before making a network request", async () => {
  let fetches = 0;
  const source = crawlIkeaUSProducts({
    authorization: { ...REFRAME_IKEA_US_AUTHORIZATION, state: "disabled" },
    fetch: async () => {
      fetches += 1;
      throw new Error("network_must_not_run");
    },
  });

  await assert.rejects(source.next(), /ikea_authorization_disabled/);
  assert.equal(fetches, 0);
});

test("the authorized smoke source acquires one observed GLB through resumable content storage", async () => {
  const checkpoints = new Map();
  const partials = new Map<string, Uint8Array>();
  const committed = new Map<string, Uint8Array>();
  const source = await runIkeaUSSourceSmoke({
    authorization: REFRAME_IKEA_US_AUTHORIZATION,
    productURL: "https://www.ikea.com/us/en/p/kallax-white-s99017186/",
    fetch: async () =>
      new Response(productHTML(), {
        status: 200,
        headers: { "content-type": "text/html" },
      }),
    state: {
      load: async (id) => checkpoints.get(id),
      save: async (checkpoint) => void checkpoints.set(checkpoint.acquisitionID, checkpoint),
    },
    content: {
      partialSize: async (id) => partials.get(id)?.byteLength ?? 0,
      appendPartial: async (id, offset, bytes) => {
        assert.equal(offset, partials.get(id)?.byteLength ?? 0);
        partials.set(id, bytes);
      },
      replacePartial: async (id, bytes) => void partials.set(id, bytes),
      readPartial: async (id) => partials.get(id) ?? new Uint8Array(),
      commitContent: async (sha256, bytes) => {
        committed.set(sha256, bytes);
        return `sha256/${sha256}`;
      },
      discardPartial: async (id) => void partials.delete(id),
    },
    transport: {
      download: async (request) => {
        assert.match(request.sourceURL, /rqp3\/glb_draco/u);
        return { status: 200, bytes: minimalGLB(), totalBytes: 24 };
      },
    },
    nowMs: 1_000,
  });

  assert.equal(source.product.id, "ikea-us-99017186");
  assert.equal(source.acquisition.status, "complete");
  assert.equal(committed.size, 1);
});

test("the product-page reader rejects a disabled policy before issuing a request", async () => {
  let fetches = 0;
  await assert.rejects(
    fetchIkeaUSProduct({
      authorization: { ...REFRAME_IKEA_US_AUTHORIZATION, state: "disabled" },
      productURL: "https://www.ikea.com/us/en/p/kallax-white-s99017186/",
      fetch: async () => {
        fetches += 1;
        throw new Error("network_must_not_run");
      },
    }),
    /ikea_authorization_disabled/,
  );
  assert.equal(fetches, 0);
});

test("the smoke source rejects malformed GLB bytes before content-addressed commit", async () => {
  const committed = new Map<string, Uint8Array>();
  await assert.rejects(
    runIkeaUSSourceSmoke({
      authorization: REFRAME_IKEA_US_AUTHORIZATION,
      productURL: "https://www.ikea.com/us/en/p/kallax-white-s99017186/",
      fetch: async () => new Response(productHTML(), { status: 200 }),
      state: { load: async () => undefined, save: async () => {} },
      content: {
        partialSize: async () => 0,
        appendPartial: async () => {},
        replacePartial: async () => {},
        readPartial: async () => new TextEncoder().encode("invalid"),
        commitContent: async (sha256, bytes) => {
          committed.set(sha256, bytes);
          return `sha256/${sha256}`;
        },
        discardPartial: async () => {},
      },
      transport: {
        download: async () => ({
          status: 200,
          bytes: new TextEncoder().encode("invalid"),
          totalBytes: 7,
        }),
      },
      nowMs: 1_000,
    }),
    /invalid_glb_header/,
  );
  assert.equal(committed.size, 0);
});

function productHTML(): string {
  return `<script type="application/ld+json">{
    "@type":"Product","name":"KALLAX shelf unit","sku":"99017186",
    "description":"A practical white shelf.","image":[],
    "offers":{"price":"199.99","priceCurrency":"USD"}
  }</script><script type="application/ld+json">{
    "@type":"3DModel","encoding":[
      {"contentUrl":"https://web-api.ikea.com/dimma/assets/99017186/rqp1/glb_draco/model.glb","encodingFormat":"model/gltf-binary"},
      {"contentUrl":"https://web-api.ikea.com/dimma/assets/99017186/rqp3/glb_draco/model.glb","encodingFormat":"model/gltf-binary"}
    ]
  }</script>`;
}

function minimalGLB(): Uint8Array {
  const bytes = new Uint8Array(24);
  bytes.set([0x67, 0x6c, 0x54, 0x46]);
  const view = new DataView(bytes.buffer);
  view.setUint32(4, 2, true);
  view.setUint32(8, bytes.byteLength, true);
  view.setUint32(12, 4, true);
  view.setUint32(16, 0x4e4f534a, true);
  bytes.set([0x7b, 0x7d, 0x20, 0x20], 20);
  return bytes;
}
