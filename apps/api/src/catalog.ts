export const CURATED_CATALOG = [
  {
    asset_id: "asset_53000000-0000-4000-8000-000000000002",
    name: "Warm Arc Chair",
  },
  {
    asset_id: "asset_53000000-0000-4000-8000-000000000003",
    name: "Cobalt Lounge Chair",
  },
  {
    asset_id: "asset_53000000-0000-4000-8000-000000000004",
    name: "Halo Side Table",
  },
] as const;

export type CatalogAssetID = (typeof CURATED_CATALOG)[number]["asset_id"];

export const CURATED_ASSET_IDS: ReadonlySet<string> = new Set(
  CURATED_CATALOG.map((asset) => asset.asset_id),
);
