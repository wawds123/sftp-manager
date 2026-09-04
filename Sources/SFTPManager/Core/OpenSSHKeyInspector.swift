import Foundation

/// Reads just enough of an OpenSSH private key to tell whether it is
/// passphrase-protected.
///
/// This lets the app ask for a passphrase only when one is actually needed —
/// Citadel's own decryption failure (`KeyError.missingDecryptionKey`) is an
/// internal type we can't match on, and probing by attempting a connection
/// would burn a round trip.
enum OpenSSHKeyInspector {
    static func isEncrypted(atPath path: String) -> Bool {
        let expanded = NSString(string: path).expandingTildeInPath
        guard let text = try? String(contentsOfFile: expanded, encoding: .utf8) else { return false }
        return isEncrypted(text)
    }

    static func isEncrypted(_ key: String) -> Bool {
        // Classic PEM keys (`-----BEGIN RSA PRIVATE KEY-----`) say so in a header.
        if key.contains("Proc-Type: 4,ENCRYPTED") { return true }

        guard let data = base64Body(of: key) else { return false }

        // openssh-key-v1\0 | string cipher | string kdfname | ...
        let magic = Array("openssh-key-v1\0".utf8)
        guard data.count > magic.count, Array(data.prefix(magic.count)) == magic else { return false }

        var offset = magic.count
        guard let cipher = readString(data, &offset) else { return false }
        return cipher != "none"
    }

    private static func base64Body(of key: String) -> [UInt8]? {
        let body = key
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.hasPrefix("-----") && !$0.contains(":") }
            .joined()
        guard let data = Data(base64Encoded: body, options: .ignoreUnknownCharacters) else { return nil }
        return Array(data)
    }

    /// Reads a 32-bit big-endian length followed by that many bytes.
    private static func readString(_ data: [UInt8], _ offset: inout Int) -> String? {
        guard offset + 4 <= data.count else { return nil }
        var length = 0
        for byte in data[offset..<(offset + 4)] {
            length = length << 8 | Int(byte)
        }
        offset += 4
        guard length >= 0, offset + length <= data.count else { return nil }
        let bytes = Array(data[offset..<(offset + length)])
        offset += length
        return String(decoding: bytes, as: UTF8.self)
    }
}
