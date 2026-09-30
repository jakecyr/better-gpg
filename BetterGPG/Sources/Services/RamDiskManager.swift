import Foundation

/// A RAM-backed volume. Ejecting it drops decrypted bytes without writing them to the SSD.
@MainActor
final class RamDiskManager {
    private(set) var mountPoint: URL?
    private var device: String?
    static let volumeName = "BetterGPGMemory"
    static let expectedMount = URL(fileURLWithPath: "/Volumes/\(volumeName)", isDirectory: true)

    /// Picks up a volume left mounted by a previous run so its contents can be swept.
    func adoptExisting() {
        if mountPoint == nil, FileManager.default.fileExists(atPath: Self.expectedMount.path) {
            mountPoint = Self.expectedMount
        }
    }

    func ensureMounted(megabytes: Int) async throws -> URL {
        if let mountPoint, FileManager.default.fileExists(atPath: mountPoint.path) {
            return mountPoint
        }

        let megabytes = min(4096, max(128, megabytes))
        let sectors = megabytes * 1024 * 1024 / 512
        let attach = try await Shell.run(
            executable: "/usr/bin/hdiutil",
            arguments: ["attach", "-nomount", "ram://\(sectors)"]
        )
        guard attach.status == 0, let device = Self.deviceNode(in: attach.stdout + "\n" + attach.stderr) else {
            throw GPGError.ramDiskFailed(Self.message(from: attach, fallback: "Could not create a memory disk."))
        }

        let erase = try await Shell.run(
            executable: "/usr/sbin/diskutil",
            arguments: ["erasevolume", "HFS+", Self.volumeName, device]
        )
        guard erase.status == 0 else {
            _ = try? await Shell.run(executable: "/usr/bin/hdiutil", arguments: ["detach", device, "-force"])
            throw GPGError.ramDiskFailed(Self.message(from: erase, fallback: "Could not format the memory disk."))
        }

        let mount = Self.expectedMount
        guard FileManager.default.fileExists(atPath: mount.path) else {
            _ = try? await Shell.run(executable: "/usr/bin/hdiutil", arguments: ["detach", device, "-force"])
            throw GPGError.ramDiskFailed("The memory disk did not appear in /Volumes.")
        }

        FileManager.default.createFile(atPath: mount.appendingPathComponent(".metadata_never_index").path, contents: nil)
        _ = try? await Shell.run(executable: "/usr/bin/mdutil", arguments: ["-i", "off", mount.path])

        self.device = device
        mountPoint = mount
        return mount
    }

    func eject() async {
        guard let mountPoint else { return }
        _ = try? await Shell.run(executable: "/usr/sbin/diskutil", arguments: ["eject", mountPoint.path])
        if FileManager.default.fileExists(atPath: mountPoint.path) {
            _ = try? await Shell.run(executable: "/usr/sbin/diskutil", arguments: ["unmount", "force", mountPoint.path])
            if let device {
                _ = try? await Shell.run(executable: "/usr/bin/hdiutil", arguments: ["detach", device, "-force"])
            }
        }
        self.mountPoint = nil
        self.device = nil
    }

    private static func deviceNode(in text: String) -> String? {
        guard let match = text.range(of: #"/dev/disk[0-9]+"#, options: .regularExpression) else { return nil }
        return String(text[match])
    }

    private static func message(from result: ShellResult, fallback: String) -> String {
        let text = (result.stderr.isEmpty ? result.stdout : result.stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? fallback : text
    }
}
