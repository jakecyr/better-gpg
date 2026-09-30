import AppKit
import Darwin
import Foundation

enum VaultError: LocalizedError {
    case noVault
    case folderMissing
    case noOwnKey
    case invalidName
    case tooLarge
    case notText
    case noteNeedsSave

    var errorDescription: String? {
        switch self {
        case .noVault:
            return "Choose a vault folder before creating a note."
        case .folderMissing:
            return "The vault folder is missing. Choose it again in the sidebar or in Settings."
        case .noOwnKey:
            return "Choose your key in Settings. Vault notes are encrypted to that key."
        case .invalidName:
            return "Use a file name without slashes or a leading period."
        case .tooLarge:
            return "This note is larger than the memory limit in Settings, so it stays encrypted."
        case .notText:
            return "This file is not a text note, so it stays encrypted."
        case .noteNeedsSave:
            return "Save or discard the open note before creating another one."
        }
    }
}

/// Encrypted notes in a folder the user chose.
///
/// The sidebar learns file names from the directory listing and never decrypts them to build that list.
/// Opening a note decrypts into memory through GPG's stdout. Locking re-encrypts through GPG's stdin,
/// then clears the text view, its undo stack, and the in-memory string. Plaintext is not written to a file.
@MainActor
@Observable
final class VaultStore {
    private(set) var files: [VaultFile] = []
    private(set) var openNote: VaultNote?
    private(set) var listingError: String?

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var watchedPath: String?
    @ObservationIgnored private var appliedPath: String?
    @ObservationIgnored private var chain: Task<Void, Never>?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var listingScheduled = false

    var isUnlocked: Bool { openNote != nil }

    func attach(_ appState: AppState) {
        self.appState = appState
    }

    func start() {
        appliedPath = appState?.settings.vaultPath ?? ""
        refreshListing()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshListing()
            }
        }
    }

    /// Called after settings are saved. Reloads the name list when the folder changes.
    func updateLocation() {
        let path = appState?.settings.vaultPath ?? ""
        guard path != appliedPath else { return }
        appliedPath = path
        refreshListing()
        guard noteIsOutsideVault() else { return }
        Task { await self.closeOpenNote(saveChanges: true, updateSidebar: true) }
    }

    func refreshListing() {
        guard let directory = vaultDirectory else {
            files = []
            listingError = vaultMissingMessage
            stopWatching()
            return
        }
        if watchedPath != directory.path {
            startWatching(directory)
        }

        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            files = urls.compactMap { url in
                let name = url.lastPathComponent
                guard !name.contains(".partial-") else { return nil }
                let ext = url.pathExtension.lowercased()
                guard ["gpg", "pgp", "asc"].contains(ext) else { return nil }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                guard values?.isRegularFile != false else { return nil }
                return VaultFile(url: url)
            }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            listingError = nil
        } catch {
            files = []
            listingError = error.localizedDescription
        }
    }

    func open(path: String) async {
        try? await enqueue {
            await self.performOpen(path: path)
        }
    }

    func retryOpenNote() async {
        try? await enqueue {
            guard let note = self.openNote, note.isFailed else { return }
            note.phase = .loading
            note.readOnlyReason = nil
            note.recipients = []
            note.text = ""
            note.savedText = ""
            await self.load(note)
        }
    }

    @discardableResult
    func closeOpenNote(saveChanges: Bool = true, updateSidebar: Bool = true) async -> Bool {
        (try? await enqueue {
            await self.performClose(saveChanges: saveChanges, updateSidebar: updateSidebar)
        }) ?? false
    }

    @discardableResult
    func saveOpenNote() async -> Bool {
        (try? await enqueue {
            guard let note = self.openNote else { return true }
            return await self.performSave(note)
        }) ?? false
    }

    @discardableResult
    func create(name: String, kind: VaultNoteKind) async throws -> URL {
        try await enqueue {
            try await self.performCreate(name: name, kind: kind)
        }
    }

    func delete(_ url: URL) async {
        do {
            try await enqueue {
                try await self.performDelete(url)
            }
        } catch {
            appState?.lastError = error.localizedDescription
        }
    }

    // MARK: - Queue

    /// Serializes open, save, and lock so a decrypt cannot finish after the note was locked.
    /// `performOpen` calls `performClose` directly. Calling `closeOpenNote` from inside the queue would deadlock.
    private func enqueue<T: Sendable>(_ work: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = chain
        let task = Task { @MainActor () throws -> T in
            _ = await previous?.value
            return try await work()
        }
        chain = Task { _ = try? await task.value }
        return try await task.value
    }

    // MARK: - Open

    private func performOpen(path: String) async {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        if let note = openNote, note.sourceURL.path == url.path, !note.closed {
            if note.isFailed {
                note.phase = .loading
                note.readOnlyReason = nil
                note.recipients = []
                note.text = ""
                note.savedText = ""
                await load(note)
            }
            return
        }

        if openNote != nil {
            let previous = openNote?.sourceURL.path
            let closed = await performClose(saveChanges: true, updateSidebar: false)
            guard closed else {
                if let previous {
                    appState?.sidebarSelection = .vaultFile(previous)
                }
                return
            }
        }

        let note = VaultNote(sourceURL: url)
        openNote = note
        appState?.refreshIndicators()
        await load(note)
    }

    private func load(_ note: VaultNote) async {
        guard let appState else { return }
        guard !note.closed else { return }
        note.phase = .loading

        let limit = appState.settings.memoryLimitBytes
        if FileInfo.byteSize(of: note.sourceURL) > limit {
            note.phase = .failed(VaultError.tooLarge.localizedDescription)
            return
        }

        do {
            var data = try await appState.gpgService.decryptToData(fileURL: note.sourceURL)
            defer {
                if !data.isEmpty {
                    data.resetBytes(in: 0..<data.count)
                }
            }
            guard !note.closed else { return }
            guard data.count <= limit else {
                note.phase = .failed(VaultError.tooLarge.localizedDescription)
                return
            }
            guard data.isEmpty || ViewerDocument.isUTF8Text(data) else {
                note.phase = .failed(VaultError.notText.localizedDescription)
                return
            }
            let plaintext = String(data: data, encoding: .utf8) ?? ""
            guard !note.closed else { return }
            if let info = try? await appState.encryptionInfo(for: note.sourceURL) {
                note.recipients = appState.saveRecipients(for: info)
            }
            if note.recipients.isEmpty {
                note.readOnlyReason = "Recipients are hidden on this note, so edits cannot be saved back into it."
            }
            guard !note.closed else { return }
            note.text = plaintext
            note.savedText = plaintext
            note.phase = .ready
        } catch {
            guard !note.closed else { return }
            note.text = ""
            note.savedText = ""
            note.phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Save and lock

    private func performSave(_ note: VaultNote) async -> Bool {
        guard let appState else { return false }
        guard note.isDirty else { return true }
        guard note.readOnlyReason == nil, !note.recipients.isEmpty, !note.isFailed else {
            note.phase = .saveFailed(note.readOnlyReason ?? "This note cannot be encrypted again.")
            return false
        }

        let snapshot = note.text
        if note.phase != .closing {
            note.phase = .saving
        }
        var data = Data(snapshot.utf8)
        defer {
            if !data.isEmpty {
                data.resetBytes(in: 0..<data.count)
            }
        }

        let source = note.sourceURL
        let partial = source.deletingLastPathComponent()
            .appendingPathComponent(".\(source.lastPathComponent).partial-\(UUID().uuidString)")
        let signingKey = appState.settings.ownKeyFingerprint
        do {
            try await appState.gpgService.encrypt(
                data: data,
                fileName: note.displayName,
                recipients: note.recipients,
                outputURL: partial,
                sign: appState.settings.signWhenEncrypting && !signingKey.isEmpty,
                signingKey: signingKey
            )
            _ = try FileManager.default.replaceItemAt(source, withItemAt: partial)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: source.path)
        } catch {
            if FileManager.default.fileExists(atPath: partial.path) {
                try? await SecureWiper.wipeFileAsync(at: partial, passes: 1)
            }
            note.phase = .saveFailed(error.localizedDescription)
            return false
        }

        note.savedText = snapshot
        if note.phase != .closing {
            note.phase = .ready
        }
        appState.record("Saved and re-encrypted \(source.lastPathComponent)", reveal: source)
        return true
    }

    private func performClose(saveChanges: Bool, updateSidebar: Bool) async -> Bool {
        guard let note = openNote else { return true }
        if note.closed { return true }

        while note.phase == .saving {
            try? await Task.sleep(for: .milliseconds(40))
            if note.closed { return true }
        }
        if note.closed { return true }

        if saveChanges, let live = note.textView?.string, live != note.text {
            note.text = live
        }
        if saveChanges, note.isDirty {
            note.sealed = true
            note.textView?.isEditable = false
            guard await performSave(note) else {
                note.sealed = false
                note.textView?.isEditable = note.allowsEditing
                return false
            }
        }

        note.closed = true
        note.sealed = true
        note.phase = .closing
        wipe(note)
        openNote = nil
        if updateSidebar, let appState, case .vaultFile = appState.sidebarSelection {
            appState.sidebarSelection = .section(appState.section)
        }
        appState?.refreshIndicators()
        return true
    }

    private func wipe(_ note: VaultNote) {
        let textView = note.textView
        textView?.isEditable = false
        textView?.undoManager?.removeAllActions()
        textView?.string = ""
        textView?.textStorage?.setAttributedString(NSAttributedString())
        textView?.undoManager?.removeAllActions()
        note.textView = nil
        note.text = ""
        note.savedText = ""
        note.recipients = []
    }

    // MARK: - Create and delete

    private func performCreate(name: String, kind: VaultNoteKind) async throws -> URL {
        guard let appState else { throw VaultError.noVault }
        guard let directory = vaultDirectory else {
            throw appState.settings.vaultPath.isEmpty ? VaultError.noVault : VaultError.folderMissing
        }
        let fingerprint = appState.settings.ownKeyFingerprint
        guard !fingerprint.isEmpty else { throw VaultError.noOwnKey }
        guard let plaintextName = VaultNoteName.make(from: name, kind: kind) else {
            throw VaultError.invalidName
        }
        if openNote != nil {
            let closed = await performClose(saveChanges: true, updateSidebar: false)
            guard closed else { throw VaultError.noteNeedsSave }
        }

        let output = FileInfo.uniqueURL(directory: directory, preferredName: plaintextName + ".gpg")
        var data = Data()
        defer {
            if !data.isEmpty {
                data.resetBytes(in: 0..<data.count)
            }
        }
        let signingKey = appState.settings.ownKeyFingerprint
        do {
            try await appState.gpgService.encrypt(
                data: data,
                fileName: plaintextName,
                recipients: [fingerprint],
                outputURL: output,
                sign: appState.settings.signWhenEncrypting && !signingKey.isEmpty,
                signingKey: signingKey
            )
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
        } catch {
            if FileManager.default.fileExists(atPath: output.path) {
                try? await SecureWiper.wipeFileAsync(at: output, passes: 1)
            }
            throw error
        }

        let note = VaultNote(sourceURL: output)
        note.recipients = [fingerprint]
        note.text = ""
        note.savedText = ""
        note.phase = .ready
        note.showsRender = kind == .markdown
        openNote = note
        refreshListing()
        appState.refreshIndicators()
        appState.record("Created encrypted note \(output.lastPathComponent)", reveal: output)
        return output.standardizedFileURL
    }

    private func performDelete(_ url: URL) async throws {
        let standard = url.standardizedFileURL
        if openNote?.sourceURL.path == standard.path {
            _ = await performClose(saveChanges: false, updateSidebar: true)
        }
        let passes = appState?.settings.secureDeletePasses ?? 1
        try await SecureWiper.wipeFileAsync(at: standard, passes: passes)
        if let appState, case .vaultFile(let path) = appState.sidebarSelection, path == standard.path {
            appState.sidebarSelection = .section(appState.section)
        }
        refreshListing()
        appState?.record("Shredded encrypted note \(standard.lastPathComponent)", reveal: nil)
    }

    // MARK: - Folder watching

    private var vaultDirectory: URL? {
        let path = appState?.settings.vaultPath ?? ""
        guard !path.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    private var vaultMissingMessage: String? {
        let path = appState?.settings.vaultPath ?? ""
        guard !path.isEmpty else { return nil }
        return "The vault folder is missing."
    }

    private func noteIsOutsideVault() -> Bool {
        guard let note = openNote else { return false }
        guard let vault = vaultDirectory else { return true }
        return note.sourceURL.deletingLastPathComponent().standardizedFileURL.path != vault.path
    }

    private func startWatching(_ directory: URL) {
        stopWatching()
        let fd = Darwin.open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .link],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self, !self.listingScheduled else { return }
                self.listingScheduled = true
                try? await Task.sleep(for: .milliseconds(200))
                self.listingScheduled = false
                self.refreshListing()
            }
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        watcher = source
        watchedPath = directory.path
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
        watchedPath = nil
    }
}
