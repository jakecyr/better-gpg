import Cocoa
import FinderSync

class FinderSync: FIFinderSync {

    override init() {
        super.init()
        // Monitor the entire filesystem so menu items appear for any file in Finder
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    // MARK: - Contextual menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems else { return nil }

        let menu = NSMenu(title: "BetterGPG")

        let encrypt = NSMenuItem(
            title: "Encrypt with BetterGPG…",
            action: #selector(encryptSelected(_:)),
            keyEquivalent: ""
        )
        encrypt.target = self
        encrypt.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        menu.addItem(encrypt)

        let decrypt = NSMenuItem(
            title: "Decrypt with BetterGPG…",
            action: #selector(decryptSelected(_:)),
            keyEquivalent: ""
        )
        decrypt.target = self
        decrypt.image = NSImage(systemSymbolName: "lock.open.fill", accessibilityDescription: nil)
        menu.addItem(decrypt)

        return menu
    }

    // MARK: - Actions

    @IBAction func encryptSelected(_ sender: AnyObject?) {
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        openMainApp(action: "encrypt", urls: urls)
    }

    @IBAction func decryptSelected(_ sender: AnyObject?) {
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        openMainApp(action: "decrypt", urls: urls)
    }

    // MARK: - IPC via URL scheme

    private func openMainApp(action: String, urls: [URL]) {
        guard !urls.isEmpty else { return }
        // JSON-encode paths then Base64 so any characters (spaces, unicode) survive the URL
        let paths = urls.map(\.path)
        guard let json = try? JSONEncoder().encode(paths) else { return }
        let b64 = json.base64EncodedString()
        guard let escaped = b64.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "bettergpg://\(action)?data=\(escaped)") else { return }
        NSWorkspace.shared.open(url)
    }
}
