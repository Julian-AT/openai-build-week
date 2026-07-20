import Foundation
import ReRoomContracts

private let maximumFileBytes = 33_554_432
private let maximumCases = 2_048

private enum Rejection: String {
    case jsonParse = "json_parse"
    case duplicateName = "duplicate_name"
    case invalidUnicode = "invalid_unicode"
    case schemaValidation = "schema_validation"
    case unsupportedContractVersion = "unsupported_contract_version"
    case unknownProperty = "unknown_property"
    case invalidIdentity = "invalid_identity"
    case invalidPath = "invalid_path"
    case numericOutOfRange = "numeric_out_of_range"
    case semanticInvariant = "semantic_invariant"
    case digestMismatch = "digest_mismatch"
    case wireMagic = "wire_magic"
    case wireVersion = "wire_version"
    case wireFlags = "wire_flags"
    case wireLength = "wire_length"
    case wireSequence = "wire_sequence"
    case wireTruncated = "wire_truncated"
    case wireTrailingBytes = "wire_trailing_bytes"
    case coordinateInvalid = "coordinate_invalid"
}

private struct RunnerFailure: Error {
    let rejection: Rejection
    let message: String

    init(_ rejection: Rejection, _ message: String) {
        self.rejection = rejection
        self.message = message
    }
}

private struct FixtureManifest: Decodable {
    let schemaVersion: String
    let fixtureID: String
    let fixtureRevision: String
    let subject: String
    let oracle: OraclePolicy
    let limits: FixtureLimits
    let schemaHashes: [SchemaReference]
    let cases: [FixtureCase]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case fixtureID = "fixture_id"
        case fixtureRevision = "fixture_revision"
        case subject
        case oracle
        case limits
        case schemaHashes = "schema_hashes"
        case cases
    }
}

private struct OraclePolicy: Decodable {
    let status: String
    let source: String
    let expectedGeneration: String
    let caseOrder: String
    let generatorRole: String

    enum CodingKeys: String, CodingKey {
        case status
        case source
        case expectedGeneration = "expected_generation"
        case caseOrder = "case_order"
        case generatorRole = "generator_role"
    }
}

private struct FixtureLimits: Decodable {
    let maxDocumentDepth: Int
    let maxCases: Int
    let maxFileBytes: Int
    let maxPathBytes: Int

    enum CodingKeys: String, CodingKey {
        case maxDocumentDepth = "max_document_depth"
        case maxCases = "max_cases"
        case maxFileBytes = "max_file_bytes"
        case maxPathBytes = "max_path_bytes"
    }
}

private struct SchemaReference: Decodable {
    let contractID: String
    let schemaID: String
    let relativePath: String
    let sha256: String

    enum CodingKeys: String, CodingKey {
        case contractID = "contract_id"
        case schemaID = "schema_id"
        case relativePath = "relative_path"
        case sha256
    }
}

private struct FileReference: Decodable {
    let relativePath: String
    let mediaType: String
    let byteLength: Int
    let sha256: String

    enum CodingKeys: String, CodingKey {
        case relativePath = "relative_path"
        case mediaType = "media_type"
        case byteLength = "byte_length"
        case sha256
    }
}

private struct ExpectedArtifact: Decodable {
    let kind: String
    let relativePath: String
    let mediaType: String
    let byteLength: Int
    let sha256: String
    let valueSHA256: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case relativePath = "relative_path"
        case mediaType = "media_type"
        case byteLength = "byte_length"
        case sha256
        case valueSHA256 = "value_sha256"
    }
}

private struct ExpectedOutcome: Decodable {
    let verdict: String
    let rejectionClass: String?
    let artifacts: [ExpectedArtifact]

    enum CodingKeys: String, CodingKey {
        case verdict
        case rejectionClass = "rejection_class"
        case artifacts
    }
}

private struct FixtureCase: Decodable {
    let caseID: String
    let caseKind: String
    let input: FileReference
    let expected: ExpectedOutcome
    let immutable: Bool

    enum CodingKeys: String, CodingKey {
        case caseID = "case_id"
        case caseKind = "case_kind"
        case input
        case expected
        case immutable
    }
}

private struct KnownManifest {
    let revision: String
    let subject: String
    let sha256: String

    static let byFixtureID: [String: KnownManifest] = [
        "FX-CONTRACT-001": KnownManifest(
            revision: "rev-001",
            subject: "CON-001-CON-005",
            sha256: "54a0753df4c6a963136a59ed1361dc0c4460c59647ab202c0b7c8e565b79194c"
        ),
        "FX-JCS-001": KnownManifest(
            revision: "rev-001",
            subject: "RR-JCS-SHA256-1",
            sha256: "160ef38aec0c3e882e7ae88b51fec9161bce363bcb20d7ead656cfd5106952e8"
        ),
        "FX-COORD-001": KnownManifest(
            revision: "rev-001",
            subject: "RR-COORD-1",
            sha256: "e707c4ddf3b1856df30420c6125532d95161a5f36f95671ea1336baef7e6c2df"
        ),
    ]
}

private struct LoadedFixture {
    let repoRoot: URL
    let fixtureRoot: URL
    let manifestBytes: Data
    let manifestSHA256: String
    let manifest: FixtureManifest
    let validator: ContractValidator
    let schemaReferences: [String: SchemaReference]
}

private struct Options {
    let manifest: URL
    let output: URL?
    let repoRoot: URL?
    let implementationRevision: String?
}

private func parseOptions(_ arguments: [String]) throws -> Options {
    var manifest: String?
    var output: String?
    var repoRoot: String?
    var implementationRevision: String?
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        if ["--manifest", "--output", "--repo-root", "--implementation-revision"].contains(argument) {
            guard index + 1 < arguments.count else {
                throw RunnerFailure(.schemaValidation, "missing value for \(argument)")
            }
            index += 1
            switch argument {
            case "--manifest": manifest = arguments[index]
            case "--output": output = arguments[index]
            case "--repo-root": repoRoot = arguments[index]
            case "--implementation-revision": implementationRevision = arguments[index]
            default: break
            }
        } else if !argument.hasPrefix("-"), manifest == nil {
            manifest = argument
        } else {
            throw RunnerFailure(.schemaValidation, "unsupported runner argument")
        }
        index += 1
    }
    guard let manifest else {
        throw RunnerFailure(
            .schemaValidation,
            "usage: ReRoomContractRunner --manifest <path> [--output <path>]"
        )
    }
    return Options(
        manifest: URL(fileURLWithPath: manifest),
        output: output.map(URL.init(fileURLWithPath:)),
        repoRoot: repoRoot.map(URL.init(fileURLWithPath:)),
        implementationRevision: implementationRevision
    )
}

private func readBounded(_ url: URL, maximum: Int = maximumFileBytes) throws -> Data {
    let values: URLResourceValues
    do {
        values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    } catch {
        throw RunnerFailure(.invalidPath, "referenced file is unavailable")
    }
    guard values.isRegularFile == true,
          let fileSize = values.fileSize,
          fileSize <= maximum
    else {
        throw RunnerFailure(.invalidPath, "referenced file is not a bounded regular file")
    }
    let data: Data
    do {
        data = try Data(contentsOf: url, options: [.mappedIfSafe])
    } catch {
        throw RunnerFailure(.invalidPath, "referenced file cannot be read")
    }
    guard data.count == fileSize else {
        throw RunnerFailure(.digestMismatch, "referenced file changed while being read")
    }
    return data
}

private func containedURL(
    base: URL,
    relativePath: String,
    containmentRoot: URL,
    archivePath: Bool = true
) throws -> URL {
    if archivePath {
        do {
            try ArchivePath.validate(relativePath)
        } catch {
            throw RunnerFailure(.invalidPath, "unsafe archive-relative path")
        }
    } else if relativePath.isEmpty || relativePath.contains("\0") {
        throw RunnerFailure(.invalidPath, "invalid file reference")
    }
    let root = containmentRoot.standardizedFileURL.resolvingSymlinksInPath()
    let candidate = base.appendingPathComponent(relativePath)
        .standardizedFileURL
        .resolvingSymlinksInPath()
    guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
        throw RunnerFailure(.invalidPath, "file reference escapes its allowed root")
    }
    return candidate
}

private func readFixtureFile(_ fixture: LoadedFixture, _ reference: FileReference) throws -> Data {
    guard (0...maximumFileBytes).contains(reference.byteLength) else {
        throw RunnerFailure(.schemaValidation, "fixture byte length is outside its bound")
    }
    let url = try containedURL(
        base: fixture.fixtureRoot,
        relativePath: reference.relativePath,
        containmentRoot: fixture.fixtureRoot
    )
    let data = try readBounded(url, maximum: min(maximumFileBytes, reference.byteLength + 1))
    guard data.count == reference.byteLength,
          CanonicalJSON.sha256Hex(data) == reference.sha256
    else {
        throw RunnerFailure(.digestMismatch, "fixture file does not match its immutable reference")
    }
    return data
}

private func readFixtureInternal(
    _ fixture: LoadedFixture,
    _ relativePath: String,
    base: URL? = nil
) throws -> Data {
    let url = try containedURL(
        base: base ?? fixture.fixtureRoot,
        relativePath: relativePath,
        containmentRoot: fixture.repoRoot,
        archivePath: false
    )
    return try readBounded(url)
}

private func jsonObject(_ data: Data) throws -> [String: Any] {
    do {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RunnerFailure(.jsonParse, "expected a JSON object")
        }
        return object
    } catch let failure as RunnerFailure {
        throw failure
    } catch {
        throw RunnerFailure(.jsonParse, "invalid JSON object")
    }
}

private func findRepositoryRoot(from location: URL) throws -> URL {
    var cursor = location.hasDirectoryPath ? location : location.deletingLastPathComponent()
    while cursor.path != cursor.deletingLastPathComponent().path {
        if FileManager.default.fileExists(atPath: cursor.appendingPathComponent(".git").path) {
            return cursor
        }
        cursor = cursor.deletingLastPathComponent()
    }
    throw RunnerFailure(.invalidPath, "repository root was not found")
}

private let registeredSchemaTuples: [String: (String, String)] = [
    "CON-001": ("urn:reroom:schema:frame-packet:1", "docs/contracts/frame-packet.schema.json"),
    "CON-002": ("urn:reroom:schema:rrcap-manifest:1", "docs/contracts/rrcap-manifest.schema.json"),
    "CON-003": ("urn:reroom:schema:scene-state:1", "docs/contracts/scene-state.schema.json"),
    "CON-004": ("urn:reroom:schema:edit-artifacts:1", "docs/contracts/edit-artifacts.schema.json"),
    "CON-005": ("urn:reroom:schema:transaction:1", "docs/contracts/transaction.schema.json"),
]

private func loadFixture(_ manifestURL: URL, repoRoot explicitRoot: URL?) throws -> LoadedFixture {
    let manifestBytes = try readBounded(manifestURL)
    do {
        _ = try CanonicalJSON.canonicalize(jsonData: manifestBytes)
    } catch let error as CanonicalJSONRejection {
        throw RunnerFailure(rejection(for: error), "fixture manifest is not strict JSON")
    }
    let manifestObject = try jsonObject(manifestBytes)
    guard let fixtureID = manifestObject["fixture_id"] as? String,
          let known = KnownManifest.byFixtureID[fixtureID]
    else {
        throw RunnerFailure(.schemaValidation, "unknown fixture family")
    }
    let manifestSHA256 = CanonicalJSON.sha256Hex(manifestBytes)
    guard manifestSHA256 == known.sha256 else {
        throw RunnerFailure(.digestMismatch, "manifest is not the complete immutable oracle revision")
    }

    let manifest: FixtureManifest
    do {
        manifest = try JSONDecoder().decode(FixtureManifest.self, from: manifestBytes)
    } catch {
        throw RunnerFailure(.schemaValidation, "manifest does not satisfy FixtureManifestV1")
    }
    guard manifest.schemaVersion == "1.0.0",
          manifest.fixtureID == fixtureID,
          manifest.fixtureRevision == known.revision,
          manifest.subject == known.subject,
          manifest.oracle.status == "immutable",
          manifest.oracle.source == "checked_in",
          manifest.oracle.expectedGeneration == "forbidden_during_verification",
          manifest.oracle.caseOrder == "lexicographic_case_id",
          manifest.oracle.generatorRole == "proposal_only",
          manifest.limits.maxDocumentDepth == 64,
          manifest.limits.maxCases == maximumCases,
          manifest.limits.maxFileBytes == maximumFileBytes,
          manifest.limits.maxPathBytes == 240,
          (1...maximumCases).contains(manifest.cases.count)
    else {
        throw RunnerFailure(.schemaValidation, "manifest policy fields are not frozen")
    }
    let caseIDs = manifest.cases.map(\.caseID)
    guard caseIDs == caseIDs.sorted(), Set(caseIDs).count == caseIDs.count else {
        throw RunnerFailure(.semanticInvariant, "fixture case IDs are not unique and lexicographic")
    }

    let repoRoot = try (explicitRoot ?? findRepositoryRoot(from: manifestURL))
        .standardizedFileURL
        .resolvingSymlinksInPath()
    var registrations = [ContractSchemaRegistration]()
    var references = [String: SchemaReference]()
    for reference in manifest.schemaHashes {
        guard let tuple = registeredSchemaTuples[reference.contractID],
              tuple.0 == reference.schemaID,
              tuple.1 == reference.relativePath,
              references[reference.contractID] == nil,
              let identifier = ContractSchemaIdentifier(rawValue: reference.schemaID)
        else {
            throw RunnerFailure(.schemaValidation, "fixture schema registry tuple is not canonical")
        }
        let schemaURL = try containedURL(
            base: repoRoot,
            relativePath: reference.relativePath,
            containmentRoot: repoRoot
        )
        let schemaData = try readBounded(schemaURL)
        guard CanonicalJSON.sha256Hex(schemaData) == reference.sha256 else {
            throw RunnerFailure(.digestMismatch, "frozen schema digest mismatch")
        }
        references[reference.contractID] = reference
        registrations.append(
            ContractSchemaRegistration(
                identifier: identifier,
                version: "1.0.0",
                sha256: reference.sha256,
                schemaData: schemaData
            )
        )
    }
    guard Set(references.keys) == Set(registeredSchemaTuples.keys) else {
        throw RunnerFailure(.schemaValidation, "fixture schema registry is incomplete")
    }
    let validator: ContractValidator
    do {
        validator = try ContractValidator(registrations: registrations)
    } catch {
        throw RunnerFailure(.schemaValidation, "frozen schema registry could not be compiled")
    }
    let fixture = LoadedFixture(
        repoRoot: repoRoot,
        fixtureRoot: manifestURL.deletingLastPathComponent(),
        manifestBytes: manifestBytes,
        manifestSHA256: manifestSHA256,
        manifest: manifest,
        validator: validator,
        schemaReferences: references
    )
    for fixtureCase in manifest.cases {
        guard fixtureCase.immutable else {
            throw RunnerFailure(.schemaValidation, "fixture case is not immutable")
        }
        _ = try readFixtureFile(fixture, fixtureCase.input)
        for artifact in fixtureCase.expected.artifacts {
            _ = try readFixtureFile(
                fixture,
                FileReference(
                    relativePath: artifact.relativePath,
                    mediaType: artifact.mediaType,
                    byteLength: artifact.byteLength,
                    sha256: artifact.sha256
                )
            )
        }
    }
    return fixture
}

private func rejection(for error: CanonicalJSONRejection) -> Rejection {
    switch error {
    case .duplicateName: .duplicateName
    case .invalidUnicode: .invalidUnicode
    case .jsonParse: .jsonParse
    case .numericOutOfRange: .numericOutOfRange
    }
}

private func rejection(for error: CoordinateMathRejection) -> Rejection {
    switch error {
    case .coordinateInvalid: .coordinateInvalid
    case .numericOutOfRange: .numericOutOfRange
    }
}

private func rejection(for error: WireFrameRejection) -> Rejection {
    switch error {
    case .wireMagic: .wireMagic
    case .wireVersion: .wireVersion
    case .wireFlags: .wireFlags
    case .wireLength: .wireLength
    case .wireSequence: .wireSequence
    case .wireTruncated: .wireTruncated
    case .wireTrailingBytes: .wireTrailingBytes
    case .digestMismatch: .digestMismatch
    }
}

private func acceptedResult(
    _ caseID: String,
    artifacts: [[String: Any]] = []
) -> [String: Any] {
    [
        "case_id": caseID,
        "verdict": "accept",
        "rejection_class": NSNull(),
        "output_artifacts": artifacts,
    ]
}

private func rejectedResult(_ caseID: String, rejection: Rejection) -> [String: Any] {
    [
        "case_id": caseID,
        "verdict": "reject",
        "rejection_class": rejection.rawValue,
        "output_artifacts": [],
    ]
}

private func executeJCSCase(_ fixture: LoadedFixture, _ fixtureCase: FixtureCase) throws -> [String: Any] {
    guard fixtureCase.caseKind == "raw_json" || fixtureCase.caseKind == "digest_scope" else {
        throw RunnerFailure(.schemaValidation, "unsupported JCS fixture case kind")
    }
    do {
        let input = try readFixtureFile(fixture, fixtureCase.input)
        let canonical = try CanonicalJSON.canonicalize(jsonData: input)
        let digest = CanonicalJSON.sha256Hex(canonical)
        let digestBytes = Data((digest + "\n").utf8)
        return acceptedResult(fixtureCase.caseID, artifacts: [
            [
                "kind": "canonical_bytes",
                "byte_length": canonical.count,
                "sha256": CanonicalJSON.sha256Hex(canonical),
            ],
            [
                "kind": "digest",
                "byte_length": digestBytes.count,
                "sha256": CanonicalJSON.sha256Hex(digestBytes),
                "value_sha256": digest,
            ],
        ])
    } catch let error as CanonicalJSONRejection {
        return rejectedResult(fixtureCase.caseID, rejection: rejection(for: error))
    } catch let error as RunnerFailure {
        return rejectedResult(fixtureCase.caseID, rejection: error.rejection)
    }
}

private func contractID(for relativePath: String) throws -> String {
    let name = URL(fileURLWithPath: relativePath).lastPathComponent
    if name.hasPrefix("con001.") { return "CON-001" }
    if name.hasPrefix("con002.") { return "CON-002" }
    if name.hasPrefix("con003.") { return "CON-003" }
    if name.hasPrefix("con004.") { return "CON-004" }
    if name.hasPrefix("con005.") { return "CON-005" }
    throw RunnerFailure(.schemaValidation, "fixture does not identify a registered contract")
}

private func validateContract(
    _ fixture: LoadedFixture,
    data: Data,
    payload: Data?,
    contractID: String
) throws {
    guard let reference = fixture.schemaReferences[contractID] else {
        throw RunnerFailure(.schemaValidation, "contract schema is absent from fixture registry")
    }
    switch fixture.validator.validate(
        ContractValidationRequest(
            schemaID: reference.schemaID,
            schemaVersion: "1.0.0",
            schemaSHA256: reference.sha256,
            documentData: data,
            payloadData: payload
        )
    ) {
    case .accepted:
        return
    case .rejected(let error):
        guard let rejection = Rejection(rawValue: error.rawValue) else {
            throw RunnerFailure(.schemaValidation, "contract rejection is not normalized")
        }
        throw RunnerFailure(rejection, "contract validation rejected the fixture case")
    }
}

private func applyJSONMutations(_ source: Any, mutations: [[String: Any]]) throws -> Any {
    var value = source
    for mutation in mutations {
        guard let operation = mutation["op"] as? String,
              operation == "add" || operation == "replace",
              let pointer = mutation["pointer"] as? String,
              pointer.hasPrefix("/"),
              pointer.count > 1
        else {
            throw RunnerFailure(.schemaValidation, "invalid JSON mutation")
        }
        let tokens = pointer.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map {
            String($0).replacingOccurrences(of: "~1", with: "/")
                .replacingOccurrences(of: "~0", with: "~")
        }
        try applyJSONMutation(
            operation: operation,
            tokens: ArraySlice(tokens),
            replacement: mutation["value"] ?? NSNull(),
            value: &value
        )
    }
    return value
}

private func applyJSONMutation(
    operation: String,
    tokens: ArraySlice<String>,
    replacement: Any,
    value: inout Any
) throws {
    guard let token = tokens.first else {
        throw RunnerFailure(.schemaValidation, "root mutation is not supported")
    }
    let remaining = tokens.dropFirst()
    if var object = value as? [String: Any] {
        if remaining.isEmpty {
            guard operation == "add" || object[token] != nil else {
                throw RunnerFailure(.schemaValidation, "replace mutation target is absent")
            }
            object[token] = replacement
        } else {
            guard var child = object[token] else {
                throw RunnerFailure(.schemaValidation, "mutation pointer does not resolve")
            }
            try applyJSONMutation(
                operation: operation,
                tokens: remaining,
                replacement: replacement,
                value: &child
            )
            object[token] = child
        }
        value = object
        return
    }
    if var array = value as? [Any], let index = Int(token), array.indices.contains(index) {
        if remaining.isEmpty {
            array[index] = replacement
        } else {
            var child = array[index]
            try applyJSONMutation(
                operation: operation,
                tokens: remaining,
                replacement: replacement,
                value: &child
            )
            array[index] = child
        }
        value = array
        return
    }
    throw RunnerFailure(.schemaValidation, "mutation pointer does not resolve")
}

private func hexadecimalData(_ text: String) throws -> Data {
    guard !text.isEmpty, text.count.isMultiple(of: 2) else {
        throw RunnerFailure(.schemaValidation, "hexadecimal input has invalid length")
    }
    var bytes = [UInt8]()
    bytes.reserveCapacity(text.count / 2)
    var index = text.startIndex
    while index < text.endIndex {
        let next = text.index(index, offsetBy: 2)
        guard let byte = UInt8(text[index..<next], radix: 16) else {
            throw RunnerFailure(.schemaValidation, "hexadecimal input is invalid")
        }
        bytes.append(byte)
        index = next
    }
    return Data(bytes)
}

private func executeContractCase(
    _ fixture: LoadedFixture,
    _ fixtureCase: FixtureCase
) throws -> [String: Any] {
    do {
        let input = try readFixtureFile(fixture, fixtureCase.input)
        if fixtureCase.caseKind == "json_instance" {
            try validateContract(
                fixture,
                data: input,
                payload: nil,
                contractID: contractID(for: fixtureCase.input.relativePath)
            )
            return acceptedResult(fixtureCase.caseID)
        }
        guard fixtureCase.caseKind == "json_mutation" else {
            throw RunnerFailure(.schemaValidation, "unsupported contract fixture case kind")
        }
        let descriptor = try jsonObject(input)
        if descriptor["migration"] != nil {
            guard descriptor["migration"] as? String == "named_1.0_to_1.1",
                  descriptor["reader_version"] as? String == "1.1.0",
                  descriptor["source_version"] as? String == "1.0.0",
                  descriptor["representable"] as? Bool == true,
                  let source = descriptor["source"] as? String
            else {
                throw RunnerFailure(
                    .unsupportedContractVersion,
                    "no lossless named compatibility migration applies"
                )
            }
            try validateContract(
                fixture,
                data: readFixtureInternal(fixture, source),
                payload: nil,
                contractID: "CON-001"
            )
            return acceptedResult(fixtureCase.caseID)
        }
        guard let base = descriptor["base"] as? String,
              let mutations = descriptor["mutations"] as? [[String: Any]]
        else {
            throw RunnerFailure(.schemaValidation, "contract mutation descriptor is incomplete")
        }
        let baseData = try readFixtureInternal(fixture, base)
        let mutated = try applyJSONMutations(
            try JSONSerialization.jsonObject(with: baseData),
            mutations: mutations
        )
        let mutatedData = try JSONSerialization.data(withJSONObject: mutated, options: [.sortedKeys])
        let payload = try (descriptor["payload"] as? String).map(hexadecimalData)
        try validateContract(
            fixture,
            data: mutatedData,
            payload: payload,
            contractID: contractID(for: base)
        )
        return acceptedResult(fixtureCase.caseID)
    } catch let error as RunnerFailure {
        return rejectedResult(fixtureCase.caseID, rejection: error.rejection)
    }
}

private func executeCoordinateCase(
    _ fixture: LoadedFixture,
    _ fixtureCase: FixtureCase
) throws -> [String: Any] {
    guard fixtureCase.caseKind == "coordinate_vector" else {
        throw RunnerFailure(.schemaValidation, "unsupported coordinate fixture case kind")
    }
    do {
        let output = try RRCoordinateMath.evaluate(
            jsonData: readFixtureFile(fixture, fixtureCase.input)
        )
        let artifacts: [[String: Any]]
        if let kind = fixtureCase.expected.artifacts.first?.kind {
            artifacts = [[
                "kind": kind,
                "byte_length": output.count,
                "sha256": CanonicalJSON.sha256Hex(output),
            ]]
        } else {
            artifacts = []
        }
        return acceptedResult(fixtureCase.caseID, artifacts: artifacts)
    } catch let error as CoordinateMathRejection {
        return rejectedResult(fixtureCase.caseID, rejection: rejection(for: error))
    } catch let error as RunnerFailure {
        return rejectedResult(fixtureCase.caseID, rejection: error.rejection)
    }
}

private func parseWireHex(_ data: Data) throws -> Data {
    guard let text = String(data: data, encoding: .utf8),
          text.hasSuffix("\n"),
          !text.dropLast().isEmpty,
          text.dropLast().allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
          text.dropLast().count.isMultiple(of: 2)
    else {
        throw RunnerFailure(.wireLength, "wire oracle is not lowercase even-length hex")
    }
    return try hexadecimalData(String(text.dropLast()))
}

private func exactInteger(_ value: Any?, field: String) throws -> Int {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.rounded(.towardZero) == number.doubleValue,
          number.doubleValue >= 0,
          number.doubleValue <= Double(Int.max)
    else {
        throw RunnerFailure(.wireLength, "invalid integer mutation field \(field)")
    }
    return number.intValue
}

private func replaceBigEndian<T: FixedWidthInteger>(
    _ value: T,
    at offset: Int,
    in data: inout Data
) throws {
    let width = MemoryLayout<T>.size
    guard offset >= 0, offset + width <= data.count else {
        throw RunnerFailure(.wireLength, "wire mutation offset is outside the frame")
    }
    let bytes = withUnsafeBytes(of: value.bigEndian) { Data($0) }
    data.replaceSubrange(offset..<(offset + width), with: bytes)
}

private func applyWireMutations(_ source: Data, _ mutations: [[String: Any]]) throws -> Data {
    var output = source
    for mutation in mutations {
        guard let operation = mutation["op"] as? String else {
            throw RunnerFailure(.wireLength, "wire mutation operation is absent")
        }
        switch operation {
        case "replace_byte":
            let offset = try exactInteger(mutation["offset"], field: "offset")
            guard offset < output.count,
                  let text = mutation["value_hex"] as? String,
                  text.count == 2,
                  let byte = UInt8(text, radix: 16)
            else {
                throw RunnerFailure(.wireLength, "invalid replace-byte mutation")
            }
            output[offset] = byte
        case "replace_u32be":
            let offset = try exactInteger(mutation["offset"], field: "offset")
            let integer = try exactInteger(mutation["value"], field: "value")
            guard let value = UInt32(exactly: integer) else {
                throw RunnerFailure(.wireLength, "u32 mutation value is outside its range")
            }
            try replaceBigEndian(value, at: offset, in: &output)
        case "replace_u64be":
            let offset = try exactInteger(mutation["offset"], field: "offset")
            let integer = try exactInteger(mutation["value"], field: "value")
            try replaceBigEndian(UInt64(integer), at: offset, in: &output)
        case "append_hex":
            guard let text = mutation["value_hex"] as? String else {
                throw RunnerFailure(.wireLength, "append mutation value is absent")
            }
            output.append(try hexadecimalData(text))
        case "truncate":
            let length = try exactInteger(mutation["byte_length"], field: "byte_length")
            guard length <= output.count else {
                throw RunnerFailure(.wireLength, "truncate mutation exceeds frame length")
            }
            output = output.prefix(length)
        default:
            throw RunnerFailure(.wireLength, "unsupported wire mutation operation")
        }
    }
    return output
}

private func executeWireCase(
    _ fixture: LoadedFixture,
    _ fixtureCase: FixtureCase
) throws -> [String: Any] {
    do {
        let descriptor = try jsonObject(readFixtureFile(fixture, fixtureCase.input))
        if fixtureCase.caseKind == "wire_bytes" {
            guard let headerSource = descriptor["header_source"] as? String,
                  let payloadHex = descriptor["payload_hex"] as? String
            else {
                throw RunnerFailure(.wireLength, "wire fixture descriptor is incomplete")
            }
            let wire = try RRFPWireFrame.encode(
                headerJSON: readFixtureInternal(fixture, headerSource),
                payload: hexadecimalData(payloadHex)
            )
            _ = try RRFPWireFrame.decode(wire)
            let output = Data((wire.map { String(format: "%02x", $0) }.joined() + "\n").utf8)
            return acceptedResult(fixtureCase.caseID, artifacts: [[
                "kind": "wire_bytes",
                "byte_length": output.count,
                "sha256": CanonicalJSON.sha256Hex(output),
            ]])
        }
        guard fixtureCase.caseKind == "wire_mutation",
              let base = descriptor["base"] as? String,
              let mutations = descriptor["mutations"] as? [[String: Any]]
        else {
            throw RunnerFailure(.wireLength, "unsupported wire fixture case kind")
        }
        let wire = try parseWireHex(readFixtureInternal(fixture, base))
        _ = try RRFPWireFrame.decode(applyWireMutations(wire, mutations))
        return acceptedResult(fixtureCase.caseID)
    } catch let error as WireFrameRejection {
        return rejectedResult(fixtureCase.caseID, rejection: rejection(for: error))
    } catch let error as RunnerFailure {
        return rejectedResult(fixtureCase.caseID, rejection: error.rejection)
    }
}

private func dispatch(_ fixture: LoadedFixture, _ fixtureCase: FixtureCase) throws -> [String: Any] {
    switch fixture.manifest.fixtureID {
    case "FX-CONTRACT-001":
        return try executeContractCase(fixture, fixtureCase)
    case "FX-JCS-001":
        return try executeJCSCase(fixture, fixtureCase)
    case "FX-COORD-001":
        if fixtureCase.caseID.hasPrefix("wire.") {
            return try executeWireCase(fixture, fixtureCase)
        }
        return try executeCoordinateCase(fixture, fixtureCase)
    default:
        throw RunnerFailure(.schemaValidation, "unknown fixture family")
    }
}

private func validImplementationRevision(_ value: String) -> Bool {
    guard value.count == 44, value.hasPrefix("git:") else { return false }
    return value.dropFirst(4).allSatisfy { character in
        character.isNumber || ("a"..."f").contains(character)
    }
}

private func resolveRevision(repoRoot: URL, explicit: String?) throws -> String {
    if let explicit {
        guard validImplementationRevision(explicit) else {
            throw RunnerFailure(
                .schemaValidation,
                "implementation revision must be git:<40 lowercase hex>"
            )
        }
        return explicit
    }
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", repoRoot.path, "rev-parse", "HEAD"]
    process.standardOutput = output
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        throw RunnerFailure(.schemaValidation, "a valid implementation revision is required")
    }
    let sha = String(
        decoding: output.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    let revision = "git:\(sha)"
    guard process.terminationStatus == 0, validImplementationRevision(revision) else {
        throw RunnerFailure(.schemaValidation, "a valid implementation revision is required")
    }
    return revision
}

private func canonicalData(_ object: Any) throws -> Data {
    do {
        let json = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try CanonicalJSON.canonicalize(jsonData: json)
    } catch let error as CanonicalJSONRejection {
        throw RunnerFailure(rejection(for: error), "runner result cannot be canonicalized")
    } catch let failure as RunnerFailure {
        throw failure
    } catch {
        throw RunnerFailure(.schemaValidation, "runner result cannot be serialized")
    }
}

private func run(_ options: Options) throws -> Data {
    let fixture = try loadFixture(options.manifest, repoRoot: options.repoRoot)
    let revision = try resolveRevision(
        repoRoot: fixture.repoRoot,
        explicit: options.implementationRevision
    )
    let caseResults = try fixture.manifest.cases.map { try dispatch(fixture, $0) }
    let accepted = caseResults.count { $0["verdict"] as? String == "accept" }
    let actualCaseIDs = caseResults.compactMap { $0["case_id"] as? String }
    guard actualCaseIDs == fixture.manifest.cases.map(\.caseID),
          actualCaseIDs.count == caseResults.count
    else {
        throw RunnerFailure(.semanticInvariant, "result cases are incomplete or out of order")
    }
    var result: [String: Any] = [
        "schema_version": "1.0.0",
        "runner": [
            "runtime": "swift",
            "name": "reroom-swift-reference",
            "version": "1.0.0",
            "implementation_revision": revision,
        ],
        "fixture": [
            "fixture_id": fixture.manifest.fixtureID,
            "fixture_revision": fixture.manifest.fixtureRevision,
            "manifest_sha256": fixture.manifestSHA256,
        ],
        "case_order": "lexicographic_case_id",
        "case_results": caseResults,
        "summary": [
            "total": caseResults.count,
            "accepted": accepted,
            "rejected": caseResults.count - accepted,
        ],
        "oracle_unchanged": true,
        "result_digest_algorithm": "RR-JCS-SHA256-1",
        "result_digest_scope": "entire_runner_result_with_result_digest_sha256_omitted",
    ]
    result["result_digest_sha256"] = CanonicalJSON.sha256Hex(try canonicalData(result))
    var output = try canonicalData(result)
    output.append(0x0a)
    return output
}

private func write(_ data: Data, output: URL?) throws {
    guard let output else {
        FileHandle.standardOutput.write(data)
        return
    }
    do {
        try data.write(to: output, options: [.withoutOverwriting])
    } catch {
        throw RunnerFailure(.invalidPath, "output path already exists or cannot be created")
    }
}

do {
    let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
    try write(run(options), output: options.output)
} catch let failure as RunnerFailure {
    FileHandle.standardError.write(Data("runner: FAIL: \(failure.message)\n".utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("runner: FAIL: unexpected runner failure\n".utf8))
    exit(1)
}
