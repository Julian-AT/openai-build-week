import Foundation
import ARKit
@preconcurrency import AVFAudio
import CoreImage
import Observation
import ReRoomContracts
import ReRoomTransactionCore
import Security
import UIKit

struct RoomEditAssetCatalog: Codable, Equatable, Sendable {
    let schemaVersion: String
    let catalogID: String
    let license: String
    let provenanceFile: String
    let assets: [RoomEditCatalogAsset]

    func asset(id: String) -> RoomEditCatalogAsset? {
        assets.first { $0.assetID == id }
    }

    static func single(manifest: Phase3ProxyManifest) -> Self {
        Self(
            schemaVersion: "1.0.0",
            catalogID: "catalog_reroom_legacy_fixture_v1",
            license: "MIT",
            provenanceFile: manifest.provenanceFile,
            assets: [RoomEditCatalogAsset(
                assetID: manifest.contractAssetID,
                artifactID: manifest.artifactID,
                artifactRevision: manifest.artifactRevision,
                proxyID: manifest.proxyID,
                displayName: "Warm Arc Chair",
                category: "chair",
                styleTags: ["minimal"],
                colorTags: ["neutral"],
                sourceFile: manifest.sourceFile,
                sourceSHA256: manifest.sourceSHA256,
                nativeFile: manifest.sourceFile,
                nativeSHA256: manifest.sourceSHA256,
                canonicalManifestFile: manifest.canonicalManifestFile,
                canonicalManifestContentSHA256: manifest.artifactContentSHA256,
                collisionProxyPassed: manifest.collisionProxyPassed,
                assetLicensePassed: manifest.assetLicensePassed,
                artifactIntegrityPassed: manifest.artifactIntegrityPassed,
                boundsM: manifest.boundsM,
                modelEntityCount: Int(manifest.cubeCount),
                qualification: "hackathon_repo_owned_demo_proxy_only",
                gate011Status: manifest.gate011Status
            )]
        )
    }

    static func load(bundle: Bundle) throws -> Self {
        guard let catalogURL = bundle.url(forResource: "asset-catalog", withExtension: "json") else {
            throw RoomEditAssetCatalogError.missingCatalog
        }
        let data = try Data(contentsOf: catalogURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == Set(CodingKeys.allCases.map(\.rawValue)),
              let rawAssets = root["assets"] as? [[String: Any]],
              rawAssets.allSatisfy({ Set($0.keys) == Set(RoomEditCatalogAsset.CodingKeys.allCases.map(\.rawValue)) })
        else {
            throw RoomEditAssetCatalogError.invalidShape
        }

        let catalog = try JSONDecoder().decode(Self.self, from: data)
        let expectedIDs = [
            "asset_53000000-0000-4000-8000-000000000002",
            "asset_53000000-0000-4000-8000-000000000003",
            "asset_53000000-0000-4000-8000-000000000004",
        ]
        guard catalog.schemaVersion == "1.0.0",
              catalog.catalogID == "catalog_reroom_hackathon_curated_v1",
              catalog.license == "MIT",
              catalog.provenanceFile == "CON004-PROVENANCE.md",
              catalog.assets.map(\.assetID) == expectedIDs,
              Set(catalog.assets.map(\.assetID)).count == catalog.assets.count
        else {
            throw RoomEditAssetCatalogError.invalidCatalog
        }

        for asset in catalog.assets {
            try asset.validate(bundle: bundle)
        }
        return catalog
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case catalogID = "catalog_id"
        case license
        case provenanceFile = "provenance_file"
        case assets
    }
}

struct RoomEditCatalogAsset: Codable, Equatable, Identifiable, Sendable {
    let assetID: String
    let artifactID: String
    let artifactRevision: UInt64
    let proxyID: String
    let displayName: String
    let category: String
    let styleTags: [String]
    let colorTags: [String]
    let sourceFile: String
    let sourceSHA256: String
    let nativeFile: String
    let nativeSHA256: String
    let canonicalManifestFile: String
    let canonicalManifestContentSHA256: String
    let collisionProxyPassed: Bool
    let assetLicensePassed: Bool
    let artifactIntegrityPassed: Bool
    let boundsM: [Double]
    let modelEntityCount: Int
    let qualification: String
    let gate011Status: String

    var id: String { assetID }

    var sourceResourceName: String {
        URL(fileURLWithPath: sourceFile).deletingPathExtension().lastPathComponent
    }

    var nativeResourceName: String {
        URL(fileURLWithPath: nativeFile).deletingPathExtension().lastPathComponent
    }

    var artifactReference: ArtifactReference {
        ArtifactReference(
            artifactID: artifactID,
            artifactType: "asset_manifest",
            artifactRevision: artifactRevision,
            sha256: canonicalManifestContentSHA256
        )
    }

    var transactionManifest: Phase3ProxyManifest {
        Phase3ProxyManifest(
            schemaVersion: "1.0.0",
            proxyID: proxyID,
            contractAssetID: assetID,
            artifactID: artifactID,
            artifactType: "asset_manifest",
            artifactRevision: artifactRevision,
            artifactContentSHA256: canonicalManifestContentSHA256,
            canonicalManifestFile: canonicalManifestFile,
            collisionProxyPassed: collisionProxyPassed,
            assetLicensePassed: assetLicensePassed,
            artifactIntegrityPassed: artifactIntegrityPassed,
            sourceFile: sourceFile,
            sourceSHA256: sourceSHA256,
            provenanceFile: "PROVENANCE.md",
            generationRecipe: "repository_owned_literal_usda_primitives",
            qualification: qualification,
            units: "metres",
            upAxis: "Y",
            floorContactYM: 0,
            boundsM: boundsM,
            cubeCount: UInt64(modelEntityCount),
            assumptionStatus: "HYPOTHESIS",
            gate011Status: gate011Status
        )
    }

    fileprivate func validate(bundle: Bundle) throws {
        guard assetID.hasPrefix("asset_"),
              artifactID.hasPrefix("artifact_"),
              artifactRevision == 1,
              proxyID.hasPrefix("asset_proxy-"),
              !displayName.isEmpty,
              ["chair", "small_table"].contains(category),
              !styleTags.isEmpty,
              !colorTags.isEmpty,
              styleTags == styleTags.sorted(),
              colorTags == colorTags.sorted(),
              Set(styleTags).count == styleTags.count,
              Set(colorTags).count == colorTags.count,
              sourceFile.hasSuffix(".usda"),
              nativeFile.hasSuffix(".usdz"),
              sourceSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              nativeSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              canonicalManifestFile.hasSuffix(".asset-manifest.json"),
              canonicalManifestContentSHA256.range(
                  of: "^[0-9a-f]{64}$",
                  options: .regularExpression
              ) != nil,
              collisionProxyPassed,
              assetLicensePassed,
              artifactIntegrityPassed,
              boundsM.count == 3,
              boundsM.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 4 }),
              modelEntityCount > 0,
              modelEntityCount <= 16,
              qualification == "hackathon_repo_owned_demo_proxy_only",
              gate011Status == "PENDING",
              let sourceURL = bundle.url(forResource: sourceResourceName, withExtension: "usda"),
              sourceSHA256 == CanonicalJSON.sha256Hex(try Data(contentsOf: sourceURL)),
              let nativeURL = bundle.url(forResource: nativeResourceName, withExtension: "usdz"),
              nativeSHA256 == CanonicalJSON.sha256Hex(try Data(contentsOf: nativeURL)),
              let manifestURL = bundle.url(
                  forResource: URL(fileURLWithPath: canonicalManifestFile)
                      .deletingPathExtension().lastPathComponent,
                  withExtension: "json"
              )
        else {
            throw RoomEditAssetCatalogError.invalidAsset(assetID)
        }
        try RoomEditAssetManifestVerifier.verify(
            manifestData: Data(contentsOf: manifestURL),
            expectedAsset: self,
            bundle: bundle
        )
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case assetID = "asset_id"
        case artifactID = "artifact_id"
        case artifactRevision = "artifact_revision"
        case proxyID = "proxy_id"
        case displayName = "display_name"
        case category
        case styleTags = "style_tags"
        case colorTags = "color_tags"
        case sourceFile = "source_file"
        case sourceSHA256 = "source_sha256"
        case nativeFile = "native_file"
        case nativeSHA256 = "native_sha256"
        case canonicalManifestFile = "canonical_manifest_file"
        case canonicalManifestContentSHA256 = "canonical_manifest_sha256"
        case collisionProxyPassed = "collision_proxy_passed"
        case assetLicensePassed = "asset_license_passed"
        case artifactIntegrityPassed = "artifact_integrity_passed"
        case boundsM = "bounds_m"
        case modelEntityCount = "model_entity_count"
        case qualification
        case gate011Status = "gate_011_status"
    }
}

enum RoomEditAssetCatalogError: Error, Equatable {
    case missingCatalog
    case invalidShape
    case invalidCatalog
    case invalidAsset(String)
}

enum RoomEditAssetManifestError: Error, Equatable {
    case invalidShape
    case invalidContract
    case contentDigestMismatch
    case identityMismatch
    case metadataMismatch
    case missingPayload(String)
    case payloadMismatch(String)
}

enum RoomEditAssetManifestVerifier {
    private static let maximumManifestBytes = 256 * 1_024
    private static let editArtifactSchemaSHA256 =
        "58dbfc8f152881cbdc31be22f6ab7631ac474bb78537ac2a9254f5ef16bd598f"

    static func verifyContentDigest(
        manifestData: Data,
        expectedContentSHA256: String
    ) throws {
        let root = try strictRoot(manifestData)
        guard let declared = root["content_sha256"] as? String,
              declared == expectedContentSHA256
        else {
            throw RoomEditAssetManifestError.contentDigestMismatch
        }
        var unsigned = root
        unsigned.removeValue(forKey: "content_sha256")
        let serialized = try JSONSerialization.data(
            withJSONObject: unsigned,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let canonical = try CanonicalJSON.canonicalize(
            jsonData: serialized,
            maximumBytes: maximumManifestBytes,
            maximumDepth: 16
        )
        guard CanonicalJSON.sha256Hex(canonical) == declared else {
            throw RoomEditAssetManifestError.contentDigestMismatch
        }
    }

    static func verify(
        manifestData: Data,
        expectedAsset: RoomEditCatalogAsset,
        bundle: Bundle
    ) throws {
        try verifyContentDigest(
            manifestData: manifestData,
            expectedContentSHA256: expectedAsset.canonicalManifestContentSHA256
        )
        let validator = try contractValidator(bundle: bundle)
        guard validator.validate(ContractValidationRequest(
            schemaID: ContractSchemaIdentifier.editArtifacts.rawValue,
            schemaVersion: "1.0.0",
            schemaSHA256: editArtifactSchemaSHA256,
            documentData: manifestData
        )) == .accepted else {
            throw RoomEditAssetManifestError.invalidContract
        }

        let root = try strictRoot(manifestData)
        guard root["artifact_id"] as? String == expectedAsset.artifactID,
              (root["artifact_revision"] as? NSNumber)?.uint64Value
                == expectedAsset.artifactRevision,
              root["artifact_type"] as? String == "asset_manifest",
              root["asset_id"] as? String == expectedAsset.assetID
        else {
            throw RoomEditAssetManifestError.identityMismatch
        }
        guard root["display_name"] as? String == expectedAsset.displayName,
              root["readiness"] as? String == "degraded",
              doubleArray(root["canonical_dimensions_m"]) == expectedAsset.boundsM,
              let visualBounds = root["visual_bounds_m"] as? [String: Any],
              let minimum = doubleArray(visualBounds["minimum"]),
              let maximum = doubleArray(visualBounds["maximum"]),
              minimum.count == 3,
              maximum.count == 3,
              zip(minimum, maximum).allSatisfy({ $0.0 < $0.1 }),
              root["origin_convention"] as? String == "floor_center_y_up",
              root["forward_axis"] as? String == "minus_z",
              let provider = root["provider"] as? [String: Any],
              provider["provenance"] as? String == "deterministic_local",
              let source = root["source"] as? [String: Any],
              source["source_sha256"] as? String == expectedAsset.sourceSHA256,
              source["source_revision"] as? String
                == "sha256:\(expectedAsset.sourceSHA256)",
              let sourceURL = source["source_url"] as? String,
              sourceURL.hasPrefix("https://github.com/Julian-AT/openai-build-week/"),
              source["author"] as? String == "ReRoom contributors",
              let license = root["license"] as? [String: Any],
              license["spdx_or_terms"] as? String == "MIT",
              license["use_approved"] as? Bool == true,
              license["redistribution_allowed"] as? Bool == true,
              license["attribution_required"] as? Bool == false,
              license["attribution"] as? String == "",
              let approvalSHA256 = license["approval_evidence_sha256"] as? String,
              let evidenceSHA256 = root["validation_evidence_sha256"] as? String
        else {
            throw RoomEditAssetManifestError.metadataMismatch
        }

        let sourceData = try resourceData(
            relativePath: expectedAsset.sourceFile,
            bundle: bundle
        )
        let nativeData = try resourceData(
            relativePath: expectedAsset.nativeFile,
            bundle: bundle
        )
        let licenseData = try resourceData(
            relativePath: "ASSET-LICENSE.txt",
            bundle: bundle
        )
        let evidenceData = try resourceData(
            relativePath: "asset-validation-evidence.json",
            bundle: bundle
        )
        let provenanceData = try resourceData(
            relativePath: "CON004-PROVENANCE.md",
            bundle: bundle
        )
        guard CanonicalJSON.sha256Hex(sourceData) == expectedAsset.sourceSHA256,
              CanonicalJSON.sha256Hex(nativeData) == expectedAsset.nativeSHA256,
              CanonicalJSON.sha256Hex(licenseData) == approvalSHA256,
              CanonicalJSON.sha256Hex(evidenceData) == evidenceSHA256,
              let evidence = try JSONSerialization.jsonObject(with: evidenceData)
                as? [String: Any],
              evidence["gate_011_status"] as? String == "PENDING",
              evidence["qualification"] as? String
                == "AUTOMATED_LOCAL_FORMAT_AND_BUNDLE",
              evidence["provenance_sha256"] as? String
                == CanonicalJSON.sha256Hex(provenanceData)
        else {
            throw RoomEditAssetManifestError.metadataMismatch
        }

        let usdz = try payload(root["usdz"], named: "usdz", bundle: bundle)
        let glb = try payload(root["glb"], named: "glb", bundle: bundle)
        _ = try payload(root["collision"], named: "collision", bundle: bundle)
        guard let lods = root["lods"] as? [[String: Any]], !lods.isEmpty else {
            throw RoomEditAssetManifestError.invalidShape
        }
        for (index, lod) in lods.enumerated() {
            _ = try payload(lod, named: "lod-\(index)", bundle: bundle)
        }
        guard usdz.relativePath.hasSuffix(expectedAsset.nativeFile),
              usdz.sha256 == expectedAsset.nativeSHA256,
              usdz.data.starts(with: [0x50, 0x4b, 0x03, 0x04])
        else {
            throw RoomEditAssetManifestError.payloadMismatch("usdz")
        }
        try validateGLB(glb.data, named: "glb")
    }

    private static func strictRoot(_ data: Data) throws -> [String: Any] {
        guard data.count <= maximumManifestBytes,
              let canonical = try? CanonicalJSON.canonicalize(
                  jsonData: data,
                  maximumBytes: maximumManifestBytes,
                  maximumDepth: 16
              ),
              let root = try? JSONSerialization.jsonObject(with: canonical)
                as? [String: Any]
        else {
            throw RoomEditAssetManifestError.invalidShape
        }
        return root
    }

    private static func contractValidator(bundle: Bundle) throws -> ContractValidator {
        let resources: [(ContractSchemaIdentifier, String, String)] = [
            (.framePacket, "frame-packet", "d50b19bfb29c6c62c494e3a47deb3c51a933609698f4ff2f9cbfba6ec4252b43"),
            (.rrcapManifest, "rrcap-manifest", "c97349820ed66fb1a1fdf60ea9afee312f532811602851d01d1e233641730b87"),
            (.sceneState, "scene-state", "9c77d27762e20ff5fad24c438e8817a03c770b55be3fc82ea72097c4c273e440"),
            (.editArtifacts, "edit-artifacts", editArtifactSchemaSHA256),
            (.transaction, "transaction", "2a4f6728978db0879b5dfb10f052f6d5280e5cf83ad5600f0cf959626c2399a2"),
        ]
        return try ContractValidator(registrations: resources.map { identifier, name, digest in
            guard let url = bundle.url(
                forResource: "\(name).schema",
                withExtension: "json"
            ) else {
                throw RoomEditAssetManifestError.missingPayload("\(name).schema.json")
            }
            return ContractSchemaRegistration(
                identifier: identifier,
                version: "1.0.0",
                sha256: digest,
                schemaData: try Data(contentsOf: url)
            )
        })
    }

    private static func doubleArray(_ value: Any?) -> [Double]? {
        guard let values = value as? [NSNumber] else { return nil }
        return values.map(\.doubleValue)
    }

    private static func resourceData(
        relativePath: String,
        bundle: Bundle
    ) throws -> Data {
        let url = URL(fileURLWithPath: relativePath)
        let resource = url.deletingPathExtension().lastPathComponent
        let extensionName = url.pathExtension
        guard let resourceURL = bundle.url(
            forResource: resource,
            withExtension: extensionName
        ) else {
            throw RoomEditAssetManifestError.missingPayload(relativePath)
        }
        return try Data(contentsOf: resourceURL)
    }

    private struct VerifiedPayload {
        let relativePath: String
        let sha256: String
        let data: Data
    }

    private static func payload(
        _ value: Any?,
        named name: String,
        bundle: Bundle
    ) throws -> VerifiedPayload {
        guard let value = value as? [String: Any],
              let relativePath = value["relative_path"] as? String,
              let byteLength = (value["byte_length"] as? NSNumber)?.intValue,
              let sha256 = value["sha256"] as? String
        else {
            throw RoomEditAssetManifestError.invalidShape
        }
        let data = try resourceData(relativePath: relativePath, bundle: bundle)
        guard data.count == byteLength,
              CanonicalJSON.sha256Hex(data) == sha256
        else {
            throw RoomEditAssetManifestError.payloadMismatch(name)
        }
        if value["codec"] as? String == "glb2" {
            try validateGLB(data, named: name)
        }
        return VerifiedPayload(
            relativePath: relativePath,
            sha256: sha256,
            data: data
        )
    }

    private static func validateGLB(_ data: Data, named name: String) throws {
        guard data.count >= 20 else {
            throw RoomEditAssetManifestError.payloadMismatch(name)
        }
        let bytes = [UInt8](data.prefix(12))
        let uint32: (Int) -> UInt32 = { offset in
            UInt32(bytes[offset])
                | (UInt32(bytes[offset + 1]) << 8)
                | (UInt32(bytes[offset + 2]) << 16)
                | (UInt32(bytes[offset + 3]) << 24)
        }
        guard uint32(0) == 0x46546c67,
              uint32(4) == 2,
              uint32(8) == UInt32(data.count)
        else {
            throw RoomEditAssetManifestError.payloadMismatch(name)
        }
    }
}

enum DesignCopilotIngressSource: String, Codable, CaseIterable, Sendable {
    case typed
    case vision
    case voice

    var intentIngressSource: IntentIngressSource {
        self == .voice ? .voice : .typed
    }
}

struct DesignCopilotRequestContext: Codable, Equatable, Sendable {
    let sessionID: String
    let revisionBranchID: String
    let baseSceneRevision: UInt64
    let worldFrameID: String
    let worldFrameVersion: UInt64
    let selectedObjectID: String?

    init(scene: SceneState, targetContext: TargetContext?) {
        sessionID = scene.sessionID
        revisionBranchID = scene.revisionAuthority.revisionBranchID
        baseSceneRevision = scene.sceneRevision
        worldFrameID = scene.worldFrame.worldFrameID
        worldFrameVersion = scene.worldFrame.worldFrameVersion
        selectedObjectID = targetContext?.selectedObjectID
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(revisionBranchID, forKey: .revisionBranchID)
        try container.encode(baseSceneRevision, forKey: .baseSceneRevision)
        try container.encode(worldFrameID, forKey: .worldFrameID)
        try container.encode(worldFrameVersion, forKey: .worldFrameVersion)
        // CON-006 requires an explicit null when there is no selected target.
        try container.encode(selectedObjectID, forKey: .selectedObjectID)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case sessionID = "session_id"
        case revisionBranchID = "revision_branch_id"
        case baseSceneRevision = "base_scene_revision"
        case worldFrameID = "world_frame_id"
        case worldFrameVersion = "world_frame_version"
        case selectedObjectID = "selected_object_id"
    }
}

struct DesignCopilotProposalRequest: Codable, Equatable, Sendable {
    let prompt: String
    let imageDataURL: String?
    let ingressSource: DesignCopilotIngressSource
    let requestContext: DesignCopilotRequestContext

    enum CodingKeys: String, CodingKey {
        case prompt
        case imageDataURL = "image_data_url"
        case ingressSource = "ingress_source"
        case requestContext = "request_context"
    }
}

enum SemanticProposalStatus: String, Codable, Sendable {
    case ready
    case needsClarification = "needs_clarification"
}

struct SemanticProposalEnvelope: Codable, Equatable, Sendable {
    let schemaVersion: String
    let envelopeID: String
    let createdAtUTC: String
    let requestContext: DesignCopilotRequestContext
    let ingressSource: DesignCopilotIngressSource
    let semanticModel: SemanticModelReference
    let status: SemanticProposalStatus
    let intent: SemanticProposalIntent?
    let explanation: String
    let clarification: String?

    static let maximumEnvelopeBytes = 64 * 1_024

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(envelopeID, forKey: .envelopeID)
        try container.encode(createdAtUTC, forKey: .createdAtUTC)
        try container.encode(requestContext, forKey: .requestContext)
        try container.encode(ingressSource, forKey: .ingressSource)
        try container.encode(semanticModel, forKey: .semanticModel)
        try container.encode(status, forKey: .status)
        // Structured Outputs requires both nullable members to remain present.
        try container.encode(intent, forKey: .intent)
        try container.encode(explanation, forKey: .explanation)
        try container.encode(clarification, forKey: .clarification)
    }

    static func decodeStrict(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= maximumEnvelopeBytes else {
            throw SemanticProposalRejection.invalidEnvelope
        }
        let canonical: Data
        do {
            canonical = try CanonicalJSON.canonicalize(
                jsonData: data,
                maximumBytes: maximumEnvelopeBytes,
                maximumDepth: 12
            )
        } catch {
            throw SemanticProposalRejection.invalidEnvelope
        }
        guard let root = try? JSONSerialization.jsonObject(with: canonical) as? [String: Any],
              Set(root.keys) == Set(CodingKeys.allCases.map(\.rawValue)),
              hasExactKeys(root["request_context"], keys: DesignCopilotRequestContext.CodingKeys.allCases.map(\.rawValue)),
              hasExactKeys(root["semantic_model"], keys: ["provider", "model", "response_id"])
        else {
            throw SemanticProposalRejection.invalidShape
        }
        if let intent = root["intent"], !(intent is NSNull) {
            guard let intentObject = intent as? [String: Any],
                  Set(intentObject.keys) == ["operation", "arguments", "constraints"],
                  let arguments = intentObject["arguments"] as? [String: Any],
                  Set(arguments.keys).isSubset(of: ["asset_id"]),
                  let constraints = intentObject["constraints"] as? [[String: Any]],
                  constraints.allSatisfy({ Set($0.keys) == ["kind", "value"] })
            else {
                throw SemanticProposalRejection.invalidShape
            }
        }
        let envelope: Self
        do {
            envelope = try JSONDecoder().decode(Self.self, from: canonical)
        } catch {
            throw SemanticProposalRejection.invalidEnvelope
        }
        try envelope.validateSemantics()
        return envelope
    }

    func bind(
        expectedContext: DesignCopilotRequestContext,
        trustedContext: TrustedIntentContext,
        currentScene: SceneState,
        catalog: RoomEditAssetCatalog
    ) throws -> BoundProposal? {
        guard requestContext == expectedContext,
              expectedContext == DesignCopilotRequestContext(
                  scene: currentScene,
                  targetContext: trustedContext.targetContext
              ),
              trustedContext.sessionID == currentScene.sessionID,
              trustedContext.revisionAuthority == currentScene.revisionAuthority,
              trustedContext.baseSceneRevision == currentScene.sceneRevision
        else {
            throw SemanticProposalRejection.staleContext
        }
        guard status == .ready, let intent else { return nil }
        if let assetID = intent.arguments.assetID,
           catalog.asset(id: assetID) == nil {
            throw SemanticProposalRejection.unknownAsset
        }
        let bytes: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            bytes = try encoder.encode(intent)
        } catch {
            throw SemanticProposalRejection.invalidIntent
        }
        do {
            return try IntentBoundary.submitUserIntent(
                bytes,
                source: ingressSource.intentIngressSource,
                trustedContext: trustedContext,
                currentScene: currentScene,
                semanticModel: semanticModel
            )
        } catch {
            throw SemanticProposalRejection.invalidIntent
        }
    }

    private func validateSemantics() throws {
        guard schemaVersion == "1.0.0",
              Self.matchesStableID(envelopeID, prefix: "envelope"),
              Self.isRFC3339DateTime(createdAtUTC),
              Self.matchesStableID(requestContext.sessionID, prefix: "session"),
              Self.matchesStableID(requestContext.revisionBranchID, prefix: "branch"),
              Self.matchesStableID(requestContext.worldFrameID, prefix: "world"),
              requestContext.worldFrameVersion > 0,
              requestContext.selectedObjectID.map({ Self.matchesStableID($0, prefix: "object") }) ?? true,
              semanticModel.provider == "openai",
              semanticModel.model == "gpt-5.6-sol",
              Self.isSafeToken(semanticModel.responseID, maximum: 128),
              Self.isSafeCopy(explanation, maximum: 280)
        else {
            throw SemanticProposalRejection.invalidEnvelope
        }
        switch status {
        case .ready:
            guard intent != nil, clarification == nil else {
                throw SemanticProposalRejection.invalidEnvelope
            }
        case .needsClarification:
            guard intent == nil,
                  let clarification,
                  Self.isSafeCopy(clarification, maximum: 280)
            else {
                throw SemanticProposalRejection.invalidEnvelope
            }
        }
    }

    private static func hasExactKeys(_ value: Any?, keys: [String]) -> Bool {
        guard let object = value as? [String: Any] else { return false }
        return Set(object.keys) == Set(keys)
    }

    private static func matchesStableID(_ value: String, prefix: String) -> Bool {
        value.range(
            of: "^\(prefix)_[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
            options: .regularExpression
        ) != nil
    }

    private static func isSafeToken(_ value: String, maximum: Int) -> Bool {
        guard !value.isEmpty, value.count <= maximum else { return false }
        return value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_")
        }
    }

    private static func isRFC3339DateTime(_ value: String) -> Bool {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if fractional.date(from: value) != nil { return true }
        return ISO8601DateFormatter().date(from: value) != nil
    }

    private static func isSafeCopy(_ value: String, maximum: Int) -> Bool {
        guard !value.isEmpty,
              value.count <= maximum,
              !value.contains("\r"),
              !value.contains("\n")
        else { return false }
        return value.range(
            of: "(?:[A-Za-z][A-Za-z0-9+.-]*://|www\\.)",
            options: .regularExpression
        ) == nil
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case envelopeID = "envelope_id"
        case createdAtUTC = "created_at_utc"
        case requestContext = "request_context"
        case ingressSource = "ingress_source"
        case semanticModel = "semantic_model"
        case status
        case intent
        case explanation
        case clarification
    }
}

struct SemanticProposalIntent: Codable, Equatable, Sendable {
    let operation: ProductOperation
    let arguments: IntentArguments
    let constraints: [TypedConstraint]
}

enum SemanticProposalRejection: String, Error, Equatable, Sendable {
    case invalidEnvelope = "invalid_envelope"
    case invalidShape = "invalid_shape"
    case staleContext = "stale_context"
    case unknownAsset = "unknown_asset"
    case invalidIntent = "invalid_intent"
    case previewAlreadyActive = "preview_already_active"
}

struct DesignCopilotGatewayClient: Sendable {
    let baseURL: URL
    private let bearerToken: String
    private let session: URLSession

    init(baseURL: URL, bearerToken: String, session: URLSession = .shared) throws {
        guard Self.isAllowedBaseURL(baseURL),
              !bearerToken.isEmpty,
              bearerToken.utf8.count <= 512
        else {
            throw DesignCopilotGatewayError.invalidConfiguration
        }
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.session = session
    }

    static func isAllowedBaseURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.percentEncodedQuery == nil,
              components.fragment == nil,
              components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/"
        else { return false }

        if scheme == "https" { return true }
        return scheme == "http" && isLocalNetworkHost(host)
    }

    private static func isLocalNetworkHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") || host == "::1" {
            return true
        }
        if host.contains(":")
            && (host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd")) {
            return true
        }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        let values = octets.compactMap { UInt8($0) }
        guard octets.count == 4, values.count == 4 else { return false }
        return values[0] == 10
            || values[0] == 127
            || (values[0] == 169 && values[1] == 254)
            || (values[0] == 192 && values[1] == 168)
            || (values[0] == 172 && (16...31).contains(values[1]))
    }

    func propose(_ proposal: DesignCopilotProposalRequest) async throws -> SemanticProposalEnvelope {
        var request = URLRequest(url: baseURL.appending(path: "v1/proposals"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        request.httpBody = try encoder.encode(proposal)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw DesignCopilotGatewayError.transport
        }
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              http.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/json") == true,
              data.count <= SemanticProposalEnvelope.maximumEnvelopeBytes
        else {
            throw DesignCopilotGatewayError.rejected
        }
        return try SemanticProposalEnvelope.decodeStrict(data)
    }

    func createRealtimeClientSecret() async throws -> RealtimeClientSecret {
        var request = URLRequest(url: baseURL.appending(path: "v1/realtime/client-secret"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw DesignCopilotGatewayError.transport
        }
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              http.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/json") == true
        else {
            throw DesignCopilotGatewayError.rejected
        }
        return try RealtimeClientSecret.decodeStrict(data)
    }
}

enum DesignCopilotGatewayError: Error, Equatable {
    case invalidConfiguration
    case transport
    case rejected
}

typealias DesignCopilotGatewayTokenProvider = @MainActor @Sendable () throws -> String?
typealias DesignCopilotProposalProvider = @MainActor @Sendable (
    URL,
    String,
    DesignCopilotProposalRequest
) async throws -> SemanticProposalEnvelope
typealias DesignCopilotMicrophonePermissionProvider = @MainActor @Sendable () async -> Bool
typealias DesignCopilotRealtimeSecretProvider = @MainActor @Sendable (
    URL,
    String
) async throws -> RealtimeClientSecret

struct DesignCopilotRealtimeCallbacks: Sendable {
    let onTranscript: @Sendable (String) async -> Void
    let onFailure: @Sendable () async -> Void
}

typealias DesignCopilotRealtimeSessionFactory = @MainActor @Sendable (
    RealtimeClientSecret,
    DesignCopilotRealtimeCallbacks
) -> DesignCopilotRealtimeSession

struct RealtimeClientSecret: Codable, Equatable, Sendable {
    let value: String
    let expiresAt: Int64
    let session: RealtimeClientSession

    var isUsable: Bool {
        expiresAt > Int64(Date().timeIntervalSince1970) + 5
    }

    static func decodeStrict(
        _ data: Data,
        nowEpochSeconds: Int64 = Int64(Date().timeIntervalSince1970)
    ) throws -> Self {
        guard data.count <= 8_192,
              nowEpochSeconds >= 0,
              nowEpochSeconds <= Int64.max - 660,
              let canonical = try? CanonicalJSON.canonicalize(
                  jsonData: data,
                  maximumBytes: 8_192,
                  maximumDepth: 4
              ),
              let root = try? JSONSerialization.jsonObject(with: canonical) as? [String: Any],
              Set(root.keys) == ["value", "expires_at", "session"],
              let session = root["session"] as? [String: Any],
              Set(session.keys) == ["id", "model"]
        else {
            throw DesignCopilotGatewayError.rejected
        }
        let value = try JSONDecoder().decode(Self.self, from: canonical)
        guard value.value.range(
                  of: "^ek_[A-Za-z0-9_-]{1,512}$",
                  options: .regularExpression
              ) != nil,
              value.expiresAt > nowEpochSeconds + 5,
              value.expiresAt <= nowEpochSeconds + 660,
              value.session.id.range(
                  of: "^sess_[A-Za-z0-9_-]{1,123}$",
                  options: .regularExpression
              ) != nil,
              value.session.model == "gpt-realtime-2.1"
        else {
            throw DesignCopilotGatewayError.rejected
        }
        return value
    }

    enum CodingKeys: String, CodingKey {
        case value
        case expiresAt = "expires_at"
        case session
    }
}

struct RealtimeClientSession: Codable, Equatable, Sendable {
    let id: String
    let model: String
}

enum DesignCopilotCredentialStore {
    private static let service = "com.reroom.design-copilot"
    private static let account = "gateway-bearer-token"

    static func saveGatewayToken(_ token: String) throws {
        guard !token.isEmpty, token.utf8.count <= 512 else {
            throw DesignCopilotCredentialError.invalidToken
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = Data(token.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
            throw DesignCopilotCredentialError.keychainFailure
        }
    }

    static func gatewayToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else {
            throw DesignCopilotCredentialError.keychainFailure
        }
        return token
    }
}

enum DesignCopilotCredentialError: Error {
    case invalidToken
    case keychainFailure
}

protocol DesignCopilotRealtimeSocket: Sendable {
    func resume()
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func cancel()
}

private final class URLSessionDesignCopilotRealtimeSocket: @unchecked Sendable, DesignCopilotRealtimeSocket {
    private let task: URLSessionWebSocketTask

    init(request: URLRequest) {
        task = URLSession.shared.webSocketTask(with: request)
    }

    func resume() {
        task.resume()
    }

    func send(_ data: Data) async throws {
        try await task.send(.data(data))
    }

    func receive() async throws -> Data {
        switch try await task.receive() {
        case .data(let data):
            return data
        case .string(let text):
            return Data(text.utf8)
        @unknown default:
            throw DesignCopilotRealtimeError.invalidState
        }
    }

    func cancel() {
        task.cancel(with: .goingAway, reason: nil)
    }
}

actor DesignCopilotRealtimeSession {
    static let maximumInboundEventBytes = 32_768
    private let secret: RealtimeClientSecret
    private let onTranscript: @Sendable (String) async -> Void
    private let onFailure: @Sendable () async -> Void
    private let audioCapture: RealtimeAudioCapture
    private let socketFactory: @Sendable (URLRequest) -> any DesignCopilotRealtimeSocket
    private let sendTimeoutNanoseconds: UInt64
    private let transcriptTimeoutNanoseconds: UInt64
    private let maximumSessionNanoseconds: UInt64
    private var socket: (any DesignCopilotRealtimeSocket)?
    private var audioContinuation: AsyncStream<Data>.Continuation?
    private var audioSender: Task<Void, Never>?
    private var receiver: Task<Void, Never>?
    private var sessionDeadline: Task<Void, Never>?
    private var transcriptDeadline: Task<Void, Never>?
    private var inputFinished = false
    private var closed = false

    init(
        secret: RealtimeClientSecret,
        audioCapture: RealtimeAudioCapture = RealtimeAudioCapture(),
        socketFactory: @escaping @Sendable (URLRequest) -> any DesignCopilotRealtimeSocket = {
            URLSessionDesignCopilotRealtimeSocket(request: $0)
        },
        sendTimeoutNanoseconds: UInt64 = 15_000_000_000,
        transcriptTimeoutNanoseconds: UInt64 = 20_000_000_000,
        maximumSessionNanoseconds: UInt64 = 595_000_000_000,
        onTranscript: @escaping @Sendable (String) async -> Void,
        onFailure: @escaping @Sendable () async -> Void
    ) {
        self.secret = secret
        self.audioCapture = audioCapture
        self.socketFactory = socketFactory
        self.sendTimeoutNanoseconds = sendTimeoutNanoseconds
        self.transcriptTimeoutNanoseconds = transcriptTimeoutNanoseconds
        self.maximumSessionNanoseconds = maximumSessionNanoseconds
        self.onTranscript = onTranscript
        self.onFailure = onFailure
    }

    func start() async throws {
        guard secret.isUsable,
              let url = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1")
        else {
            throw DesignCopilotRealtimeError.expiredCredential
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(secret.value)", forHTTPHeaderField: "Authorization")
        guard sendTimeoutNanoseconds > 0,
              transcriptTimeoutNanoseconds > 0,
              maximumSessionNanoseconds > 0
        else { throw DesignCopilotRealtimeError.invalidState }
        let socket = socketFactory(request)
        self.socket = socket
        socket.resume()
        let now = Int64(Date().timeIntervalSince1970)
        let remainingSeconds = max(1, secret.expiresAt - now - 5)
        let credentialNanoseconds = UInt64(remainingSeconds) * 1_000_000_000
        scheduleSessionDeadline(after: min(maximumSessionNanoseconds, credentialNanoseconds))

        let (stream, continuation) = AsyncStream<Data>.makeStream(
            bufferingPolicy: .bufferingOldest(64)
        )
        audioContinuation = continuation
        audioSender = Task { [weak self] in
            for await bytes in stream {
                guard let self else { return }
                do {
                    try await self.sendJSON([
                        "type": "input_audio_buffer.append",
                        "audio": bytes.base64EncodedString(),
                    ])
                } catch {
                    await self.failAndClose()
                    return
                }
            }
        }
        receiver = Task { [weak self] in
            await self?.receiveLoop()
        }
        do {
            try audioCapture.start { bytes in
                if case .dropped = continuation.yield(bytes) {
                    Task { [weak self] in
                        await self?.failAndClose()
                    }
                }
            }
        } catch {
            await failAndClose()
            throw DesignCopilotRealtimeError.audioUnavailable
        }
    }

    func finishInput() async throws {
        guard !closed, !inputFinished, socket != nil else {
            throw DesignCopilotRealtimeError.invalidState
        }
        inputFinished = true
        audioCapture.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        await audioSender?.value
        audioSender = nil
        try await sendJSON(["type": "input_audio_buffer.commit"])
        guard !closed else { throw DesignCopilotRealtimeError.invalidState }
        scheduleTranscriptDeadline()
    }

    func cancel() {
        guard !closed else { return }
        closed = true
        closeResources()
    }

    static func event(from data: Data) -> DesignCopilotRealtimeEvent {
        guard !data.isEmpty,
              data.count <= maximumInboundEventBytes,
              let canonical = try? CanonicalJSON.canonicalize(
                  jsonData: data,
                  maximumBytes: maximumInboundEventBytes,
                  maximumDepth: 8
              ),
              let object = try? JSONSerialization.jsonObject(with: canonical) as? [String: Any],
              let type = object["type"] as? String
        else { return .invalid }

        switch type {
        case "conversation.item.input_audio_transcription.completed":
            guard Set(object.keys) == ["type", "transcript"],
                  let transcript = object["transcript"] as? String
            else { return .invalid }
            let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty,
                  normalized.count <= 2_000,
                  normalized == transcript
            else { return .invalid }
            return .transcript(normalized)
        case "error":
            return .providerError
        default:
            return .ignored
        }
    }

    private func receiveLoop() async {
        guard let socket else { return }
        do {
            while !Task.isCancelled {
                let data = try await socket.receive()
                switch Self.event(from: data) {
                case .transcript(let transcript):
                    guard !closed else { return }
                    closed = true
                    closeResources()
                    await onTranscript(transcript)
                    return
                case .providerError, .invalid:
                    await failAndClose()
                    return
                case .ignored:
                    continue
                }
            }
        } catch {
            if !Task.isCancelled {
                await failAndClose()
            }
        }
    }

    private func sendJSON(_ value: [String: Any]) async throws {
        guard !closed, let socket else { throw DesignCopilotRealtimeError.invalidState }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard data.count <= 2_000_000 else { throw DesignCopilotRealtimeError.invalidState }
        let timeoutNanoseconds = sendTimeoutNanoseconds
        let deadline = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
            } catch {
                return
            }
            await self?.failAndClose()
        }
        defer { deadline.cancel() }
        try await socket.send(data)
        guard !closed else { throw DesignCopilotRealtimeError.invalidState }
    }

    private func failAndClose() async {
        guard !closed else { return }
        closed = true
        closeResources()
        await onFailure()
    }

    private func scheduleSessionDeadline(after nanoseconds: UInt64) {
        sessionDeadline?.cancel()
        sessionDeadline = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            await self?.failAndClose()
        }
    }

    private func scheduleTranscriptDeadline() {
        transcriptDeadline?.cancel()
        let timeoutNanoseconds = transcriptTimeoutNanoseconds
        transcriptDeadline = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
            } catch {
                return
            }
            await self.failAndClose()
        }
    }

    private func closeResources() {
        sessionDeadline?.cancel()
        sessionDeadline = nil
        transcriptDeadline?.cancel()
        transcriptDeadline = nil
        audioCapture.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        audioSender?.cancel()
        audioSender = nil
        receiver?.cancel()
        receiver = nil
        socket?.cancel()
        socket = nil
    }
}

enum DesignCopilotRealtimeEvent: Equatable, Sendable {
    case transcript(String)
    case providerError
    case ignored
    case invalid
}

protocol RealtimeAudioCaptureBackend: Sendable {
    func activateSession() throws
    func installTap(yield: @escaping @Sendable (Data) -> Void) throws
    func startEngine() throws
    func stopEngine()
    func removeTap()
    func deactivateSession()
}

final class RealtimeAudioCapture: @unchecked Sendable {
    private let backend: any RealtimeAudioCaptureBackend
    private let lock = NSLock()
    private var sessionActive = false
    private var tapInstalled = false
    private var engineStarted = false

    init(backend: any RealtimeAudioCaptureBackend = AVAudioRealtimeCaptureBackend()) {
        self.backend = backend
    }

    func start(yield: @escaping @Sendable (Data) -> Void) throws {
        try lock.withLock {
            guard !sessionActive, !tapInstalled, !engineStarted else {
                throw DesignCopilotRealtimeError.invalidState
            }
            do {
                try backend.activateSession()
                sessionActive = true
                try backend.installTap(yield: yield)
                tapInstalled = true
                try backend.startEngine()
                engineStarted = true
            } catch {
                cleanupLocked()
                throw DesignCopilotRealtimeError.audioUnavailable
            }
        }
    }

    func stop() {
        lock.withLock {
            cleanupLocked()
        }
    }

    private func cleanupLocked() {
        if engineStarted {
            backend.stopEngine()
            engineStarted = false
        }
        if tapInstalled {
            backend.removeTap()
            tapInstalled = false
        }
        if sessionActive {
            backend.deactivateSession()
            sessionActive = false
        }
    }
}

private final class AVAudioRealtimeCaptureBackend: @unchecked Sendable, RealtimeAudioCaptureBackend {
    private let engine = AVAudioEngine()

    func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true)
    }

    func installTap(yield: @escaping @Sendable (Data) -> Void) throws {
        let input = engine.inputNode
        let sourceFormat = input.outputFormat(forBus: 0)
        guard sourceFormat.sampleRate > 0,
              let destinationFormat = AVAudioFormat(
                  commonFormat: .pcmFormatInt16,
                  sampleRate: 24_000,
                  channels: 1,
                  interleaved: false
              ),
              let converter = AVAudioConverter(from: sourceFormat, to: destinationFormat)
        else {
            throw DesignCopilotRealtimeError.audioUnavailable
        }
        input.installTap(onBus: 0, bufferSize: 2_048, format: sourceFormat) { buffer, _ in
            guard let data = Self.convert(
                buffer,
                converter: converter,
                destinationFormat: destinationFormat
            ) else { return }
            yield(data)
        }
    }

    func startEngine() throws {
        engine.prepare()
        try engine.start()
    }

    func stopEngine() {
        engine.stop()
    }

    func removeTap() {
        engine.inputNode.removeTap(onBus: 0)
    }

    func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private static func convert(
        _ input: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        destinationFormat: AVAudioFormat
    ) -> Data? {
        let ratio = destinationFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio) + 32)
        guard let output = AVAudioPCMBuffer(pcmFormat: destinationFormat, frameCapacity: capacity) else {
            return nil
        }
        let inputBox = ConverterInputBox(input)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            guard let input = inputBox.take() else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputStatus.pointee = .haveData
            return input
        }
        guard conversionError == nil,
              status != .error,
              output.frameLength > 0,
              let samples = output.int16ChannelData?[0]
        else { return nil }
        return Data(bytes: samples, count: Int(output.frameLength) * MemoryLayout<Int16>.size)
    }

    private final class ConverterInputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var input: AVAudioPCMBuffer?

        init(_ input: AVAudioPCMBuffer) {
            self.input = input
        }

        func take() -> AVAudioPCMBuffer? {
            lock.withLock {
                defer { input = nil }
                return input
            }
        }
    }
}

enum DesignCopilotRealtimeError: Error {
    case expiredCredential
    case audioUnavailable
    case invalidState
}

@MainActor
enum DesignCopilotFrameEncoder {
    static let maximumJPEGBytes = 1_500_000
    static let maximumLongEdge = 1_280

    static func jpegDataURL(frame: ARFrame) throws -> String {
        let image = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
        let extent = image.extent.integral
        guard extent.width > 0,
              extent.height > 0,
              let cgImage = CIContext(options: [.cacheIntermediates: false]).createCGImage(image, from: extent)
        else {
            throw DesignCopilotFrameError.encodingFailed
        }
        let original = UIImage(cgImage: cgImage)
        let longEdge = max(original.size.width, original.size.height)
        let scale = min(1, CGFloat(maximumLongEdge) / longEdge)
        let size = CGSize(
            width: max(1, floor(original.size.width * scale)),
            height: max(1, floor(original.size.height * scale))
        )
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in
            original.draw(in: CGRect(origin: .zero, size: size))
        }
        for quality in [0.72, 0.58, 0.44] {
            guard let data = rendered.jpegData(compressionQuality: quality) else { continue }
            if data.count <= maximumJPEGBytes,
               data.starts(with: [0xff, 0xd8]),
               data.suffix(2) == Data([0xff, 0xd9]) {
                return "data:image/jpeg;base64,\(data.base64EncodedString())"
            }
        }
        throw DesignCopilotFrameError.encodingFailed
    }
}

enum DesignCopilotFrameError: Error {
    case encodingFailed
}

@MainActor
@Observable
final class DesignCopilotModel {
    static let gatewayURLDefaultsKey = "reroom.design-copilot.gateway-url"

    var prompt = "Make this corner feel warmer and more intentional"
    var includeCurrentFrame = false
    var frameConsentGranted = false
    var gatewayURLText: String
    var pendingGatewayToken = ""
    private(set) var isWorking = false
    private(set) var hasSavedGatewayToken = false
    private(set) var envelope: SemanticProposalEnvelope?
    private(set) var message = "Offline editing stays available; AI only proposes."
    private(set) var isVoiceActive = false
    private(set) var isAwaitingTranscript = false

    @ObservationIgnored private let runtime: RoomEditRuntime
    @ObservationIgnored private let gatewayTokenProvider: DesignCopilotGatewayTokenProvider
    @ObservationIgnored private let proposalProvider: DesignCopilotProposalProvider
    @ObservationIgnored private let microphonePermissionProvider: DesignCopilotMicrophonePermissionProvider
    @ObservationIgnored private let realtimeSecretProvider: DesignCopilotRealtimeSecretProvider
    @ObservationIgnored private let realtimeSessionFactory: DesignCopilotRealtimeSessionFactory
    @ObservationIgnored private var realtimeSession: DesignCopilotRealtimeSession?
    @ObservationIgnored private var voiceAttemptCounter: UInt64 = 0
    @ObservationIgnored private var currentVoiceAttemptID: UInt64?

    init(
        runtime: RoomEditRuntime,
        defaults: UserDefaults = .standard,
        gatewayTokenProvider: @escaping DesignCopilotGatewayTokenProvider = {
            try DesignCopilotCredentialStore.gatewayToken()
        },
        proposalProvider: @escaping DesignCopilotProposalProvider = { baseURL, token, request in
            let client = try DesignCopilotGatewayClient(baseURL: baseURL, bearerToken: token)
            return try await client.propose(request)
        },
        microphonePermissionProvider: @escaping DesignCopilotMicrophonePermissionProvider = {
            await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        },
        realtimeSecretProvider: @escaping DesignCopilotRealtimeSecretProvider = { baseURL, token in
            let client = try DesignCopilotGatewayClient(baseURL: baseURL, bearerToken: token)
            return try await client.createRealtimeClientSecret()
        },
        realtimeSessionFactory: @escaping DesignCopilotRealtimeSessionFactory = { secret, callbacks in
            DesignCopilotRealtimeSession(
                secret: secret,
                onTranscript: callbacks.onTranscript,
                onFailure: callbacks.onFailure
            )
        }
    ) {
        self.runtime = runtime
        self.gatewayTokenProvider = gatewayTokenProvider
        self.proposalProvider = proposalProvider
        self.microphonePermissionProvider = microphonePermissionProvider
        self.realtimeSecretProvider = realtimeSecretProvider
        self.realtimeSessionFactory = realtimeSessionFactory
        gatewayURLText = defaults.string(forKey: Self.gatewayURLDefaultsKey)
            ?? "http://127.0.0.1:8787/"
        hasSavedGatewayToken = (try? gatewayTokenProvider()) != nil
    }

    var proposedAsset: RoomEditCatalogAsset? {
        guard let assetID = envelope?.intent?.arguments.assetID else { return nil }
        return runtime.catalog.asset(id: assetID)
    }

    var canApplyProposal: Bool {
        envelope?.status == .ready
            && !isWorking
            && !isVoiceActive
            && !isAwaitingTranscript
            && !runtime.model.hasActivePreview
    }

    var canAsk: Bool {
        !isWorking
            && !isVoiceActive
            && !isAwaitingTranscript
            && !runtime.model.previewTransitionInFlight
    }

    func saveGatewaySettings(defaults: UserDefaults = .standard) {
        let trimmedURL = gatewayURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              DesignCopilotGatewayClient.isAllowedBaseURL(url)
        else {
            message = "Use an HTTPS root URL or a root-only local HTTP gateway URL."
            return
        }
        do {
            if !pendingGatewayToken.isEmpty {
                try DesignCopilotCredentialStore.saveGatewayToken(pendingGatewayToken)
                pendingGatewayToken = ""
            }
            guard try DesignCopilotCredentialStore.gatewayToken() != nil else {
                message = "Add the gateway bearer token."
                return
            }
            gatewayURLText = url.absoluteString
            defaults.set(gatewayURLText, forKey: Self.gatewayURLDefaultsKey)
            hasSavedGatewayToken = true
            message = "Gateway settings saved locally; no OpenAI API key is stored on iPhone."
        } catch {
            message = "The gateway token could not be stored in Keychain."
        }
    }

    func ask() async {
        await ask(ingressOverride: nil)
    }

    func startVoice() async {
        guard !isWorking, !isVoiceActive, !isAwaitingTranscript else { return }
        voiceAttemptCounter &+= 1
        let attemptID = voiceAttemptCounter
        currentVoiceAttemptID = attemptID
        isWorking = true
        message = "Requesting microphone access for one push-to-talk turn…"
        defer {
            if currentVoiceAttemptID == attemptID {
                isWorking = false
            }
        }
        let microphoneGranted = await microphonePermissionProvider()
        guard currentVoiceAttemptID == attemptID else { return }
        guard !Task.isCancelled else {
            currentVoiceAttemptID = nil
            isWorking = false
            return
        }
        guard microphoneGranted else {
            currentVoiceAttemptID = nil
            isWorking = false
            message = "Microphone access is off. Typed/tap editing remains complete."
            return
        }
        let storedToken = try? gatewayTokenProvider()
        guard let baseURL = URL(string: gatewayURLText),
              let token = storedToken
        else {
            currentVoiceAttemptID = nil
            isWorking = false
            message = "Configure the local gateway and bearer token before voice."
            return
        }
        message = "Minting a short-lived Realtime credential…"
        do {
            let secret = try await realtimeSecretProvider(baseURL, token)
            guard currentVoiceAttemptID == attemptID else { return }
            guard !Task.isCancelled else {
                currentVoiceAttemptID = nil
                isWorking = false
                return
            }
            let callbacks = DesignCopilotRealtimeCallbacks(
                onTranscript: { [weak self] transcript in
                    await self?.receiveVoiceTranscript(transcript, attemptID: attemptID)
                },
                onFailure: { [weak self] in
                    await self?.receiveVoiceFailure(attemptID: attemptID)
                }
            )
            let session = realtimeSessionFactory(secret, callbacks)
            realtimeSession = session
            try await session.start()
            guard currentVoiceAttemptID == attemptID, !Task.isCancelled else {
                if currentVoiceAttemptID == attemptID {
                    currentVoiceAttemptID = nil
                    realtimeSession = nil
                    isWorking = false
                }
                await session.cancel()
                return
            }
            isVoiceActive = true
            message = "Listening with Realtime. Tap Stop when your design request is complete."
        } catch {
            guard currentVoiceAttemptID == attemptID else { return }
            realtimeSession = nil
            currentVoiceAttemptID = nil
            isVoiceActive = false
            isWorking = false
            message = "Realtime voice is unavailable. Typed/tap editing still works."
        }
    }

    func stopVoice() async {
        guard isVoiceActive, let realtimeSession else { return }
        isVoiceActive = false
        isAwaitingTranscript = true
        message = "Transcribing the completed push-to-talk turn…"
        do {
            try await realtimeSession.finishInput()
        } catch {
            await realtimeSession.cancel()
            self.realtimeSession = nil
            isAwaitingTranscript = false
            message = "Voice transcription failed. Typed/tap editing remains available."
        }
    }

    func cancelVoice() async {
        guard currentVoiceAttemptID != nil
            || realtimeSession != nil
            || isVoiceActive
            || isAwaitingTranscript
        else { return }
        voiceAttemptCounter &+= 1
        let cancellationGeneration = voiceAttemptCounter
        let session = realtimeSession
        realtimeSession = nil
        currentVoiceAttemptID = nil
        isWorking = false
        isVoiceActive = false
        isAwaitingTranscript = false
        await session?.cancel()
        guard voiceAttemptCounter == cancellationGeneration else { return }
        message = "Voice turn cancelled. Typed/tap editing remains available."
    }

    private func receiveVoiceTranscript(_ transcript: String, attemptID: UInt64) async {
        guard currentVoiceAttemptID == attemptID else { return }
        realtimeSession = nil
        currentVoiceAttemptID = nil
        isVoiceActive = false
        isAwaitingTranscript = false
        prompt = transcript
        message = "Realtime transcript received; asking Sol for the strict proposal…"
        await ask(ingressOverride: .voice)
    }

    private func receiveVoiceFailure(attemptID: UInt64) {
        guard currentVoiceAttemptID == attemptID else { return }
        realtimeSession = nil
        currentVoiceAttemptID = nil
        isVoiceActive = false
        isAwaitingTranscript = false
        isWorking = false
        message = "Realtime voice ended safely. Typed/tap editing remains available."
    }

    private func ask(ingressOverride: DesignCopilotIngressSource?) async {
        guard !isWorking else { return }
        if ingressOverride == nil {
            guard !isVoiceActive, !isAwaitingTranscript else {
                message = "Finish or cancel the voice turn before starting another request."
                return
            }
        }
        guard !runtime.model.previewTransitionInFlight else {
            message = "Finish the current local preview transition before asking again."
            return
        }
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPrompt.isEmpty,
              normalizedPrompt.count <= 2_000,
              normalizedPrompt == prompt
        else {
            message = "Use a non-empty prompt of at most 2,000 characters without edge whitespace."
            return
        }
        if ingressOverride == nil, includeCurrentFrame, !frameConsentGranted {
            message = "Confirm one-frame sharing before asking the vision copilot."
            return
        }
        let storedToken = try? gatewayTokenProvider()
        guard let baseURL = URL(string: gatewayURLText),
              let token = storedToken
        else {
            message = "Configure the local gateway and bearer token first."
            return
        }

        isWorking = true
        envelope = nil
        message = ingressOverride == .voice
            ? "Asking GPT-5.6 Sol to normalize the Realtime transcript…"
            : (includeCurrentFrame
            ? "Encoding one explicit frame for GPT-5.6 Sol…"
            : "Asking GPT-5.6 Sol for typed design intent…")
        defer { isWorking = false }
        do {
            let imageDataURL: String?
            if ingressOverride == nil, includeCurrentFrame {
                guard let frame = runtime.deviceProof?.currentARFrame else {
                    throw DesignCopilotModelError.frameUnavailable
                }
                imageDataURL = try DesignCopilotFrameEncoder.jpegDataURL(frame: frame)
                // Consent covers exactly this encoded frame; another Ask requires renewal.
                frameConsentGranted = false
            } else {
                imageDataURL = nil
            }
            let context = await runtime.model.designCopilotRequestContext()
            let result = try await proposalProvider(baseURL, token, DesignCopilotProposalRequest(
                prompt: normalizedPrompt,
                imageDataURL: imageDataURL,
                ingressSource: ingressOverride ?? (imageDataURL == nil ? .typed : .vision),
                requestContext: context
            ))
            guard result.requestContext == context else {
                throw SemanticProposalRejection.staleContext
            }
            envelope = result
            message = result.status == .ready
                ? result.explanation
                : (result.clarification ?? "The copilot needs more detail.")
        } catch DesignCopilotModelError.frameUnavailable {
            message = "A current AR frame is unavailable. Keep using typed/tap editing or retry with the camera running."
        } catch SemanticProposalRejection.staleContext {
            message = "The room changed while AI was thinking. Ask again from the current revision."
        } catch {
            message = "AI is unavailable. Typed/tap editing and local restore still work."
        }
    }

    func applyProposal() async {
        guard canApplyProposal,
              let envelope,
              envelope.status == .ready
        else {
            message = runtime.model.hasActivePreview
                ? "Cancel the current preview before applying another proposal."
                : "Finish the current copilot turn before applying a proposal."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let previewCreated = try await runtime.model.previewSemanticProposal(envelope)
            guard previewCreated else {
                message = "No preview was created: \(runtime.model.snapshot.status). Resolve the local blocker and retry Apply."
                return
            }
            self.envelope = nil
            message = "Deterministic preview created. Inspect it, then Confirm or Cancel."
        } catch SemanticProposalRejection.staleContext {
            self.envelope = nil
            message = "That suggestion is stale. Ask again from the current room revision."
        } catch {
            message = "The suggestion failed deterministic local validation and was not applied."
        }
    }

    func selectLocalAsset(_ asset: RoomEditCatalogAsset) async {
        await runtime.model.selectCatalogAsset(asset.assetID)
        message = "Selected \(asset.displayName) locally. Choose Place or Replace to preview without AI."
    }
}

enum DesignCopilotModelError: Error {
    case frameUnavailable
}
