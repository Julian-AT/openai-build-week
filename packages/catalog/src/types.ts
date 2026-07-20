export const SEMANTIC_VECTOR_NAME = "semantic_v1";
export const SEMANTIC_VECTOR_SIZE = 1_024;

export type AssetAuthorizationStatus = "authorized" | "unverified" | "prohibited";
export type AssetSupportType = "floor" | "surface" | "wall" | "ceiling";

export interface CatalogDimensionsM {
  width: number;
  height: number;
  depth: number;
}

export interface ValidatedCatalogDerivative {
  /** Opaque content-addressed storage reference. Never a public delivery URL. */
  storageKey: string;
  sha256: string;
  byteLength: number;
  validated: boolean;
}

export interface CatalogCollisionDerivative extends ValidatedCatalogDerivative {
  representation: "aabb" | "convex_hull" | "mesh";
}

/** Preparation facts used to derive injection readiness; readiness is never trusted as input. */
export interface CatalogAssetRecord {
  assetID: string;
  authorization: {
    status: AssetAuthorizationStatus;
    reference: string;
  };
  category: string;
  dimensionsM: CatalogDimensionsM;
  supportType: AssetSupportType;
  normalization: {
    units: "meters";
    origin: "floor-contact-center";
    forwardAxis: "+z";
  };
  derivatives: {
    glb: ValidatedCatalogDerivative;
    usdz: ValidatedCatalogDerivative;
    collision: CatalogCollisionDerivative;
  };
  cacheProfiles: string[];
}

export interface CatalogProduct {
  /** Stable canonical product identity exposed across public boundaries. */
  id: string;
  /** Optional stable source variant identity; asset records remain individually indexable. */
  variantID?: string;
  parentProductID?: string;
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
  preparedAsset?: CatalogAssetRecord;
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
