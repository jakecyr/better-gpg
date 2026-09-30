import SwiftUI

struct ViewerWindow: View {
    let documentID: UUID?
    @Environment(AppState.self) private var appState
    @Environment(DocumentStore.self) private var store
    @State private var closeObserver = WindowCloseObserver()

    private var document: ViewerDocument? {
        documentID.flatMap { store.document($0) }
    }

    var body: some View {
        Group {
            if let document {
                ViewerContent(document: document)
            } else {
                ContentUnavailableView(
                    "This file is locked",
                    systemImage: "lock.fill",
                    description: Text("Its unlocked copy has been removed.")
                )
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(WindowAccessor { window in attach(window) })
    }

    private func attach(_ window: NSWindow) {
        guard closeObserver.window !== window else { return }
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.sharingType = appState.settings.hideViewersFromCapture ? .none : .readOnly

        guard let documentID, let document = store.document(documentID) else {
            DispatchQueue.main.async { window.close() }
            return
        }
        document.window = window
        closeObserver.observe(window) { [store] in
            store.document(documentID)?.window = nil
            Task { await store.close(documentID) }
        }
    }
}

private struct ViewerContent: View {
    @Bindable var document: ViewerDocument
    @Environment(DocumentStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            if case .saveFailed(let message) = document.phase {
                saveFailedBanner(message)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .navigationTitle(document.plaintextName)
        .navigationSubtitle(document.statusText)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if document.kind == .text, document.phase != .loading {
                    Button("Save", systemImage: "square.and.arrow.down") {
                        Task { await store.save(document) }
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!document.isDirty || !document.canEdit || document.isBusy)
                    .help("Encrypt your changes back into \(document.sourceURL.lastPathComponent)")
                }
                Button("Open in Another App", systemImage: "arrow.up.forward.app") {
                    Task { await store.openExternally(document) }
                }
                .disabled(document.isBusy)
                .help("Close this window and open the file in its usual app, locked again when that app closes it")
                Button("Lock", systemImage: "lock.fill") {
                    Task { await store.close(document.id) }
                }
                .disabled(document.phase == .closing)
                .help("Save changes, wipe the unlocked copy, and close")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch document.phase {
        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                Text("Unlocking…")
                Text("Enter your passphrase if GPG asks for it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .closing:
            ProgressView("Locking…")
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not open this file", systemImage: "xmark.octagon")
            } description: {
                Text(message)
            } actions: {
                Button("Close") {
                    Task { await store.close(document.id, saveChanges: false) }
                }
            }
        case .ready, .saving, .saveFailed:
            loaded
        }
    }

    @ViewBuilder
    private var loaded: some View {
        switch document.kind {
        case .text:
            TextEditor(text: document.canEdit ? $document.text : .constant(document.text))
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .disabled(document.phase == .saving)
        case .pdf:
            if let pdf = document.pdf {
                PDFKitView(document: pdf)
            }
        case .image:
            if let image = document.image {
                ImageViewer(image: image)
            }
        case .quickLook:
            if let url = document.fileURL {
                QuickLookView(url: url)
            } else {
                ContentUnavailableView("Nothing to preview", systemImage: "doc.questionmark")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.secondary)
            Text(footerText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            if let deadline = document.deadline {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("Locks in \(PlaintextSession.format(deadline.timeIntervalSince(context.date)))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var footerText: String {
        if document.kind == .text, document.canEdit {
            return "Closing this window encrypts your changes into \(document.sourceURL.lastPathComponent), then wipes the unlocked copy."
        }
        if let reason = document.readOnlyReason, document.kind == .text || document.kind == .quickLook {
            return "\(reason) Closing wipes the unlocked copy."
        }
        return "View only. Closing wipes the unlocked copy."
    }

    private func saveFailedBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your changes are not saved yet")
                    .font(.callout.bold())
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Try Again") {
                Task { await store.save(document) }
            }
            Button("Discard and Lock", role: .destructive) {
                Task { await store.close(document.id, saveChanges: false) }
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
    }
}
