import FinderSync
import SwiftUI

struct VaultNoteDetail: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let note = appState.vaultNotes.openNote {
            VaultEditorView(note: note)
                .id(note.id)
        } else {
            VStack(spacing: 10) {
                ProgressView()
                Text("Unlocking…")
                Text("Enter your passphrase if GPG asks for it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionManager.self) private var sessions
    @State private var extensionEnabled = FIFinderSyncController.isExtensionEnabled
    @State private var extensionBannerDismissed = false

    private var showExtensionBanner: Bool {
        !extensionEnabled && !extensionBannerDismissed
    }

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            if showExtensionBanner {
                extensionBanner
            }

            NavigationSplitView {
                List(selection: $appState.sidebarSelection) {
                    Section {
                        ForEach(AppSection.allCases) { section in
                            Label(section.title, systemImage: section.icon)
                                .badge(section == .sessions ? appState.unlockedCount : 0)
                                .tag(SidebarSelection.section(section))
                        }
                    }
                    VaultSidebarSection()
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
                .navigationTitle("BetterGPG")
            } detail: {
                switch appState.sidebarSelection {
                case .vaultFile:
                    VaultNoteDetail()
                case .section(let section):
                    sectionDetail(section)
                }
            }
            .navigationSplitViewStyle(.balanced)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task {
                let urls = await FileDrop.load(providers)
                guard !urls.isEmpty else { return }
                appState.handleIncomingFiles(urls, source: .drag)
            }
            return true
        }
        .sheet(item: $appState.activeSheet) { sheet in
            switch sheet {
            case .encrypt(let urls, let groupID):
                EncryptSheet(urls: urls, preselectedGroupID: groupID)
            case .decrypt(let urls, let mode):
                DecryptSheet(urls: urls, initialMode: mode)
            case .importKey(let text):
                ImportKeySheet(initialText: text)
            case .generateKey:
                GenerateKeySheet()
            case .review(let items):
                DropReviewSheet(items: items)
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { appState.lastError != nil },
            set: { if !$0 { appState.lastError = nil } }
        )) {
            Button("OK") { appState.lastError = nil }
        } message: {
            Text(appState.lastError ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            extensionEnabled = FIFinderSyncController.isExtensionEnabled
        }
        .onChange(of: appState.sidebarSelection) { _, selection in
            switch selection {
            case .section(let section):
                if appState.section != section {
                    appState.section = section
                }
                Task {
                    let closed = await appState.vaultNotes.closeOpenNote(saveChanges: true, updateSidebar: false)
                    if !closed, let path = appState.vaultNotes.openNote?.sourceURL.path {
                        appState.sidebarSelection = .vaultFile(path)
                    }
                }
            case .vaultFile(let path):
                Task { await appState.vaultNotes.open(path: path) }
            }
        }
        .sheet(isPresented: $appState.isCreatingVaultNote) {
            NewVaultNoteSheet { url in
                appState.sidebarSelection = .vaultFile(url.path)
            }
        }
    }

    @ViewBuilder
    private func sectionDetail(_ section: AppSection) -> some View {
        switch section {
        case .home:
            HomeView()
        case .sessions:
            SessionsView()
        case .keys:
            KeysView()
        case .groups:
            GroupsView()
        }
    }

    private var extensionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "contextualmenu.and.cursorarrow")
                .foregroundStyle(Color.accentColor)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Turn on the Finder extension")
                    .font(.callout.bold())
                Text("Then you can encrypt or open a file from its right-click menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Enable") {
                FIFinderSyncController.showExtensionManagementInterface()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button {
                extensionBannerDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }
}
