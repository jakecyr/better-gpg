import Foundation

enum OpenMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case viewer
    case externalApp

    var id: String { rawValue }
}

struct AppSettings: Codable, Equatable, Sendable {
    var includeOwnKey: Bool = true
    var ownKeyFingerprint: String = ""
    var gpgBinaryPath: String = ""
    var deleteOriginalAfterEncrypt: Bool = false
    var signWhenEncrypting: Bool = false
    var secureDeletePasses: Int = 1
    var useRamDisk: Bool = true
    var ramDiskMegabytes: Int = 512
    var lockWhenClosed: Bool = true
    var autoLockMinutes: Int = 15
    var openAfterDecrypt: Bool = true
    var confirmBeforeOpen: Bool = true
    var lastGroupID: UUID?
    var defaultOpenMode: OpenMode = .viewer
    var memoryLimitMegabytes: Int = 256
    var hideViewersFromCapture: Bool = true
    var lockOnScreenLock: Bool = true
    /// Folder of encrypted notes. Empty until the user chooses one.
    var vaultPath: String = ""

    static let candidateGPGPaths = [
        "/opt/homebrew/bin/gpg",
        "/usr/local/bin/gpg",
        "/opt/local/bin/gpg",
        "/usr/bin/gpg"
    ]

    static var defaults: AppSettings {
        var settings = AppSettings()
        settings.gpgBinaryPath = candidateGPGPaths.first {
            FileManager.default.isExecutableFile(atPath: $0)
        } ?? "/opt/homebrew/bin/gpg"
        return settings
    }

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .defaults
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    var resolvedAutoLockInterval: TimeInterval? {
        autoLockMinutes > 0 ? TimeInterval(autoLockMinutes * 60) : nil
    }

    var memoryLimitBytes: Int64 {
        Int64(memoryLimitMegabytes) * 1_048_576
    }

    mutating func clamp() {
        secureDeletePasses = min(3, max(1, secureDeletePasses))
        ramDiskMegabytes = min(4096, max(128, ramDiskMegabytes))
        memoryLimitMegabytes = min(2048, max(32, memoryLimitMegabytes))
    }

    private static let storageKey = "appSettings"

    private enum CodingKeys: String, CodingKey {
        case includeOwnKey
        case ownKeyFingerprint
        case gpgBinaryPath
        case deleteOriginalAfterEncrypt
        case signWhenEncrypting
        case secureDeletePasses
        case useRamDisk
        case ramDiskMegabytes
        case lockWhenClosed
        case autoLockMinutes
        case openAfterDecrypt
        case confirmBeforeOpen
        case lastGroupID
        case defaultOpenMode
        case memoryLimitMegabytes
        case hideViewersFromCapture
        case lockOnScreenLock
        case vaultPath
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        includeOwnKey = try container.decodeIfPresent(Bool.self, forKey: .includeOwnKey) ?? true
        ownKeyFingerprint = try container.decodeIfPresent(String.self, forKey: .ownKeyFingerprint) ?? ""
        gpgBinaryPath = try container.decodeIfPresent(String.self, forKey: .gpgBinaryPath) ?? ""
        deleteOriginalAfterEncrypt = try container.decodeIfPresent(Bool.self, forKey: .deleteOriginalAfterEncrypt) ?? false
        signWhenEncrypting = try container.decodeIfPresent(Bool.self, forKey: .signWhenEncrypting) ?? false
        secureDeletePasses = try container.decodeIfPresent(Int.self, forKey: .secureDeletePasses) ?? 1
        useRamDisk = try container.decodeIfPresent(Bool.self, forKey: .useRamDisk) ?? true
        ramDiskMegabytes = try container.decodeIfPresent(Int.self, forKey: .ramDiskMegabytes) ?? 512
        lockWhenClosed = try container.decodeIfPresent(Bool.self, forKey: .lockWhenClosed) ?? true
        autoLockMinutes = try container.decodeIfPresent(Int.self, forKey: .autoLockMinutes) ?? 15
        openAfterDecrypt = try container.decodeIfPresent(Bool.self, forKey: .openAfterDecrypt) ?? true
        confirmBeforeOpen = try container.decodeIfPresent(Bool.self, forKey: .confirmBeforeOpen) ?? true
        lastGroupID = try container.decodeIfPresent(UUID.self, forKey: .lastGroupID)
        defaultOpenMode = try container.decodeIfPresent(OpenMode.self, forKey: .defaultOpenMode) ?? .viewer
        memoryLimitMegabytes = try container.decodeIfPresent(Int.self, forKey: .memoryLimitMegabytes) ?? 256
        hideViewersFromCapture = try container.decodeIfPresent(Bool.self, forKey: .hideViewersFromCapture) ?? true
        lockOnScreenLock = try container.decodeIfPresent(Bool.self, forKey: .lockOnScreenLock) ?? true
        vaultPath = try container.decodeIfPresent(String.self, forKey: .vaultPath) ?? ""
        if gpgBinaryPath.isEmpty {
            gpgBinaryPath = Self.defaults.gpgBinaryPath
        }
        clamp()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(includeOwnKey, forKey: .includeOwnKey)
        try container.encode(ownKeyFingerprint, forKey: .ownKeyFingerprint)
        try container.encode(gpgBinaryPath, forKey: .gpgBinaryPath)
        try container.encode(deleteOriginalAfterEncrypt, forKey: .deleteOriginalAfterEncrypt)
        try container.encode(signWhenEncrypting, forKey: .signWhenEncrypting)
        try container.encode(secureDeletePasses, forKey: .secureDeletePasses)
        try container.encode(useRamDisk, forKey: .useRamDisk)
        try container.encode(ramDiskMegabytes, forKey: .ramDiskMegabytes)
        try container.encode(lockWhenClosed, forKey: .lockWhenClosed)
        try container.encode(autoLockMinutes, forKey: .autoLockMinutes)
        try container.encode(openAfterDecrypt, forKey: .openAfterDecrypt)
        try container.encode(confirmBeforeOpen, forKey: .confirmBeforeOpen)
        try container.encodeIfPresent(lastGroupID, forKey: .lastGroupID)
        try container.encode(defaultOpenMode, forKey: .defaultOpenMode)
        try container.encode(memoryLimitMegabytes, forKey: .memoryLimitMegabytes)
        try container.encode(hideViewersFromCapture, forKey: .hideViewersFromCapture)
        try container.encode(lockOnScreenLock, forKey: .lockOnScreenLock)
        try container.encode(vaultPath, forKey: .vaultPath)
    }
}
