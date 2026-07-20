import { createFilesystemAcquisitionStores } from "./filesystem-acquisition-store.ts";
import { REFRAME_IKEA_US_AUTHORIZATION } from "./ikea-authorization.ts";
import { createIkeaGLBFetchTransport } from "./ikea-glb-transport.ts";
import { type IkeaUSSourceSmokeResult, runIkeaUSSourceSmoke } from "./ikea-source.ts";

export interface IkeaSourceSmokeEnvironment {
  [name: string]: string | undefined;
  REFRAME_DATA_DIR?: string;
  REFRAME_IKEA_SMOKE_PRODUCT_URL?: string;
}

/** Executes one explicitly configured live source acquisition without broadening the frontier. */
export async function runIkeaSourceSmokeFromEnvironment(
  environment: IkeaSourceSmokeEnvironment,
): Promise<IkeaUSSourceSmokeResult> {
  const dataDirectory = environment.REFRAME_DATA_DIR;
  if (dataDirectory === undefined || dataDirectory.length === 0) {
    throw new Error("missing_reframe_data_dir");
  }
  const productURL = environment.REFRAME_IKEA_SMOKE_PRODUCT_URL;
  if (productURL === undefined || productURL.length === 0) {
    throw new Error("missing_reframe_ikea_smoke_product_url");
  }
  const stores = await createFilesystemAcquisitionStores({ dataDirectory });
  const result = await runIkeaUSSourceSmoke({
    authorization: REFRAME_IKEA_US_AUTHORIZATION,
    productURL,
    state: stores.state,
    content: stores.content,
    transport: createIkeaGLBFetchTransport(),
    nowMs: Date.now(),
  });
  if (result.acquisition.status !== "complete") throw new Error("ikea_source_smoke_incomplete");
  return result;
}
