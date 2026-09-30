import AppKit
import Foundation
import PDFKit
import os

extension Notification.Name {
    static let bettergpgOpenViewer = Notification.Name("bettergpgOpenViewer")
}

/// Encrypted files open in BetterGPG's own windows.
///
/// Text, PDFs, and images under the memory limit are decrypted straight into memory.
/// Everything else goes through a vault workspace. Closing a window saves edits back
/// into the encrypted file, then wipes the buffer and shreds the workspace.
@MainActor
@Observable
final class DocumentStore {
    private(set) var documents: [ViewerDocument] = []

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "com.better-gpg.app", category: "viewer")

    func attach(_ appState: AppState) {
        self.appState = appState
    }

    func document(_ id: UUID) -> ViewerDocument? {
        documents.first { $0.id == id }
    }

    func open(_ urls: [URL], autoCloseMinutes: Int? = nil) {
        guard let appState else { return }
        for url in urls {
            if let existing = documents.first(where: { $0.sourceURL.standardizedFileURL == url.standardizedFileURL }) {
                focus(existing)
                continue
            }
            let document = ViewerDocument(sourceURL: url)
            let minutes = autoCloseMinutes ?? appState.settings.autoLockMinutes
            if minutes > 0 {
                document.deadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
            }
            documents.append(document)
            NotificationCenter.default.post(name: .bettergpgOpenViewer, object: document.id)
            Task { await load(document) }
        }
        NSApp.activate(ignoringOtherApps: true)
        appState.refreshIndicators()
        ensureTicker()
    }

    func focus(_ document: ViewerDocument) {
        NSApp.activate(ignoringOtherApps: true)
        if let window = document.window {
            window.makeKeyAndOrderFront(nil)
        } else {
            NotificationCenter.default.post(name: .bettergpgOpenViewer, object: document.id)
        }
    }

    // MARK: - Save

    @discardableResult
    func save(_ document: ViewerDocument) async -> Bool {
        guard let appState else { return false }
        guard document.isDirty else { return true }
        guard document.canEdit else {
            document.phase = .saveFailed(document.readOnlyReason ?? "Recipients are hidden on this file, so changes cannot be encrypted back into it.")
            return false
        }
        switch document.phase {
        case .ready, .saveFailed: break
        default: return false
        }

        document.phase = .saving
        let snapshot = document.text
        var data = Data(snapshot.utf8)
        defer {
            if !data.isEmpty { data.resetBytes(in: 0..<data.count) }
        }

        let source = document.sourceURL
        let partial = source.deletingLastPathComponent()
            .appendingPathComponent(".\(source.lastPathComponent).partial-\(UUID().uuidString)")
        let signingKey = appState.settings.ownKeyFingerprint
        do {
            try await appState.gpgService.encrypt(
                data: data,
                fileName: document.plaintextName,
                recipients: document.recipients,
                outputURL: partial,
                sign: appState.settings.signWhenEncrypting && !signingKey.isEmpty,
                signingKey: signingKey
            )
            _ = try FileManager.default.replaceItemAt(source, withItemAt: partial)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            document.phase = .saveFailed(error.localizedDescription)
            return false
        }

        document.savedText = snapshot
        document.lastSaved = Date()
        document.phase = .ready
        appState.record("Saved and re-encrypted \(source.lastPathComponent)", reveal: source)
        return true
    }

    // MARK: - Close

    /// Saves edits, wipes the plaintext, and closes the window.
    /// Returns false when the save failed; the document stays open so nothing is lost.
    @discardableResult
    func close(_ id: UUID, saveChanges: Bool = true) async -> Bool {
        guard let document = document(id) else { return true }
        if document.closed { return true }
        while document.phase == .saving {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if document.closed { return true }

        if saveChanges, document.isDirty {
            guard await save(document) else {
                if document.window == nil {
                    NotificationCenter.default.post(name: .bettergpgOpenViewer, object: id)
                }
                return false
            }
        }

        document.closed = true
        document.phase = .closing
        let window = document.window
        document.window = nil
        window?.close()
        await teardown(document)
        documents.removeAll { $0.id == id }
        appState?.refreshIndicators()
        return true
    }

    func closeAll() async -> Bool {
        var allClosed = true
        for document in documents {
            let closed = await close(document.id)
            allClosed = allClosed && closed
        }
        return allClosed
    }

    func openExternally(_ document: ViewerDocument) async {
        guard let appState else { return }
        let source = document.sourceURL
        guard await close(document.id) else { return }
        appState.section = .sessions
        NotificationCenter.default.post(name: .bettergpgShowMain, object: nil)
        await appState.sessions.open(urls: [source], policy: .from(settings: appState.settings))
    }

    // MARK: - Load

    private func load(_ document: ViewerDocument) async {
        guard let appState else { return }
        if let info = try? await appState.encryptionInfo(for: document.sourceURL) {
            document.recipients = appState.saveRecipients(for: info)
        }
        document.recipientsHidden = document.recipients.isEmpty
        if document.recipientsHidden {
            document.readOnlyReason = "Recipients are hidden on this file, so edits cannot be saved back into it."
        }
        guard !document.closed else { return }

        let estimated = FileInfo.byteSize(of: document.sourceURL)
        let large = estimated > appState.settings.memoryLimitBytes
        let guessed = ViewerDocument.kind(forName: document.plaintextName)

        do {
            if guessed == .quickLook || large {
                let file = try await decryptToWorkspace(document, estimatedBytes: estimated)
                guard !document.closed else { return await teardown(document) }
                await present(document, file: file, guessed: guessed, large: large)
            } else {
                var data = try await appState.gpgService.decryptToData(fileURL: document.sourceURL)
                let buffer = SecureBuffer(taking: &data)
                document.buffer = buffer
                guard !document.closed else { return await teardown(document) }
                try await present(document, buffer: buffer, guessed: guessed)
            }
            guard !document.closed else { return await teardown(document) }
            document.phase = .ready
        } catch {
            logger.error("Viewer failed to open a file: \(error.localizedDescription, privacy: .public)")
            await teardown(document)
            if !document.closed {
                document.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func decryptToWorkspace(_ document: ViewerDocument, estimatedBytes: Int64) async throws -> URL {
        guard let appState else { throw GPGError.commandFailed("The app is not ready.") }
        let workspace = try await appState.vault.makeWorkspace(
            id: document.id,
            estimatedBytes: estimatedBytes,
            preferMemoryDisk: appState.settings.useRamDisk
        )
        let file = workspace.directory.appendingPathComponent(document.plaintextName)
        try await appState.gpgService.decrypt(fileURL: document.sourceURL, outputURL: file)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        appState.vault.record(id: document.id, source: document.sourceURL, fileURL: file, recipients: document.recipients)
        document.fileURL = file
        document.storageNote = workspace.onMemoryDisk
            ? "Temporary file on the memory disk"
            : "Temporary file, shredded when closed"
        return file
    }

    private func present(_ document: ViewerDocument, file: URL, guessed: ViewerKind?, large: Bool) async {
        let kind = guessed ?? (Self.sampleIsText(file) ? .text : .quickLook)
        switch kind {
        case .text where !large:
            if let text = try? String(contentsOf: file, encoding: .utf8) {
                document.text = text
                document.savedText = text
                document.kind = .text
                await dropWorkspace(document, note: "In memory only")
                return
            }
        case .text:
            document.readOnlyReason = "This file is larger than the in-memory limit, so it opens read-only."
        case .image:
            if let image = NSImage(contentsOf: file) {
                document.image = image
                document.kind = .image
                if !large {
                    await dropWorkspace(document, note: "In memory only")
                }
                return
            }
        case .pdf:
            if let pdf = PDFDocument(url: file) {
                document.pdf = pdf
                document.kind = .pdf
                return
            }
        case .quickLook:
            break
        }
        document.kind = .quickLook
    }

    private func present(_ document: ViewerDocument, buffer: SecureBuffer, guessed: ViewerKind?) async throws {
        let kind = guessed ?? (ViewerDocument.isUTF8Text(buffer.data.prefix(8192)) ? .text : .quickLook)
        switch kind {
        case .text:
            if let text = String(data: buffer.data, encoding: .utf8) {
                document.text = text
                document.savedText = text
                document.kind = .text
                document.storageNote = "In memory only"
                buffer.wipe()
                document.buffer = nil
                return
            }
        case .pdf:
            if let pdf = PDFDocument(data: buffer.data) {
                document.pdf = pdf
                document.kind = .pdf
                document.storageNote = "In memory only"
                return
            }
        case .image:
            if let image = NSImage(data: buffer.data) {
                document.image = image
                document.kind = .image
                document.storageNote = "In memory only"
                return
            }
        case .quickLook:
            break
        }

        guard let appState else { return }
        let workspace = try await appState.vault.makeWorkspace(
            id: document.id,
            estimatedBytes: Int64(buffer.count),
            preferMemoryDisk: appState.settings.useRamDisk
        )
        let file = workspace.directory.appendingPathComponent(document.plaintextName)
        guard FileManager.default.createFile(
            atPath: file.path,
            contents: buffer.data,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw GPGError.commandFailed("Could not write the temporary copy for Quick Look.")
        }
        appState.vault.record(id: document.id, source: document.sourceURL, fileURL: file, recipients: document.recipients)
        buffer.wipe()
        document.buffer = nil
        document.fileURL = file
        document.kind = .quickLook
        document.storageNote = workspace.onMemoryDisk
            ? "Temporary file on the memory disk"
            : "Temporary file, shredded when closed"
    }

    /// The content is in memory now, so the file copy can go early.
    private func dropWorkspace(_ document: ViewerDocument, note: String) async {
        document.fileURL = nil
        document.storageNote = note
        await appState?.vault.release(document.id)
    }

    private func teardown(_ document: ViewerDocument) async {
        document.pdf = nil
        document.image = nil
        document.text = ""
        document.savedText = ""
        document.buffer?.wipe()
        document.buffer = nil
        document.fileURL = nil
        await appState?.vault.release(document.id)
    }

    private static func sampleIsText(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let sample = handle.readData(ofLength: 8192)
        return ViewerDocument.isUTF8Text(sample)
    }

    // MARK: - Timer

    private func ensureTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                if self.documents.isEmpty {
                    self.ticker = nil
                    return
                }
                let now = Date()
                for document in self.documents where document.phase == .ready {
                    if let deadline = document.deadline, deadline <= now {
                        await self.close(document.id)
                    }
                }
            }
        }
    }
}
