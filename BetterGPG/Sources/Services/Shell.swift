import Foundation

struct ShellResult: Sendable {
    var stdout: String
    var stderr: String
    var status: Int32
}

struct RawShellResult: Sendable {
    var stdout: Data
    var stderr: Data
    var status: Int32

    var stderrText: String {
        String(decoding: stderr, as: UTF8.self)
    }
}

enum Shell {
    static func run(executable: String, arguments: [String], input: Data? = nil) async throws -> ShellResult {
        let raw = try await runRaw(executable: executable, arguments: arguments, input: input)
        return ShellResult(
            stdout: String(decoding: raw.stdout, as: UTF8.self),
            stderr: raw.stderrText,
            status: raw.status
        )
    }

    /// Runs a process off the main thread, feeding stdin and draining both output pipes concurrently.
    static func runRaw(executable: String, arguments: [String], input: Data? = nil) async throws -> RawShellResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw ShellError.notFound(executable)
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let outPipe = Pipe()
                let errPipe = Pipe()
                let inPipe = input == nil ? nil : Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                if let inPipe {
                    process.standardInput = inPipe
                } else {
                    process.standardInput = FileHandle.nullDevice
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let stdoutBox = LockedData()
                let stderrBox = LockedData()
                let group = DispatchGroup()

                if let input, let inPipe {
                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        try? inPipe.fileHandleForWriting.write(contentsOf: input)
                        try? inPipe.fileHandleForWriting.close()
                        group.leave()
                    }
                }

                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    stdoutBox.set(outPipe.fileHandleForReading.readDataToEndOfFile())
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    stderrBox.set(errPipe.fileHandleForReading.readDataToEndOfFile())
                    group.leave()
                }

                process.waitUntilExit()
                group.wait()

                continuation.resume(returning: RawShellResult(
                    stdout: stdoutBox.value,
                    stderr: stderrBox.value,
                    status: process.terminationStatus
                ))
            }
        }
    }
}

enum ShellError: LocalizedError {
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let path):
            return "Could not run \(path)."
        }
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func set(_ data: Data) {
        lock.lock()
        storage = data
        lock.unlock()
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
