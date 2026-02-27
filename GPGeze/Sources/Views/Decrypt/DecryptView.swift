import SwiftUI

struct DecryptView: View {
    @EnvironmentObject var appState: AppState
    @State private var files: [URL] = []
    @State private var isDecrypting = false
    @State private var resultURLs: [URL] = []
    @State private var errorMessage: String?
    @State private var selectedFileURL: URL?
    @State private var encryptionInfo: EncryptionInfo?
    @State private var isLoadingInfo = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !appState.gpgAvailable {
                    GPGNotInstalledBanner()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Encrypted Files", systemImage: "lock.doc.fill")
                        .font(.headline)

                    FileDropZone(
                        label: "Drop .gpg files here or click to choose",
                        systemImage: "lock.circle.dotted",
                        droppedURLs: $files
                    ) {
                        chooseFiles()
                    }

                    if !files.isEmpty {
                        fileList
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("GPG will prompt for your passphrase via the system pinentry dialog.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let err = errorMessage {
                    Label(err, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                if !resultURLs.isEmpty {
                    resultList
                }

                HStack {
                    Spacer()
                    Button {
                        performDecrypt()
                    } label: {
                        Label("Decrypt \(files.count == 1 ? "File" : "\(files.count) Files")", systemImage: "lock.open.fill")
                            .frame(minWidth: 160)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(files.isEmpty || isDecrypting || !appState.gpgAvailable)
                }
            }
            .padding(24)
        }
        .navigationTitle("Decrypt")
        .overlay {
            if isDecrypting {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Decrypting…").foregroundStyle(.secondary)
                        Text("Enter your passphrase if prompted").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var fileList: some View {
        VStack(spacing: 2) {
            ForEach(files, id: \.absoluteString) { url in
                HStack {
                    Button {
                        showEncryptionInfo(for: url)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.doc")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
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
        .sheet(isPresented: Binding(
            get: { selectedFileURL != nil },
            set: { if !$0 { selectedFileURL = nil; encryptionInfo = nil } }
        )) {
            if let url = selectedFileURL {
                if let info = encryptionInfo {
                    EncryptionInfoPanel(fileURL: url, info: info, appState: appState)
                } else if isLoadingInfo {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Reading encryption info…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 300, minHeight: 150)
                }
            }
        }
    }

    private func showEncryptionInfo(for url: URL) {
        selectedFileURL = url
        encryptionInfo = nil
        isLoadingInfo = true
        Task {
            do {
                let info = try await appState.getEncryptionInfo(for: url)
                await MainActor.run {
                    encryptionInfo = info
                    isLoadingInfo = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Could not read file: \(error.localizedDescription)"
                    selectedFileURL = nil
                    encryptionInfo = nil
                    isLoadingInfo = false
                }
            }
        }
    }

    private var resultList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Decrypted Files", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            ForEach(resultURLs, id: \.absoluteString) { url in
                HStack {
                    Image(systemName: "doc.fill").foregroundStyle(.green)
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
        panel.message = "Select encrypted (.gpg) files to decrypt"
        if panel.runModal() == .OK {
            files.append(contentsOf: panel.urls)
        }
    }

    private func performDecrypt(revealAfter: Bool = false) {
        isDecrypting = true
        errorMessage = nil
        resultURLs = []
        let filesToDecrypt = files

        Task {
            do {
                let outputs = try await appState.decrypt(files: filesToDecrypt)
                await MainActor.run {
                    resultURLs = outputs
                    files = []
                    if revealAfter, !outputs.isEmpty {
                        NSWorkspace.shared.activateFileViewerSelecting(outputs)
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                isDecrypting = false
            }
        }
    }
}
