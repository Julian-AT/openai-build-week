export type {
  AcquireCatalogBinaryOptions,
  AcquiredContentReference,
  AcquisitionCheckpoint,
  AcquisitionContentStore,
  AcquisitionDownloadRequest,
  AcquisitionDownloadResponse,
  AcquisitionPhase,
  AcquisitionResult,
  AcquisitionStateStore,
  AcquisitionTransport,
} from "./acquisition.ts";
export { acquireCatalogBinary } from "./acquisition.ts";
export type {
  AssetPreparationBudgets,
  AssetPreparationContentStore,
  AssetPreparationDerivativeKind,
  CatalogAssetProcessor,
  CatalogAssetProcessorOutput,
  CatalogAssetProcessorRequest,
  PrepareCatalogAssetOptions,
  PreparedCatalogAssetRecord,
} from "./asset-preparation.ts";
export {
  DEFAULT_ASSET_PREPARATION_BUDGETS,
  prepareCatalogAsset,
} from "./asset-preparation.ts";
export type { AssetBytes, AssetManifest } from "./asset-validator.ts";
export { validateAssetDerivatives, validateGLB, validateUSDZ } from "./asset-validator.ts";
export type {
  AssetProcessorCommandRunner,
  BlenderAssetProcessorOptions,
} from "./blender-asset-processor.ts";
export {
  BLENDER_NORMALIZER_SCRIPT_PATH,
  createBlenderAssetProcessor,
} from "./blender-asset-processor.ts";
export type {
  InjectionReadiness,
  InjectionReadinessFailure,
} from "./catalog-eligibility.ts";
export { assessAssetInjectionReadiness } from "./catalog-eligibility.ts";
export type {
  CatalogOperationDiscovery,
  CatalogOperationProgress,
  CatalogSource,
  RunCatalogOperationOptions,
} from "./catalog-operation.ts";
export { runCatalogOperation } from "./catalog-operation.ts";
export type {
  PreparedCatalogProofOptions,
  PreparedCatalogProofResult,
  PreparedCatalogProofStore,
} from "./catalog-proof.ts";
export { provePreparedCatalogAsset } from "./catalog-proof.ts";
export type {
  CatalogAcquisitionOutcome,
  CatalogAssetLifecycleState,
  CatalogDiscoveryObservation,
  CatalogDiscoveryReceipt,
  CatalogFrontierIdentity,
  CatalogRunCheckpoint,
  CatalogRunConfiguration,
  CatalogRunCounters,
  CatalogRunProfile,
  CatalogRunReconciliation,
  CatalogRunRecord,
  CatalogRunStore,
  CatalogStageUpdate,
  FilesystemCatalogRunStoreOptions,
} from "./catalog-run-store.ts";
export { createFilesystemCatalogRunStore } from "./catalog-run-store.ts";
export type {
  ClientCacheSyncReport,
  FilesystemLocalAssetCacheOptions,
  SynchronizePreparedAssetsToLocalCacheOptions,
} from "./client-cache-sync.ts";
export {
  createFilesystemLocalAssetCache,
  synchronizePreparedAssetsToLocalCache,
} from "./client-cache-sync.ts";
export type {
  CachedAssetBinary,
  CatalogDerivativeKind,
  LocalAssetCache,
  LocalAssetCacheRequest,
  LocalAssetDelivery,
  LocalAssetDeliveryRequest,
} from "./delivery.ts";
export { resolveLocalAssetDelivery } from "./delivery.ts";
export type {
  FilesystemAcquisitionStoreOptions,
  FilesystemAcquisitionStores,
} from "./filesystem-acquisition-store.ts";
export { createFilesystemAcquisitionStores } from "./filesystem-acquisition-store.ts";
export type {
  FilesystemPreparedAssetStore,
  FilesystemPreparedAssetStoreOptions,
} from "./filesystem-prepared-asset-store.ts";
export { createFilesystemPreparedAssetStore } from "./filesystem-prepared-asset-store.ts";
export type { IkeaSourceAuthorization } from "./ikea-authorization.ts";
export {
  assertIkeaSourceAuthorization,
  REFRAME_IKEA_US_AUTHORIZATION,
} from "./ikea-authorization.ts";
export type { IkeaCatalogOperationEnvironment } from "./ikea-catalog-operation.ts";
export { runIkeaCatalogOperationFromEnvironment } from "./ikea-catalog-operation.ts";
export type {
  IkeaDownloaderContentStore,
  IkeaDownloaderImportReport,
  ImportedIkeaDownloaderContent,
  ImportedIkeaDownloaderRecord,
  ImportPinnedIkeaDownloaderOutputOptions,
} from "./ikea-downloader-import.ts";
export {
  importPinnedIkeaDownloaderOutput,
  PINNED_IKEA_DOWNLOADER,
} from "./ikea-downloader-import.ts";
export type { IkeaGLBFetchTransportOptions } from "./ikea-glb-transport.ts";
export { createIkeaGLBFetchTransport } from "./ikea-glb-transport.ts";
export type {
  FetchIkeaUSProductOptions,
  IkeaCatalogDiscovery,
  IkeaCatalogSource,
  IkeaProductResponseValidators,
  IkeaProductSourceFacts,
  IkeaRawProductRecord,
  IkeaSourceOptions,
  IkeaUSCatalogSourceOptions,
  IkeaUSSourceSmokeOptions,
  IkeaUSSourceSmokeResult,
  SitemapResult,
} from "./ikea-source.ts";
export {
  crawlIkeaUSProducts,
  createIkeaUSCatalogSource,
  extractGLBURLs,
  extractIkeaProduct,
  extractIkeaProductSourceFacts,
  fetchIkeaUSProduct,
  IKEA_HTML_PARSER_REVISION,
  parseSitemap,
  runIkeaUSSourceSmoke,
} from "./ikea-source.ts";
export type { OpenAICatalogEnricherOptions } from "./openai-enricher.ts";
export { CATALOG_DESCRIPTOR_MODEL, createOpenAICatalogEnricher } from "./openai-enricher.ts";
export type { OpenAICatalogQueryVectorizerOptions } from "./openai-vectorizer.ts";
export {
  CATALOG_EMBEDDING_MODEL,
  createOpenAICatalogQueryVectorizer,
} from "./openai-vectorizer.ts";
export type { CatalogSyncOptions, CatalogSyncResult } from "./pipeline.ts";
export { syncCatalog } from "./pipeline.ts";
export type {
  CatalogSearchHit,
  CatalogVectorDatabase,
  EligibleCatalogSearch,
  QdrantCatalogStoreOptions,
} from "./qdrant-store.ts";
export { CATALOG_COLLECTION, QdrantCatalogStore } from "./qdrant-store.ts";
export type {
  CatalogQueryVectorizer,
  CatalogRetrievalRequest,
  CatalogRetriever,
  CatalogSearchStore,
} from "./retrieval.ts";
export { createCatalogRetriever, MAX_CATALOG_RETRIEVAL_RESULTS } from "./retrieval.ts";
export type {
  AssetAuthorizationStatus,
  AssetSupportType,
  CatalogAssetRecord,
  CatalogCollisionDerivative,
  CatalogDimensionsM,
  CatalogEnricher,
  CatalogProduct,
  CatalogSink,
  EmbeddedCatalogProduct,
  ValidatedCatalogDerivative,
} from "./types.ts";
export { SEMANTIC_VECTOR_NAME, SEMANTIC_VECTOR_SIZE } from "./types.ts";
