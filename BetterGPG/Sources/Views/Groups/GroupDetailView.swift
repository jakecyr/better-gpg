import SwiftUI

struct GroupDetailView: View {
    @Environment(AppState.self) private var appState
    let groupID: UUID
    @State private var showAddPeople = false
    @State private var searchText = ""
    @State private var selection = Set<String>()

    private var group: KeyGroup? {
        appState.groups.first { $0.id == groupID }
    }

    private var members: [GPGKey] {
        group.map { appState.recipients(for: $0) } ?? []
    }

    private var filteredMembers: [GPGKey] {
        guard !searchText.isEmpty else { return members }
        return members.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.fingerprint.localizedCaseInsensitiveContains(searchText.replacingOccurrences(of: " ", with: ""))
        }
    }

    var body: some View {
        if let group {
            Group {
                if members.isEmpty {
                    ContentUnavailableView {
                        Label("No People Yet", systemImage: "person.crop.circle.badge.plus")
                    } description: {
                        Text("Add everyone who should be able to open files you encrypt for \(group.name).")
                    } actions: {
                        Button("Add People…") { showAddPeople = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    peopleList(group)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    header(group)
                    Divider()
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
            .sheet(isPresented: $showAddPeople) {
                AddPeopleSheet(groupID: groupID)
            }
        }
    }

    private func header(_ group: KeyGroup) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.title2.bold())
                    .lineLimit(1)
                if !members.isEmpty {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            if !members.isEmpty {
                Button("Add People…") { showAddPeople = true }
                Button("Encrypt Files…") { encrypt(for: group) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!appState.gpgAvailable)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        var text = "\(peopleCount(members.count)). Any of them can open files encrypted for this group."
        if appState.settings.includeOwnKey, appState.ownKey != nil {
            text += " So can you."
        }
        return text
    }

    private func peopleList(_ group: KeyGroup) -> some View {
        VStack(spacing: 0) {
            SearchField(text: $searchText, prompt: "Search people")
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 4)

            List(selection: $selection) {
                ForEach(filteredMembers) { key in
                    HStack {
                        KeyRow(key: key, isOwn: key.fingerprint == appState.settings.ownKeyFingerprint)
                        Button("Remove from Group", systemImage: "minus.circle") {
                            remove([key.fingerprint], from: group)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Remove from group")
                    }
                    .tag(key.fingerprint)
                }
            }
            .listStyle(.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contextMenu(forSelectionType: String.self) { fingerprints in
                if !fingerprints.isEmpty {
                    Button(fingerprints.count == 1 ? "Remove from Group" : "Remove \(fingerprints.count) People from Group", role: .destructive) {
                        remove(fingerprints, from: group)
                    }
                }
            }
            .onDeleteCommand { remove(selection, from: group) }
            .overlay {
                if filteredMembers.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    private func remove(_ fingerprints: Set<String>, from group: KeyGroup) {
        for fingerprint in fingerprints {
            appState.removeKey(fingerprint, fromGroup: group.id)
        }
        selection.subtract(fingerprints)
    }

    private func encrypt(for group: KeyGroup) {
        let urls = SystemDialogs.chooseFiles(
            allowsDirectories: true,
            message: "Choose files to encrypt for \(group.name)",
            extensions: nil
        )
        guard !urls.isEmpty else { return }
        appState.activeSheet = .encrypt(urls: urls, groupID: group.id)
    }
}

private struct AddPeopleSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let groupID: UUID
    @State private var selection = Set<String>()
    @State private var searchText = ""

    private var group: KeyGroup? {
        appState.groups.first { $0.id == groupID }
    }

    private var candidates: [GPGKey] {
        let existing = Set(group?.keyFingerprints ?? [])
        return appState.publicKeys.filter { !existing.contains($0.fingerprint) }
    }

    private var filteredCandidates: [GPGKey] {
        guard !searchText.isEmpty else { return candidates }
        return candidates.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.fingerprint.localizedCaseInsensitiveContains(searchText.replacingOccurrences(of: " ", with: ""))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add People to \(group?.name ?? "Group")")
                    .font(.headline)
                Text("Select one or more people. Hold ⌘ to select several.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 12)

            if candidates.isEmpty {
                ContentUnavailableView {
                    Label(appState.publicKeys.isEmpty ? "No Keys Yet" : "Everyone Is Already Here", systemImage: "person.crop.circle")
                } description: {
                    Text(appState.publicKeys.isEmpty
                        ? "Import someone's public key first, then add them to this group."
                        : "Everyone you have imported is already in this group.")
                } actions: {
                    Button("Import Key…") {
                        dismiss()
                        Task {
                            try? await Task.sleep(for: .milliseconds(350))
                            appState.activeSheet = .importKey(text: "")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SearchField(text: $searchText, prompt: "Search people")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                List(filteredCandidates, selection: $selection) { key in
                    KeyRow(key: key, isOwn: key.fingerprint == appState.settings.ownKeyFingerprint)
                        .tag(key.fingerprint)
                }
                .listStyle(.inset)
                .overlay {
                    if filteredCandidates.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(selection.count > 1 ? "Add \(selection.count) People" : "Add") {
                    for fingerprint in selection {
                        appState.addKey(fingerprint, toGroup: groupID)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 500, height: 460)
    }
}
