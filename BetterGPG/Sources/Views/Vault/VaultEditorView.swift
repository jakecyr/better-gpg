import SwiftUI

struct VaultEditorView: View {
    @Bindable var note: VaultNote
    @Environment(AppState.self) private var appState
    @State private var capture = WindowCaptureGuard()

    var body: some View {
        VStack(spacing: 0) {
            if case .saveFailed(let message) = note.phase {
                saveFailedBanner(message)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if note.showsEditor {
                Divider()
                footer
            }
        }
        .navigationTitle(note.displayName)
        .navigationSubtitle(note.statusText)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $note.showsRender) {
                    Label("Render", systemImage: "text.alignleft")
                }
                .toggleStyle(.button)
                .disabled(note.phase == .loading || note.phase == .closing || note.isFailed)
                .help("Show rendered Markdown beside the text")
                Button("Save", systemImage: "square.and.arrow.down") {
                    Task { await appState.vaultNotes.saveOpenNote() }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!note.isDirty || !note.canEdit || note.isBusy)
                .help("Encrypt your changes back into \(note.sourceURL.lastPathComponent)")
                Button("Lock", systemImage: "lock.fill") {
                    Task { await appState.vaultNotes.closeOpenNote() }
                }
                .disabled(note.phase == .closing)
                .help("Encrypt your changes, wipe the unlocked text, and close")
            }
        }
        .background(WindowAccessor { window in
            capture.window = window
            window.sharingType = appState.settings.hideViewersFromCapture ? .none : .readOnly
        })
        .onDisappear {
            capture.window?.sharingType = .readOnly
        }
    }

    @ViewBuilder
    private var content: some View {
        switch note.phase {
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
                Label("Could not open this note", systemImage: "xmark.octagon")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await appState.vaultNotes.retryOpenNote() }
                }
                Button("Close") {
                    Task { await appState.vaultNotes.closeOpenNote(saveChanges: false) }
                }
            }
        case .ready, .saving, .saveFailed:
            editor
        }
    }

    @ViewBuilder
    private var editor: some View {
        if note.showsRender {
            HSplitView {
                textPane
                    .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 0) {
                    paneLabel("Rendered")
                    MarkdownPreview(source: note.text)
                }
                .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            textPane
        }
    }

    private var textPane: some View {
        VStack(spacing: 0) {
            if note.showsRender {
                paneLabel("Text")
            }
            VaultTextView(text: $note.text, isEditable: note.allowsEditing, note: note) {
                Task { await appState.vaultNotes.saveOpenNote() }
            }
        }
    }

    private func paneLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var footerText: String {
        if let reason = note.readOnlyReason {
            return "\(reason) Locking wipes the unlocked text."
        }
        if note.isDirty {
            return "Edited in memory. Locking encrypts your changes into \(note.sourceURL.lastPathComponent), then wipes the unlocked text."
        }
        return "Unlocked in memory. Locking wipes the text. The only copy on disk is the encrypted file."
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
                Task { await appState.vaultNotes.saveOpenNote() }
            }
            Button("Discard and Lock", role: .destructive) {
                Task { await appState.vaultNotes.closeOpenNote(saveChanges: false) }
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
    }
}

private final class WindowCaptureGuard {
    weak var window: NSWindow?
}

struct VaultTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    var note: VaultNote
    var onSave: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, note: note, onSave: onSave)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = VaultNSTextView()
        textView.isRichText = false
        textView.importsGraphics = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.enabledTextCheckingTypes = 0
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.onCommandSave = context.coordinator.onSave
        textView.string = text
        context.coordinator.acceptsEdits = !note.closed && !note.sealed
        note.textView = textView

        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        context.coordinator.note = note
        context.coordinator.onSave = onSave
        context.coordinator.acceptsEdits = !note.closed && !note.sealed
        note.textView = textView
        if let textView = textView as? VaultNSTextView {
            textView.onCommandSave = context.coordinator.onSave
        }
        textView.isEditable = isEditable && !note.sealed && !note.closed
        if textView.string != text {
            let selected = textView.selectedRanges
            textView.string = text
            if selected.allSatisfy({ ($0 as? NSRange).map { NSMaxRange($0) <= (text as NSString).length } == true }) {
                textView.selectedRanges = selected
            }
        }
        if !context.coordinator.didFocus, isEditable, textView.window != nil {
            context.coordinator.didFocus = true
            textView.window?.makeFirstResponder(textView)
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.acceptsEdits = false
        guard let textView = scroll.documentView as? NSTextView else { return }
        textView.isEditable = false
        textView.undoManager?.removeAllActions()
        textView.string = ""
        textView.textStorage?.setAttributedString(NSAttributedString())
        textView.undoManager?.removeAllActions()
        if coordinator.note?.textView === textView {
            coordinator.note?.textView = nil
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var note: VaultNote?
        var acceptsEdits = false
        var didFocus = false

        var onSave: () -> Void

        init(text: Binding<String>, note: VaultNote, onSave: @escaping () -> Void) {
            self.text = text
            self.note = note
            self.onSave = onSave
        }

        func textDidChange(_ notification: Notification) {
            guard acceptsEdits, let textView = notification.object as? NSTextView else { return }
            guard let note, !note.closed, !note.sealed else { return }
            text.wrappedValue = textView.string
        }
    }
}

/// Clears its undo stack if the view is released while a note is still unlocking.
private final class VaultNSTextView: NSTextView {
    var onCommandSave: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "s" {
            onCommandSave?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func removeFromSuperview() {
        undoManager?.removeAllActions()
        super.removeFromSuperview()
    }
}
