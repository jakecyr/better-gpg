import Foundation

enum GPGError: LocalizedError {
    case notFound(String)
    case commandFailed(String)
    case noRecipients

    var errorDescription: String? {
        switch self {
        case .notFound(let path):
            return "GPG binary not found at \(path). Install GPG via Homebrew (`brew install gnupg`) or GPG Suite, then update the path in Settings."
        case .commandFailed(let msg):
            return msg
        case .noRecipients:
            return "No recipients selected. Add at least one key to a group before encrypting."
        }
    }
}

final class GPGService: Sendable {
    let gpgPath: String

    init(gpgPath: String) {
        self.gpgPath = gpgPath
    }

    func isAvailable() -> Bool {
        FileManager.default.fileExists(atPath: gpgPath)
    }

    // MARK: - Shell runner

    private func run(_ args: [String], input: String? = nil) async throws -> String {
        guard FileManager.default.fileExists(atPath: gpgPath) else {
            throw GPGError.notFound(gpgPath)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: gpgPath)
            process.arguments = args

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            if let input {
                let inPipe = Pipe()
                process.standardInput = inPipe
                if let data = input.data(using: .utf8) {
                    inPipe.fileHandleForWriting.write(data)
                    inPipe.fileHandleForWriting.closeFile()
                }
            }

            process.terminationHandler = { proc in
                let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else {
                    let msg = stderr.isEmpty ? stdout : stderr
                    continuation.resume(throwing: GPGError.commandFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Key listing

    func listPublicKeys() async throws -> [GPGKey] {
        let output = try await run(["--batch", "--with-colons", "--with-fingerprint", "--list-keys"])
        return parseColonFormat(output, isSecret: false)
    }

    func listSecretKeys() async throws -> [GPGKey] {
        let output = try await run(["--batch", "--with-colons", "--with-fingerprint", "--list-secret-keys"])
        return parseColonFormat(output, isSecret: true)
    }

    private func parseColonFormat(_ output: String, isSecret: Bool) -> [GPGKey] {
        var keys: [GPGKey] = []
        var fingerprint = ""
        var keyId = ""
        var name = ""
        var email = ""
        var createdDate: Date?
        var expiresDate: Date?
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
                expiresDate: expiresDate
            ))
        }

        for line in output.components(separatedBy: "\n") {
            let f = line.components(separatedBy: ":")
            guard f.count >= 2 else { continue }
            switch f[0] {
            case "pub", "sec":
                flush()
                fingerprint = ""; keyId = ""; name = ""; email = ""
                createdDate = nil; expiresDate = nil; inEntry = true
                keyId = f.count > 4 ? f[4] : ""
                createdDate = f.count > 5 ? parseTimestamp(f[5]) : nil
                expiresDate = f.count > 6 && !f[6].isEmpty ? parseTimestamp(f[6]) : nil
            case "fpr":
                if fingerprint.isEmpty {
                    fingerprint = f.count > 9 ? f[9] : ""
                }
            case "uid":
                let uid = f.count > 9 ? f[9] : ""
                let (n, e) = splitUID(uid)
                if name.isEmpty { name = n }
                if email.isEmpty { email = e }
            default: break
            }
        }
        flush()
        return keys
    }

    private func splitUID(_ uid: String) -> (String, String) {
        if let start = uid.firstIndex(of: "<"), let end = uid.lastIndex(of: ">"), start < end {
            let n = String(uid[uid.startIndex..<start]).trimmingCharacters(in: .whitespaces)
            let e = String(uid[uid.index(after: start)..<end])
            return (n, e)
        }
        return (uid, "")
    }

    private func parseTimestamp(_ str: String) -> Date? {
        guard let t = TimeInterval(str), t > 0 else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    // MARK: - Import / Export / Delete

    func importKey(armored: String) async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".asc")
        try armored.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        _ = try await run(["--batch", "--import", tmp.path])
    }

    func exportPublicKey(fingerprint: String) async throws -> String {
        return try await run(["--armor", "--export", fingerprint])
    }

    func deleteKey(fingerprint: String, isSecret: Bool) async throws {
        if isSecret {
            _ = try await run(["--batch", "--yes", "--delete-secret-and-public-key", fingerprint])
        } else {
            _ = try await run(["--batch", "--yes", "--delete-key", fingerprint])
        }
    }

    // MARK: - Encrypt / Decrypt

    func encrypt(
        fileURL: URL,
        recipients: [String],
        outputURL: URL,
        sign: Bool = false,
        signingKey: String? = nil
    ) async throws {
        guard !recipients.isEmpty else { throw GPGError.noRecipients }
        var args = ["--batch", "--yes", "--output", outputURL.path, "--encrypt"]
        if sign, let sk = signingKey, !sk.isEmpty {
            args += ["--sign", "--local-user", sk]
        }
        for fp in recipients {
            args += ["--recipient", fp]
        }
        args.append(fileURL.path)
        _ = try await run(args)
    }

    func decrypt(fileURL: URL, outputURL: URL) async throws {
        _ = try await run(["--batch", "--yes", "--output", outputURL.path, "--decrypt", fileURL.path])
    }

    // MARK: - Inspect encrypted file (no decryption)

    /// Lists encryption metadata from a .gpg file without decrypting.
    /// Uses `--list-packets` and `--list-only` to avoid passphrase prompts.
    func listEncryptionInfo(fileURL: URL) async throws -> (recipientKeyIds: [String], signerKeyId: String?) {
        let output = try await run([
            "--list-packets",
            "--list-only",
            "--pinentry-mode", "cancel",
            fileURL.path
        ])
        return parseListPacketsOutput(output)
    }

    /// Returns true if the current user has a secret key that can decrypt the given key ID.
    func hasSecretKey(keyId: String) async -> Bool {
        guard !keyId.isEmpty else { return false }
        let normalized = keyId.hasPrefix("0x") ? keyId : "0x\(keyId)"
        do {
            _ = try await run(["--batch", "--list-secret-keys", normalized])
            return true
        } catch {
            return false
        }
    }

    private func parseListPacketsOutput(_ output: String) -> (recipientKeyIds: [String], signerKeyId: String?) {
        var recipientKeyIds: [String] = []
        var signerKeyId: String?

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(":pubkey enc packet:") {
                if let keyId = extractKeyId(from: trimmed) {
                    recipientKeyIds.append(keyId)
                }
            } else if trimmed.hasPrefix(":signature packet:") || trimmed.hasPrefix(":onepass_sig packet:") {
                if signerKeyId == nil, let keyId = extractKeyId(from: trimmed) {
                    signerKeyId = keyId
                }
            }
        }
        return (recipientKeyIds, signerKeyId)
    }

    private func extractKeyId(from line: String) -> String? {
        // Match "keyid XXXXXXXX" or "keyid XXXXXXXXXXXXXXXX" (8 or 16 hex chars)
        let keyIdPattern = #"keyid\s+([0-9A-Fa-f]{8,16})"#
        guard let regex = try? NSRegularExpression(pattern: keyIdPattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[range])
    }
}
