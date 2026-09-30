import SwiftUI

struct KeysView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var keyToDelete: GPGKey?
    @State private var exportedText: String?
    @State private var showExport = false

    private var secretKeys: [GPGKey] {
        filtered(appState.secretKeys)
    }

    private var contactKeys: [GPGKey] {
        filtered(appState.contactKeys)
    }

    private var hasVisibleKeys: Bool {
        !secretKeys.isEmpty || !contactKeys.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if !appState.gpgAvailable {
                GPGNotInstalledBanner()
                    .padding()
            }

            Group {
                if appState.isLoadingKeys && !hasVisibleKeys {
                    ProgressView("Loading keys…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !hasVisibleKeys {
                    if searchText.isEmpty {
                        ContentUnavailableView {
                            Label("No Keys", systemImage: "person.text.rectangle")
                        } description: {
                            Text("Generate a secret key for yourself, or paste a public key, drop a .asc file, or fetch one by email.")
                        } actions: {
                            Button("Generate a Key…") { appState.activeSheet = .generateKey }
                                .buttonStyle(.borderedProminent)
                                .disabled(!appState.gpgAvailable)
                            Button("Import Key…") { appState.activeSheet = .importKey(text: "") }
                        }
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                } else {
                    List {
                        if !secretKeys.isEmpty {
                            Section("My Keys") {
                                ForEach(secretKeys) { key in
                                    keyRow(key, isOwn: key.fingerprint == appState.settings.ownKeyFingerprint, isSecret: true)
                                }
                            }
                        }
                        if !contactKeys.isEmpty {
                            Section("People") {
                                ForEach(contactKeys) { key in
                                    keyRow(key, isOwn: false, isSecret: false)
                                }
                            }
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                    .overlay {
                        if appState.isLoadingKeys {
                            ProgressView("Loading keys…")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.regularMaterial)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $searchText, prompt: "Search keys")
        .navigationTitle("Keys")
        .toolbar {
            if appState.secretKeys.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Generate Key", systemImage: "key") {
                        appState.activeSheet = .generateKey
                    }
                    .disabled(!appState.gpgAvailable)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Import Key", systemImage: "plus") {
                    appState.activeSheet = .importKey(text: "")
                }
            }
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await appState.refreshKeys() }
                }
            }
        }
        .confirmationDialog(
            "Delete \(keyToDelete?.displayName ?? "this key")?",
            isPresented: Binding(
                get: { keyToDelete != nil },
                set: { if !$0 { keyToDelete = nil } }
            ),
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
                 ? "This removes the secret key and the public key from your keyring."
                 : "This removes the public key from your keyring.")
        }
        .sheet(isPresented: $showExport) {
            if let exportedText {
                ExportKeySheet(armoredKey: exportedText)
            }
        }
    }

    private func filtered(_ keys: [GPGKey]) -> [GPGKey] {
        guard !searchText.isEmpty else { return keys }
        return keys.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.fingerprint.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func keyRow(_ key: GPGKey, isOwn: Bool, isSecret: Bool) -> some View {
        KeyRow(key: key, isOwn: isOwn, isSecret: isSecret)
            .contextMenu {
                if isSecret {
                    Button(isOwn ? "This Is My Key" : "Use as My Key") {
                        appState.settings.ownKeyFingerprint = key.fingerprint
                        appState.settings.includeOwnKey = true
                        appState.persistSettings()
                    }
                    .disabled(isOwn)
                }
                Button("Copy Fingerprint") { copy(key.formattedFingerprint) }
                Button("Export Public Key…") { export(key) }
                Menu("Add to Group") {
                    if appState.groups.isEmpty {
                        Button("Create a Group") { appState.section = .groups }
                    }
                    ForEach(appState.groups) { group in
                        let included = group.keyFingerprints.contains(key.fingerprint)
                        Button(included ? "\(group.name) ✓" : group.name) {
                            appState.addKey(key.fingerprint, toGroup: group.id)
                        }
                        .disabled(included)
                    }
                }
                Divider()
                Button(isSecret ? "Delete Secret Key" : "Delete Key", role: .destructive) {
                    keyToDelete = key
                }
            }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func export(_ key: GPGKey) {
        Task {
            do {
                exportedText = try await appState.exportPublicKey(fingerprint: key.fingerprint)
                showExport = true
            } catch {
                appState.lastError = error.localizedDescription
            }
        }
    }
}

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
                HStack(spacing: 8) {
                    Text(key.shortFingerprint)
                        .font(.caption.monospaced())
                    if !key.algorithmSummary.isEmpty {
                        Text(key.algorithmSummary)
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct ExportKeySheet: View {
    let armoredKey: String
    @Environment(\.dismiss) private var dismiss

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
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(armoredKey, forType: .string)
                }
                Button("Save…") {
                    if let url = SystemDialogs.saveFile(suggestedName: "public-key.asc") {
                        try? armoredKey.write(to: url, atomically: true, encoding: .utf8)
                    }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 420)
    }
}
