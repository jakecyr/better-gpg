import SwiftUI

struct GroupsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedGroupID: UUID?
    @State private var searchText = ""
    @State private var showNewGroup = false
    @State private var newGroupName = ""
    @State private var renameTarget: KeyGroup?
    @State private var renameText = ""

    private var filteredGroups: [KeyGroup] {
        guard !searchText.isEmpty else { return appState.groups }
        return appState.groups.filter { group in
            group.name.localizedCaseInsensitiveContains(searchText)
                || appState.recipients(for: group).contains { $0.displayName.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        Group {
            if appState.groups.isEmpty {
                ContentUnavailableView {
                    Label("No Groups", systemImage: "person.3")
                } description: {
                    Text("A group is a set of people you encrypt files for together.")
                } actions: {
                    Button("New Group…") { showNewGroup = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                GeometryReader { proxy in
                    HSplitView {
                        groupList
                            .frame(minWidth: 190, idealWidth: 230, maxWidth: 340)
                            .frame(height: proxy.size.height, alignment: .top)
                        detail
                            .frame(minWidth: 380, maxWidth: .infinity)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .frame(height: proxy.size.height, alignment: .topLeading)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                }
            }
        }
        .navigationTitle("Groups")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Group", systemImage: "plus") { showNewGroup = true }
            }
        }
        .onAppear(perform: ensureSelection)
        .onChange(of: appState.groups) { ensureSelection() }
        .alert("New Group", isPresented: $showNewGroup) {
            TextField("Name", text: $newGroupName)
            Button("Create") {
                let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    searchText = ""
                    selectedGroupID = appState.addGroup(name: name)
                }
                newGroupName = ""
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { newGroupName = "" }
        }
        .alert("Rename Group", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let renameTarget, !name.isEmpty {
                    appState.renameGroup(id: renameTarget.id, to: name)
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        }
    }

    private var groupList: some View {
        VStack(spacing: 0) {
            SearchField(text: $searchText, prompt: "Search groups")
                .padding(10)

            List(selection: $selectedGroupID) {
                ForEach(filteredGroups) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name)
                        Text(peopleCount(group.keyFingerprints.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .tag(group.id)
                    .contextMenu {
                        Button("Rename…") {
                            renameTarget = group
                            renameText = group.name
                        }
                        Divider()
                        Button("Delete Group", role: .destructive) { delete(group) }
                    }
                }
            }
            .listStyle(.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDeleteCommand {
                if let group = appState.groups.first(where: { $0.id == selectedGroupID }) {
                    delete(group)
                }
            }
            .overlay {
                if filteredGroups.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }

            Divider()
            HStack {
                Button { showNewGroup = true } label: {
                    Label("New Group", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedGroupID, appState.groups.contains(where: { $0.id == selectedGroupID }) {
            GroupDetailView(groupID: selectedGroupID)
                .id(selectedGroupID)
        } else {
            ContentUnavailableView {
                Label("No Group Selected", systemImage: "person.3")
            } description: {
                Text("Choose a group to see who can open files encrypted for it.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func ensureSelection() {
        if selectedGroupID == nil || !appState.groups.contains(where: { $0.id == selectedGroupID }) {
            selectedGroupID = appState.groups.first?.id
        }
    }

    private func delete(_ group: KeyGroup) {
        appState.deleteGroup(group)
        ensureSelection()
    }
}

func peopleCount(_ count: Int) -> String {
    count == 1 ? "1 person" : "\(count) people"
}
