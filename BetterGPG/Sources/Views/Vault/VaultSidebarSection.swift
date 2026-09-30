import SwiftUI

struct NewVaultNoteSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: VaultNoteKind = .markdown
    @State private var isCreating = false
    @State private var errorMessage: String?

    var onCreated: (URL) -> Void

    private var resolvedName: String? {
        VaultNoteName.make(from: name, kind: kind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Encrypted Note")
                .font(.title2.bold())
            Text("The note is encrypted to your key and stored in the vault. The sidebar shows its name only. Opening it decrypts the text into memory.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("Note name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { create() }

            Picker("Kind", selection: $kind) {
                ForEach(VaultNoteKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            if let resolvedName {
                Text("Will be saved as \(resolvedName).gpg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Use a name without slashes or a leading period.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isCreating)
                Button(isCreating ? "Encrypting…" : "Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(resolvedName == nil || isCreating)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func create() {
        guard !isCreating, let resolvedName else { return }
        isCreating = true
        errorMessage = nil
        let chosenKind = kind
        Task {
            do {
                let url = try await appState.vaultNotes.create(name: resolvedName, kind: chosenKind)
                onCreated(url)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}

struct VaultSidebarSection: View {
    @Environment(AppState.self) private var appState
    @State private var pendingDelete: VaultFile?

    private var location: VaultLocation {
        let path = appState.settings.vaultPath
        if path.isEmpty { return .unset }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return .ready
        }
        return .missing
    }

    var body: some View {
        Section {
            switch location {
            case .unset:
                Text("Choose a folder for encrypted notes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .selectionDisabled(true)
                Button("Choose Folder…") {
                    appState.chooseVaultFolder()
                }
                .buttonStyle(.borderless)
            case .missing:
                Text(appState.vaultNotes.listingError ?? "The vault folder is missing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .selectionDisabled(true)
                Button("Choose Again…") {
                    appState.chooseVaultFolder()
                }
                .buttonStyle(.borderless)
            case .ready:
                if let listingError = appState.vaultNotes.listingError {
                    Text(listingError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if appState.vaultNotes.files.isEmpty {
                    Text("No notes yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .selectionDisabled(true)
                }
                ForEach(appState.vaultNotes.files) { file in
                    noteRow(file)
                        .tag(SidebarSelection.vaultFile(file.path))
                        .contextMenu {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([file.url])
                            }
                            if appState.vaultNotes.openNote?.sourceURL.path == file.path {
                                Button("Lock") {
                                    Task { await appState.vaultNotes.closeOpenNote() }
                                }
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                pendingDelete = file
                            }
                        }
                }
            }
        } header: {
            HStack(spacing: 6) {
                Text("Vault")
                if location == .ready {
                    Button {
                        appState.beginNewVaultNote()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New encrypted note")
                }
            }
        }
        .alert(
            "Delete this note?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { file in
            Button("Delete", role: .destructive) {
                let url = file.url
                pendingDelete = nil
                Task { await appState.vaultNotes.delete(url) }
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: { file in
            Text("\(file.displayName) is shredded. If it is open, the unlocked text is wiped and unsaved edits are discarded.")
        }
    }

    private func noteRow(_ file: VaultFile) -> some View {
        let isOpen = appState.vaultNotes.openNote?.sourceURL.path == file.path
        return Label {
            Text(file.displayName)
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: isOpen ? "lock.open.fill" : "lock.fill")
                .foregroundStyle(isOpen ? Color.accentColor : .secondary)
        }
        .help(file.displayName)
    }
}

private enum VaultLocation {
    case unset
    case missing
    case ready
}
