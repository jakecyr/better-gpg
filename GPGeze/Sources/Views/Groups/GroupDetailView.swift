import SwiftUI

struct GroupDetailView: View {
    @EnvironmentObject var appState: AppState
    @Binding var group: KeyGroup
    @State private var showAddKeySheet = false
    @State private var searchText = ""

    private var groupKeys: [GPGKey] {
        group.keyFingerprints.compactMap { fp in
            appState.publicKeys.first { $0.fingerprint == fp }
            ?? appState.secretKeys.first { $0.fingerprint == fp }
        }
    }

    private var filteredGroupKeys: [GPGKey] {
        guard !searchText.isEmpty else { return groupKeys }
        return groupKeys.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.fingerprint.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                if filteredGroupKeys.isEmpty && searchText.isEmpty {
                    ContentUnavailableView {
                        Label("No Keys in Group", systemImage: "person.crop.circle.badge.plus")
                    } description: {
                        Text("Add public keys to this group. Files encrypted for this group can be decrypted by anyone with a matching private key.")
                    } actions: {
                        Button("Add Keys…") { showAddKeySheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    Section("Members (\(filteredGroupKeys.count))") {
                        ForEach(filteredGroupKeys) { key in
                            HStack {
                                KeyRow(key: key, isOwn: key.fingerprint == appState.settings.ownKeyFingerprint)
                                Spacer()
                                Button {
                                    appState.removeKey(key.fingerprint, fromGroup: group.id)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .help("Remove from group")
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search members…")
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Divider()

            HStack {
                if appState.settings.includeOwnKey && !appState.settings.ownKeyFingerprint.isEmpty {
                    Label("Your key will be auto-included when encrypting", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add Keys…") { showAddKeySheet = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .navigationTitle(group.name)
        .sheet(isPresented: $showAddKeySheet) {
            AddKeysToGroupSheet(group: $group)
        }
    }
}

// MARK: - Add Keys Sheet

struct AddKeysToGroupSheet: View {
    @EnvironmentObject var appState: AppState
    @Binding var group: KeyGroup
    @Environment(\.dismiss) var dismiss
    @State private var selected = Set<String>()
    @State private var searchText = ""

    private var availableKeys: [GPGKey] {
        let existing = Set(group.keyFingerprints)
        let keys = appState.publicKeys.filter { !existing.contains($0.fingerprint) }
        guard !searchText.isEmpty else { return keys }
        return keys.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.fingerprint.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Add Keys to \u{201C}\(group.name)\u{201D}")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { addSelected(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.top, .horizontal], 20)
            .padding(.bottom, 12)

            Divider()

            if availableKeys.isEmpty {
                ContentUnavailableView("No Keys Available", systemImage: "person.crop.circle", description: Text("All imported keys are already in this group, or you haven't imported any keys yet."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(availableKeys, selection: $selected) { key in
                    KeyRow(key: key, isOwn: key.fingerprint == appState.settings.ownKeyFingerprint)
                        .tag(key.fingerprint)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .searchable(text: $searchText, prompt: "Search keys…")
            }
        }
        .frame(width: 480, height: 400)
    }

    private func addSelected() {
        for fp in selected {
            appState.addKey(fp, toGroup: group.id)
        }
    }
}
