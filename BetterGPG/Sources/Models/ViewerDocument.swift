import AppKit
import PDFKit
import UniformTypeIdentifiers

enum ViewerKind: Equatable, Sendable {
    case text
    case pdf
    case image
    case quickLook
}

enum ViewerPhase: Equatable, Sendable {
    case loading
    case ready
    case saving
    case saveFailed(String)
    case failed(String)
    case closing
}

/// An encrypted file opened inside BetterGPG.
@MainActor
@Observable
final class ViewerDocument: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let plaintextName: String
    var kind: ViewerKind = .text
    var phase: ViewerPhase = .loading
    var text = ""
    var savedText = ""
    var pdf: PDFDocument?
    var image: NSImage?
    var fileURL: URL?
    var storageNote = ""
    var recipients: [String] = []
    var recipientsHidden = false
    var readOnlyReason: String?
    var deadline: Date?
    var lastSaved: Date?

    @ObservationIgnored var buffer: SecureBuffer?
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored var closed = false

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
        plaintextName = FileInfo.plaintextName(forEncrypted: sourceURL)
    }

    var isDirty: Bool {
        kind == .text && text != savedText
    }

    var canEdit: Bool {
        kind == .text && readOnlyReason == nil && !recipients.isEmpty
    }

    var isBusy: Bool {
        phase == .loading || phase == .saving || phase == .closing
    }

    var statusText: String {
        switch phase {
        case .loading: return "Unlocking…"
        case .saving: return "Saving…"
        case .closing: return "Locking…"
        case .failed(let message): return message
        case .saveFailed(let message): return "Not saved: \(message)"
        case .ready: return isDirty ? "Edited · \(storageNote)" : storageNote
        }
    }

    /// Picks a viewer from the decrypted file's name. `nil` means sniff the bytes.
    static func kind(forName name: String) -> ViewerKind? {
        let ext = (name as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        if Self.textExtensions.contains(ext) { return .text }
        guard let type = UTType(filenameExtension: ext), !type.isDynamic else { return nil }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .rtf) || type.conforms(to: .rtfd) { return .quickLook }
        if type.conforms(to: .text) { return .text }
        return .quickLook
    }

    static func isUTF8Text(_ sample: Data) -> Bool {
        guard !sample.contains(0) else { return false }
        for trim in 0...min(3, sample.count) where String(data: sample.dropLast(trim), encoding: .utf8) != nil {
            return true
        }
        return false
    }

    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "log", "json", "yaml", "yml", "toml",
        "ini", "conf", "cfg", "env", "xml", "html", "css", "js", "ts", "swift", "py",
        "rb", "go", "rs", "sh", "zsh", "sql", "tex", "org", "rst", "pem", "key", "asc"
    ]
}
