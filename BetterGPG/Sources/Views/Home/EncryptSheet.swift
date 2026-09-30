import SwiftUI

private enum RecipientTab: String, CaseIterable, Identifiable {
    case groups = "Groups"
    case people = "People"
    var id: String { rawValue }
}

struct EncryptSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var files: [URL]
    private let initialGroupID: UUID?

    @State private var tab: RecipientTab = .groups
    @State private var selectedGroupID: UUID?
    @State private var selectedFingerprints = Set<String>()
    @State private var search = ""
    @State private var includeOwnKey = true
    @State private var secureDeleteOriginals = false
    @State private var sign = false
    @State private var isEncrypting = false
    @State private var outputs: [URL] = []
    @State private var errorMessage: String?
    @State private var didConfigure = false

    init(urls: [URL], preselectedGroupID: UUID?) {
        _files = State(initialValue: urls)
        initialGroupID = preselectedGroupID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if outputs.isEmpty {
                composer
            } else {
                success
            }
        }
        .padding(24)
        .frame(width: 580, height: 640)
        .overlay {
            if isEncrypting {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Encrypting…")
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .onAppear(perform: configureIfNeeded)
        .onDisappear {
            appState.consumeQueuedDecrypt()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(outputs.isEmpty ? "Encrypt" : "Encrypted")
                .font(.title2.bold())
            Text(outputs.isEmpty
                 ? "Choose a group, or pick people. Your key can be added so you can still open the file."
                 : "The encrypted files are next to the originals.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(files, id: \.path) { url in
                        FileChip(url: url, detail: FileInfo.kind(of: url) == .folder ? "Will be zipped first" : nil) {
                            files.removeAll { $0.path == url.path }
                        }
                    }
                }
            }
            .frame(maxHeight: 120)

            Picker("Recipients", selection: $tab) {
                ForEach(RecipientTab.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                if tab == .groups {
                    groupList
                } else {
                    peopleList
                }
            }
            .frame(maxHeight: .infinity)

            Toggle("Include my key", isOn: $includeOwnKey)
                .disabled(resolvedOwnFingerprint == nil)
            if includeOwnKey, let own = appState.ownKey ?? appState.secretKeys.first {
                Text(own.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if appState.secretKeys.isEmpty {
                Text("No secret key yet. You can still encrypt for other people, and you will need one of their keys to open the file.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Toggle("Securely delete the originals after encrypting", isOn: $secureDeleteOriginals)
            Text("Folders are zipped and kept. Only regular files are overwritten and removed.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Sign with my key", isOn: $sign)
                .disabled(resolvedOwnFingerprint == nil)

            if let errorMessage {
                Label(errorMessage, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Encrypt") { performEncrypt() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canEncrypt || isEncrypting || !appState.gpgAvailable)
            }
        }
    }

    private var success: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(outputs, id: \.path) { url in
                HStack {
                    Image(systemName: "lock.doc.fill")
                        .foregroundStyle(.green)
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                    Spacer()
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .controlSize(.small)
                }
            }
            Spacer()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var groupList: some View {
        Group {
            if appState.groups.isEmpty {
                ContentUnavailableView("No Groups", systemImage: "person.3", description: Text("Create a group, or switch to People and pick keys directly."))
            } else {
                List(selection: $selectedGroupID) {
                    ForEach(appState.groups) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name)
                            Text(memberSummary(group))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(group.id)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private var peopleList: some View {
        VStack(spacing: 0) {
            if availablePeople.isEmpty {
                ContentUnavailableView("No Keys", systemImage: "person.crop.circle", description: Text("Import a public key, then choose who can open the file."))
            } else {
                List(availablePeople) { key in
                    Button {
                        toggle(key.fingerprint)
                    } label: {
                        HStack {
                            Image(systemName: selectedFingerprints.contains(key.fingerprint) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedFingerprints.contains(key.fingerprint) ? Color.accentColor : Color.secondary)
                            KeyRow(key: key, isOwn: key.fingerprint == resolvedOwnFingerprint)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .searchable(text: $search, prompt: "Search people")
            }
        }
    }

    private func toggle(_ fingerprint: String) {
        if selectedFingerprints.contains(fingerprint) {
            selectedFingerprints.remove(fingerprint)
        } else {
            selectedFingerprints.insert(fingerprint)
        }
    }

    private var availablePeople: [GPGKey] {
        let keys = appState.publicKeys
        guard !search.isEmpty else { return keys }
        return keys.filter {
            $0.displayName.localizedCaseInsensitiveContains(search)
                || $0.fingerprint.localizedCaseInsensitiveContains(search)
        }
    }

    private var resolvedOwnFingerprint: String? {
        if let own = appState.ownKey { return own.fingerprint }
        return appState.secretKeys.first?.fingerprint
    }

    private var recipientFingerprints: [String] {
        var fingerprints: [String] = []
        switch tab {
        case .groups:
            if let selectedGroupID, let group = appState.groups.first(where: { $0.id == selectedGroupID }) {
                fingerprints = group.keyFingerprints
            }
        case .people:
            fingerprints = Array(selectedFingerprints)
        }
        if includeOwnKey, let own = resolvedOwnFingerprint, !fingerprints.contains(own) {
            fingerprints.append(own)
        }
        return fingerprints
    }

    private var canEncrypt: Bool {
        !files.isEmpty && !recipientFingerprints.isEmpty
    }

    private func memberSummary(_ group: KeyGroup) -> String {
        let names = appState.recipients(for: group).map(\.shortName)
        if names.isEmpty { return "No keys yet" }
        return names.prefix(4).joined(separator: ", ")
    }

    private func configureIfNeeded() {
        guard !didConfigure else { return }
        didConfigure = true
        includeOwnKey = appState.settings.includeOwnKey && resolvedOwnFingerprint != nil
        secureDeleteOriginals = appState.settings.deleteOriginalAfterEncrypt
        sign = appState.settings.signWhenEncrypting && resolvedOwnFingerprint != nil
        if let initialGroupID, appState.groups.contains(where: { $0.id == initialGroupID }) {
            selectedGroupID = initialGroupID
            tab = .groups
        } else if appState.groups.isEmpty {
            tab = .people
        } else if appState.groups.count == 1 {
            selectedGroupID = appState.groups.first?.id
        }
    }

    private func performEncrypt() {
        let fingerprints = recipientFingerprints
        let groupID = tab == .groups ? selectedGroupID : nil
        isEncrypting = true
        errorMessage = nil
        Task {
            do {
                outputs = try await appState.encrypt(
                    files: files,
                    recipients: fingerprints,
                    secureDeleteOriginals: secureDeleteOriginals,
                    sign: sign,
                    groupID: groupID
                )
                files = []
            } catch {
                errorMessage = error.localizedDescription
            }
            isEncrypting = false
        }
    }
}
