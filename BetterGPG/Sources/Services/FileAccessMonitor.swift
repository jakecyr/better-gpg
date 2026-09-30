import Foundation

enum FileOpenState: Sendable {
    case open
    case closed
    case unknown
}

enum FileAccessMonitor {
    /// Whether another process has the file open.
    /// `.unknown` means `lsof` could not be trusted, usually because Full Disk Access is off.
    static func state(of url: URL) async -> FileOpenState {
        await Task.detached(priority: .utility) {
            stateSynchronously(of: url)
        }.value
    }

    private static func stateSynchronously(of url: URL) -> FileOpenState {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-t", "--", url.path]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            return .unknown
        }
        process.waitUntilExit()
        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let others = stdout.split(whereSeparator: \.isNewline).contains { line in
            guard let pid = Int32(line) else { return false }
            return pid != ownPID
        }
        if others { return .open }
        let lowered = stderr.lowercased()
        if lowered.contains("denied") || lowered.contains("can't stat") || lowered.contains("operation not permitted") {
            return .unknown
        }
        return .closed
    }
}
