import Foundation
import Crypto
import NIOCore
import NIOSSH

/// Reads and writes OpenSSH's `~/.ssh/known_hosts`.
///
/// The same file `ssh` uses, so a server trusted here is trusted there and vice
/// versa. Entries are only ever appended, except when the user explicitly
/// accepts a changed host key.
enum KnownHosts {
    static var defaultPath: String {
        NSString(string: "~/.ssh/known_hosts").expandingTildeInPath
    }

    /// How OpenSSH writes a host in the file: bare for port 22, bracketed otherwise.
    static func hostPattern(host: String, port: Int) -> String {
        port == 22 ? host : "[\(host)]:\(port)"
    }

    // MARK: - Reading

    struct Entry {
        let hostField: String
        let keyType: String
        let base64Key: String
        /// `@revoked` entries must never be trusted.
        let isRevoked: Bool
        /// `@cert-authority` entries are CA keys, not host keys; we don't use them.
        let isCertAuthority: Bool
        let line: String

        var publicKey: NIOSSHPublicKey? {
            try? NIOSSHPublicKey(openSSHPublicKey: "\(keyType) \(base64Key)")
        }
    }

    static func parse(_ contents: String) -> [Entry] {
        contents.split(separator: "\n", omittingEmptySubsequences: false).compactMap { rawLine in
            let line = String(rawLine)
            var rest = line.trimmingCharacters(in: .whitespaces)
            guard !rest.isEmpty, !rest.hasPrefix("#") else { return nil }

            var revoked = false
            var certAuthority = false
            while rest.hasPrefix("@") {
                let marker = rest.prefix(while: { !$0.isWhitespace })
                if marker == "@revoked" { revoked = true }
                if marker == "@cert-authority" { certAuthority = true }
                rest = String(rest.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            }

            let fields = rest.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count >= 3 else { return nil }
            return Entry(
                hostField: String(fields[0]),
                keyType: String(fields[1]),
                base64Key: String(fields[2]).split(separator: " ").first.map(String.init) ?? String(fields[2]),
                isRevoked: revoked,
                isCertAuthority: certAuthority,
                line: line
            )
        }
    }

    static func entries(path: String = defaultPath) -> [Entry] {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return parse(contents)
    }

    /// Entries whose host field matches this host, ignoring CA entries.
    static func entries(matching host: String, port: Int, in all: [Entry]) -> [Entry] {
        let target = hostPattern(host: host, port: port)
        return all.filter { !$0.isCertAuthority && matches(hostField: $0.hostField, target: target) }
    }

    // MARK: - Host matching

    static func matches(hostField: String, target: String) -> Bool {
        if hostField.hasPrefix("|1|") {
            return matchesHashed(hostField, target: target)
        }
        var matched = false
        for pattern in hostField.split(separator: ",") {
            if pattern.hasPrefix("!") {
                // A negated pattern vetoes the whole line.
                if glob(String(pattern.dropFirst()), target) { return false }
            } else if glob(String(pattern), target) {
                matched = true
            }
        }
        return matched
    }

    /// `|1|<base64 salt>|<base64 HMAC-SHA1(salt, host)>`, OpenSSH's hashed form.
    private static func matchesHashed(_ field: String, target: String) -> Bool {
        let parts = field.split(separator: "|", omittingEmptySubsequences: false)
        // ["", "1", salt, hash] — the leading empty piece comes from the first `|`.
        guard parts.count == 4, parts[1] == "1",
              let salt = Data(base64Encoded: String(parts[2])),
              let expected = Data(base64Encoded: String(parts[3])) else { return false }
        let mac = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(target.utf8),
            using: SymmetricKey(data: salt)
        )
        return Data(mac) == expected
    }

    private static func glob(_ pattern: String, _ candidate: String) -> Bool {
        if !pattern.contains("*") && !pattern.contains("?") {
            return pattern == candidate
        }
        return fnmatch(pattern, candidate, 0) == 0
    }

    // MARK: - Fingerprints

    /// OpenSSH's `SHA256:…` fingerprint of a public key.
    static func fingerprint(of key: NIOSSHPublicKey) -> String {
        fingerprint(ofBlob: blob(of: key))
    }

    static func fingerprint(ofBlob blob: [UInt8]) -> String {
        let digest = SHA256.hash(data: blob)
        let encoded = Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "SHA256:\(encoded)"
    }

    /// The SSH wire encoding of a public key — the same bytes that are base64'd
    /// into a `known_hosts` line.
    static func blob(of key: NIOSSHPublicKey) -> [UInt8] {
        var buffer = ByteBufferAllocator().buffer(capacity: 256)
        key.write(to: &buffer)
        return buffer.readBytes(length: buffer.readableBytes) ?? []
    }

    static func base64(of key: NIOSSHPublicKey) -> String {
        Data(blob(of: key)).base64EncodedString()
    }

    /// The key algorithm name, read back out of the key's own wire encoding.
    static func algorithm(of key: NIOSSHPublicKey) -> String {
        let bytes = blob(of: key)
        guard bytes.count > 4 else { return "" }
        let length = bytes[0..<4].reduce(0) { $0 << 8 | Int($1) }
        guard length > 0, bytes.count >= 4 + length else { return "" }
        return String(decoding: bytes[4..<(4 + length)], as: UTF8.self)
    }

    // MARK: - Writing

    static func line(host: String, port: Int, key: NIOSSHPublicKey) -> String {
        "\(hostPattern(host: host, port: port)) \(algorithm(of: key)) \(base64(of: key))"
    }

    static func append(line: String, path: String = defaultPath) throws {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var contents = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        if !contents.isEmpty && !contents.hasSuffix("\n") { contents += "\n" }
        contents += line + "\n"
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    /// Drops every entry for this host of the given algorithm. Used only when
    /// the user explicitly accepts a changed host key.
    static func removeEntries(host: String, port: Int, algorithm: String, path: String = defaultPath) throws {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let target = hostPattern(host: host, port: port)
        let kept = contents.split(separator: "\n", omittingEmptySubsequences: false).filter { rawLine in
            guard let entry = parse(String(rawLine)).first else { return true }
            guard matches(hostField: entry.hostField, target: target) else { return true }
            return entry.keyType != algorithm
        }
        try kept.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }
}
