import AppKit
import Foundation
import os

/// Files unlocked for another app, watched until they can be locked again.
@MainActor
@Observable
final class SessionManager {
    private(set) var sessions: [PlaintextSession] = []

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private let logger = Logger(subsystem: "com.better-gpg.app", category: "sessions")
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var lockingIDs = Set<UUID>()

    var exposedSessions: [PlaintextSession] {
        sessions.filter(\.holdsPlaintext)
    }

    var needsAttention: Bool {
        sessions.contains { $0.phase == .overdue || ($0.phase == .failed && $0.holdsPlaintext) }
    }

    func attach(_ appState: AppState) {
        self.appState = appState
    }

    func open(urls: [URL], policy: SessionPolicy) async {
        for url in urls {
            await openOne(url, policy: policy)
        }
    }

    func lock(_ id: UUID, force: Bool) async {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        guard session.phase == .exposed || session.phase == .overdue || session.phase == .failed else { return }
        guard let plaintextURL = session.plaintextURL else {
            finish(id, phase: .failed, message: "The unlocked file is missing.")
            return
        }
        guard !lockingIDs.contains(id) else { return }

        if !force {
            let openState = await FileAccessMonitor.state(of: plaintextURL)
            if openState != .closed {
                update(id) { item in
                    item.phase = .overdue
                    if openState == .open {
                        item.sawFileOpen = true
                        item.lastOpenAt = Date()
                    } else {
                        item.resultNote = "BetterGPG cannot see whether another app still has this file open. Choose Lock Anyway when you are finished."
                    }
                }
                return
            }
        }

        lockingIDs.insert(id)
        defer { lockingIDs.remove(id) }
        update(id) { $0.phase = .locking }

        do {
            if session.policy.finishAction == .reencryptAndShred {
                try await reencrypt(session)
            }
            let wiped = await appState?.vault.release(id) ?? false
            let saved = session.policy.finishAction == .reencryptAndShred
                ? "Saved changes into the encrypted file"
                : "Discarded changes"
            finish(id, phase: .done, message: wiped
                   ? "\(saved) and shredded the unlocked copy."
                   : "\(saved). The unlocked copy will be shredded on the next cleanup pass.")
        } catch {
            logger.error("Lock failed: \(error.localizedDescription, privacy: .public)")
            update(id) { item in
                item.phase = .failed
                item.errorMessage = error.localizedDescription
                item.resultNote = "The unlocked copy is still available."
            }
        }
        updateActivity()
    }

    func shredPlaintext(_ id: UUID, force: Bool) async {
        guard let session = sessions.first(where: { $0.id == id }),
              let plaintextURL = session.plaintextURL else { return }
        if !force, await FileAccessMonitor.state(of: plaintextURL) != .closed {
            update(id) { $0.phase = .overdue }
            return
        }
        update(id) { $0.phase = .locking }
        let wiped = await appState?.vault.release(id) ?? false
        finish(id, phase: .done, message: wiped
               ? "Shredded the unlocked copy. The original encrypted file is unchanged."
               : "The unlocked copy will be shredded on the next cleanup pass.")
    }

    func lockAll(force: Bool) async {
        for id in sessions.filter(\.holdsPlaintext).map(\.id) {
            await lock(id, force: force)
        }
    }

    func dismiss(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }), !session.holdsPlaintext else { return }
        sessions.removeAll { $0.id == id }
        updateActivity()
    }

    func clearFinished() {
        sessions.removeAll { $0.phase == .done }
        updateActivity()
    }

    // MARK: - Open

    private func openOne(_ url: URL, policy: SessionPolicy) async {
        let id = UUID()
        sessions.insert(PlaintextSession(
            id: id,
            sourceURL: url,
            plaintextURL: nil,
            recipientKeyIDs: [],
            policy: policy,
            phase: .preparing,
            startedAt: Date(),
            deadline: policy.autoLockAfter.map { Date().addingTimeInterval($0) },
            sawFileOpen: false,
            lastOpenAt: nil,
            usingRamDisk: policy.useRamDisk,
            fellBackToDisk: false,
            errorMessage: nil,
            resultNote: nil,
            encryptionInfo: nil
        ), at: 0)
        updateActivity()
        ensureMonitor()

        guard let appState else {
            finish(id, phase: .failed, message: "The app is not ready.")
            return
        }

        let info = (try? await appState.encryptionInfo(for: url)) ?? EncryptionInfo(
            recipientKeyIds: [],
            signerKeyId: nil,
            isCurrentUserRecipient: false,
            isSigned: false
        )
        var resolvedPolicy = policy
        let recipients = appState.saveRecipients(for: info)
        if recipients.isEmpty {
            resolvedPolicy.finishAction = .shredOnly
        }

        let workspace: PlaintextVault.Workspace
        do {
            workspace = try await appState.vault.makeWorkspace(
                id: id,
                estimatedBytes: FileInfo.byteSize(of: url),
                preferMemoryDisk: resolvedPolicy.useRamDisk
            )
        } catch {
            finish(id, phase: .failed, message: error.localizedDescription, info: info)
            return
        }

        let plaintextURL = workspace.directory.appendingPathComponent(FileInfo.plaintextName(forEncrypted: url))
        do {
            try await appState.gpgService.decrypt(fileURL: url, outputURL: plaintextURL)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plaintextURL.path)
        } catch {
            await appState.vault.release(id)
            finish(id, phase: .failed, message: error.localizedDescription, info: info)
            return
        }
        appState.vault.record(id: id, source: url, fileURL: plaintextURL, recipients: recipients)

        let fellBack = resolvedPolicy.useRamDisk && !workspace.onMemoryDisk
        update(id) { session in
            session.plaintextURL = plaintextURL
            session.recipientKeyIDs = recipients
            session.policy = resolvedPolicy
            session.phase = .exposed
            session.usingRamDisk = workspace.onMemoryDisk
            session.fellBackToDisk = fellBack
            session.encryptionInfo = info
            if recipients.isEmpty {
                session.resultNote = "Recipients are hidden, so locking will shred the unlocked copy and leave the original encrypted file as it is."
            } else if fellBack {
                session.resultNote = "The memory disk was full or unavailable, so this copy is in a private temporary folder until it is shredded."
            }
        }

        if resolvedPolicy.openAfterDecrypt, !NSWorkspace.shared.open(plaintextURL) {
            update(id) { $0.resultNote = "The file is unlocked. Use Reveal to open it." }
        }
        updateActivity()
    }

    private func reencrypt(_ session: PlaintextSession) async throws {
        guard let appState, let plaintextURL = session.plaintextURL else {
            throw GPGError.commandFailed("Nothing to encrypt.")
        }
        let recipients = session.recipientKeyIDs.filter { !$0.isEmpty }
        guard !recipients.isEmpty else { throw GPGError.noRecipients }

        let partial = session.sourceURL.deletingLastPathComponent()
            .appendingPathComponent(".\(session.sourceURL.lastPathComponent).partial-\(session.id.uuidString)")
        let signingKey = appState.settings.ownKeyFingerprint
        do {
            try await appState.gpgService.encrypt(
                fileURL: plaintextURL,
                recipients: recipients,
                outputURL: partial,
                sign: appState.settings.signWhenEncrypting && !signingKey.isEmpty,
                signingKey: signingKey
            )
            _ = try FileManager.default.replaceItemAt(session.sourceURL, withItemAt: partial)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    // MARK: - Monitor

    private func ensureMonitor() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                await self.tick()
                if self.exposedSessions.isEmpty {
                    self.monitorTask = nil
                    return
                }
            }
        }
    }

    private func tick() async {
        for session in sessions where session.phase == .exposed || session.phase == .overdue {
            guard let plaintextURL = session.plaintextURL else { continue }
            let openState = await FileAccessMonitor.state(of: plaintextURL)
            await applyTick(id: session.id, openState: openState)
        }
        updateActivity()
    }

    private func applyTick(id: UUID, openState: FileOpenState) async {
        guard let session = sessions.first(where: { $0.id == id }),
              session.phase == .exposed || session.phase == .overdue else { return }
        let timerExpired = session.deadline.map { Date() >= $0 } ?? false

        switch openState {
        case .open:
            update(id) { item in
                item.sawFileOpen = true
                item.lastOpenAt = Date()
                item.phase = timerExpired ? .overdue : .exposed
            }
        case .unknown:
            update(id) { item in
                if timerExpired { item.phase = .overdue }
                if item.resultNote == nil {
                    item.resultNote = "BetterGPG cannot see whether another app still has this file open. Lock it yourself when you are finished. Full Disk Access lets the close watcher work."
                }
            }
        case .closed:
            let closedLongEnough = session.policy.lockWhenClosed
                && session.sawFileOpen
                && session.lastOpenAt.map { Date().timeIntervalSince($0) >= 6 } == true
            if timerExpired || closedLongEnough {
                await lock(id, force: false)
            }
        }
    }

    private func updateActivity() {
        let busy = !exposedSessions.isEmpty
        if busy, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Watching unlocked files so they can be locked again"
            )
        } else if !busy, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        appState?.refreshIndicators()
    }

    private func finish(_ id: UUID, phase: SessionPhase, message: String, info: EncryptionInfo? = nil) {
        update(id) { item in
            item.phase = phase
            item.encryptionInfo = info ?? item.encryptionInfo
            if phase == .failed {
                item.errorMessage = message
            } else {
                item.resultNote = message
                item.errorMessage = nil
            }
        }
        updateActivity()
    }

    private func update(_ id: UUID, _ change: (inout PlaintextSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        change(&sessions[index])
    }
}
