import Foundation
import AppKit

@MainActor
final class AppState: ObservableObject {
    // MARK: - Published state
    @Published var publicKeys: [GPGKey] = []
    @Published var secretKeys: [GPGKey] = []
    @Published var groups: [KeyGroup] = []
    @Published var settings: AppSettings = AppSettings.load()
    @Published var isLoadingKeys: Bool = false
    @Published var gpgAvailable: Bool = false
    @Published var lastError: String? = nil

    // Pending file requests from Finder right-click
    @Published var pendingEncryptURLs: [URL] = []
    @Published var pendingDecryptURLs: [URL] = []
    @Published var activeTab: SidebarItem = .keys

    // MARK: - Private
    private(set) var gpgService: GPGService
    private let groupsFileURL: URL

    init() {
        let settings = AppSettings.load()
        self.settings = settings
        self.gpgService = GPGService(gpgPath: settings.gpgBinaryPath)
        self.groupsFileURL = Self.groupsStorageURL()
        self.gpgAvailable = FileManager.default.fileExists(atPath: settings.gpgBinaryPath)
        loadGroups()
    }

    // MARK: - GPG path management

    func updateGPGPath(_ path: String) {
        settings.gpgBinaryPath = path
        settings.save()
        gpgService = GPGService(gpgPath: path)
        gpgAvailable = FileManager.default.fileExists(atPath: path)
    }

    // MARK: - Keys

    func refreshKeys() async {
        isLoadingKeys = true
        lastError = nil
        do {
            async let pub = gpgService.listPublicKeys()
            async let sec = gpgService.listSecretKeys()
            let (pubKeys, secKeys) = try await (pub, sec)
            publicKeys = pubKeys
            secretKeys = secKeys
            gpgAvailable = true
        } catch {
            lastError = error.localizedDescription
            gpgAvailable = gpgService.isAvailable()
        }
        isLoadingKeys = false
    }

    func importKey(armored: String) async throws {
        try await gpgService.importKey(armored: armored)
        await refreshKeys()
    }

    func exportPublicKey(fingerprint: String) async throws -> String {
        return try await gpgService.exportPublicKey(fingerprint: fingerprint)
    }

    func deleteKey(_ key: GPGKey) async throws {
        try await gpgService.deleteKey(fingerprint: key.fingerprint, isSecret: key.isSecret)
        // Remove from groups
        for i in groups.indices {
            groups[i].keyFingerprints.removeAll { $0 == key.fingerprint }
        }
        saveGroups()
        await refreshKeys()
    }

    // MARK: - Groups

    func addGroup(name: String) {
        let group = KeyGroup(name: name)
        groups.append(group)
        saveGroups()
    }

    func deleteGroup(_ group: KeyGroup) {
        groups.removeAll { $0.id == group.id }
        saveGroups()
    }

    func renameGroup(_ group: KeyGroup, to name: String) {
        guard let i = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[i].name = name
        saveGroups()
    }

    func addKey(_ fingerprint: String, toGroup groupID: UUID) {
        guard let i = groups.firstIndex(where: { $0.id == groupID }) else { return }
        if !groups[i].keyFingerprints.contains(fingerprint) {
            groups[i].keyFingerprints.append(fingerprint)
            saveGroups()
        }
    }

    func removeKey(_ fingerprint: String, fromGroup groupID: UUID) {
        guard let i = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[i].keyFingerprints.removeAll { $0 == fingerprint }
        saveGroups()
    }

    // MARK: - Encrypt / Decrypt

    func encrypt(files: [URL], recipients: [String], outputSameDir: Bool) async throws -> [URL] {
        var allRecipients = recipients
        if settings.includeOwnKey && !settings.ownKeyFingerprint.isEmpty {
            if !allRecipients.contains(settings.ownKeyFingerprint) {
                allRecipients.append(settings.ownKeyFingerprint)
            }
        }

        var outputs: [URL] = []
        for file in files {
            let dir = outputSameDir ? file.deletingLastPathComponent() : file.deletingLastPathComponent()
            let outURL = dir.appendingPathComponent(file.lastPathComponent + ".gpg")
            try await gpgService.encrypt(
                fileURL: file,
                recipients: allRecipients,
                outputURL: outURL,
                sign: settings.signWhenEncrypting,
                signingKey: settings.ownKeyFingerprint.isEmpty ? nil : settings.ownKeyFingerprint
            )
            if settings.deleteOriginalAfterEncrypt {
                try? FileManager.default.removeItem(at: file)
            }
            outputs.append(outURL)
        }
        return outputs
    }

    func decrypt(files: [URL]) async throws -> [URL] {
        var outputs: [URL] = []
        for file in files {
            let dir = file.deletingLastPathComponent()
            var outName = file.lastPathComponent
            if outName.hasSuffix(".gpg") {
                outName = String(outName.dropLast(4))
            } else {
                outName += ".decrypted"
            }
            let outURL = dir.appendingPathComponent(outName)
            try await gpgService.decrypt(fileURL: file, outputURL: outURL)
            outputs.append(outURL)
        }
        return outputs
    }

    // MARK: - Settings

    func saveSettings() {
        settings.save()
        updateGPGPath(settings.gpgBinaryPath)
    }

    // MARK: - Persistence helpers

    private func saveGroups() {
        do {
            let data = try JSONEncoder().encode(groups)
            try FileManager.default.createDirectory(
                at: groupsFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: groupsFileURL)
        } catch {
            lastError = "Failed to save groups: \(error.localizedDescription)"
        }
    }

    private func loadGroups() {
        guard let data = try? Data(contentsOf: groupsFileURL),
              let loaded = try? JSONDecoder().decode([KeyGroup].self, from: data) else { return }
        groups = loaded
    }

    private static func groupsStorageURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("GPGeze/groups.json")
    }

    // MARK: - Helpers

    func key(forFingerprint fp: String) -> GPGKey? {
        publicKeys.first { $0.fingerprint == fp } ?? secretKeys.first { $0.fingerprint == fp }
    }

    func recipients(forGroup group: KeyGroup) -> [GPGKey] {
        group.keyFingerprints.compactMap { key(forFingerprint: $0) }
    }
}

enum SidebarItem: String, Hashable, CaseIterable {
    case keys = "Keys"
    case groups = "Groups"
    case encrypt = "Encrypt"
    case decrypt = "Decrypt"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .keys: return "person.text.rectangle"
        case .groups: return "person.3"
        case .encrypt: return "lock.fill"
        case .decrypt: return "lock.open.fill"
        case .settings: return "gear"
        }
    }
}
