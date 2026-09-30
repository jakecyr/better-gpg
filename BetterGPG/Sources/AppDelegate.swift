import AppKit
import SwiftUI

extension Notification.Name {
    static let bettergpgShowMain = Notification.Name("bettergpgShowMain")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private(set) lazy var serviceHandler = ServiceHandler(appState: appState)

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Viewer windows hold plaintext, so they must never be restored on relaunch.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        signal(SIGPIPE, SIG_IGN)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        PinentrySetup.ensureGUIPinentry(gpgBinary: appState.settings.gpgBinaryPath)
        NSApp.servicesProvider = serviceHandler
        NSUpdateDynamicServices()
        Task {
            await appState.vault.prepareOnLaunch()
            appState.vault.startJanitor()
            await appState.refreshKeys()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NotificationCenter.default.post(name: .bettergpgShowMain, object: nil)
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let exposed = appState.sessions.exposedSessions
        var lockSessions = false

        if !exposed.isEmpty {
            let alert = NSAlert()
            alert.messageText = exposed.count == 1
                ? "A file is still unlocked in another app"
                : "\(exposed.count) files are still unlocked in other apps"
            alert.informativeText = "BetterGPG can save them back into their encrypted files and shred the unlocked copies before quitting. If you quit without locking, the copies are shredded the next time BetterGPG starts."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Lock and Quit")
            alert.addButton(withTitle: "Quit Without Locking")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                lockSessions = true
            case .alertSecondButtonReturn:
                lockSessions = false
            default:
                return .terminateCancel
            }
        }

        Task { @MainActor in
            let noteClosed = await self.appState.vaultNotes.closeOpenNote(saveChanges: true, updateSidebar: false)
            let viewersClosed = await self.appState.documents.closeAll()
            if lockSessions {
                await self.appState.sessions.lockAll(force: true)
            }
            await self.appState.vault.shutdown()
            let sessionsLeft = lockSessions && !self.appState.sessions.exposedSessions.isEmpty
            let blocked = !noteClosed || !viewersClosed || sessionsLeft
            if !noteClosed, let path = self.appState.vaultNotes.openNote?.sourceURL.path {
                self.appState.sidebarSelection = .vaultFile(path)
                NotificationCenter.default.post(name: .bettergpgShowMain, object: nil)
            } else if blocked {
                self.appState.section = .sessions
                NotificationCenter.default.post(name: .bettergpgShowMain, object: nil)
            }
            NSApp.reply(toApplicationShouldTerminate: !blocked)
        }
        return .terminateLater
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        let commands = urls.filter { $0.scheme == "bettergpg" }
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            var needsMain = false
            if !files.isEmpty {
                needsMain = self.appState.handleIncomingFiles(files, source: .open) || needsMain
            }
            for url in commands {
                needsMain = self.handleBetterGPGURL(url) || needsMain
            }
            if needsMain {
                NotificationCenter.default.post(name: .bettergpgShowMain, object: nil)
            }
        }
    }

    private func handleBetterGPGURL(_ url: URL) -> Bool {
        guard url.scheme == "bettergpg",
              let action = url.host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let dataParam = components.queryItems?.first(where: { $0.name == "data" })?.value
        else { return false }

        let cleaned = dataParam.removingPercentEncoding ?? dataParam
        guard let jsonData = Data(base64Encoded: cleaned),
              let paths = try? JSONDecoder().decode([String].self, from: jsonData)
        else { return false }

        let fileURLs = paths.map { URL(fileURLWithPath: $0) }
        guard !fileURLs.isEmpty else { return false }

        switch action {
        case "encrypt":
            return appState.handleIncomingFiles(fileURLs, source: .finderEncrypt)
        case "view":
            return appState.handleIncomingFiles(fileURLs, source: .finderView)
        default:
            return appState.handleIncomingFiles(fileURLs, source: .finderExternal)
        }
    }
}
