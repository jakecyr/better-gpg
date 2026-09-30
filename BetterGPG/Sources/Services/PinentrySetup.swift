import Foundation

/// Points gpg-agent at a graphical passphrase prompt.
/// The default Homebrew pinentry is curses, which cannot ask for a passphrase
/// from a Mac app and fails before any secret key is tried.
enum PinentrySetup {
    static func ensureGUIPinentry(gpgBinary: String) {
        guard let fallback = guiPinentryPath() else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directory = home.appendingPathComponent(".gnupg", isDirectory: true)
        let configURL = directory.appendingPathComponent("gpg-agent.conf")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
            let updated = rewritten(existing, fallback: fallback)
            guard updated != normalized(existing) else { return }
            try Data(updated.utf8).write(to: configURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
            reloadAgent(gpgBinary: gpgBinary)
        } catch {
            return
        }
    }

    private static func guiPinentryPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/pinentry-mac",
            "/usr/local/bin/pinentry-mac",
            "/opt/local/bin/pinentry-mac"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func rewritten(_ existing: String, fallback: String) -> String {
        var kept: [String] = []
        var chosen: String?
        for line in existing.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.hasPrefix("#"),
               trimmed.lowercased().hasPrefix("pinentry-program") {
                let path = String(trimmed.dropFirst("pinentry-program".count))
                    .trimmingCharacters(in: .whitespaces)
                if isGraphicalPinentry(path) {
                    chosen = path
                }
                continue
            }
            kept.append(line)
        }
        while kept.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            kept.removeLast()
        }
        kept.append("pinentry-program \(chosen ?? fallback)")
        return kept.joined(separator: "\n") + "\n"
    }

    private static func isGraphicalPinentry(_ path: String) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name == "pinentry-mac"
            || name == "pinentry-gnome3"
            || name == "pinentry-qt"
            || name == "pinentry-gtk-2"
    }

    private static func normalized(_ text: String) -> String {
        text.hasSuffix("\n") || text.isEmpty ? text : text + "\n"
    }

    private static func reloadAgent(gpgBinary: String) {
        let sibling = URL(fileURLWithPath: gpgBinary)
            .deletingLastPathComponent()
            .appendingPathComponent("gpgconf")
            .path
        let binary = FileManager.default.isExecutableFile(atPath: sibling) ? sibling : "/usr/bin/gpgconf"
        guard FileManager.default.isExecutableFile(atPath: binary) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["--kill", "gpg-agent"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return
        }
        _ = finished.wait(timeout: .now() + 3)
    }
}
