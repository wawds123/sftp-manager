import Foundation
import Security

/// The app no longer stores connection secrets: passwords and key passphrases
/// are asked for at connect time and kept only for the duration of the attempt.
///
/// This type exists solely to clear credentials written by earlier builds.
enum Keychain {
    private static let service = "com.sftpmanager.credentials"

    /// Deletes every generic-password item this app ever wrote.
    ///
    /// Scoped to our own service name, so nothing else in the user's Keychain is
    /// touched. Returns true when items were actually removed.
    @discardableResult
    static func purgeStoredCredentials() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
