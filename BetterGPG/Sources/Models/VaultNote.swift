import AppKit

enum SidebarSelection: Hashable {
    case section(AppSection)
    case vaultFile(String)
}

enum VaultNoteKind: String, CaseIterable, Identifiable {
    case markdown
    case plainText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markdown: return "Markdown"
        case .plainText: return "Plain text"
        }
    }

    var pathExtension: String {
        switch self {
        case .markdown: return "md"
        case .plainText: return "txt"
        }
    }
}

enum VaultNoteName {
    /// Plaintext file name, such as `Journal.md`. Nil when the typed name cannot be stored safely.
    static func make(from raw: String, kind: VaultNoteKind) -> String? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 200 else { return nil }
        guard !name.hasPrefix(".") else { return nil }
        guard name != ".", name != ".." else { return nil }
        guard !name.contains("/"), !name.contains(":"), !name.contains("\\") else { return nil }
        guard !name.unicodeScalars.contains(where: { $0.value < 32 }) else { return nil }

        let lower = name.lowercased()
        for suffix in [".gpg", ".pgp", ".asc"] where lower.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
            break
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix(".") else { return nil }

        let current = (name as NSString).pathExtension.lowercased()
        switch kind {
        case .markdown where current == "md" || current == "markdown":
            return name
        case .plainText where current == "txt":
            return name
        default:
            let base = current.isEmpty ? name : (name as NSString).deletingPathExtension
            guard !base.isEmpty, base != ".", !base.hasPrefix(".") else { return nil }
            return base + "." + kind.pathExtension
        }
    }
}

struct VaultFile: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let url: URL
    let displayName: String

    init(url: URL) {
        let standard = url.standardizedFileURL
        self.url = standard
        self.path = standard.path
        self.displayName = FileInfo.plaintextName(forEncrypted: standard)
    }

    var isMarkdown: Bool {
        let ext = (displayName as NSString).pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }
}

enum VaultNotePhase: Equatable, Sendable {
    case loading
    case ready
    case saving
    case saveFailed(String)
    case failed(String)
    case closing
}

/// One vault note unlocked in memory. Dropped, and its text cleared, when the note locks.
@MainActor
@Observable
final class VaultNote: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let displayName: String
    let isMarkdown: Bool
    var showsRender: Bool
    var text = ""
    var savedText = ""
    var phase: VaultNotePhase = .loading
    var recipients: [String] = []
    var readOnlyReason: String?

    @ObservationIgnored weak var textView: NSTextView?
    @ObservationIgnored var closed = false
    /// Set while locking so keystrokes cannot change the text that is about to be encrypted.
    @ObservationIgnored var sealed = false

    init(sourceURL: URL) {
        let standard = sourceURL.standardizedFileURL
        self.sourceURL = standard
        displayName = FileInfo.plaintextName(forEncrypted: standard)
        let ext = (displayName as NSString).pathExtension.lowercased()
        isMarkdown = ext == "md" || ext == "markdown"
        showsRender = isMarkdown
    }

    var isDirty: Bool {
        text != savedText
    }

    var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    var isBusy: Bool {
        phase == .loading || phase == .saving || phase == .closing
    }

    /// The text view can change the note. False while a lock is in progress.
    var allowsEditing: Bool {
        !sealed && readOnlyReason == nil && !recipients.isEmpty && !isFailed && phase != .loading && phase != .closing
    }

    var canEdit: Bool {
        allowsEditing && phase != .saving
    }

    var showsEditor: Bool {
        switch phase {
        case .ready, .saving, .saveFailed:
            return true
        case .loading, .failed, .closing:
            return false
        }
    }

    var statusText: String {
        switch phase {
        case .loading: return "Unlocking…"
        case .saving: return "Saving…"
        case .closing: return "Locking…"
        case .failed(let message): return message
        case .saveFailed(let message): return "Not saved: \(message)"
        case .ready: return isDirty ? "Edited · in memory" : "In memory"
        }
    }
}
