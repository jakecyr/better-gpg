import Foundation

enum GPGError: LocalizedError {
    case notFound(String)
    case commandFailed(String)
    case noRecipients
    case ramDiskFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let path):
            return "GPG was not found at \(path). Install it with `brew install gnupg pinentry-mac`, or choose the binary in Settings."
        case .commandFailed(let message):
            return message
        case .noRecipients:
            return "Choose at least one person or group before encrypting."
        case .ramDiskFailed(let message):
            return message
        }
    }
}

final class GPGService: @unchecked Sendable {
    private let lock = NSLock()
    private var path: String

    var gpgPath: String {
        lock.lock()
        defer { lock.unlock() }
        return path
    }

    init(gpgPath: String) {
        self.path = gpgPath
    }

    func setPath(_ path: String) {
        lock.lock()
        self.path = path
        lock.unlock()
    }

    func isAvailable() -> Bool {
        FileManager.default.isExecutableFile(atPath: gpgPath)
    }

    func versionLine() async -> String? {
        guard let output = try? await run(["--version"]) else { return nil }
        return output.split(separator: "\n").first.map(String.init)
    }

    // MARK: - Keys

    func listPublicKeys() async throws -> [GPGKey] {
        let output = try await run(["--batch", "--with-colons", "--with-fingerprint", "--list-keys"])
        return parseColonFormat(output, isSecret: false)
    }

    func listSecretKeys() async throws -> [GPGKey] {
        let output = try await run(["--batch", "--with-colons", "--with-fingerprint", "--list-secret-keys"])
        return parseColonFormat(output, isSecret: true)
    }

    func importKey(data: Data) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".asc")
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        defer { try? SecureWiper.wipeFile(at: url, passes: 1) }
        _ = try await run(["--batch", "--import", url.path])
    }

    func importKey(armored: String) async throws {
        guard let data = armored.data(using: .utf8) else {
            throw GPGError.commandFailed("That key text could not be read.")
        }
        try await importKey(data: data)
    }

    func receiveKeys(query: String) async throws {
        let compact = query.replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else {
            throw GPGError.commandFailed("Enter an email address or a fingerprint.")
        }
        if compact.allSatisfy(\.isHexDigit), compact.count >= 16 {
            _ = try await run([
                "--batch",
                "--keyserver", "hkps://keys.openpgp.org",
                "--recv-keys", compact
            ])
        } else {
            _ = try await run([
                "--batch",
                "--keyserver", "hkps://keys.openpgp.org",
                "--auto-key-locate", "keyserver,wkd",
                "--locate-keys", query.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        }
    }

    func exportPublicKey(fingerprint: String) async throws -> String {
        try await run(["--armor", "--export", fingerprint])
    }

    /// Creates an Ed25519 secret key and an encryption subkey.
    /// An empty passphrase stores the key with no protection.
    /// The passphrase is written to a private file for GPG, never placed on the command line, then shredded.
    func generateSecretKey(realName: String, email: String, passphrase: Data?) async throws -> String {
        let name = realName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains(where: \.isNewline) else {
            throw GPGError.commandFailed("Enter a name for the new key.")
        }
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if mail.contains(where: \.isNewline) {
            throw GPGError.commandFailed("Enter an email address without a line break, or leave it blank.")
        }
        var secret = passphrase ?? Data()
        defer {
            if !secret.isEmpty {
                secret.resetBytes(in: 0..<secret.count)
            }
        }
        if secret.contains(0x00) || secret.contains(0x0A) || secret.contains(0x0D) {
            throw GPGError.commandFailed("The passphrase cannot contain a line break.")
        }

        var parameters = Data()
        func appendLine(_ text: String) {
            parameters.append(Data(text.utf8))
            parameters.append(0x0A)
        }
        appendLine("Key-Type: eddsa")
        appendLine("Key-Curve: Ed25519")
        appendLine("Key-Usage: sign")
        appendLine("Subkey-Type: ecdh")
        appendLine("Subkey-Curve: Curve25519")
        appendLine("Subkey-Usage: encrypt")
        appendLine("Name-Real: \(name)")
        if !mail.isEmpty {
            appendLine("Name-Email: \(mail)")
        }
        appendLine("Expire-Date: 0")
        if secret.isEmpty {
            appendLine("%no-protection")
        } else {
            parameters.append(Data("Passphrase: ".utf8))
            parameters.append(secret)
            parameters.append(0x0A)
        }
        appendLine("%commit")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergpg-keygen-\(UUID().uuidString)")
        defer {
            if !parameters.isEmpty {
                parameters.resetBytes(in: 0..<parameters.count)
            }
            try? SecureWiper.wipeFile(at: url, passes: 1)
        }

        guard FileManager.default.createFile(
            atPath: url.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw GPGError.commandFailed("Could not prepare a private file for the new key.")
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.write(contentsOf: parameters)
            try handle.close()
        } catch {
            try? handle.close()
            throw GPGError.commandFailed("Could not prepare a private file for the new key.")
        }

        let captured = try await runDetailed(["--batch", "--status-fd", "2", "--generate-key", url.path])
        let combined = captured.stdout + "\n" + captured.stderr
        if let fingerprint = Self.createdFingerprint(in: combined) {
            return fingerprint
        }
        throw GPGError.commandFailed("The key was created, but its fingerprint could not be read. Refresh the key list.")
    }

    func deleteKey(fingerprint: String, isSecret: Bool) async throws {
        if isSecret {
            _ = try await run(["--batch", "--yes", "--delete-secret-and-public-key", fingerprint])
        } else {
            _ = try await run(["--batch", "--yes", "--delete-key", fingerprint])
        }
    }

    // MARK: - Encrypt / decrypt

    func encrypt(
        fileURL: URL,
        recipients: [String],
        outputURL: URL,
        sign: Bool,
        signingKey: String?
    ) async throws {
        var args = try encryptArguments(recipients: recipients, outputURL: outputURL, sign: sign, signingKey: signingKey)
        args.append(fileURL.path)
        _ = try await run(args)
    }

    /// Encrypts bytes piped through stdin, so the plaintext never lands in a file.
    func encrypt(
        data: Data,
        fileName: String,
        recipients: [String],
        outputURL: URL,
        sign: Bool,
        signingKey: String?
    ) async throws {
        var args = try encryptArguments(recipients: recipients, outputURL: outputURL, sign: sign, signingKey: signingKey)
        args += ["--set-filename", fileName]
        _ = try await runRaw(args, input: data)
    }

    func decrypt(fileURL: URL, outputURL: URL) async throws {
        _ = try await run([
            "--yes",
            "--pinentry-mode", "default",
            "--output", outputURL.path,
            "--decrypt", fileURL.path
        ])
    }

    /// Decrypts to stdout and returns the bytes, so the plaintext never lands in a file.
    /// The app reads the ciphertext and pipes it in, so gpg does not have to open the file itself.
    func decryptToData(fileURL: URL) async throws -> Data {
        var ciphertext: Data
        do {
            ciphertext = try Data(contentsOf: fileURL)
        } catch {
            throw GPGError.commandFailed("Couldn't read \(fileURL.lastPathComponent). \(error.localizedDescription)")
        }
        defer {
            if !ciphertext.isEmpty {
                ciphertext.resetBytes(in: 0..<ciphertext.count)
            }
        }
        return try await runRaw([
            "--yes",
            "--pinentry-mode", "default",
            "--output", "-",
            "--decrypt"
        ], input: ciphertext)
    }

    private func encryptArguments(recipients: [String], outputURL: URL, sign: Bool, signingKey: String?) throws -> [String] {
        guard !recipients.isEmpty else { throw GPGError.noRecipients }
        var args = [
            "--batch", "--yes",
            "--trust-model", "always",
            "--output", outputURL.path,
            "--encrypt"
        ]
        if sign, let signingKey, !signingKey.isEmpty {
            args += ["--sign", "--local-user", signingKey]
        }
        for recipient in recipients {
            args += ["--recipient", recipient]
        }
        return args
    }

    func listEncryptionInfo(fileURL: URL) async throws -> (recipientKeyIds: [String], signerKeyId: String?) {
        let ciphertext = try Data(contentsOf: fileURL)
        let output = try await run([
            "--list-packets",
            "--list-only",
            "--pinentry-mode", "error"
        ], input: ciphertext)
        return parseListPacketsOutput(output)
    }

    func hasSecretKey(keyId: String) async -> Bool {
        let trimmed = keyId.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.contains(where: { $0 != "0" }) else { return false }
        let normalized = trimmed.hasPrefix("0x") ? trimmed : "0x\(trimmed)"
        do {
            _ = try await run(["--batch", "--list-secret-keys", normalized])
            return true
        } catch {
            return false
        }
    }

    // MARK: - Parsing

    private func runDetailed(_ args: [String]) async throws -> (stdout: String, stderr: String) {
        let binary = gpgPath
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            throw GPGError.notFound(binary)
        }
        let result = try await Shell.run(executable: binary, arguments: args)
        guard result.status == 0 else {
            throw GPGError.commandFailed(Self.friendlyMessage(result.stderr.isEmpty ? result.stdout : result.stderr))
        }
        return (result.stdout, result.stderr)
    }

    private static func createdFingerprint(in output: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"KEY_CREATED\s+\S+\s+([0-9A-Fa-f]{40})"#),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return String(output[range]).uppercased()
    }

    private func run(_ args: [String], input: Data? = nil) async throws -> String {
        let binary = gpgPath
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            throw GPGError.notFound(binary)
        }
        let result = try await Shell.run(executable: binary, arguments: args, input: input)
        guard result.status == 0 else {
            throw GPGError.commandFailed(Self.friendlyMessage(result.stderr.isEmpty ? result.stdout : result.stderr))
        }
        return result.stdout
    }

    /// Only stderr is used for errors here, because stdout may hold plaintext.
    private func runRaw(_ args: [String], input: Data? = nil) async throws -> Data {
        let binary = gpgPath
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            throw GPGError.notFound(binary)
        }
        var result = try await Shell.runRaw(executable: binary, arguments: args, input: input)
        guard result.status == 0 else {
            if !result.stdout.isEmpty {
                result.stdout.resetBytes(in: 0..<result.stdout.count)
            }
            throw GPGError.commandFailed(Self.friendlyMessage(result.stderrText))
        }
        return result.stdout
    }

    private func parseColonFormat(_ output: String, isSecret: Bool) -> [GPGKey] {
        var keys: [GPGKey] = []
        var fingerprint = ""
        var keyId = ""
        var name = ""
        var email = ""
        var createdDate: Date?
        var expiresDate: Date?
        var keyBits = 0
        var algorithm = ""
        var inEntry = false

        func flush() {
            guard inEntry, !fingerprint.isEmpty else { return }
            keys.append(GPGKey(
                id: fingerprint,
                name: name,
                email: email,
                fingerprint: fingerprint,
                keyId: keyId,
                isSecret: isSecret,
                createdDate: createdDate,
                expiresDate: expiresDate,
                keyBits: keyBits,
                algorithm: algorithm
            ))
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let fields = line.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 2 else { continue }
            switch fields[0] {
            case "pub", "sec":
                flush()
                fingerprint = ""
                keyId = fields.count > 4 ? fields[4] : ""
                name = ""
                email = ""
                createdDate = fields.count > 5 ? parseTimestamp(fields[5]) : nil
                expiresDate = fields.count > 6 && !fields[6].isEmpty ? parseTimestamp(fields[6]) : nil
                keyBits = fields.count > 2 ? Int(fields[2]) ?? 0 : 0
                algorithm = fields.count > 3 ? Self.algorithmName(fields[3]) : ""
                inEntry = true
            case "fpr":
                if fingerprint.isEmpty {
                    fingerprint = fields.count > 9 ? fields[9] : ""
                }
            case "uid":
                let uid = fields.count > 9 ? fields[9] : ""
                let (parsedName, parsedEmail) = splitUID(uid)
                if name.isEmpty { name = parsedName }
                if email.isEmpty { email = parsedEmail }
            default:
                break
            }
        }
        flush()
        return keys
    }

    private func splitUID(_ uid: String) -> (String, String) {
        guard let start = uid.firstIndex(of: "<"),
              let end = uid.lastIndex(of: ">"),
              start < end else {
            return (uid, "")
        }
        let name = String(uid[uid.startIndex..<start]).trimmingCharacters(in: .whitespaces)
        let email = String(uid[uid.index(after: start)..<end])
        return (name, email)
    }

    private func parseTimestamp(_ value: String) -> Date? {
        guard let timestamp = TimeInterval(value), timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func parseListPacketsOutput(_ output: String) -> (recipientKeyIds: [String], signerKeyId: String?) {
        var recipientKeyIds: [String] = []
        var signerKeyId: String?

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(":pubkey enc packet:") {
                if let keyId = extractKeyId(from: String(trimmed)) {
                    recipientKeyIds.append(keyId)
                }
            } else if trimmed.hasPrefix(":signature packet:") || trimmed.hasPrefix(":onepass_sig packet:") {
                if signerKeyId == nil, let keyId = extractKeyId(from: String(trimmed)) {
                    signerKeyId = keyId
                }
            }
        }
        return (recipientKeyIds, signerKeyId)
    }

    private func extractKeyId(from line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"keyid\s+([0-9A-Fa-f]{8,16})"#),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[range])
    }

    private static func algorithmName(_ code: String) -> String {
        switch code {
        case "1": return "RSA"
        case "16": return "Elgamal"
        case "17": return "DSA"
        case "18": return "ECDH"
        case "19": return "ECDSA"
        case "22": return "EdDSA"
        default: return code.isEmpty ? "" : "algo \(code)"
        }
    }

    private static func friendlyMessage(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        if lower.contains("bad passphrase") || lower.contains("bad session key") {
            return "The passphrase was not accepted, or this file was not encrypted for one of your keys."
        }
        if lower.contains("cancelled") || lower.contains("canceled") {
            return "Passphrase entry was cancelled."
        }
        if lower.contains("inappropriate ioctl")
            || lower.contains("no pinentry")
            || lower.contains("problem with the agent") {
            return "GPG could not open a passphrase window. Install it with `brew install pinentry-mac`, then try again."
        }
        if lower.contains("no secret key") {
            return "None of your secret keys can decrypt this file."
        }
        if lower.contains("operation not permitted") || lower.contains("permission denied") {
            return "BetterGPG could not read this file. Choose the vault folder again in Settings, then try the note."
        }
        if lower.contains("unusable public key") {
            return "One of the recipient keys is expired or cannot encrypt. Remove it from the group, or import a current key."
        }
        if lower.contains("no public key") {
            return "A recipient key is not in your keyring."
        }
        return text.isEmpty ? "GPG could not complete that request." : text
    }
}
