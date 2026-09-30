import SwiftUI

struct SessionsView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionManager.self) private var sessions
    @Environment(DocumentStore.self) private var documents
    @State private var pendingForceLock: PlaintextSession?
    @State private var pendingShred: PlaintextSession?
    @State private var detail: PlaintextSession?

    var body: some View {
        Group {
            if sessions.sessions.isEmpty && documents.documents.isEmpty {
                ContentUnavailableView {
                    Label("No Sessions", systemImage: "lock")
                } description: {
                    Text("Open an encrypted file and it will show up here until it is locked again.")
                } actions: {
                    Button("Open Encrypted…") {
                        let urls = SystemDialogs.chooseFiles(
                            allowsDirectories: false,
                            message: "Choose encrypted files to open",
                            extensions: ["gpg", "pgp", "asc"]
                        )
                        guard !urls.isEmpty else { return }
                        appState.handleIncomingFiles(urls, source: .drag)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    let active = sessions.sessions.filter { $0.phase != .done }
                    let done = sessions.sessions.filter { $0.phase == .done }
                    if !documents.documents.isEmpty {
                        Section("Open in BetterGPG") {
                            ForEach(documents.documents) { document in
                                DocumentRow(document: document)
                            }
                        }
                    }
                    if !active.isEmpty {
                        Section("Open in other apps") {
                            ForEach(active) { session in
                                SessionRow(session: session)
                            }
                        }
                    }
                    if !done.isEmpty {
                        Section("Locked") {
                            ForEach(done) { session in
                                SessionRow(session: session)
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem {
                Button("Lock All") {
                    Task { _ = await appState.lockEverything() }
                }
                .disabled(appState.unlockedCount == 0)
            }
            ToolbarItem {
                Button("Clear Locked") { sessions.clearFinished() }
                    .disabled(!sessions.sessions.contains { $0.phase == .done })
            }
        }
        .confirmationDialog(
            "This file may still be open",
            isPresented: Binding(
                get: { pendingForceLock != nil },
                set: { if !$0 { pendingForceLock = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Lock Anyway", role: .destructive) {
                if let session = pendingForceLock {
                    Task { await sessions.lock(session.id, force: true) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unsaved changes in the other app will be missed. Saved changes are written back, then the unlocked copy is shredded.")
        }
        .confirmationDialog(
            "Shred the unlocked copy?",
            isPresented: Binding(
                get: { pendingShred != nil },
                set: { if !$0 { pendingShred = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Shred Unlocked Copy", role: .destructive) {
                if let session = pendingShred {
                    Task { await sessions.shredPlaintext(session.id, force: true) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The original encrypted file stays as it is. Changes in the unlocked copy are discarded.")
        }
        .sheet(item: $detail) { session in
            if let info = session.encryptionInfo {
                EncryptionInfoPanel(fileURL: session.sourceURL, info: info, appState: appState)
            }
        }
        .environment(\.sessionActions, SessionActions(
            lock: { session in
                if session.phase == .overdue {
                    pendingForceLock = session
                } else {
                    Task { await sessions.lock(session.id, force: false) }
                }
            },
            shred: { pendingShred = $0 },
            revealPlaintext: { session in
                if let url = session.plaintextURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            },
            revealSource: { NSWorkspace.shared.activateFileViewerSelecting([$0.sourceURL]) },
            showDetail: { detail = $0 },
            dismiss: { sessions.dismiss($0.id) }
        ))
    }
}

private struct SessionActions {
    var lock: (PlaintextSession) -> Void
    var shred: (PlaintextSession) -> Void
    var revealPlaintext: (PlaintextSession) -> Void
    var revealSource: (PlaintextSession) -> Void
    var showDetail: (PlaintextSession) -> Void
    var dismiss: (PlaintextSession) -> Void
}

private struct SessionActionKey: EnvironmentKey {
    static let defaultValue: SessionActions? = nil
}

private extension EnvironmentValues {
    var sessionActions: SessionActions? {
        get { self[SessionActionKey.self] }
        set { self[SessionActionKey.self] = newValue }
    }
}

private struct SessionRow: View {
    @Environment(\.sessionActions) private var actions
    let session: PlaintextSession

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.body.weight(.medium))
                Text(session.sourceURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(session.summary)
                    .font(.callout)
                    .foregroundStyle(session.phase == .failed || session.phase == .overdue ? Color.orange : Color.secondary)
                if let note = session.resultNote, session.phase != .done {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if session.phase == .preparing || session.phase == .locking {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            Spacer(minLength: 8)
            controls
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var controls: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if session.phase == .exposed || session.phase == .overdue || session.phase == .failed {
                Button(session.phase == .overdue ? "Lock Anyway" : "Lock Now") {
                    actions?.lock(session)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            if session.holdsPlaintext, session.phase != .preparing, session.phase != .locking {
                Button("Shred Copy") { actions?.shred(session) }
                    .controlSize(.small)
            }
            if session.plaintextURL != nil, session.holdsPlaintext {
                Button("Reveal") { actions?.revealPlaintext(session) }
                    .controlSize(.small)
            }
            if session.encryptionInfo != nil {
                Button("Details") { actions?.showDetail(session) }
                    .controlSize(.small)
            }
            if session.phase == .done || (session.phase == .failed && !session.holdsPlaintext) {
                Button("Remove") { actions?.dismiss(session) }
                    .controlSize(.small)
            }
        }
    }

    private var icon: String {
        switch session.phase {
        case .preparing, .locking: return "hourglass"
        case .exposed: return "lock.open.fill"
        case .overdue: return "exclamationmark.triangle.fill"
        case .done: return "lock.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch session.phase {
        case .done: return .green
        case .overdue, .failed: return .orange
        default: return .accentColor
        }
    }
}

private struct DocumentRow: View {
    @Environment(DocumentStore.self) private var store
    let document: ViewerDocument

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(isWarning ? Color.orange : Color.accentColor)
                .frame(width: 28)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(document.plaintextName)
                    .font(.body.weight(.medium))
                Text(document.sourceURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(document.statusText)
                    .font(.callout)
                    .foregroundStyle(isWarning ? Color.orange : Color.secondary)
                if document.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Button("Show") { store.focus(document) }
                    .controlSize(.small)
                if case .saveFailed = document.phase {
                    Button("Try Again") {
                        Task { await store.close(document.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button("Discard Changes") {
                        Task { await store.close(document.id, saveChanges: false) }
                    }
                    .controlSize(.small)
                } else {
                    Button("Lock") {
                        Task { await store.close(document.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(document.phase == .closing)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var isWarning: Bool {
        switch document.phase {
        case .saveFailed, .failed: return true
        default: return false
        }
    }

    private var icon: String {
        switch document.kind {
        case .text: return "doc.text"
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        case .quickLook: return "eye"
        }
    }
}

struct SessionMenu: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionManager.self) private var sessions
    @Environment(DocumentStore.self) private var documents
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if appState.unlockedCount == 0 {
            Text("No unlocked files")
        } else {
            if let note = appState.vaultNotes.openNote {
                Button("Lock \(note.displayName)") {
                    Task { await appState.vaultNotes.closeOpenNote() }
                }
            }
            ForEach(documents.documents) { document in
                Button("Lock \(document.plaintextName)") {
                    Task { await documents.close(document.id) }
                }
            }
            ForEach(sessions.exposedSessions) { session in
                Button("Lock \(session.title)") {
                    Task { await sessions.lock(session.id, force: session.phase == .overdue) }
                }
            }
            Divider()
            Button("Lock Everything") {
                Task { _ = await appState.lockEverything() }
            }
        }
        Divider()
        Button("Open BetterGPG") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            if case .vaultFile = appState.sidebarSelection, appState.vaultNotes.openNote != nil {
                return
            }
            appState.section = appState.unlockedCount == 0 ? .home : .sessions
        }
    }
}
