export interface IkeaSourceAuthorization {
  state: "enabled" | "disabled";
  sourceOwner: string;
  market: string;
  locale: string;
  permittedDiscovery: string;
  permittedMetadataTypes: readonly string[];
  permittedBinaryTypes: readonly string[];
  permittedUse: string;
  attribution: string;
  authorizationReference: string;
  reviewedOn: string;
  rawRetentionDays: number;
}

/**
 * Operator-recorded authorization for the initial controlled US smoke and
 * frontier runs. It does not authorize redistribution of source assets.
 */
export const REFRAME_IKEA_US_AUTHORIZATION: IkeaSourceAuthorization = {
  state: "enabled",
  sourceOwner: "IKEA",
  market: "us",
  locale: "en-US",
  permittedDiscovery: "sitemap_and_controlled_browser_observation",
  permittedMetadataTypes: ["product_page", "product_metadata", "product_image"],
  permittedBinaryTypes: ["model/gltf-binary"],
  permittedUse: "internal",
  attribution: "IKEA product metadata and 3D assets; retain source attribution with every asset.",
  authorizationReference: "operator-authorized-2026-07-20",
  reviewedOn: "2026-07-20",
  rawRetentionDays: 30,
};

export function assertIkeaSourceAuthorization(policy: IkeaSourceAuthorization): void {
  if (policy.state !== "enabled") throw new Error("ikea_authorization_disabled");
  if (policy.sourceOwner !== "IKEA") throw new Error("invalid_ikea_authorization_owner");
  if (policy.market !== "us") throw new Error("invalid_ikea_authorization_market");
  if (policy.locale !== "en-US") throw new Error("invalid_ikea_authorization_locale");
  if (policy.permittedDiscovery !== "sitemap_and_controlled_browser_observation") {
    throw new Error("invalid_ikea_authorization_discovery");
  }
  if (
    policy.permittedMetadataTypes.join(",") !== "product_page,product_metadata,product_image" ||
    policy.permittedBinaryTypes.length !== 1 ||
    policy.permittedBinaryTypes[0] !== "model/gltf-binary"
  ) {
    throw new Error("invalid_ikea_authorization_types");
  }
  if (policy.permittedUse !== "internal") throw new Error("invalid_ikea_authorization_use");
  if (policy.attribution.trim().length === 0) throw new Error("missing_ikea_attribution");
  if (policy.authorizationReference.trim().length === 0) {
    throw new Error("missing_ikea_authorization_reference");
  }
  if (!/^\d{4}-\d{2}-\d{2}$/u.test(policy.reviewedOn)) {
    throw new Error("invalid_ikea_authorization_review_date");
  }
  if (!Number.isSafeInteger(policy.rawRetentionDays) || policy.rawRetentionDays < 1) {
    throw new Error("invalid_ikea_authorization_retention");
  }
}
