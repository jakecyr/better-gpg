import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionManager.self) private var sessions
    @Environment(DocumentStore.self) private var documents

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !appState.gpgAvailable {
                    GPGNotInstalledBanner()
                }

                FileDropZone(
                    title: "Drop files here",
                    subtitle: "Encrypted files open in BetterGPG's viewer or in another app. Everything else can be encrypted for a person or a group.",
                    systemImage: "lock.rectangle.stack"
                ) { urls in
                    appState.handleIncomingFiles(urls, source: .drag)
                }

                HStack(spacing: 10) {
                    Button("Encrypt…") { chooseAndEncrypt() }
                        .buttonStyle(.borderedProminent)
                    Button("Open Encrypted…") { chooseAndOpen() }
                    Button("Import Key…") {
                        appState.activeSheet = .importKey(text: "")
                    }
                    Spacer()
                }

                if !sessions.exposedSessions.isEmpty || !documents.documents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Unlocked now")
                            .font(.headline)
                        ForEach(documents.documents.prefix(4)) { document in
                            HStack {
                                Image(systemName: "eye.fill")
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(document.plaintextName)
                                    Text(document.statusText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Show") { documents.focus(document) }
                                    .controlSize(.small)
                            }
                        }
                        ForEach(sessions.exposedSessions.prefix(4)) { session in
                            HStack {
                                Image(systemName: session.phase == .overdue ? "exclamationmark.triangle.fill" : "lock.open.fill")
                                    .foregroundStyle(session.phase == .overdue ? Color.orange : Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title)
                                    Text(session.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Show") { appState.section = .sessions }
                                    .controlSize(.small)
                            }
                        }
                    }
                }

                if !appState.isLoadingKeys, appState.gpgAvailable, appState.secretKeys.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No secret key yet. Generate one so you can open files you encrypt for yourself. A passphrase is optional.", systemImage: "key")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Generate a Key…") { appState.activeSheet = .generateKey }
                                .buttonStyle(.borderedProminent)
                            if appState.publicKeys.isEmpty {
                                Button("Import Key…") { appState.activeSheet = .importKey(text: "") }
                            }
                        }
                    }
                } else if appState.publicKeys.isEmpty, !appState.isLoadingKeys, appState.gpgAvailable {
                    Label("Import a key before you encrypt for someone else. Your own key is included by default once GPG has a secret key.", systemImage: "person.crop.circle.badge.plus")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if !appState.activity.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent")
                            .font(.headline)
                        ForEach(appState.activity) { entry in
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundStyle(.secondary)
                                Text(entry.message)
                                    .lineLimit(2)
                                Spacer()
                                if let url = entry.revealURL {
                                    Button("Reveal") {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    }
                                    .controlSize(.small)
                                }
                            }
                            .font(.callout)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle("Home")
    }

    private func chooseAndEncrypt() {
        let urls = SystemDialogs.chooseFiles(
            allowsDirectories: true,
            message: "Choose files or folders to encrypt",
            extensions: nil
        )
        guard !urls.isEmpty else { return }
        appState.handleIncomingFiles(urls, source: .finderEncrypt)
    }

    private func chooseAndOpen() {
        let urls = SystemDialogs.chooseFiles(
            allowsDirectories: false,
            message: "Choose encrypted files to open",
            extensions: ["gpg", "pgp", "asc"]
        )
        guard !urls.isEmpty else { return }
        appState.handleIncomingFiles(urls, source: .drag)
    }
}
