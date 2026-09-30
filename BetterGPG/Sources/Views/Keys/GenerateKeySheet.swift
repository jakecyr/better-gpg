import SwiftUI

struct GenerateKeySheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var realName = ""
    @State private var email = ""
    @State private var passphrase = ""
    @State private var confirmPassphrase = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var confirmUnprotected = false

    private var trimmedName: String {
        realName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var emailError: String? {
        let value = trimmedEmail
        guard !value.isEmpty else { return nil }
        if value.contains(where: { $0.isWhitespace || $0 == "<" || $0 == ">" }) {
            return "Enter an email address without spaces."
        }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains(".") else {
            return "Enter an email address, or leave it blank."
        }
        return nil
    }

    private var canGenerate: Bool {
        !trimmedName.isEmpty
            && emailError == nil
            && (passphrase.isEmpty || passphrase == confirmPassphrase)
            && !isGenerating
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Generate a Key")
                .font(.title2.bold())
            Text("This creates a secret key on this Mac. Use it to encrypt files you can open yourself.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("Name", text: $realName)
                .textFieldStyle(.roundedBorder)
            TextField("Email (optional)", text: $email)
                .textFieldStyle(.roundedBorder)
            SecureField("Passphrase (optional)", text: $passphrase)
                .textFieldStyle(.roundedBorder)
            if !passphrase.isEmpty {
                SecureField("Confirm passphrase", text: $confirmPassphrase)
                    .textFieldStyle(.roundedBorder)
            }

            Text(passphrase.isEmpty
                 ? "Leave the passphrase blank to skip it. Anyone who can use this Mac can then open files encrypted to this key."
                 : "GPG asks for this passphrase when you open files encrypted to this key. It is handed to GPG, then cleared from this window.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let emailError {
                Text(emailError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if !passphrase.isEmpty && confirmPassphrase.isEmpty {
                Text("Enter the passphrase again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !passphrase.isEmpty && passphrase != confirmPassphrase {
                Text("The passphrases do not match.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isGenerating)
                Button("Generate") { start() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canGenerate)
            }
        }
        .padding(24)
        .frame(width: 480)
        .overlay {
            if isGenerating {
                ProgressView("Generating key…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial)
            }
        }
        .confirmationDialog(
            "Create this key without a passphrase?",
            isPresented: $confirmUnprotected,
            titleVisibility: .visible
        ) {
            Button("Create Without a Passphrase") {
                Task { await perform() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anyone who can use this Mac will be able to open files encrypted to this key, without being asked for a passphrase.")
        }
        .onDisappear {
            passphrase = ""
            confirmPassphrase = ""
        }
    }

    private func start() {
        guard canGenerate else { return }
        if passphrase.isEmpty {
            confirmUnprotected = true
        } else {
            Task { await perform() }
        }
    }

    private func perform() async {
        isGenerating = true
        errorMessage = nil
        var secret = Data(passphrase.utf8)
        defer {
            if !secret.isEmpty {
                secret.resetBytes(in: 0..<secret.count)
            }
        }
        do {
            try await appState.generateSecretKey(
                realName: trimmedName,
                email: trimmedEmail,
                passphrase: secret.isEmpty ? nil : secret
            )
            passphrase = ""
            confirmPassphrase = ""
            isGenerating = false
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isGenerating = false
        }
    }
}
