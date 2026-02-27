import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var settings: AppSettings = AppSettings.load()
    @State private var isSaved = false

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

            // Services
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Finder right-click services are active when GPGeze is running.")
                        .font(.callout)
                }
                Text("Right-click any file in Finder → Services → **Encrypt with GPGeze…** or **Decrypt with GPGeze…**")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Finder Integration")
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
        }
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
