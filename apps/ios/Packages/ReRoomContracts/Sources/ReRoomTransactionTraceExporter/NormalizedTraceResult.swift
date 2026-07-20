import Foundation

struct NormalizedTraceResult: Encodable {
    struct Fixture: Encodable {
        let fixtureID: String
        let fixtureRevision: String
        let manifestSHA256: String

        enum CodingKeys: String, CodingKey {
            case fixtureID = "fixture_id"
            case fixtureRevision = "fixture_revision"
            case manifestSHA256 = "manifest_sha256"
        }
    }

    struct Runtime: Encodable {
        let language: String
        let name: String
        let version: String
    }

    struct Implementation: Encodable {
        let repositoryRevision: String
        let sourceFiles: [String]
        let sourceTreeSHA256: String

        enum CodingKeys: String, CodingKey {
            case repositoryRevision = "repository_revision"
            case sourceFiles = "source_files"
            case sourceTreeSHA256 = "source_tree_sha256"
        }
    }

    let traceFormat: String
    let fixture: Fixture
    let runtime: Runtime
    let implementation: Implementation
    let operationOrder: [String]
    let operationDeltaOrder: [String: [String]]
    let proposals: [JSONValue]
    let safety: JSONValue
    let cases: [JSONValue]
    let traces: [JSONValue]
    let revisions: JSONValue
    let fingerprints: JSONValue
    let projections: JSONValue
    let receipts: [JSONValue]
    let retry: JSONValue
    let restore: JSONValue
    let divergence: JSONValue

    enum CodingKeys: String, CodingKey {
        case traceFormat = "trace_format"
        case fixture, runtime, implementation
        case operationOrder = "operation_order"
        case operationDeltaOrder = "operation_delta_order"
        case proposals, safety, cases, traces, revisions, fingerprints, projections, receipts, retry, restore, divergence
    }
}

/// A closed JSON algebra keeps the normalized evidence payload typed while allowing
/// trace events with intentionally different, fixture-owned members.
enum JSONValue: Codable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case integer(Int)
    case boolean(Bool)
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(Int.self) { self = .integer(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }
}
