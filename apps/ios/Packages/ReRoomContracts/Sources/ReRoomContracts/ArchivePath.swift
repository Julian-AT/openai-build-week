import Foundation

public enum ArchivePathRejection: String, Error, Equatable, Sendable {
    case invalidPath = "invalid_path"
}

public enum ArchivePath {
    public static let maximumUTF8Bytes = 240

    public static func validate(
        _ path: String,
        maximumBytes: Int = maximumUTF8Bytes
    ) throws {
        guard (1...Self.maximumUTF8Bytes).contains(maximumBytes),
              !path.isEmpty,
              path.utf8.count <= maximumBytes,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains("\0")
        else {
            throw ArchivePathRejection.invalidPath
        }

        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !segments.isEmpty,
              segments.allSatisfy({ segment in
                  guard segment != ".", segment != "..", let first = segment.utf8.first else {
                      return false
                  }
                  guard first.isArchivePathInitial else { return false }
                  return segment.utf8.allSatisfy(\.isArchivePathByte)
              })
        else {
            throw ArchivePathRejection.invalidPath
        }
    }

    public static func resolve(_ path: String, under root: URL) throws -> URL {
        try validate(path)
        guard root.isFileURL else { throw ArchivePathRejection.invalidPath }

        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = resolvedRoot.path
        var candidate = resolvedRoot
        for segment in path.split(separator: "/", omittingEmptySubsequences: false) {
            candidate = candidate
                .appendingPathComponent(String(segment), isDirectory: false)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard candidate.path.hasPrefix(rootPath + "/") else {
                throw ArchivePathRejection.invalidPath
            }
        }
        return candidate
    }
}

private extension UInt8 {
    var isArchivePathInitial: Bool {
        isASCIILetter || isASCIIDigit || self == 0x2d || self == 0x5f
    }

    var isArchivePathByte: Bool {
        isArchivePathInitial || self == 0x2e
    }

    var isASCIILetter: Bool {
        (0x41...0x5a).contains(self) || (0x61...0x7a).contains(self)
    }

    var isASCIIDigit: Bool {
        (0x30...0x39).contains(self)
    }
}
