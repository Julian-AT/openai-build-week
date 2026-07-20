import { runIkeaCatalogOperationFromEnvironment } from "./ikea-catalog-operation.ts";
import { runIkeaIndexedSmokeFromEnvironment } from "./source-smoke.ts";

const [profile, ...additionalArguments] = process.argv.slice(2);
if (additionalArguments.length !== 0) throw new Error("catalog_profile_arguments_unsupported");

if (profile === "smoke") {
  const result = await runIkeaIndexedSmokeFromEnvironment(process.env);
  process.stdout.write(
    `${JSON.stringify({
      profile,
      productID: result.product.id,
      sourceGLBURL: result.sourceGLBURL,
      sourceContent: result.acquisition.checkpoint.content,
      preparedAssetID: result.prepared.asset.assetID,
      derivationID: result.prepared.derivationID,
      catalogID: result.proof.hit.id,
      delivery: {
        derivative: result.proof.delivery.derivative,
        sha256: result.proof.delivery.sha256,
        byteLength: result.proof.delivery.byteLength,
      },
    })}\n`,
  );
} else if (profile === "full" || profile === "incremental") {
  const result = await runIkeaCatalogOperationFromEnvironment({
    ...process.env,
    REFRAME_CATALOG_PROFILE: profile,
  });
  process.stdout.write(
    `${JSON.stringify({
      profile,
      runID: result.runID,
      status: result.status,
      configurationDigest: result.configurationDigest,
      counters: result.counters,
      reconciliation: result.reconciliation,
    })}\n`,
  );
} else {
  throw new Error("catalog_profile_must_be_smoke_full_or_incremental");
}
