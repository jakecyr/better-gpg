import SwiftUI

struct EncryptionInfoPanel: View {
    let fileURL: URL
    let info: EncryptionInfo
    let appState: AppState
    var showDoneButton: Bool = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(fileURL.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("Encryption details")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if showDoneButton {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }

            Divider()

            // Current user status
            HStack(spacing: 12) {
                Image(systemName: info.isCurrentUserRecipient ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(info.isCurrentUserRecipient ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.isCurrentUserRecipient ? "You can decrypt this file" : "Your key is not included")
                        .font(.subheadline.weight(.medium))
                    Text(info.isCurrentUserRecipient
                         ? "One of your secret keys can decrypt this file."
                         : "None of the recipient keys match your keyring. You may need the sender to add your public key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(info.isCurrentUserRecipient ? Color.green.opacity(0.08) : Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            // Signer (who encrypted it)
            if info.isSigned, let signerKeyId = info.signerKeyId {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Signed by", systemImage: "signature")
                        .font(.subheadline.weight(.medium))
                    recipientRow(keyId: signerKeyId, isSigner: true)
                }
            }

            // Recipients (public keys included)
            VStack(alignment: .leading, spacing: 8) {
                Label("Encrypted for \(info.recipientKeyIds.count) recipient\(info.recipientKeyIds.count == 1 ? "" : "s")", systemImage: "key.fill")
                    .font(.subheadline.weight(.medium))
                if info.recipientKeyIds.isEmpty {
                    Text("Hidden recipients (key IDs not visible)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(info.recipientKeyIds, id: \.self) { keyId in
                        recipientRow(keyId: keyId, isSigner: false)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 380, minHeight: 320)
    }

    private func recipientRow(keyId: String, isSigner: Bool) -> some View {
        let key = appState.key(forKeyId: keyId)
        let isOwnKey = appState.secretKeys.contains { $0.fingerprint == key?.fingerprint }
        return HStack(spacing: 10) {
            Image(systemName: "person.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                if let k = key {
                    Text(k.displayName)
                        .font(.callout)
                    Text(k.shortFingerprint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Key ID \(keyId)")
                        .font(.callout)
                    Text("Not in your keyring")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if isOwnKey {
                Text("You")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.2), in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}
