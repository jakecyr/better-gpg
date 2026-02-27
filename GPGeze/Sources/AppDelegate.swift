import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private(set) lazy var serviceHandler = ServiceHandler(appState: appState)

    func applicationDidFinishLaunching(_ notification: Notification) {
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
            for window in NSApp.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}
