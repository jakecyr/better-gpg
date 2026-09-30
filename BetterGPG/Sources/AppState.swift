import AppKit
import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case home
    case sessions
    case keys
    case groups

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .sessions: return "Sessions"
        case .keys: return "Keys"
        case .groups: return "Groups"
        }
    }

    var icon: String {
        switch self {
        case .home: return "square.and.arrow.down"
        case .sessions: return "lock.open"
        case .keys: return "person.text.rectangle"
        case .groups: return "person.3"
        }
    }
}

enum ActiveSheet: Identifiable {
    case encrypt(urls: [URL], groupID: UUID?)
    case decrypt(urls: [URL], mode: OpenMode)
    case importKey(text: String)
    case generateKey
    case review(items: [IncomingFile])

    var id: String {
        switch self {
        case .encrypt: return "encrypt"
        case .decrypt: return "decrypt"
        case .importKey: return "import"
        case .generateKey: return "generate"
        case .review: return "review"
        }
    }
}

struct ActivityEntry: Identifiable, Equatable {
    let id: UUID
    let date: Date
    var message: String
    var revealURL: URL?

    init(message: String, revealURL: URL?) {
        id = UUID()
        date = Date()
        self.message = message
        self.revealURL = revealURL
    }
}

@MainActor
@Observable
final class AppState {
    var publicKeys: [GPGKey] = []
    var secretKeys: [GPGKey] = []
    var groups: [KeyGroup] = []
    var settings: AppSettings = AppSettings.load()
    var isLoadingKeys = false
    var gpgAvailable = false
    var lastError: String?
    var section: AppSection = .home {
        didSet {
            guard section != oldValue else { return }
            let next = SidebarSelection.section(section)
            if sidebarSelection != next {
                sidebarSelection = next
            }
        }
    }
    var sidebarSelection: SidebarSelection = .section(.home)
    var isCreatingVaultNote = false
    var activeSheet: ActiveSheet?
    var activity: [ActivityEntry] = []

    let sessions: SessionManager
    let documents: DocumentStore
    let vault: PlaintextVault
    let vaultNotes: VaultStore
    private(set) var gpgService: GPGService
    private let groupsFileURL: URL
    private var queuedDecryptURLs: [URL] = []
    @ObservationIgnored private var absenceObservers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        let settings = AppSettings.load()
        self.settings = settings
        let service = GPGService(gpgPath: settings.gpgBinaryPath)
        self.gpgService = service
        self.gpgAvailable = service.isAvailable()
        self.groupsFileURL = Self.groupsStorageURL()
        sessions = SessionManager()
        documents = DocumentStore()
        vault = PlaintextVault()
        vaultNotes = VaultStore()
        loadGroups()
        vault.appState = self
        sessions.attach(self)
        documents.attach(self)
        vaultNotes.attach(self)
        vaultNotes.start()
        installAbsenceObservers()
    }

    /// Every unlocked file, whether it is in a BetterGPG window, a vault note, or another app.
    var unlockedCount: Int {
        sessions.exposedSessions.count + documents.documents.count + (vaultNotes.isUnlocked ? 1 : 0)
    }

    func refreshIndicators() {
        let count = unlockedCount
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    /// Recipients to encrypt edits back to: the file's own recipients, plus my key when that setting is on.
    func saveRecipients(for info: EncryptionInfo) -> [String] {
        var recipients = info.visibleRecipientKeyIds
        guard !recipients.isEmpty else { return [] }
        let own = settings.ownKeyFingerprint
        if settings.includeOwnKey, !own.isEmpty,
           !recipients.contains(where: { key(forKeyId: $0)?.fingerprint == own }) {
            recipients.append(own)
        }
        return recipients
    }

    func lockEverything() async -> Bool {
        let noteClosed = await vaultNotes.closeOpenNote()
        let viewersClosed = await documents.closeAll()
        await sessions.lockAll(force: false)
        return noteClosed && viewersClosed
    }

    private func installAbsenceObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification
        ]
        for name in names {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.lockForAbsence() }
            }
            absenceObservers.append((workspace, token))
        }
        let distributed = DistributedNotificationCenter.default()
        let token = distributed.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.lockForAbsence() }
        }
        absenceObservers.append((distributed, token))
    }

    private func lockForAbsence() async {
        guard settings.lockOnScreenLock, unlockedCount > 0 else { return }
        _ = await lockEverything()
    }

    var contactKeys: [GPGKey] {
        let secretIDs = Set(secretKeys.map(\.fingerprint))
        return publicKeys.filter { !secretIDs.contains($0.fingerprint) }
    }

    var ownKey: GPGKey? {
        secretKeys.first { $0.fingerprint == settings.ownKeyFingerprint }
    }

    // MARK: - Incoming files

    /// Routes files from drag, double-click, Finder, or Services.
    /// Returns true when the result needs the main window, for example a sheet.
    @discardableResult
    func handleIncomingFiles(_ urls: [URL], source: IncomingSource) -> Bool {
        let items = urls.map { IncomingFile(url: $0, kind: FileInfo.kind(of: $0)) }
        guard !items.isEmpty else { return false }

        if source == .finderEncrypt {
            activeSheet = .encrypt(urls: urls, groupID: preferredGroupID)
            section = .home
            return true
        }

        let kinds = Set(items.map(\.kind))
        if kinds.count == 1, let kind = kinds.first {
            return present(kind: kind, items: items, source: source)
        }
        activeSheet = .review(items: items)
        section = .home
        return true
    }

    func continueReview(_ items: [IncomingFile]) {
        let keyURLs = items.filter { $0.kind == .key }.map(\.url)
        let plain = items.filter { $0.kind == .plain || $0.kind == .folder }.map(\.url)
        let encrypted = items.filter { $0.kind == .encrypted }.map(\.url)

        Task {
            if !keyURLs.isEmpty {
                do {
                    try await importKeys(at: keyURLs)
                } catch {
                    lastError = error.localizedDescription
                }
            }
            if !plain.isEmpty {
                queuedDecryptURLs = encrypted
                activeSheet = .encrypt(urls: plain, groupID: preferredGroupID)
            } else if !encrypted.isEmpty {
                activeSheet = .decrypt(urls: encrypted, mode: settings.defaultOpenMode)
            } else {
                activeSheet = nil
                section = .keys
            }
        }
    }

    func consumeQueuedDecrypt() {
        let urls = queuedDecryptURLs
        queuedDecryptURLs = []
        guard !urls.isEmpty else { return }
        Task { @MainActor in
            activeSheet = .decrypt(urls: urls, mode: settings.defaultOpenMode)
        }
    }

    private func present(kind: FileKind, items: [IncomingFile], source: IncomingSource) -> Bool {
        switch kind {
        case .key:
            let text = items.compactMap { try? String(contentsOf: $0.url, encoding: .utf8) }.joined(separator: "\n")
            activeSheet = .importKey(text: text)
            return true
        case .encrypted:
            let urls = items.map(\.url)
            switch source {
            case .finderView:
                documents.open(urls)
                return false
            case .finderExternal:
                return openInExternalApp(urls)
            case .open:
                if settings.defaultOpenMode == .viewer {
                    documents.open(urls)
                    return false
                }
                return openInExternalApp(urls)
            case .drag, .finderEncrypt:
                activeSheet = .decrypt(urls: urls, mode: settings.defaultOpenMode)
                return true
            }
        case .plain, .folder:
            activeSheet = .encrypt(urls: items.map(\.url), groupID: preferredGroupID)
            section = .home
            return true
        }
    }

    private func openInExternalApp(_ urls: [URL]) -> Bool {
        if settings.confirmBeforeOpen {
            activeSheet = .decrypt(urls: urls, mode: .externalApp)
        } else {
            section = .sessions
            let policy = SessionPolicy.from(settings: settings)
            Task { await sessions.open(urls: urls, policy: policy) }
        }
        return true
    }

    private var preferredGroupID: UUID? {
        if let last = settings.lastGroupID, groups.contains(where: { $0.id == last }) {
            return last
        }
        return groups.count == 1 ? groups.first?.id : nil
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
            if settings.ownKeyFingerprint.isEmpty, secretKeys.count == 1, let only = secretKeys.first {
                settings.ownKeyFingerprint = only.fingerprint
                settings.includeOwnKey = true
                persistSettings()
            }
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

    func importKeys(at urls: [URL]) async throws {
        for url in urls {
            let data = try Data(contentsOf: url)
            try await gpgService.importKey(data: data)
        }
        await refreshKeys()
    }

    func receiveKeys(query: String) async throws {
        try await gpgService.receiveKeys(query: query)
        await refreshKeys()
    }

    func exportPublicKey(fingerprint: String) async throws -> String {
        try await gpgService.exportPublicKey(fingerprint: fingerprint)
    }

    func generateSecretKey(realName: String, email: String, passphrase: Data?) async throws {
        let fingerprint = try await gpgService.generateSecretKey(
            realName: realName,
            email: email,
            passphrase: passphrase
        )
        await refreshKeys()
        guard settings.ownKeyFingerprint.isEmpty else { return }
        settings.ownKeyFingerprint = fingerprint
        settings.includeOwnKey = true
        persistSettings()
    }

    func deleteKey(_ key: GPGKey) async throws {
        try await gpgService.deleteKey(fingerprint: key.fingerprint, isSecret: key.isSecret)
        for index in groups.indices {
            groups[index].keyFingerprints.removeAll { $0 == key.fingerprint }
        }
        if settings.ownKeyFingerprint == key.fingerprint {
            settings.ownKeyFingerprint = ""
            persistSettings()
        }
        saveGroups()
        await refreshKeys()
    }

    func gpgVersion() async -> String? {
        await gpgService.versionLine()
    }

    func key(forFingerprint fingerprint: String) -> GPGKey? {
        publicKeys.first { $0.fingerprint == fingerprint } ?? secretKeys.first { $0.fingerprint == fingerprint }
    }

    func key(forKeyId keyId: String) -> GPGKey? {
        (publicKeys + secretKeys).first { $0.matches(keyId) }
    }

    func recipients(for group: KeyGroup) -> [GPGKey] {
        group.keyFingerprints.compactMap { key(forFingerprint: $0) }
    }

    // MARK: - Groups

    @discardableResult
    func addGroup(name: String) -> UUID {
        let group = KeyGroup(name: name)
        groups.append(group)
        saveGroups()
        return group.id
    }

    func deleteGroup(_ group: KeyGroup) {
        groups.removeAll { $0.id == group.id }
        if settings.lastGroupID == group.id {
            settings.lastGroupID = nil
            persistSettings()
        }
        saveGroups()
    }

    func renameGroup(id: UUID, to name: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = name
        saveGroups()
    }

    func addKey(_ fingerprint: String, toGroup groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        guard !groups[index].keyFingerprints.contains(fingerprint) else { return }
        groups[index].keyFingerprints.append(fingerprint)
        saveGroups()
    }

    func removeKey(_ fingerprint: String, fromGroup groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].keyFingerprints.removeAll { $0 == fingerprint }
        saveGroups()
    }

    // MARK: - Encrypt / inspect

    func encrypt(
        files: [URL],
        recipients: [String],
        secureDeleteOriginals: Bool,
        sign: Bool,
        groupID: UUID?
    ) async throws -> [URL] {
        guard !recipients.isEmpty else { throw GPGError.noRecipients }

        var outputs: [URL] = []
        var temporaryZips: [URL] = []

        do {
            try await encryptPrepared(
                files: files,
                recipients: recipients,
                secureDeleteOriginals: secureDeleteOriginals,
                sign: sign,
                outputs: &outputs,
                temporaryZips: &temporaryZips
            )
        } catch {
            await discardTemporaryZips(temporaryZips)
            if !outputs.isEmpty {
                record("Encrypted \(outputs.count) file\(outputs.count == 1 ? "" : "s") before a failure", reveal: outputs.first)
            }
            throw error
        }
        await discardTemporaryZips(temporaryZips)

        if let groupID {
            settings.lastGroupID = groupID
            persistSettings()
        }
        let names = outputs.map(\.lastPathComponent).joined(separator: ", ")
        record("Encrypted \(names)", reveal: outputs.first)
        return outputs
    }

    private func encryptPrepared(
        files: [URL],
        recipients: [String],
        secureDeleteOriginals: Bool,
        sign: Bool,
        outputs: inout [URL],
        temporaryZips: inout [URL]
    ) async throws {
        for file in files {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory)
            let input: URL
            let outputName: String
            if isDirectory.boolValue {
                let zip = try await Zipper.zipDirectory(file)
                temporaryZips.append(zip)
                input = zip
                outputName = file.lastPathComponent + ".zip.gpg"
            } else {
                input = file
                outputName = file.lastPathComponent + ".gpg"
            }

            let output = FileInfo.uniqueURL(directory: file.deletingLastPathComponent(), preferredName: outputName)
            try await gpgService.encrypt(
                fileURL: input,
                recipients: recipients,
                outputURL: output,
                sign: sign && !settings.ownKeyFingerprint.isEmpty,
                signingKey: settings.ownKeyFingerprint
            )
            outputs.append(output)

            if secureDeleteOriginals, !isDirectory.boolValue {
                try await SecureWiper.wipeFileAsync(at: file, passes: settings.secureDeletePasses)
            }
        }
    }

    private func discardTemporaryZips(_ urls: [URL]) async {
        for url in urls {
            try? await SecureWiper.wipeFileAsync(at: url, passes: 1)
        }
    }

    func encryptionInfo(for fileURL: URL) async throws -> EncryptionInfo {
        let (recipientKeyIds, signerKeyId) = try await gpgService.listEncryptionInfo(fileURL: fileURL)
        var isCurrentUserRecipient = false
        for keyId in recipientKeyIds where await gpgService.hasSecretKey(keyId: keyId) {
            isCurrentUserRecipient = true
            break
        }
        return EncryptionInfo(
            recipientKeyIds: recipientKeyIds,
            signerKeyId: signerKeyId,
            isCurrentUserRecipient: isCurrentUserRecipient,
            isSigned: signerKeyId != nil
        )
    }

    // MARK: - Settings

    func persistSettings() {
        settings.clamp()
        settings.save()
        gpgService.setPath(settings.gpgBinaryPath)
        gpgAvailable = FileManager.default.isExecutableFile(atPath: settings.gpgBinaryPath)
        vaultNotes.updateLocation()
    }

    var vaultFolderIsAvailable: Bool {
        let path = settings.vaultPath
        guard !path.isEmpty else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func chooseVaultFolder() {
        let start = settings.vaultPath.isEmpty ? nil : URL(fileURLWithPath: settings.vaultPath)
        guard let url = SystemDialogs.chooseDirectory(
            message: "Choose where encrypted notes are stored. You can create a folder.",
            startingAt: start
        ) else { return }
        settings.vaultPath = url.path
        persistSettings()
    }

    func beginNewVaultNote() {
        Task { await self.prepareNewVaultNote() }
    }

    private func prepareNewVaultNote() async {
        guard gpgAvailable || gpgService.isAvailable() else {
            lastError = "GPG isn't available, so a note can't be encrypted."
            return
        }
        if secretKeys.isEmpty {
            await refreshKeys()
        }
        if settings.ownKeyFingerprint.isEmpty, secretKeys.count == 1, let only = secretKeys.first {
            settings.ownKeyFingerprint = only.fingerprint
            settings.includeOwnKey = true
            persistSettings()
        }
        guard !settings.ownKeyFingerprint.isEmpty else {
            lastError = secretKeys.isEmpty
                ? "Generate a secret key in Settings before creating a note. Vault notes are encrypted to that key."
                : "Choose your key in Settings before creating a note. Vault notes are encrypted to that key."
            return
        }
        if !vaultFolderIsAvailable {
            let start = settings.vaultPath.isEmpty ? nil : URL(fileURLWithPath: settings.vaultPath)
            guard let url = SystemDialogs.chooseDirectory(
                message: "Choose where encrypted notes are stored. You can create a folder.",
                startingAt: start
            ) else { return }
            settings.vaultPath = url.path
            persistSettings()
        }
        isCreatingVaultNote = true
    }

    func record(_ message: String, reveal: URL?) {
        activity.insert(ActivityEntry(message: message, revealURL: reveal), at: 0)
        if activity.count > 12 {
            activity.removeLast(activity.count - 12)
        }
    }

    // MARK: - Persistence

    private func saveGroups() {
        do {
            let data = try JSONEncoder().encode(groups)
            try FileManager.default.createDirectory(
                at: groupsFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: groupsFileURL, options: .atomic)
        } catch {
            lastError = "Could not save groups: \(error.localizedDescription)"
        }
    }

    private func loadGroups() {
        guard let data = try? Data(contentsOf: groupsFileURL),
              let loaded = try? JSONDecoder().decode([KeyGroup].self, from: data) else { return }
        groups = loaded
    }

    private static func groupsStorageURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("BetterGPG/groups.json")
    }
}
