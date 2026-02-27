import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private(set) lazy var serviceHandler = ServiceHandler(appState: appState, appDelegate: self)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // NSServices: set provider so right-click Services menu items work
        NSApp.servicesProvider = serviceHandler
        NSUpdateDynamicServices()

        Task {
            await appState.refreshKeys()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            NSApp.windows.forEach { $0.makeKeyAndOrderFront(nil) }
        }
        return true
    }

    // MARK: - URL scheme handler (gpgeze://encrypt or gpgeze://decrypt)
    // Called when the FinderSync extension opens gpgeze://action?data=<base64json>

    func application(_ application: NSApplication, open urls: [URL]) {
        let gpgExtensions = ["gpg", "asc"]
        let fileURLs = urls.filter { url in
            url.isFileURL && gpgExtensions.contains(url.pathExtension.lowercased())
        }
        let gpgezeURLs = urls.filter { $0.scheme == "gpgeze" }

        // Handle double-click on .gpg/.asc files: decrypt in background, don't show window
        if !fileURLs.isEmpty {
            deferToNextRunLoop {
                Task { await self.handleBackgroundDecrypt(fileURLs) }
            }
        }

        for url in gpgezeURLs {
            handleGPGezeURL(url)
        }
    }

    private func handleGPGezeURL(_ url: URL) {
        guard url.scheme == "gpgeze",
              let action = url.host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let dataParam = components.queryItems?.first(where: { $0.name == "data" })?.value
        else { return }

        // Remove any extra percent-encoding then base64-decode
        let cleaned = dataParam.removingPercentEncoding ?? dataParam
        guard let jsonData = Data(base64Encoded: cleaned),
              let paths = try? JSONDecoder().decode([String].self, from: jsonData)
        else { return }

        let fileURLs = paths.map { URL(fileURLWithPath: $0) }
        guard !fileURLs.isEmpty else { return }

        deferToNextRunLoop {
            if action == "encrypt" {
                self.appState.pendingEncryptURLs = fileURLs
                self.appState.activeTab = .encrypt
                self.activateAndShowWindow()
            } else if action == "decrypt" {
                Task { await self.handleBackgroundDecrypt(fileURLs) }
            }
        }
    }

    /// Decrypt files in background without showing the main window.
    /// On success: reveal decrypted files in Finder.
    /// On failure (no permission): show encryption info window.
    func handleBackgroundDecrypt(_ urls: [URL]) async {
        let (success, failed) = await appState.backgroundDecrypt(urls: urls)

        if !success.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(success)
        }

        if !failed.isEmpty {
            showDecryptionFailedWindow(items: failed)
        }
    }

    private var decryptionFailedWindow: NSWindow?

    private func showDecryptionFailedWindow(items: [(URL, EncryptionInfo)]) {
        let content = DecryptionFailedView(items: items, appState: appState) { [weak self] in
            self?.decryptionFailedWindow?.close()
            self?.decryptionFailedWindow = nil
        }

        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Cannot Decrypt"
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        decryptionFailedWindow = window
    }

    /// Defer work to next run loop so SwiftUI view hierarchy is ready (fixes race when launched via URL/Services)
    private func deferToNextRunLoop(_ work: @escaping () -> Void) {
        DispatchQueue.main.async(execute: work)
    }

    private func activateAndShowWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.isVisible })?.makeKeyAndOrderFront(nil)
            ?? NSApp.windows.forEach { $0.makeKeyAndOrderFront(nil) }
    }
}
