export interface CatalogProduct {
  id: string;
  source: "ikea-us";
  sourceProductID: string;
  locale: "en-US";
  name: string;
  description: string;
  productURL: string;
  imageURLs: string[];
  assetURLs: string[];
  price?: { amount: number; currency: string };
  searchableText: string;
}

export interface EmbeddedCatalogProduct extends CatalogProduct {
  textVector: number[];
  visualDescriptor: string;
}

export interface CatalogSink {
  prepare(vectorSize: number): Promise<void>;
  upsert(products: readonly EmbeddedCatalogProduct[]): Promise<void>;
}

export interface CatalogEnricher {
  enrich(product: CatalogProduct): Promise<EmbeddedCatalogProduct>;
}
