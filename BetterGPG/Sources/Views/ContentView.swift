import SwiftUI
import FinderSync

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var extensionEnabled = FIFinderSyncController.isExtensionEnabled
    @State private var extensionBannerDismissed = false

    private var showExtensionBanner: Bool {
        !extensionEnabled && !extensionBannerDismissed
    }

    var body: some View {
        VStack(spacing: 0) {
            if showExtensionBanner {
                extensionBanner
            }

            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
            } detail: {
                detailView
            }
            .navigationSplitViewStyle(.balanced)
        }
        .onChange(of: appState.pendingEncryptURLs) { _, urls in
            if !urls.isEmpty { appState.activeTab = .encrypt }
        }
        .alert("Error", isPresented: Binding(
            get: { appState.lastError != nil },
            set: { if !$0 { appState.lastError = nil } }
        )) {
            Button("OK") { appState.lastError = nil }
        } message: {
            Text(appState.lastError ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Refresh status whenever app comes back to foreground (e.g. after user enables extension)
            extensionEnabled = FIFinderSyncController.isExtensionEnabled
        }
    }

    // MARK: - Extension banner

    private var extensionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.point.right.fill")
                .foregroundStyle(Color.accentColor)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Enable Finder Extension for right-click access")
                    .font(.callout.bold())
                Text("One tap to add Encrypt/Decrypt to every file's right-click menu in Finder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Enable Now") {
                FIFinderSyncController.showExtensionManagementInterface()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                extensionBannerDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.08))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(SidebarItem.allCases, id: \.self, selection: $appState.activeTab) { item in
            Label(item.rawValue, systemImage: item.icon)
                .tag(item)
        }
        .listStyle(.sidebar)
        .navigationTitle("BetterGPG")
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }

    // MARK: - Detail

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
