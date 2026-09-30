import Foundation

/// Metadata read from a GPG file without decrypting it.
struct EncryptionInfo: Equatable, Sendable {
    var recipientKeyIds: [String]
    var signerKeyId: String?
    var isCurrentUserRecipient: Bool
    var isSigned: Bool

    var hasHiddenRecipients: Bool {
        let visible = recipientKeyIds.filter { !$0.isEmpty && $0 != String(repeating: "0", count: $0.count) }
        return visible.isEmpty
    }

    var visibleRecipientKeyIds: [String] {
        recipientKeyIds.filter { keyId in
            let stripped = keyId.trimmingCharacters(in: .whitespaces)
            return !stripped.isEmpty && stripped.contains(where: { $0 != "0" })
        }
    }
}
