import Foundation

struct GPGKey: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var email: String
    var fingerprint: String
    var keyId: String
    var isSecret: Bool
    var createdDate: Date?
    var expiresDate: Date?
    var keyBits: Int
    var algorithm: String

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty && trimmedEmail.isEmpty { return shortFingerprint }
        if trimmedName.isEmpty { return trimmedEmail }
        if trimmedEmail.isEmpty { return trimmedName }
        return "\(trimmedName) <\(trimmedEmail)>"
    }

    var shortName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty { return trimmedName }
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        if !trimmedEmail.isEmpty { return trimmedEmail }
        return shortFingerprint
    }

    var shortFingerprint: String {
        let tail = fingerprint.count >= 16 ? String(fingerprint.suffix(16)) : fingerprint
        return Self.grouped(tail)
    }

    var formattedFingerprint: String {
        Self.grouped(fingerprint.uppercased())
    }

    var algorithmSummary: String {
        if algorithm.isEmpty { return "" }
        if keyBits > 0 { return "\(algorithm) \(keyBits)" }
        return algorithm
    }

    var isExpired: Bool {
        guard let expires = expiresDate else { return false }
        return expires < Date()
    }

    func matches(_ keyId: String) -> Bool {
        let needle = keyId.uppercased().replacingOccurrences(of: "0X", with: "")
        guard !needle.isEmpty else { return false }
        let fingerprint = fingerprint.uppercased()
        let ownKeyId = self.keyId.uppercased()
        return ownKeyId == needle
            || fingerprint.hasSuffix(needle)
            || (needle.count >= 8 && ownKeyId.hasSuffix(needle))
    }

    private static func grouped(_ value: String) -> String {
        value.uppercased().enumerated().reduce(into: "") { result, item in
            if item.offset > 0, item.offset.isMultiple(of: 4) {
                result.append(" ")
            }
            result.append(item.element)
        }
    }
}
