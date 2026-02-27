import SwiftUI

@main
struct GPGezeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.appState)
                .frame(minWidth: 860, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Keys") {
                Button("Refresh Keys") {
                    Task { await appDelegate.appState.refreshKeys() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }
    }
}
