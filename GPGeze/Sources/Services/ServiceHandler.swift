import AppKit

/// Handles macOS Services (right-click in Finder) for encrypt/decrypt.
/// The methods here are called when the user selects "Encrypt with GPGeze" or
/// "Decrypt with GPGeze" from Finder's right-click > Services menu.
@objc
final class ServiceHandler: NSObject {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Service handlers
    // These selectors must match the NSMessage values in Info.plist.

    @objc func encryptFiles(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        let urls = fileURLs(from: pboard)
        guard !urls.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.appState.pendingEncryptURLs = urls
            self.appState.activeTab = .encrypt
            self.activateApp()
        }
    }

    @objc func decryptFiles(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        let urls = fileURLs(from: pboard)
        guard !urls.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.appState.pendingDecryptURLs = urls
            self.appState.activeTab = .decrypt
            self.activateApp()
        }
    }

    // MARK: - Helpers

    private func fileURLs(from pboard: NSPasteboard) -> [URL] {
        // Modern API
        if let urls = pboard.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return urls
        }
        // Legacy NSFilenamesPboardType
        if let names = pboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            return names.map { URL(fileURLWithPath: $0) }
        }
        return []
    }

    private func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
        if NSApp.windows.isEmpty || NSApp.windows.allSatisfy({ !$0.isVisible }) {
            // Re-open the main window if it was closed
            for window in NSApp.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
