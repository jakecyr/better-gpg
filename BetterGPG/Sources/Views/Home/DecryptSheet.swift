import SwiftUI

struct DecryptSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionManager.self) private var sessions
    @Environment(DocumentStore.self) private var documents
    @Environment(\.dismiss) private var dismiss

    let urls: [URL]
    let initialMode: OpenMode

    @State private var mode: OpenMode = .viewer
    @State private var useRamDisk = true
    @State private var finishAction: SessionPolicy.FinishAction = .reencryptAndShred
    @State private var lockWhenClosed = true
    @State private var autoLockMinutes = 15
    @State private var openAfterDecrypt = true
    @State private var remember = false
    @State private var didLoad = false
    @State private var infos: [EncryptionInfo] = []
    @State private var inspecting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Open encrypted file")
                .font(.title2.bold())

            Picker("Open with", selection: $mode) {
                Text("View in BetterGPG").tag(OpenMode.viewer)
                Text("Open in another app").tag(OpenMode.externalApp)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(modeDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(urls, id: \.path) { url in
                        FileChip(url: url, detail: nil, onRemove: nil)
                    }
                }
            }
            .frame(maxHeight: 110)

            if inspecting {
                ProgressView("Reading recipients…")
                    .controlSize(.small)
            } else if !recipientNames.isEmpty {
                Label(recipientNames.joined(separator: ", "), systemImage: "person.2")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if recipientsHidden {
                Label("Recipients are hidden on this file, so changes cannot be saved back into it. Closing wipes the unlocked copy and leaves the original as it is.", systemImage: "eye.slash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if cannotDecrypt {
                Label("Your secret key does not appear to be on this file. You can still try.", systemImage: "key.slash")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if mode == .externalApp {
                Picker("Unlocked copy", selection: $useRamDisk) {
                    Text("Memory disk").tag(true)
                    Text("Private temporary folder").tag(false)
                }
                .pickerStyle(.radioGroup)

                Picker("When it locks", selection: $finishAction) {
                    Text("Save changes, then shred the unlocked copy").tag(SessionPolicy.FinishAction.reencryptAndShred)
                    Text("Discard changes and shred the unlocked copy").tag(SessionPolicy.FinishAction.shredOnly)
                }
                .pickerStyle(.radioGroup)
                .disabled(recipientsHidden)

                Toggle("Lock when the file is closed", isOn: $lockWhenClosed)
                Toggle("Open the file after unlocking", isOn: $openAfterDecrypt)
            }

            Picker("Safety timer", selection: $autoLockMinutes) {
                Text("Off").tag(0)
                Text("5 minutes").tag(5)
                Text("15 minutes").tag(15)
                Text("1 hour").tag(60)
                Text("4 hours").tag(240)
            }

            if mode == .externalApp, !lockWhenClosed, autoLockMinutes == 0 {
                Text("The unlocked copy stays until you lock it from Sessions or the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Remember these choices", isOn: $remember)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(mode == .viewer ? "View" : "Open") { open() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!appState.gpgAvailable || urls.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: loadDefaults)
        .task { await inspect() }
    }

    private var modeDescription: String {
        switch mode {
        case .viewer:
            return "Text, PDFs, and images up to \(appState.settings.memoryLimitMegabytes) MB stay in memory. Larger or other files use a private temporary folder. Closing the window saves text edits back into the encrypted file and wipes everything."
        case .externalApp:
            return "The file opens in its usual app. When that app closes it, or the timer runs out, BetterGPG locks it again and shreds the unlocked copy."
        }
    }

    private var recipientsHidden: Bool {
        !infos.isEmpty && infos.allSatisfy(\.hasHiddenRecipients)
    }

    private var cannotDecrypt: Bool {
        !infos.isEmpty && infos.allSatisfy { !$0.isCurrentUserRecipient }
    }

    private var recipientNames: [String] {
        var names: [String] = []
        for info in infos {
            for keyId in info.visibleRecipientKeyIds {
                let name = appState.key(forKeyId: keyId)?.shortName ?? "Key \(keyId.suffix(8))"
                if !names.contains(name) { names.append(name) }
            }
        }
        return names
    }

    private func loadDefaults() {
        guard !didLoad else { return }
        didLoad = true
        let settings = appState.settings
        mode = initialMode
        useRamDisk = settings.useRamDisk
        lockWhenClosed = settings.lockWhenClosed
        autoLockMinutes = settings.autoLockMinutes
        openAfterDecrypt = settings.openAfterDecrypt
    }

    private func inspect() async {
        inspecting = true
        var loaded: [EncryptionInfo] = []
        for url in urls {
            if let info = try? await appState.encryptionInfo(for: url) {
                loaded.append(info)
            }
        }
        infos = loaded
        if !loaded.isEmpty, loaded.allSatisfy(\.hasHiddenRecipients) {
            finishAction = .shredOnly
        }
        inspecting = false
    }

    private func open() {
        if remember {
            appState.settings.defaultOpenMode = mode
            appState.settings.autoLockMinutes = autoLockMinutes
            if mode == .externalApp {
                appState.settings.useRamDisk = useRamDisk
                appState.settings.lockWhenClosed = lockWhenClosed
                appState.settings.openAfterDecrypt = openAfterDecrypt
            }
            appState.persistSettings()
        }

        let files = urls
        dismiss()
        switch mode {
        case .viewer:
            documents.open(files, autoCloseMinutes: autoLockMinutes)
        case .externalApp:
            let policy = SessionPolicy(
                useRamDisk: useRamDisk,
                openAfterDecrypt: openAfterDecrypt,
                finishAction: recipientsHidden ? .shredOnly : finishAction,
                lockWhenClosed: lockWhenClosed,
                autoLockAfter: autoLockMinutes > 0 ? TimeInterval(autoLockMinutes * 60) : nil
            )
            appState.section = .sessions
            Task { await sessions.open(urls: files, policy: policy) }
        }
    }
}
