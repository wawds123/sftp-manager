import Foundation
import NIOCore
import NIOSSH
import NIOConcurrencyHelpers

/// Why a host key was rejected, with everything the UI needs to ask the user.
struct HostKeyError: LocalizedError {
    enum Kind {
        /// No entry for this host (or none for this key algorithm).
        case unknown
        /// The host is known and presented a different key of the same algorithm.
        case changed
        /// The key is marked `@revoked` in known_hosts.
        case revoked
    }

    let kind: Kind
    let host: String
    let port: Int
    let algorithm: String
    let fingerprint: String
    /// Fingerprints already trusted for this host, for the "it changed" warning.
    let knownFingerprints: [String]
    /// The line to append to known_hosts if the user accepts.
    let knownHostsLine: String
    /// Which known_hosts file this decision applies to.
    let knownHostsPath: String

    var errorDescription: String? {
        switch kind {
        case .unknown:
            return L.hostKeyUnknownMessage(fingerprint)
        case .changed:
            return L.hostKeyChangedMessage(fingerprint)
        case .revoked:
            return L.hostKeyRevokedMessage
        }
    }
}

/// Checks the server's host key against `known_hosts` during key exchange.
///
/// Rejection happens *before* user authentication, so a password or key is never
/// sent to a server the user hasn't trusted. The rejected key is recorded here
/// so the app can show its fingerprint and offer to trust it.
final class KnownHostsValidator: NIOSSHClientServerAuthenticationDelegate {
    private let host: String
    private let port: Int
    private let path: String
    private let entries: [KnownHosts.Entry]
    private let failure = NIOLockedValueBox<HostKeyError?>(nil)

    init(host: String, port: Int, path: String, entries: [KnownHosts.Entry]) {
        self.host = host
        self.port = port
        self.path = path
        self.entries = entries
    }

    convenience init(host: String, port: Int, path: String = KnownHosts.defaultPath) {
        let all = KnownHosts.entries(path: path)
        self.init(host: host, port: port, path: path, entries: KnownHosts.entries(matching: host, port: port, in: all))
    }

    /// Set when validation failed; read after `SSHClient.connect` throws.
    var rejection: HostKeyError? { failure.withLockedValue { $0 } }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let error = check(hostKey)
        if let error {
            failure.withLockedValue { $0 = error }
            validationCompletePromise.fail(error)
        } else {
            validationCompletePromise.succeed(())
        }
    }

    /// Exposed for tests: the decision, without the promise plumbing.
    func check(_ hostKey: NIOSSHPublicKey) -> HostKeyError? {
        let algorithm = KnownHosts.algorithm(of: hostKey)
        let fingerprint = KnownHosts.fingerprint(of: hostKey)

        func makeError(_ kind: HostKeyError.Kind, known: [KnownHosts.Entry]) -> HostKeyError {
            HostKeyError(
                kind: kind,
                host: host,
                port: port,
                algorithm: algorithm,
                fingerprint: fingerprint,
                knownFingerprints: known.compactMap { $0.publicKey.map(KnownHosts.fingerprint(of:)) },
                knownHostsLine: KnownHosts.line(host: host, port: port, key: hostKey),
                knownHostsPath: path
            )
        }

        if entries.contains(where: { $0.isRevoked && $0.publicKey == hostKey }) {
            return makeError(.revoked, known: [])
        }
        if entries.contains(where: { !$0.isRevoked && $0.publicKey == hostKey }) {
            return nil
        }

        // A key of an algorithm we've never recorded for this host is new, not
        // changed — OpenSSH treats that as a first sighting too.
        let sameAlgorithm = entries.filter { !$0.isRevoked && $0.keyType == algorithm }
        return makeError(sameAlgorithm.isEmpty ? .unknown : .changed, known: sameAlgorithm)
    }
}
