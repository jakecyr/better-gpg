import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: appState.pendingEncryptURLs) { _, urls in
            if !urls.isEmpty { appState.activeTab = .encrypt }
        }
        .onChange(of: appState.pendingDecryptURLs) { _, urls in
            if !urls.isEmpty { appState.activeTab = .decrypt }
        }
        .alert("Error", isPresented: Binding(
            get: { appState.lastError != nil },
            set: { if !$0 { appState.lastError = nil } }
        )) {
            Button("OK") { appState.lastError = nil }
        } message: {
            Text(appState.lastError ?? "")
        }
    }

    private var sidebar: some View {
        List(SidebarItem.allCases, id: \.self, selection: $appState.activeTab) { item in
            Label(item.rawValue, systemImage: item.icon)
                .tag(item)
        }
        .listStyle(.sidebar)
        .navigationTitle("GPGeze")
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.activeTab {
        case .keys:
            KeysView()
        case .groups:
            GroupsView()
        case .encrypt:
            EncryptView()
        case .decrypt:
            DecryptView()
        case .settings:
            SettingsView()
        }
    }
}
