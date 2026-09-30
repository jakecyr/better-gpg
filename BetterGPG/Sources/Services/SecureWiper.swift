import Darwin
import Foundation
import Security

enum SecureWiper {
    /// Overwrites a regular file, then deletes it.
    ///
    /// On APFS this cannot promise the previous blocks are gone, because the
    /// filesystem is copy-on-write. Callers that need a stronger guarantee
    /// should keep plaintext on the memory disk and eject it.
    static func wipeFile(at url: URL, passes: Int) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        if isDirectory.boolValue {
            throw SecureDeleteError.refusedDirectory(url)
        }

        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let handle = try FileHandle(forUpdating: url)
        let fd = handle.fileDescriptor
        _ = fcntl(fd, F_NOCACHE, 1)

        let passCount = min(3, max(1, passes))
        if size > 0 {
            for _ in 0..<passCount {
                try handle.seek(toOffset: 0)
                var remaining = size
                while remaining > 0 {
                    let count = Int(min(Int64(1 << 20), remaining))
                    var buffer = [UInt8](repeating: 0, count: count)
                    if SecRandomCopyBytes(kSecRandomDefault, count, &buffer) != errSecSuccess {
                        for index in buffer.indices {
                            buffer[index] = UInt8.random(in: .min ... .max)
                        }
                    }
                    try handle.write(contentsOf: buffer)
                    remaining -= Int64(count)
                }
                try handle.synchronize()
                _ = fcntl(fd, F_FULLFSYNC)
            }
        }

        try handle.truncate(atOffset: 0)
        try handle.synchronize()
        _ = fcntl(fd, F_FULLFSYNC)
        try handle.close()
        try fileManager.removeItem(at: url)
    }

    static func wipeFileAsync(at url: URL, passes: Int) async throws {
        try await Task.detached(priority: .userInitiated) {
            try wipeFile(at: url, passes: passes)
        }.value
    }

    /// Shreds every regular file under `url`, then removes the tree. Symlinks are removed, never followed.
    static func wipeItem(at url: URL, passes: Int) throws {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return }

        if values.isSymbolicLink == true {
            try fileManager.removeItem(at: url)
            return
        }
        if values.isDirectory != true {
            try wipeFile(at: url, passes: passes)
            return
        }

        var files: [URL] = []
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: keys) {
            for case let item as URL in enumerator {
                files.append(item)
            }
        }
        for item in files {
            let itemValues = try? item.resourceValues(forKeys: Set(keys))
            if itemValues?.isSymbolicLink == true {
                try? fileManager.removeItem(at: item)
            } else if itemValues?.isRegularFile == true {
                try wipeFile(at: item, passes: passes)
            }
        }
        try fileManager.removeItem(at: url)
    }

    static func wipeItemAsync(at url: URL, passes: Int) async throws {
        try await Task.detached(priority: .userInitiated) {
            try wipeItem(at: url, passes: passes)
        }.value
    }
}

enum SecureDeleteError: LocalizedError {
    case refusedDirectory(URL)

    var errorDescription: String? {
        switch self {
        case .refusedDirectory(let url):
            return "\(url.lastPathComponent) is a folder. BetterGPG shreds files, and leaves folders in place."
        }
    }
}
