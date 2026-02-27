import SwiftUI

struct KeysView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var showImportSheet = false
    @State private var selectedKey: GPGKey?
    @State private var showDeleteConfirm = false
    @State private var keyToDelete: GPGKey?
    @State private var exportedText: String?
    @State private var showExportSheet = false

    private var filteredPublicKeys: [GPGKey] {
        guard !searchText.isEmpty else { return appState.publicKeys }
        return appState.publicKeys.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.fingerprint.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredSecretKeys: [GPGKey] {
        let base = appState.secretKeys.filter { !$0.fingerprint.isEmpty }
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.fingerprint.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !appState.gpgAvailable {
                GPGNotInstalledBanner().padding()
            }

            List(selection: $selectedKey) {
                if !filteredPublicKeys.isEmpty {
                    Section("Public Keys (\(filteredPublicKeys.count))") {
                        ForEach(filteredPublicKeys) { key in
                            KeyRow(key: key, isOwn: key.fingerprint == appState.settings.ownKeyFingerprint)
                                .tag(key)
                                .contextMenu {
                                    Button("Export Public Key…") { exportKey(key) }
                                    Divider()
                                    Button("Delete Key", role: .destructive) { promptDelete(key) }
                                }
                        }
                    }
                }

                let secretFps = Set(appState.secretKeys.map(\.fingerprint))
                if !filteredSecretKeys.isEmpty {
                    Section("Secret Keys (\(filteredSecretKeys.count))") {
                        ForEach(filteredSecretKeys) { key in
                            KeyRow(key: key, isOwn: true, isSecret: true)
                                .tag(key)
                                .contextMenu {
                                    Button("Export Public Key…") { exportKey(key) }
                                    Divider()
                                    Button("Delete Secret + Public Key", role: .destructive) { promptDelete(key) }
                                }
                        }
                    }
                    let _ = secretFps // suppress warning
                }

                if filteredPublicKeys.isEmpty && filteredSecretKeys.isEmpty && !appState.isLoadingKeys {
                    ContentUnavailableView {
                        Label(searchText.isEmpty ? "No Keys Found" : "No Matching Keys", systemImage: "person.text.rectangle")
                    } description: {
                        Text(searchText.isEmpty
                             ? "Import keys using the + button above, or have your contacts share their public keys."
                             : "No public or secret keys match your search.")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search keys…")
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .overlay {
                if appState.isLoadingKeys {
                    ProgressView("Loading keys…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.regularMaterial)
                }
            }
        }
        .navigationTitle("Keys")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Import Key", systemImage: "plus") { showImportSheet = true }
                    .help("Import a GPG public key")
            }
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await appState.refreshKeys() }
                }
                .help("Reload keys from GPG keyring")
            }
        }
        .sheet(isPresented: $showImportSheet) {
            ImportKeySheet()
        }
        .sheet(isPresented: $showExportSheet) {
            if let text = exportedText {
                ExportKeySheet(armoredKey: text)
            }
        }
        .confirmationDialog(
            "Delete \(keyToDelete?.displayName ?? "key")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let key = keyToDelete {
                    Task {
                        do { try await appState.deleteKey(key) }
                        catch { appState.lastError = error.localizedDescription }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(keyToDelete?.isSecret == true
                 ? "This will permanently delete both the secret and public key from your keyring."
                 : "This will permanently delete the public key from your keyring.")
        }
    }

    private func promptDelete(_ key: GPGKey) {
        keyToDelete = key
        showDeleteConfirm = true
    }

    private func exportKey(_ key: GPGKey) {
        Task {
            do {
                exportedText = try await appState.exportPublicKey(fingerprint: key.fingerprint)
                showExportSheet = true
            } catch {
                appState.lastError = error.localizedDescription
            }
        }
    }
}

// MARK: - Key Row

struct KeyRow: View {
    let key: GPGKey
    var isOwn: Bool = false
    var isSecret: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSecret ? "key.fill" : "person.crop.circle")
                .foregroundStyle(isOwn ? Color.accentColor : Color.secondary)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(key.displayName)
                        .font(.body)
                        .lineLimit(1)
                    if isOwn {
                        Text("me")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                    if key.isExpired {
                        Text("expired")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.red.opacity(0.15), in: Capsule())
                            .foregroundStyle(.red)
                    }
                }
                Text(key.shortFingerprint)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Export Sheet

struct ExportKeySheet: View {
    let armoredKey: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Public Key")
                .font(.title2.bold())

            ScrollView {
                Text(armoredKey)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Button("Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(armoredKey, forType: .string)
                }
                .buttonStyle(.bordered)

                Button("Save to File…") {
                    saveToFile()
                }
                .buttonStyle(.bordered)

                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500, height: 400)
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "asc")!]
        panel.nameFieldStringValue = "public-key.asc"
        if panel.runModal() == .OK, let url = panel.url {
            try? armoredKey.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
