import AppKit

/// Finder's Services menu lands here. The selectors match `NSMessage` in Info.plist.
@MainActor
final class ServiceHandler: NSObject {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    @objc func encryptFiles(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        deliver(pasteboard, source: .finderEncrypt)
    }

    @objc func viewFiles(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        deliver(pasteboard, source: .finderView)
    }

    @objc func decryptFiles(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        deliver(pasteboard, source: .finderExternal)
    }

    private func deliver(_ pasteboard: NSPasteboard, source: IncomingSource) {
        let urls = fileURLs(from: pasteboard)
        guard !urls.isEmpty else { return }
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            if self.appState.handleIncomingFiles(urls, source: source) {
                NotificationCenter.default.post(name: .bettergpgShowMain, object: nil)
            }
        }
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            return urls
        }
        if let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            return paths.map { URL(fileURLWithPath: $0) }
        }
        return []
    }
}
