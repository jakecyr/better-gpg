import Foundation

struct SessionPolicy: Equatable, Sendable {
    var useRamDisk: Bool
    var openAfterDecrypt: Bool
    var finishAction: FinishAction
    var lockWhenClosed: Bool
    var autoLockAfter: TimeInterval?

    enum FinishAction: String, Equatable, Sendable {
        case reencryptAndShred
        case shredOnly
    }

    static func from(settings: AppSettings) -> SessionPolicy {
        SessionPolicy(
            useRamDisk: settings.useRamDisk,
            openAfterDecrypt: settings.openAfterDecrypt,
            finishAction: .reencryptAndShred,
            lockWhenClosed: settings.lockWhenClosed,
            autoLockAfter: settings.resolvedAutoLockInterval
        )
    }

    var keepsPlaintextUntilManualLock: Bool {
        !lockWhenClosed && autoLockAfter == nil
    }
}

enum SessionPhase: Equatable, Sendable {
    case preparing
    case exposed
    case overdue
    case locking
    case done
    case failed
}

struct PlaintextSession: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceURL: URL
    var plaintextURL: URL?
    var recipientKeyIDs: [String]
    var policy: SessionPolicy
    var phase: SessionPhase
    var startedAt: Date
    var deadline: Date?
    var sawFileOpen: Bool
    var lastOpenAt: Date?
    var usingRamDisk: Bool
    var fellBackToDisk: Bool
    var errorMessage: String?
    var resultNote: String?
    var encryptionInfo: EncryptionInfo?

    var title: String {
        if let plaintextURL {
            return plaintextURL.lastPathComponent
        }
        return FileInfo.plaintextName(forEncrypted: sourceURL)
    }

    var holdsPlaintext: Bool {
        switch phase {
        case .done:
            return false
        case .failed:
            guard let plaintextURL else { return false }
            return FileManager.default.fileExists(atPath: plaintextURL.path)
        case .preparing, .exposed, .overdue, .locking:
            return true
        }
    }

    var summary: String {
        switch phase {
        case .preparing:
            return "Unlocking…"
        case .locking:
            return "Locking…"
        case .done:
            return resultNote ?? "Locked"
        case .failed:
            return errorMessage ?? "Could not finish locking this file"
        case .exposed, .overdue:
            var parts: [String] = []
            parts.append(usingRamDisk ? "Memory disk" : "Private temporary folder")
            switch policy.finishAction {
            case .reencryptAndShred:
                parts.append("saves changes")
            case .shredOnly:
                parts.append("discards changes")
            }
            if policy.lockWhenClosed {
                parts.append("locks when closed")
            }
            if let deadline {
                let remaining = deadline.timeIntervalSinceNow
                if remaining > 0 {
                    parts.append("timer \(Self.format(remaining))")
                } else {
                    parts.append("timer elapsed")
                }
            }
            if phase == .overdue {
                parts.append("still open in another app")
            }
            return parts.joined(separator: " · ")
        }
    }

    static func format(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        if seconds >= 3600 {
            return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
        }
        if seconds >= 60 {
            return "\(seconds / 60)m"
        }
        return "\(seconds)s"
    }
}
