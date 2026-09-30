import FinderSync
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var gpgVersion: String?
    @State private var extensionEnabled = FIFinderSyncController.isExtensionEnabled
    @State private var showGenerateKey = false

    private var sweepSummary: String {
        let report = appState.vault.lastSweepReport
        var parts: [String] = []
        if report.removed > 0 {
            parts.append("Shredded \(report.removed) leftover \(report.removed == 1 ? "copy" : "copies").")
        }
        if report.kept > 0 {
            parts.append("\(report.kept) edited \(report.kept == 1 ? "copy is" : "copies are") waiting to be recovered, and will be retried.")
        }
        return parts.joined(separator: " ")
    }

    var body: some View {
        @Bindable var appState = appState

        Form {
            Section {
                LabeledContent("GPG") {
                    HStack {
                        TextField("Path to gpg", text: $appState.settings.gpgBinaryPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse…") {
                            if let url = SystemDialogs.chooseExecutable(message: "Choose the gpg binary") {
                                appState.settings.gpgBinaryPath = url.path
                            }
                        }
                        Image(systemName: appState.gpgAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(appState.gpgAvailable ? .green : .red)
                    }
                }
                if let gpgVersion {
                    Text(gpgVersion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Install with `brew install gnupg pinentry-mac`. Pinentry is what asks for your passphrase, and BetterGPG never sees it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("GPG")
            }

            Section {
                if appState.secretKeys.isEmpty {
                    Text("No secret key yet. Generate one to encrypt files you can open yourself. A passphrase is optional.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Generate a Key…") { showGenerateKey = true }
                        .disabled(!appState.gpgAvailable)
                }
                Toggle("Include my key whenever I encrypt", isOn: $appState.settings.includeOwnKey)
                if appState.settings.includeOwnKey {
                    Picker("My key", selection: $appState.settings.ownKeyFingerprint) {
                        Text("Choose a key").tag("")
                        ForEach(appState.secretKeys) { key in
                            Text(key.displayName).tag(key.fingerprint)
                        }
                    }
                    .disabled(appState.secretKeys.isEmpty)
                }
                Toggle("Sign files when encrypting", isOn: $appState.settings.signWhenEncrypting)
                    .disabled(appState.settings.ownKeyFingerprint.isEmpty)
            } header: {
                Text("Identity")
            }

            Section {
                if appState.settings.vaultPath.isEmpty {
                    Text("No vault folder yet. Notes you create stay encrypted in the folder you choose.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent("Folder") {
                        Text((appState.settings.vaultPath as NSString).abbreviatingWithTildeInPath)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                }
                HStack {
                    Button(appState.settings.vaultPath.isEmpty ? "Choose Vault Folder…" : "Change Folder…") {
                        appState.chooseVaultFolder()
                    }
                    if !appState.settings.vaultPath.isEmpty {
                        Button("Show in Finder") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appState.settings.vaultPath)
                        }
                        Button("Remove Vault Location") {
                            appState.settings.vaultPath = ""
                            appState.persistSettings()
                        }
                    }
                }
                Text("The sidebar lists only file names. Opening a note decrypts it into memory. Locking it, or leaving it, encrypts your changes and clears that text. Nothing decrypted is written to disk. The text view can keep short-lived copies that are freed when the note locks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Notes vault")
            }

            Section {
                Toggle("Overwrite and delete originals after encrypting", isOn: $appState.settings.deleteOriginalAfterEncrypt)
                Stepper(value: $appState.settings.secureDeletePasses, in: 1...3) {
                    Text("Shred passes: \(appState.settings.secureDeletePasses)")
                }
                Text("Each pass overwrites the unlocked file with random data before it is deleted. On APFS that still cannot promise old blocks are gone. Keeping the unlocked file on the memory disk is the stronger choice, because ejecting the disk drops it from RAM.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Deleting plaintext")
            }

            Section {
                Picker("Double-clicking an encrypted file", selection: $appState.settings.defaultOpenMode) {
                    Text("Opens it in BetterGPG").tag(OpenMode.viewer)
                    Text("Opens it in its usual app").tag(OpenMode.externalApp)
                }
                Stepper(value: $appState.settings.memoryLimitMegabytes, in: 32...2048, step: 32) {
                    Text("Keep files in memory up to \(appState.settings.memoryLimitMegabytes) MB")
                }
                Picker("Safety timer", selection: $appState.settings.autoLockMinutes) {
                    Text("Off").tag(0)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("1 hour").tag(60)
                    Text("4 hours").tag(240)
                }
                Toggle("Lock everything when the screen locks or the Mac sleeps", isOn: $appState.settings.lockOnScreenLock)
                Toggle("Hide BetterGPG windows from screenshots and screen sharing", isOn: $appState.settings.hideViewersFromCapture)
                Text("In BetterGPG, text, PDFs, and images are decrypted straight into memory. Larger files, and types that need Quick Look, use a private temporary folder. Closing the window saves text edits back into the encrypted file, then wipes the memory and shreds the folder. Newer versions of macOS may not honor the screenshot setting for every capture tool.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Opening encrypted files")
            }

            Section {
                Toggle("Put unlocked copies on a memory disk", isOn: $appState.settings.useRamDisk)
                Stepper(value: $appState.settings.ramDiskMegabytes, in: 128...4096, step: 128) {
                    Text("Memory disk size: \(appState.settings.ramDiskMegabytes) MB")
                }
                .disabled(!appState.settings.useRamDisk)
                Toggle("Open the file after unlocking", isOn: $appState.settings.openAfterDecrypt)
                Toggle("Lock when the file is closed", isOn: $appState.settings.lockWhenClosed)
                Toggle("Ask before opening in another app", isOn: $appState.settings.confirmBeforeOpen)
                Text("Used when a file opens in its usual app, and for large files in BetterGPG. If the timer runs out while the file is still open, BetterGPG waits until it is closed, then locks it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Unlocked copies on disk")
            }

            Section {
                LabeledContent("Last check") {
                    if let lastSweep = appState.vault.lastSweep {
                        Text(lastSweep, format: .dateTime.hour().minute().second())
                    } else {
                        Text("Not yet")
                    }
                }
                if appState.vault.lastSweepReport.removed > 0 || appState.vault.lastSweepReport.kept > 0 {
                    Text(sweepSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Check Now") {
                    Task { await appState.vault.sweep() }
                }
                Text("At launch, at quit, and every 5 minutes, BetterGPG looks for unlocked copies that no open file owns and shreds them. If a crash left behind a copy you had edited, it is encrypted to “name (recovered).gpg” next to the original first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Cleanup")
            }

            Section {
                HStack(spacing: 10) {
                    Image(systemName: extensionEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(extensionEnabled ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(extensionEnabled ? "Finder extension is on" : "Finder extension is off")
                        Text("Right-click a file in Finder to encrypt it, view it in BetterGPG, or open it in its usual app. The same actions are in Finder’s Services menu.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button(extensionEnabled ? "Manage Extension…" : "Enable Finder Extension…") {
                    FIFinderSyncController.showExtensionManagementInterface()
                }
            } header: {
                Text("Finder")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: appState.settings) { _, _ in
            appState.persistSettings()
        }
        .task(id: appState.settings.gpgBinaryPath) {
            gpgVersion = await appState.gpgVersion()
            appState.gpgAvailable = appState.gpgService.isAvailable()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            extensionEnabled = FIFinderSyncController.isExtensionEnabled
        }
        .sheet(isPresented: $showGenerateKey) {
            GenerateKeySheet()
        }
    }
}
