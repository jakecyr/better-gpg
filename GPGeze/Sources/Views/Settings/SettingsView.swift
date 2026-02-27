import SwiftUI
import FinderSync

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var settings: AppSettings = AppSettings.load()
    @State private var isSaved = false
    @State private var extensionEnabled = false

    var body: some View {
        Form {
            // GPG Binary
            Section {
                LabeledContent("GPG Binary Path") {
                    HStack {
                        TextField("Path to gpg", text: $settings.gpgBinaryPath)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 280)
                        Button("Browse…") { browseBinary() }
                            .buttonStyle(.bordered)
                        if FileManager.default.fileExists(atPath: settings.gpgBinaryPath) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
                Text("Default locations: `/opt/homebrew/bin/gpg` (Apple Silicon) or `/usr/local/bin/gpg` (Intel). Install via `brew install gnupg` or [GPG Suite](https://gpgtools.org).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("GPG Configuration")
            }

            // Own key
            Section {
                Toggle("Always include my key when encrypting", isOn: $settings.includeOwnKey)
                    .help("Your key will be added as a recipient on every encryption, so you can always decrypt files you've encrypted for others.")

                if settings.includeOwnKey {
                    LabeledContent("My Key") {
                        Picker("", selection: $settings.ownKeyFingerprint) {
                            Text("None selected").tag("")
                            ForEach(appState.secretKeys) { key in
                                Text(key.displayName).tag(key.fingerprint)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 280)
                    }

                    if appState.secretKeys.isEmpty {
                        Text("No secret keys found in your keyring. Generate one with `gpg --gen-key` in Terminal.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("My Identity")
            }

            // Encryption options
            Section {
                Toggle("Sign files when encrypting", isOn: $settings.signWhenEncrypting)
                    .help("Digitally sign encrypted files with your key so recipients can verify authenticity.")
                    .disabled(settings.ownKeyFingerprint.isEmpty)

                Toggle("Delete original file after encryption", isOn: $settings.deleteOriginalAfterEncrypt)
                    .help("Permanently delete the source file after it has been successfully encrypted.")

                Toggle("Save encrypted file next to original", isOn: $settings.outputSameDirectory)
                    .help("Place the .gpg output file in the same directory as the source file.")
            } header: {
                Text("Encryption Options")
            }

            // Finder Extension
            Section {
                // Status row
                HStack(spacing: 10) {
                    Image(systemName: extensionEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(extensionEnabled ? .green : .red)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(extensionEnabled ? "Finder Extension is enabled" : "Finder Extension is disabled")
                            .font(.callout.weight(.medium))
                        Text(extensionEnabled
                             ? "Right-click any file in Finder — you'll see Encrypt/Decrypt options."
                             : "Click the button below to enable it. This is a one-time step.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                // The system sheet button — uses FIFinderSyncController directly
                Button(extensionEnabled ? "Manage Extension…" : "Enable Finder Extension…") {
                    // showExtensionManagementInterface() opens the native enable/disable sheet
                    FIFinderSyncController.showExtensionManagementInterface()
                }
                .buttonStyle(.borderedProminent)
                .tint(extensionEnabled ? .secondary : .accentColor)

                if !extensionEnabled {
                    Text("After clicking Enable, tick the checkbox next to **GPGezeFinderExtension** in the sheet that appears.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Finder Right-Click Integration")
            } footer: {
                if extensionEnabled {
                    Text("Items appear directly in Finder's right-click menu.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isSaved ? "Saved ✓" : "Save") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaved)
            }
        }
        .onAppear {
            settings = appState.settings
            refreshExtensionStatus()
        }
    }

    private func refreshExtensionStatus() {
        extensionEnabled = FIFinderSyncController.isExtensionEnabled
    }

    private func saveSettings() {
        appState.settings = settings
        appState.saveSettings()
        isSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isSaved = false }
    }

    private func browseBinary() {
        let panel = NSOpenPanel()
        panel.message = "Select the gpg binary"
        panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.gpgBinaryPath = url.path
        }
    }
}
