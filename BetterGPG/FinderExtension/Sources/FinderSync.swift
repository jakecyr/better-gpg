import Cocoa
import FinderSync

class FinderSync: FIFinderSync {
    private let encryptedExtensions: Set<String> = ["gpg", "pgp", "asc"]

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        switch menuKind {
        case .contextualMenuForItems:
            return menuForSelection()
        case .contextualMenuForContainer:
            return menuForFolder()
        default:
            return nil
        }
    }

    @objc private func encryptSelected(_ sender: AnyObject?) {
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        openMainApp(action: "encrypt", urls: urls)
    }

    @objc private func viewSelected(_ sender: AnyObject?) {
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        openMainApp(action: "view", urls: urls)
    }

    @objc private func openSelected(_ sender: AnyObject?) {
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        openMainApp(action: "open", urls: urls)
    }

    @objc private func encryptFolder(_ sender: AnyObject?) {
        guard let url = FIFinderSyncController.default().targetedURL() else { return }
        openMainApp(action: "encrypt", urls: [url])
    }

    private func menuForSelection() -> NSMenu? {
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        guard !urls.isEmpty else { return nil }

        let menu = NSMenu(title: "")
        let encrypted = urls.contains { encryptedExtensions.contains($0.pathExtension.lowercased()) }
        let plain = urls.contains { !encryptedExtensions.contains($0.pathExtension.lowercased()) }

        if plain {
            menu.addItem(item("Encrypt with BetterGPG…", #selector(encryptSelected(_:)), "lock.fill"))
        }
        if encrypted {
            menu.addItem(item("View in BetterGPG", #selector(viewSelected(_:)), "eye.fill"))
            menu.addItem(item("Open in Default App with BetterGPG", #selector(openSelected(_:)), "lock.open.fill"))
        }
        return menu.items.isEmpty ? nil : menu
    }

    private func menuForFolder() -> NSMenu? {
        guard FIFinderSyncController.default().targetedURL() != nil else { return nil }
        let menu = NSMenu(title: "")
        menu.addItem(item("Encrypt This Folder with BetterGPG…", #selector(encryptFolder(_:)), "lock.fill"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, _ symbol: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    private func openMainApp(action: String, urls: [URL]) {
        guard !urls.isEmpty else { return }
        let paths = urls.map(\.path)
        guard let json = try? JSONEncoder().encode(paths) else { return }
        let encoded = json.base64EncodedString()
        guard let escaped = encoded.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "bettergpg://\(action)?data=\(escaped)") else { return }
        NSWorkspace.shared.open(url)
    }
}
