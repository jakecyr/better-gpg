import SwiftUI
import UniformTypeIdentifiers

struct EncryptView: View {
    @EnvironmentObject var appState: AppState
    @State private var files: [URL] = []
    @State private var selectedGroupID: UUID?
    @State private var isEncrypting = false
    @State private var resultURLs: [URL] = []
    @State private var errorMessage: String?

    private var selectedGroup: KeyGroup? {
        appState.groups.first { $0.id == selectedGroupID }
    }

    private var recipients: [GPGKey] {
        guard let group = selectedGroup else { return [] }
        return appState.recipients(forGroup: group)
    }

    private var canEncrypt: Bool {
        !files.isEmpty && selectedGroupID != nil && !recipients.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !appState.gpgAvailable {
                    GPGNotInstalledBanner()
                }

                // File drop zone
                VStack(alignment: .leading, spacing: 8) {
                    Label("Files to Encrypt", systemImage: "doc.fill")
                        .font(.headline)

                    FileDropZone(
                        label: "Drop files here or click to choose",
                        systemImage: "plus.circle.dashed",
                        droppedURLs: $files
                    ) {
                        chooseFiles()
                    }

                    if !files.isEmpty {
                        fileList
                    }
                }

                // Group picker
                VStack(alignment: .leading, spacing: 8) {
                    Label("Recipient Group", systemImage: "person.3")
                        .font(.headline)

                    if appState.groups.isEmpty {
                        Text("No groups created yet. Create a group in the Groups tab and add public keys to it.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        Picker("Group", selection: $selectedGroupID) {
                            Text("Select a group…").tag(Optional<UUID>.none)
                            ForEach(appState.groups) { group in
                                Text("\(group.name) (\(group.keyFingerprints.count) keys)")
                                    .tag(Optional(group.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 320)
                    }

                    if let group = selectedGroup, !group.keyFingerprints.isEmpty {
                        recipientsList
                    }
                }

                // Own key info
                if appState.settings.includeOwnKey {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Your key will also be included (configured in Settings).")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                // Error
                if let err = errorMessage {
                    Label(err, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                // Result
                if !resultURLs.isEmpty {
                    resultList
                }

                // Encrypt button
                HStack {
                    Spacer()
                    Button {
                        performEncrypt()
                    } label: {
                        Label("Encrypt \(files.count == 1 ? "File" : "\(files.count) Files")", systemImage: "lock.fill")
                            .frame(minWidth: 160)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canEncrypt || isEncrypting || !appState.gpgAvailable)
                }
            }
            .padding(24)
        }
        .navigationTitle("Encrypt")
        .overlay {
            if isEncrypting {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Encrypting…").foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .task(id: appState.pendingEncryptURLs) {
            // Process pending URLs when view appears or when they arrive (e.g. from right-click)
            guard !appState.pendingEncryptURLs.isEmpty else { return }
            let urls = appState.pendingEncryptURLs
            appState.pendingEncryptURLs = []
            files = urls
            resultURLs = []
            errorMessage = nil
        }
        .onChange(of: appState.pendingEncryptURLs) { _, urls in
            if !urls.isEmpty {
                files = urls
                appState.pendingEncryptURLs = []
                resultURLs = []
                errorMessage = nil
            }
        }
    }

    private var fileList: some View {
        VStack(spacing: 2) {
            ForEach(files, id: \.absoluteString) { url in
                HStack {
                    Image(systemName: "doc")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                    Spacer()
                    Text(url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        files.removeAll { $0 == url }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var recipientsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recipients:")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(recipients) { key in
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                    Text(key.displayName).font(.callout)
                }
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var resultList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Encrypted Files", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            ForEach(resultURLs, id: \.absoluteString) { url in
                HStack {
                    Image(systemName: "lock.doc.fill").foregroundStyle(.green)
                    Text(url.lastPathComponent).lineLimit(1)
                    Spacer()
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            files.append(contentsOf: panel.urls)
        }
    }

    private func performEncrypt() {
        guard let group = selectedGroup else { return }
        let recipients = group.keyFingerprints
        isEncrypting = true
        errorMessage = nil
        resultURLs = []

        Task {
            do {
                let outputs = try await appState.encrypt(
                    files: files,
                    recipients: recipients,
                    outputSameDir: appState.settings.outputSameDirectory
                )
                resultURLs = outputs
                files = []
            } catch {
                errorMessage = error.localizedDescription
            }
            isEncrypting = false
        }
    }
}
