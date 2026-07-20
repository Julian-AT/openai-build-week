import Foundation
import ReRoomCaptureCore

/// Transaction-scoped synchronous durability operations over the existing capture filesystem seam.
/// The branch-authority actor calls this adapter without any suspension point.
public struct TransactionFileSystemAdapter: Sendable {
    public let rootPath: String
    private let fileSystem: any CaptureFileSystem

    public init(
        fileSystem: any CaptureFileSystem,
        rootPath: String = "transactions"
    ) {
        self.fileSystem = fileSystem
        self.rootPath = rootPath
    }

    func prepareRoot() throws {
        guard validComponent(rootPath) else { throw TransactionFileSystemError.invalidRoot }
        var createdDirectory = false
        if try !fileSystem.fileExists(at: rootPath) {
            try fileSystem.createDirectory(at: rootPath)
            createdDirectory = true
        }
        let generations = generationsPath
        if try !fileSystem.fileExists(at: generations) {
            try fileSystem.createDirectory(at: generations)
            createdDirectory = true
        }
        if createdDirectory {
            try fileSystem.synchronizeDirectory(at: rootPath)
        }
    }

    func generationExists(_ digest: String) throws -> Bool {
        try fileSystem.fileExists(at: generationPath(digest))
    }

    func createGeneration(_ digest: String) throws {
        try fileSystem.createDirectory(at: generationPath(digest))
    }

    func writeGenerationMember(_ data: Data, named name: String, generation digest: String) throws {
        guard Self.validMemberNames.contains(name) else { throw TransactionFileSystemError.invalidMember }
        let path = generationMemberPath(name, generation: digest)
        try fileSystem.write(data, to: path)
        try fileSystem.synchronizeFile(at: path)
    }

    func finishGeneration(_ digest: String) throws {
        try fileSystem.synchronizeDirectory(at: generationPath(digest))
        try fileSystem.synchronizeDirectory(at: generationsPath)
    }

    func activatePointer(_ data: Data) throws {
        try fileSystem.replace(data, at: activePointerPath)
        try fileSystem.synchronizeFile(at: activePointerPath)
        try fileSystem.synchronizeDirectory(at: rootPath)
    }

    func activePointerExists() throws -> Bool {
        try fileSystem.fileExists(at: activePointerPath)
    }

    func readActivePointer() throws -> Data {
        try fileSystem.read(at: activePointerPath, maximumBytes: 16_384)
    }

    func generationMemberExists(_ name: String, generation digest: String) throws -> Bool {
        guard Self.validMemberNames.contains(name) else { throw TransactionFileSystemError.invalidMember }
        return try fileSystem.fileExists(at: generationMemberPath(name, generation: digest))
    }

    func readGenerationMember(_ name: String, generation digest: String) throws -> Data {
        guard Self.validMemberNames.contains(name) else { throw TransactionFileSystemError.invalidMember }
        return try fileSystem.read(
            at: generationMemberPath(name, generation: digest),
            maximumBytes: fileSystem.limits.maximumReadBytes
        )
    }

    private var generationsPath: String { "\(rootPath)/generations" }
    private var activePointerPath: String { "\(rootPath)/active-generation.json" }

    private func generationPath(_ digest: String) -> String {
        "\(generationsPath)/\(digest)"
    }

    private func generationMemberPath(_ name: String, generation digest: String) -> String {
        "\(generationPath(digest))/\(name)"
    }

    private func validComponent(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("/") && value != "." && value != ".."
    }

    static let validMemberNames: Set<String> = [
        "scene.json",
        "transactions.json",
        "inverse-index.json",
        "artifacts.json",
        "receipts.json",
        "idempotency.json",
        "inventory.json",
    ]
}

public enum TransactionFileSystemError: String, Error, Equatable, Sendable {
    case invalidRoot = "invalid_root"
    case invalidMember = "invalid_member"
}
