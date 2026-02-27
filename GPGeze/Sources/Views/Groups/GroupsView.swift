import SwiftUI

struct GroupsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedGroup: KeyGroup?
    @State private var showNewGroupAlert = false
    @State private var newGroupName = ""
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var groupToRename: KeyGroup?

    var body: some View {
        NavigationSplitView {
            List(appState.groups, selection: $selectedGroup) { group in
                GroupRow(group: group, keyCount: group.keyFingerprints.count)
                    .tag(group)
                    .contextMenu {
                        Button("Rename…") {
                            groupToRename = group
                            renameText = group.name
                            showRenameAlert = true
                        }
                        Divider()
                        Button("Delete Group", role: .destructive) {
                            appState.deleteGroup(group)
                            if selectedGroup?.id == group.id { selectedGroup = nil }
                        }
                    }
            }
            .listStyle(.sidebar)
            .overlay {
                if appState.groups.isEmpty {
                    ContentUnavailableView {
                        Label("No Groups", systemImage: "person.3")
                    } description: {
                        Text("Create a group to organize recipients for file encryption.")
                    } actions: {
                        Button("New Group") { showNewGroupAlert = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Group", systemImage: "plus") { showNewGroupAlert = true }
                }
            }
            .navigationTitle("Groups")
        } detail: {
            if let group = selectedGroup, let idx = appState.groups.firstIndex(where: { $0.id == group.id }) {
                GroupDetailView(group: $appState.groups[idx])
            } else {
                ContentUnavailableView("Select a Group", systemImage: "person.3", description: Text("Choose a group from the sidebar to manage its members."))
            }
        }
        .alert("New Group", isPresented: $showNewGroupAlert) {
            TextField("Group name", text: $newGroupName)
            Button("Create") {
                let name = newGroupName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { appState.addGroup(name: name) }
                newGroupName = ""
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { newGroupName = "" }
        }
        .alert("Rename Group", isPresented: $showRenameAlert) {
            TextField("Group name", text: $renameText)
            Button("Rename") {
                if let g = groupToRename {
                    appState.renameGroup(g, to: renameText.trimmingCharacters(in: .whitespaces))
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct GroupRow: View {
    let group: KeyGroup
    let keyCount: Int

    var body: some View {
        HStack {
            Image(systemName: "person.3.fill")
                .foregroundStyle(Color.accentColor)
                .font(.callout)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.name)
                    .font(.body)
                Text("\(keyCount) \(keyCount == 1 ? "key" : "keys")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
