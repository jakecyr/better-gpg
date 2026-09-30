import AppKit
import SwiftUI

/// Hands the hosting `NSWindow` to SwiftUI code that needs AppKit-level control.
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowReportingView {
        let view = WindowReportingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: WindowReportingView, context: Context) {
        nsView.onWindow = onWindow
        if let window = nsView.window {
            onWindow(window)
        }
    }
}

final class WindowReportingView: NSView {
    var onWindow: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onWindow?(window)
        }
    }
}

/// Calls back once when its window is about to close.
final class WindowCloseObserver {
    private(set) weak var window: NSWindow?
    private var token: NSObjectProtocol?

    func observe(_ window: NSWindow, onClose: @escaping () -> Void) {
        guard self.window !== window else { return }
        stop()
        self.window = window
        token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
            onClose()
        }
    }

    private func stop() {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
        token = nil
    }

    deinit {
        stop()
    }
}
