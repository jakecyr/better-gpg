import Foundation

enum FileKind: String, Hashable, Sendable {
    case plain
    case folder
    case encrypted
    case key
}

struct IncomingFile: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let kind: FileKind

    init(url: URL, kind: FileKind) {
        self.id = UUID()
        self.url = url
        self.kind = kind
    }

    var actionTitle: String {
        switch kind {
        case .plain:
            return "Encrypt"
        case .folder:
            return "Zip, then encrypt"
        case .encrypted:
            return "Open securely"
        case .key:
            return "Import key"
        }
    }
}

enum IncomingSource: Sendable {
    /// Dropped on the window or chosen from a panel. Always asks first.
    case drag
    /// Double-clicked. Uses the default open mode.
    case open
    case finderEncrypt
    case finderView
    case finderExternal
}

enum FileInfo {
    static func kind(of url: URL) -> FileKind {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if exists, isDirectory.boolValue { return .folder }

        if let sniffed = sniff(url) {
            return sniffed
        }

        switch url.pathExtension.lowercased() {
        case "gpg", "pgp":
            return .encrypted
        default:
            return .plain
        }
    }

    static func byteSize(of url: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return Int64(values?.fileSize ?? 0)
        }

        let keys: Set<URLResourceKey> = [.fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: keys), values.isDirectory != true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func plaintextName(forEncrypted url: URL) -> String {
        let name = url.lastPathComponent
        let lower = name.lowercased()
        for suffix in [".gpg", ".pgp", ".asc"] where lower.hasSuffix(suffix) {
            let stripped = String(name.dropLast(suffix.count))
            if !stripped.isEmpty { return stripped }
        }
        return name + ".decrypted"
    }

    static func uniqueURL(directory: URL, preferredName: String) -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent(preferredName)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let ext = candidate.pathExtension
        let base = candidate.deletingPathExtension().lastPathComponent
        for index in 2..<500 {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = directory.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return directory.appendingPathComponent(UUID().uuidString + "-" + preferredName)
    }

    static func freeSpace(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])
        if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 {
            return important
        }
        return Int64(values?.volumeAvailableCapacity ?? 0)
    }

    /// Reads only the leading bytes, enough to tell a key from an encrypted message.
    private static func sniff(_ url: URL) -> FileKind? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 8192)
        guard let text = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .utf8) else {
            return nil
        }
        if text.contains("BEGIN PGP PUBLIC KEY BLOCK") || text.contains("BEGIN PGP PRIVATE KEY BLOCK") {
            return .key
        }
        if text.contains("BEGIN PGP MESSAGE") {
            return .encrypted
        }
        return nil
    }
}
