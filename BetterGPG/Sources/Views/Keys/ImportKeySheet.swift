import SwiftUI
import UniformTypeIdentifiers

struct ImportKeySheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var pastedText = ""
    @State private var isImporting = false
    @State private var importError: String?
    @State private var importSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Import Public Key")
                .font(.title2.bold())

            Text("Paste an armored GPG public key block, or drag a .asc / .gpg file into the text area.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $pastedText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 200)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                        loadDroppedFile(providers)
                    }

                if pastedText.isEmpty {
                    Text("Paste key here or drag a .asc file…")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }

            if let error = importError {
                Label(error, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            if importSuccess {
                Label("Key imported successfully!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }

            HStack {
                Button("Choose File…") { chooseFile() }
                    .buttonStyle(.bordered)

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Import") { performImport() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
            }
        }
        .padding(24)
        .frame(width: 520, height: 420)
        .overlay {
            if isImporting {
                ProgressView("Importing…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
            }
        }
    }

    private func performImport() {
        let text = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isImporting = true
        importError = nil
        importSuccess = false

        Task {
            do {
                try await appState.importKey(armored: text)
                importSuccess = true
                isImporting = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
            } catch {
                importError = error.localizedDescription
                isImporting = false
            }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .init(filenameExtension: "asc") ?? .data,
            .init(filenameExtension: "gpg") ?? .data,
            .init(filenameExtension: "pgp") ?? .data
        ]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let contents = try? String(contentsOf: url, encoding: .utf8) {
            pastedText = contents
        }
    }

    private func loadDroppedFile(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true),
                      let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
                DispatchQueue.main.async { pastedText = contents }
            }
        }
        return true
    }
}
