import Foundation
import os

struct PlaintextJournalEntry: Codable, Identifiable, Sendable {
    var id: UUID
    var directoryPath: String
    var sourcePath: String?
    var fileName: String?
    var recipients: [String]
    var baseline: Date?
    var needsRecovery: Bool
    var createdAt: Date
}

struct SweepReport: Sendable {
    var removed = 0
    var recovered: [URL] = []
    var kept = 0
}

/// Owns every place decrypted bytes can touch a filesystem.
///
/// Each open file gets its own directory, either on the memory disk or under a
/// private temp root. Anything in those roots that no open file owns is an orphan,
/// and the janitor shreds it. A journal on disk lets that happen after a crash too.
@MainActor
@Observable
final class PlaintextVault {
    struct Workspace: Sendable {
        let id: UUID
        let directory: URL
        let onMemoryDisk: Bool
    }

    private(set) var lastSweep: Date?
    private(set) var lastSweepReport = SweepReport()
    private(set) var liveCount = 0

    let diskRoot: URL
    @ObservationIgnored let ramDisk = RamDiskManager()
    @ObservationIgnored weak var appState: AppState?
    @ObservationIgnored private var live: [UUID: Workspace] = [:]
    @ObservationIgnored private var journal: [UUID: PlaintextJournalEntry] = [:]
    @ObservationIgnored private let journalURL: URL
    @ObservationIgnored private var janitor: Task<Void, Never>?
    @ObservationIgnored private var isSweeping = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.better-gpg.app", category: "vault")

    private static let markerName = ".metadata_never_index"
    private static let janitorInterval: Duration = .seconds(300)
    private static let recoveryGiveUp: TimeInterval = 86_400

    init() {
        diskRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterGPG-Plaintext", isDirectory: true)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        journalURL = support.appendingPathComponent("BetterGPG/plaintext-journal.json")
        loadJournal()
    }

    var hasLiveWorkspaces: Bool { !live.isEmpty }

    // MARK: - Lifecycle

    func prepareOnLaunch() async {
        _ = try? ensureDiskRoot()
        ramDisk.adoptExisting()
        await sweep()
    }

    func startJanitor() {
        guard janitor == nil else { return }
        janitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.janitorInterval)
                guard let self else { return }
                await self.sweep()
            }
        }
    }

    func shutdown() async {
        janitor?.cancel()
        janitor = nil
        await sweep()
    }

    // MARK: - Workspaces

    func makeWorkspace(id: UUID, estimatedBytes: Int64, preferMemoryDisk: Bool) async throws -> Workspace {
        if let existing = live[id] { return existing }

        var base: URL?
        if preferMemoryDisk, let appState {
            do {
                let mount = try await ramDisk.ensureMounted(megabytes: appState.settings.ramDiskMegabytes)
                let headroom: Int64 = 32 * 1_048_576
                if FileInfo.freeSpace(at: mount) > estimatedBytes * 2 + headroom {
                    base = mount
                }
            } catch {
                logger.error("Memory disk unavailable: \(error.localizedDescription, privacy: .public)")
            }
        }

        let root = try base ?? ensureDiskRoot()
        let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let workspace = Workspace(id: id, directory: directory, onMemoryDisk: base != nil)
        live[id] = workspace
        journal[id] = PlaintextJournalEntry(
            id: id,
            directoryPath: directory.path,
            sourcePath: nil,
            fileName: nil,
            recipients: [],
            baseline: nil,
            needsRecovery: false,
            createdAt: Date()
        )
        saveJournal()
        liveCount = live.count
        return workspace
    }

    /// Records what was decrypted so a crash leftover can be re-encrypted instead of lost.
    func record(id: UUID, source: URL, fileURL: URL, recipients: [String]) {
        guard var entry = journal[id] else { return }
        entry.sourcePath = source.path
        entry.fileName = fileURL.lastPathComponent
        entry.recipients = recipients
        entry.baseline = Self.modificationDate(of: fileURL) ?? Date()
        entry.needsRecovery = !recipients.isEmpty
        journal[id] = entry
        saveJournal()
    }

    /// Shreds a workspace. Returns false if something could not be removed; the janitor retries it.
    @discardableResult
    func release(_ id: UUID) async -> Bool {
        let directory = live[id]?.directory ?? journal[id].map { URL(fileURLWithPath: $0.directoryPath, isDirectory: true) }
        let onMemoryDisk = live[id]?.onMemoryDisk ?? false
        guard let directory else { return true }

        journal[id]?.needsRecovery = false
        live[id] = nil
        liveCount = live.count
        saveJournal()

        var succeeded = true
        do {
            try await SecureWiper.wipeItemAsync(at: directory, passes: onMemoryDisk ? 1 : passes)
            journal[id] = nil
        } catch {
            succeeded = false
            logger.error("Could not shred a workspace: \(error.localizedDescription, privacy: .public)")
        }
        saveJournal()
        await ejectMemoryDiskIfIdle()
        return succeeded
    }

    // MARK: - Janitor

    @discardableResult
    func sweep() async -> SweepReport {
        guard !isSweeping else { return lastSweepReport }
        isSweeping = true
        defer { isSweeping = false }

        var report = SweepReport()
        var candidates = children(of: diskRoot).filter { $0.lastPathComponent != Self.markerName }
        if let mount = ramDisk.mountPoint {
            candidates += children(of: mount).filter { UUID(uuidString: $0.lastPathComponent) != nil }
        }

        for url in candidates {
            let id = UUID(uuidString: url.lastPathComponent)
            if let id, live[id] != nil { continue }

            if let id, let entry = journal[id], entry.needsRecovery, Self.wasEdited(entry) {
                if let recovered = await recover(entry) {
                    report.recovered.append(recovered)
                } else if Date().timeIntervalSince(entry.createdAt) < Self.recoveryGiveUp {
                    report.kept += 1
                    continue
                }
            }

            let onMemoryDisk = ramDisk.mountPoint.map { url.path.hasPrefix($0.path) } ?? false
            do {
                try await SecureWiper.wipeItemAsync(at: url, passes: onMemoryDisk ? 1 : passes)
                report.removed += 1
                if let id { journal[id] = nil }
            } catch {
                report.kept += 1
                logger.error("Janitor could not remove a leftover: \(error.localizedDescription, privacy: .public)")
            }
        }

        journal = journal.filter { id, entry in
            live[id] != nil || FileManager.default.fileExists(atPath: entry.directoryPath)
        }
        saveJournal()

        lastSweep = Date()
        lastSweepReport = report
        if !report.recovered.isEmpty {
            let names = report.recovered.map(\.lastPathComponent).joined(separator: ", ")
            appState?.record("Recovered edits from a previous session into \(names)", reveal: report.recovered.first)
        }
        await ejectMemoryDiskIfIdle()
        return report
    }

    // MARK: - Helpers

    private var passes: Int {
        appState?.settings.secureDeletePasses ?? 1
    }

    private func ejectMemoryDiskIfIdle() async {
        guard ramDisk.mountPoint != nil, !live.values.contains(where: \.onMemoryDisk) else { return }
        let leftovers = ramDisk.mountPoint.map { children(of: $0).filter { UUID(uuidString: $0.lastPathComponent) != nil } } ?? []
        let waitingForRecovery = leftovers.contains { url in
            UUID(uuidString: url.lastPathComponent).flatMap { journal[$0] }?.needsRecovery == true
        }
        if !waitingForRecovery {
            await ramDisk.eject()
        }
    }

    private func recover(_ entry: PlaintextJournalEntry) async -> URL? {
        guard let appState, let fileName = entry.fileName, !entry.recipients.isEmpty else { return nil }
        let file = URL(fileURLWithPath: entry.directoryPath).appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }

        var directory = entry.sourcePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
            ?? FileManager.default.homeDirectoryForCurrentUser
        if !FileManager.default.fileExists(atPath: directory.path) {
            directory = FileManager.default.homeDirectoryForCurrentUser
        }
        let ext = (fileName as NSString).pathExtension
        let stem = (fileName as NSString).deletingPathExtension
        let name = ext.isEmpty ? "\(stem) (recovered).gpg" : "\(stem) (recovered).\(ext).gpg"
        let output = FileInfo.uniqueURL(directory: directory, preferredName: name)
        do {
            try await appState.gpgService.encrypt(
                fileURL: file,
                recipients: entry.recipients,
                outputURL: output,
                sign: false,
                signingKey: nil
            )
            return output
        } catch {
            logger.error("Recovery failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func wasEdited(_ entry: PlaintextJournalEntry) -> Bool {
        guard let fileName = entry.fileName, let baseline = entry.baseline else { return false }
        let file = URL(fileURLWithPath: entry.directoryPath).appendingPathComponent(fileName)
        guard let modified = modificationDate(of: file) else { return false }
        return modified > baseline.addingTimeInterval(1)
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    @discardableResult
    private func ensureDiskRoot() throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: diskRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: diskRoot.path)
        let marker = diskRoot.appendingPathComponent(Self.markerName)
        if !fileManager.fileExists(atPath: marker.path) {
            fileManager.createFile(atPath: marker.path, contents: nil)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var root = diskRoot
        try? root.setResourceValues(values)
        return diskRoot
    }

    private func children(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []
    }

    private func loadJournal() {
        guard let data = try? Data(contentsOf: journalURL),
              let entries = try? JSONDecoder().decode([PlaintextJournalEntry].self, from: data) else { return }
        journal = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func saveJournal() {
        do {
            try FileManager.default.createDirectory(
                at: journalURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(Array(journal.values))
            try data.write(to: journalURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journalURL.path)
        } catch {
            logger.error("Could not save the plaintext journal: \(error.localizedDescription, privacy: .public)")
        }
    }
}
