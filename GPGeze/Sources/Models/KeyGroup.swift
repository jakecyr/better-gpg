import Foundation

struct KeyGroup: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var keyFingerprints: [String] = []
    var createdAt: Date = Date()

    init(id: UUID = UUID(), name: String, keyFingerprints: [String] = []) {
        self.id = id
        self.name = name
        self.keyFingerprints = keyFingerprints
        self.createdAt = Date()
    }
}
