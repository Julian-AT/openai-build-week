import { runIkeaSourceSmokeFromEnvironment } from "./source-smoke.ts";

const [profile, ...additionalArguments] = process.argv.slice(2);
if (profile !== "smoke" || additionalArguments.length !== 0) {
  throw new Error("catalog_profile_must_be_smoke");
}

const result = await runIkeaSourceSmokeFromEnvironment(process.env);
process.stdout.write(
  `${JSON.stringify({
    productID: result.product.id,
    sourceGLBURL: result.sourceGLBURL,
    sourceContent: result.acquisition.checkpoint.content,
  })}\n`,
);
