import Foundation

struct AppSettings: Codable, Sendable {
    var includeOwnKey: Bool = false
    var ownKeyFingerprint: String = ""
    var gpgBinaryPath: String = ""
    var outputSameDirectory: Bool = true
    var deleteOriginalAfterEncrypt: Bool = false
    var signWhenEncrypting: Bool = false

    static let defaults: AppSettings = {
        let paths = ["/opt/homebrew/bin/gpg", "/usr/local/bin/gpg", "/usr/bin/gpg"]
        let found = paths.first { FileManager.default.fileExists(atPath: $0) } ?? "/usr/local/bin/gpg"
        var s = AppSettings()
        s.gpgBinaryPath = found
        return s
    }()

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: "appSettings"),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .defaults
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "appSettings")
        }
    }
}
