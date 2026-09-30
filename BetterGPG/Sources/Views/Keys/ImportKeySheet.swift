import SwiftUI
import UniformTypeIdentifiers

struct ImportKeySheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var initialText: String = ""

    @State private var pastedText = ""
    @State private var lookup = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var didLoad = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import a Key")
                .font(.title2.bold())
            Text("Paste a public key, drop a file, or fetch one from keys.openpgp.org with an email or fingerprint.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Email or fingerprint", text: $lookup)
                    .textFieldStyle(.roundedBorder)
                Button("Fetch") { fetch() }
                    .disabled(lookup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $pastedText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 180)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        Task {
                            let urls = await FileDrop.load(providers)
                            await load(urls)
                        }
                        return true
                    }
                if pastedText.isEmpty {
                    Text("Paste a key here, or drop a .asc file")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            if let successMessage {
                Label(successMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }

            HStack {
                Button("Paste") { pasteFromClipboard() }
                Button("Choose File…") { chooseFile() }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") { importPasted() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
            }
        }
        .padding(24)
        .frame(width: 560, height: 480)
        .overlay {
            if isImporting {
                ProgressView("Working…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if pastedText.isEmpty { pastedText = initialText }
        }
    }

    private func pasteFromClipboard() {
        if let value = NSPasteboard.general.string(forType: .string) {
            pastedText = value
        }
    }

    private func chooseFile() {
        let urls = SystemDialogs.chooseFiles(
            allowsDirectories: false,
            message: "Choose a key file",
            extensions: ["asc", "gpg", "pgp", "key", "pub"]
        )
        Task { await load(urls) }
    }

    private func load(_ urls: [URL]) async {
        var chunks: [String] = []
        for url in urls {
            if let text = try? String(contentsOf: url, encoding: .utf8), text.contains("BEGIN PGP") {
                chunks.append(text)
            } else {
                await run {
                    try await appState.importKeys(at: [url])
                    return "Imported \(url.lastPathComponent)"
                }
            }
        }
        if !chunks.isEmpty {
            pastedText = chunks.joined(separator: "\n")
        }
    }

    private func importPasted() {
        let text = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task {
            await run {
                try await appState.importKey(armored: text)
                return "Key imported"
            }
        }
    }

    private func fetch() {
        let query = lookup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        Task {
            await run {
                try await appState.receiveKeys(query: query)
                return "Fetched keys for \(query)"
            }
        }
    }

    private func run(_ operation: () async throws -> String) async {
        isImporting = true
        errorMessage = nil
        successMessage = nil
        do {
            successMessage = try await operation()
            isImporting = false
            try? await Task.sleep(for: .milliseconds(700))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isImporting = false
        }
    }
}
