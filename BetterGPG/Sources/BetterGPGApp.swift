import SwiftUI

@main
struct BetterGPGApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private var appState: AppState { appDelegate.appState }

    var body: some Scene {
        Window("BetterGPG", id: "main") {
            ContentView()
                .environment(appState)
                .environment(appState.sessions)
                .environment(appState.documents)
                .frame(minWidth: 920, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("New Note…") {
                    appState.beginNewVaultNote()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Import Key…") {
                    appState.activeSheet = .importKey(text: "")
                    appState.section = .keys
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("Lock Everything") {
                    Task { _ = await appState.lockEverything() }
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandMenu("Keys") {
                Button("Refresh Keys") {
                    Task { await appState.refreshKeys() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        WindowGroup("Encrypted File", id: "viewer", for: UUID.self) { $documentID in
            ViewerWindow(documentID: documentID)
                .environment(appState)
                .environment(appState.sessions)
                .environment(appState.documents)
        }
        .defaultSize(width: 900, height: 720)

        MenuBarExtra {
            SessionMenu()
                .environment(appState)
                .environment(appState.sessions)
                .environment(appState.documents)
        } label: {
            MenuBarIcon()
                .environment(appState)
                .environment(appState.sessions)
                .environment(appState.documents)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(appState)
                .environment(appState.sessions)
                .environment(appState.documents)
                .frame(width: 640)
        }
    }
}

/// Always alive in the menu bar, so it is the one place that can open windows on request.
private struct MenuBarIcon: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionManager.self) private var sessions
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: icon)
            .onReceive(NotificationCenter.default.publisher(for: .bettergpgShowMain)) { _ in
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .bettergpgOpenViewer)) { note in
                if let id = note.object as? UUID {
                    openWindow(id: "viewer", value: id)
                }
            }
    }

    private var icon: String {
        if sessions.needsAttention {
            return "lock.trianglebadge.exclamationmark.fill"
        }
        if appState.unlockedCount == 0 {
            return "lock.fill"
        }
        return "lock.open.fill"
    }
}
