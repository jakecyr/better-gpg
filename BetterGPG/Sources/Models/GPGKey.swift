import Foundation

struct GPGKey: Identifiable, Codable, Hashable, Sendable {
    let id: String  // fingerprint
    var name: String
    var email: String
    var fingerprint: String
    var keyId: String
    var isSecret: Bool
    var createdDate: Date?
    var expiresDate: Date?

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty && trimmedEmail.isEmpty { return shortFingerprint }
        if trimmedName.isEmpty { return trimmedEmail }
        if trimmedEmail.isEmpty { return trimmedName }
        return "\(trimmedName) <\(trimmedEmail)>"
    }

    var shortFingerprint: String {
        fingerprint.count >= 16 ? String(fingerprint.suffix(16)) : fingerprint
    }

    var isExpired: Bool {
        guard let expires = expiresDate else { return false }
        return expires < Date()
    }
}
