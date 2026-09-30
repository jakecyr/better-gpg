import AppKit
import UniformTypeIdentifiers

enum SystemDialogs {
    @MainActor
    static func chooseFiles(allowsDirectories: Bool, message: String, extensions: [String]?) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = allowsDirectories
        panel.message = message
        if let extensions {
            panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        }
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }

    @MainActor
    static func chooseExecutable(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    @MainActor
    static func chooseDirectory(message: String, startingAt: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = message
        panel.directoryURL = startingAt
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    @MainActor
    static func saveFile(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [UTType(filenameExtension: "asc") ?? .data]
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
