#if canImport(Darwin)
import Darwin
#endif
import Foundation
import ReRoomContracts

public enum CaptureFileSystemError: String, Error, Equatable, Sendable {
    case invalidRoot = "invalid_root"
    case invalidLimits = "invalid_limits"
    case invalidPath = "invalid_path"
    case byteLimitExceeded = "byte_limit_exceeded"
    case missingFile = "missing_file"
    case destinationExists = "destination_exists"
    case ioFailure = "io_failure"
}

public struct CaptureFileSystemLimits: Equatable, Sendable {
    public static let production = CaptureFileSystemLimits(
        maximumFileBytes: 33_554_432,
        maximumAppendBytes: 1_048_576,
        maximumReadBytes: 33_554_432
    )

    public let maximumFileBytes: Int
    public let maximumAppendBytes: Int
    public let maximumReadBytes: Int

    public init(
        maximumFileBytes: Int,
        maximumAppendBytes: Int,
        maximumReadBytes: Int
    ) {
        self.maximumFileBytes = maximumFileBytes
        self.maximumAppendBytes = maximumAppendBytes
        self.maximumReadBytes = maximumReadBytes
    }
}

public enum CaptureFileOperationKind: String, Codable, CaseIterable, Sendable {
    case createDirectory = "create_directory"
    case write
    case synchronizeFile = "synchronize_file"
    case synchronizeDirectory = "synchronize_directory"
    case append
    case replace
    case rename
    case read
    case fileExists = "file_exists"
}

public struct CaptureFileOperation: Codable, Equatable, Sendable {
    public let kind: CaptureFileOperationKind
    public let path: String
    public let destinationPath: String?
    public let byteCount: Int?

    public init(
        kind: CaptureFileOperationKind,
        path: String,
        destinationPath: String? = nil,
        byteCount: Int? = nil
    ) {
        self.kind = kind
        self.path = path
        self.destinationPath = destinationPath
        self.byteCount = byteCount
    }
}

public typealias CaptureFileOperationObserver = @Sendable (CaptureFileOperation) throws -> Void

public protocol CaptureFileSystem: Sendable {
    var limits: CaptureFileSystemLimits { get }

    func createDirectory(at path: String) throws
    func write(_ data: Data, to path: String) throws
    func synchronizeFile(at path: String) throws
    func synchronizeDirectory(at path: String) throws
    func append(_ data: Data, to path: String) throws
    func replace(_ data: Data, at path: String) throws
    func rename(from sourcePath: String, to destinationPath: String) throws
    func read(at path: String, maximumBytes: Int?) throws -> Data
    func fileExists(at path: String) throws -> Bool
}

public extension CaptureFileSystem {
    func read(at path: String) throws -> Data {
        try read(at: path, maximumBytes: nil)
    }
}

/// Synchronous archive I/O for use inside a non-reentrant storage transaction.
///
/// The observers run immediately before and after each valid operation and may throw to
/// inject a deterministic fault on either side of the durability boundary. No mutable
/// state is stored here; one writer actor owns ordering and calls these methods without a
/// suspension point.
public struct FoundationCaptureFileSystem: CaptureFileSystem, Sendable {
    public let root: URL
    public let limits: CaptureFileSystemLimits
    private let observe: CaptureFileOperationObserver
    private let afterOperation: CaptureFileOperationObserver

    public init(
        root: URL,
        limits: CaptureFileSystemLimits = .production,
        observe: @escaping CaptureFileOperationObserver = { _ in },
        afterOperation: @escaping CaptureFileOperationObserver = { _ in }
    ) throws {
        guard root.isFileURL else { throw CaptureFileSystemError.invalidRoot }
        guard limits.maximumFileBytes > 0,
              limits.maximumAppendBytes > 0,
              limits.maximumReadBytes > 0,
              limits.maximumAppendBytes <= limits.maximumFileBytes,
              limits.maximumReadBytes <= limits.maximumFileBytes
        else { throw CaptureFileSystemError.invalidLimits }

        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: resolvedRoot.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue
        else { throw CaptureFileSystemError.invalidRoot }

        self.root = resolvedRoot
        self.limits = limits
        self.observe = observe
        self.afterOperation = afterOperation
    }

    public func createDirectory(at path: String) throws {
        let destination = try resolve(path)
        let operation = CaptureFileOperation(kind: .createDirectory, path: path)
        try observe(operation)
        do {
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: false
            )
        } catch {
            throw CaptureFileSystemError.ioFailure
        }
        try afterOperation(operation)
    }

    public func write(_ data: Data, to path: String) throws {
        try requireWriteSize(data.count)
        let destination = try resolve(path)
        guard FileManager.default.fileExists(atPath: destination.path) == false else {
            throw CaptureFileSystemError.destinationExists
        }
        let operation = CaptureFileOperation(kind: .write, path: path, byteCount: data.count)
        try observe(operation)
        guard FileManager.default.createFile(atPath: destination.path, contents: data) else {
            throw CaptureFileSystemError.ioFailure
        }
        try afterOperation(operation)
    }

    public func synchronizeFile(at path: String) throws {
        let file = try existing(path)
        let operation = CaptureFileOperation(kind: .synchronizeFile, path: path)
        try observe(operation)
        do {
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.synchronize()
        } catch {
            throw CaptureFileSystemError.ioFailure
        }
        try afterOperation(operation)
    }

    public func synchronizeDirectory(at path: String) throws {
        let directory = try existing(path, requiresDirectory: true)
        let operation = CaptureFileOperation(kind: .synchronizeDirectory, path: path)
        try observe(operation)
        #if canImport(Darwin)
        let descriptor = Darwin.open(directory.path, O_RDONLY)
        guard descriptor >= 0 else { throw CaptureFileSystemError.ioFailure }
        defer { _ = Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw CaptureFileSystemError.ioFailure }
        #else
        throw CaptureFileSystemError.ioFailure
        #endif
        try afterOperation(operation)
    }

    public func append(_ data: Data, to path: String) throws {
        guard data.isEmpty == false,
              data.count <= limits.maximumAppendBytes
        else { throw CaptureFileSystemError.byteLimitExceeded }
        let file = try existing(path)
        let currentSize = try size(of: file)
        guard currentSize <= limits.maximumFileBytes - data.count else {
            throw CaptureFileSystemError.byteLimitExceeded
        }
        let operation = CaptureFileOperation(kind: .append, path: path, byteCount: data.count)
        try observe(operation)
        do {
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            throw CaptureFileSystemError.ioFailure
        }
        try afterOperation(operation)
    }

    public func replace(_ data: Data, at path: String) throws {
        try requireWriteSize(data.count)
        let destination = try resolve(path)
        let operation = CaptureFileOperation(kind: .replace, path: path, byteCount: data.count)
        try observe(operation)
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            throw CaptureFileSystemError.ioFailure
        }
        try afterOperation(operation)
    }

    public func rename(from sourcePath: String, to destinationPath: String) throws {
        let source = try existing(sourcePath)
        let destination = try resolve(destinationPath)
        guard FileManager.default.fileExists(atPath: destination.path) == false else {
            throw CaptureFileSystemError.destinationExists
        }
        let operation = CaptureFileOperation(
            kind: .rename,
            path: sourcePath,
            destinationPath: destinationPath
        )
        try observe(operation)
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            throw CaptureFileSystemError.ioFailure
        }
        try afterOperation(operation)
    }

    public func read(at path: String, maximumBytes: Int? = nil) throws -> Data {
        let limit = maximumBytes ?? limits.maximumReadBytes
        guard limit > 0, limit <= limits.maximumReadBytes else {
            throw CaptureFileSystemError.byteLimitExceeded
        }
        let file = try existing(path)
        guard try size(of: file) <= limit else {
            throw CaptureFileSystemError.byteLimitExceeded
        }
        let operation = CaptureFileOperation(kind: .read, path: path, byteCount: limit)
        try observe(operation)
        let data: Data
        do {
            data = try Data(contentsOf: file, options: .mappedIfSafe)
            guard data.count <= limit else { throw CaptureFileSystemError.byteLimitExceeded }
        } catch let error as CaptureFileSystemError {
            throw error
        } catch {
            throw CaptureFileSystemError.ioFailure
        }
        try afterOperation(operation)
        return data
    }

    public func fileExists(at path: String) throws -> Bool {
        let file = try resolve(path)
        let operation = CaptureFileOperation(kind: .fileExists, path: path)
        try observe(operation)
        let exists = FileManager.default.fileExists(atPath: file.path)
        try afterOperation(operation)
        return exists
    }

    private func requireWriteSize(_ count: Int) throws {
        guard count > 0, count <= limits.maximumFileBytes else {
            throw CaptureFileSystemError.byteLimitExceeded
        }
    }

    private func resolve(_ path: String) throws -> URL {
        do {
            return try ArchivePath.resolve(path, under: root)
        } catch {
            throw CaptureFileSystemError.invalidPath
        }
    }

    private func existing(_ path: String, requiresDirectory: Bool = false) throws -> URL {
        let file = try resolve(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory),
              requiresDirectory == false || isDirectory.boolValue
        else { throw CaptureFileSystemError.missingFile }
        return file
    }

    private func size(of file: URL) throws -> Int {
        do {
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let size = values.fileSize else {
                throw CaptureFileSystemError.missingFile
            }
            return size
        } catch let error as CaptureFileSystemError {
            throw error
        } catch {
            throw CaptureFileSystemError.ioFailure
        }
    }
}
