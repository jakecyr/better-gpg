import Foundation

enum Zipper {
    static func zipDirectory(_ url: URL) async throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("zip")
        let result = try await Shell.run(
            executable: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--keepParent", url.path, destination.path]
        )
        guard result.status == 0 else {
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            throw GPGError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return destination
    }
}
