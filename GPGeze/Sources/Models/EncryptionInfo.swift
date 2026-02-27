import Foundation

/// Metadata extracted from a GPG-encrypted file without decrypting it.
struct EncryptionInfo: Sendable {
    /// Key IDs of recipients (from pubkey enc packets; typically 16-char subkey IDs).
    let recipientKeyIds: [String]
    /// Key ID of the signer, if the message is signed.
    let signerKeyId: String?
    /// Whether the current user has a secret key that can decrypt this file.
    let isCurrentUserRecipient: Bool
    /// Whether the message is signed (has a signature packet).
    let isSigned: Bool
}
