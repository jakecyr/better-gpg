import AppKit

/// Handles macOS Services (right-click in Finder → Services → "Encrypt/Decrypt with GPGeze…").
///
/// The NSMessage keys in Info.plist map to the @objc selectors below.
/// NSPortName is NOT set in the plist — without it macOS uses the standard delivery
/// mechanism rather than legacy Distributed Objects (which caused silent failures).
@objc
final class ServiceHandler: NSObject {
    private let appState: AppState
    private weak var appDelegate: AppDelegate?

    init(appState: AppState, appDelegate: AppDelegate) {
        self.appState = appState
        self.appDelegate = appDelegate
    }

    // MARK: - NSServices entry points
    // Selector: encryptFiles:userData:error:  (matches NSMessage "encryptFiles")

    @objc func encryptFiles(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        let urls = fileURLs(from: pboard)
        guard !urls.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.appState.pendingEncryptURLs = urls
            self?.appState.activeTab = .encrypt
            Self.bringToFront()
        }
    }

    // Selector: decryptFiles:userData:error:  (matches NSMessage "decryptFiles")

    @objc func decryptFiles(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        let urls = fileURLs(from: pboard)
        guard !urls.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let delegate = self.appDelegate else { return }
            Task { @MainActor in
                await delegate.handleBackgroundDecrypt(urls)
            }
        }
    }

    // MARK: - Helpers

    private func fileURLs(from pboard: NSPasteboard) -> [URL] {
        // Modern: public.file-url items (macOS 10.14+)
        if let urls = pboard.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return urls
        }
        // Legacy: NSFilenamesPboardType (array of paths)
        if let paths = pboard.propertyList(
            forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ) as? [String] {
            return paths.map { URL(fileURLWithPath: $0) }
        }
        return []
    }

    private static func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        // Make the first non-miniaturized window key, or restore all windows
        if let window = NSApp.windows.first(where: { $0.isVisible && !$0.isMiniaturized }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.windows.forEach { $0.makeKeyAndOrderFront(nil) }
        }
    }
}
