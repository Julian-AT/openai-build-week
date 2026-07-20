import { test } from "bun:test";
import assert from "node:assert/strict";

import { extractIkeaProduct, parseSitemap } from "../src/index.ts";

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
