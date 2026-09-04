import Foundation
import Citadel
import NIOCore
import Crypto
import Logging

enum SFTPSessionError: LocalizedError {
    case missingSecret
    case unsupportedKeyType(String)
    case keyReadFailed(String)
    case localFileUnavailable(String)
    case notConnected
    case authenticationFailed(hint: String?)

    var errorDescription: String? {
        switch self {
        case .missingSecret:
            return L.errNoPassword
        case .unsupportedKeyType(let type):
            return L.errUnsupportedKey(type)
        case .keyReadFailed(let path):
            return L.errKeyUnreadable(path)
        case .localFileUnavailable(let path):
            return L.errLocalFileUnavailable(path)
        case .notConnected:
            return L.errNotConnected
        case .authenticationFailed(let hint):
            var message = L.errAuthFailed
            if let hint { message += "\n\n\(hint)" }
            return message
        }
    }
}

/// `SFTPFile` is not `Sendable`, but the only members a transfer's task group
/// touches are `read`/`write`, which mutate nothing on the handle and forward to
/// the `Sendable`, event-loop-serialised `SFTPClient`. Citadel tracks in-flight
/// requests by id, so concurrent requests on one handle are supported.
private struct UncheckedFile: @unchecked Sendable {
    let file: SFTPFile

    init(_ file: SFTPFile) { self.file = file }
}

/// One live SSH + SFTP connection. Serialised through an actor because a single
/// Citadel SFTP channel multiplexes requests over one event loop.
actor SFTPSession {
    /// One SFTP read/write per request. 32,000 is the largest payload Citadel
    /// will put in a single packet (swift-nio-ssh issue #99), so a bigger chunk
    /// would just be split and sent serially.
    private static let chunkSize = 32_000

    /// SSH channel window, which is what actually caps download throughput.
    ///
    /// swift-nio-ssh derives a child channel's inbound window from
    /// `maximumPacketSize`, whose default is 128KB — so a server may only send
    /// 128KB per round trip no matter how many reads we pipeline. OpenSSH uses a
    /// 2MB window (64 × 32KB), which is what `scp` gets its speed from; match it.
    private static let sshMaximumPacketSize = 1 << 21

    /// Default number of requests in flight at once.
    ///
    /// Transfers used to send one chunk and wait for its reply, which caps
    /// throughput at `chunkSize / RTT` — about 3 MB/s on a link where `scp`
    /// reaches 33 MB/s. OpenSSH's own sftp client pipelines 64 outstanding
    /// requests; matching that keeps ~2 MB in flight and hides the round trip.
    static let defaultPipelineDepth = 64

    private let client: SSHClient
    private let sftp: SFTPClient
    let homePath: String
    /// Requests in flight per transfer; configurable in Settings.
    private let pipelineDepth: Int

    private init(client: SSHClient, sftp: SFTPClient, homePath: String, pipelineDepth: Int) {
        self.client = client
        self.sftp = sftp
        self.homePath = homePath
        self.pipelineDepth = max(1, pipelineDepth)
    }

    // MARK: - Connecting

    static func connect(
        _ connection: Connection,
        secret: String?,
        knownHostsPath: String = KnownHosts.defaultPath,
        pipelineDepth: Int = defaultPipelineDepth
    ) async throws -> SFTPSession {
        let auth = try makeAuthentication(connection, secret: secret)
        // Host keys are checked against known_hosts during key exchange, which
        // happens before user authentication — so a rejected server never sees
        // the password or key.
        let validator = KnownHostsValidator(host: connection.host, port: connection.port, path: knownHostsPath)
        let client: SSHClient
        do {
            client = try await SSHClient.connect(
                host: connection.host,
                port: connection.port,
                authenticationMethod: auth,
                hostKeyValidator: .custom(validator),
                reconnect: .never,
                protocolOptions: [.maximumPacketSize(Self.sshMaximumPacketSize)]
            )
        } catch {
            if let rejection = validator.rejection { throw rejection }
            throw enrich(error, for: connection)
        }
        // Citadel logs every request at .info; that is far too chatty for a
        // GUI that lists directories on every navigation.
        var logger = Logger(label: "nl.orlandos.citadel.sftp")
        logger.logLevel = .warning
        let sftp = try await client.openSFTP(logger: logger)
        let home = (try? await sftp.getRealPath(atPath: ".")) ?? "/"
        return SFTPSession(client: client, sftp: sftp, homePath: home, pipelineDepth: pipelineDepth)
    }

    /// Turns Citadel's opaque auth failure into something actionable.
    private static func enrich(_ error: Error, for connection: Connection) -> Error {
        guard "\(error)".contains("allAuthenticationOptionsFailed") else { return error }
        var hint: String?
        if connection.authMethod != .password,
           let key = try? String(contentsOfFile: NSString(string: connection.privateKeyPath).expandingTildeInPath, encoding: .utf8),
           (try? SSHKeyDetection.detectPrivateKeyType(from: key)) == .rsa {
            // Citadel signs with the legacy `ssh-rsa` algorithm, which OpenSSH 8.8+
            // rejects by default.
            hint = L.errRSAHint
        }
        return SFTPSessionError.authenticationFailed(hint: hint)
    }

    private static func makeAuthentication(_ connection: Connection, secret: String?) throws -> SSHAuthenticationMethod {
        switch connection.authMethod {
        case .password:
            guard let secret, !secret.isEmpty else { throw SFTPSessionError.missingSecret }
            return .passwordBased(username: connection.username, password: secret)

        case .privateKey, .agentKeyFile:
            let path = NSString(string: connection.privateKeyPath).expandingTildeInPath
            guard let key = try? String(contentsOfFile: path, encoding: .utf8) else {
                throw SFTPSessionError.keyReadFailed(connection.privateKeyPath)
            }
            let passphrase = (secret?.isEmpty == false) ? Data(secret!.utf8) : nil
            let type = try SSHKeyDetection.detectPrivateKeyType(from: key)
            switch type {
            case .ed25519:
                let pk = try Curve25519.Signing.PrivateKey(sshEd25519: key, decryptionKey: passphrase)
                return .ed25519(username: connection.username, privateKey: pk)
            case .rsa:
                let pk = try Insecure.RSA.PrivateKey(sshRsa: key, decryptionKey: passphrase)
                return .rsa(username: connection.username, privateKey: pk)
            default:
                throw SFTPSessionError.unsupportedKeyType(type.description)
            }
        }
    }

    func disconnect() async {
        try? await sftp.close()
        try? await client.close()
    }

    var isActive: Bool { sftp.isActive }

    /// The live SSH connection, boxed so it can leave the actor.
    ///
    /// The shell panel opens a second channel on this same connection rather
    /// than dialing the server again: no re-authentication, no second host-key
    /// check, and it goes away when the connection does.
    struct ClientHandle: @unchecked Sendable {
        let client: SSHClient
    }

    func clientHandle() -> ClientHandle { ClientHandle(client: client) }

    // MARK: - Browsing

    func realPath(_ path: String) async throws -> String {
        try await sftp.getRealPath(atPath: path)
    }

    func list(_ path: String) async throws -> [FileItem] {
        let names = try await sftp.listDirectory(atPath: path)
        var items: [FileItem] = []
        for name in names {
            for component in name.components {
                // Dropped rather than shown: a name with a slash or `..` in it
                // is not a legal directory entry, and joining it onto a local
                // download path would land the file outside the chosen folder.
                guard PathUtil.isSafeComponent(component.filename) else { continue }
                items.append(makeItem(component, in: path))
            }
        }
        return items
    }

    private func makeItem(_ component: SFTPPathComponent, in directory: String) -> FileItem {
        let attrs = component.attributes
        let mode = attrs.permissions ?? 0
        var kind: FileItem.Kind
        switch mode & 0xF000 {
        case 0x4000: kind = .directory
        case 0xA000: kind = .symlink
        case 0x8000: kind = .file
        default:
            // Some servers omit the type bits; fall back to the `ls -l` line.
            switch component.longname.first {
            case "d": kind = .directory
            case "l": kind = .symlink
            case "-": kind = .file
            default: kind = .other
            }
        }
        return FileItem(
            path: PathUtil.join(directory, component.filename),
            name: component.filename,
            kind: kind,
            size: attrs.size ?? 0,
            modified: attrs.accessModificationTime?.modificationTime,
            permissions: attrs.permissions.map { $0 & 0o7777 },
            // The name if the server's `ls -l` line carries one, else the uid.
            owner: PathUtil.owner(fromLongname: component.longname)
                ?? attrs.uidgid.map { String($0.userId) }
        )
    }

    func isDirectory(_ path: String) async -> Bool {
        guard let attrs = try? await sftp.getAttributes(at: path) else { return false }
        if let permissions = attrs.permissions, permissions & 0xF000 != 0 {
            return permissions & 0xF000 == 0x4000
        }
        // Type bits missing — a successful opendir is the reliable fallback.
        return (try? await sftp.listDirectory(atPath: path)) != nil
    }

    func size(of path: String) async -> UInt64 {
        (try? await sftp.getAttributes(at: path))?.size ?? 0
    }

    // MARK: - Mutating

    func makeDirectory(_ path: String) async throws {
        try await sftp.createDirectory(atPath: path)
    }

    func rename(from: String, to: String) async throws {
        try await sftp.rename(at: from, to: to)
    }

    func removeFile(_ path: String) async throws {
        try await sftp.remove(at: path)
    }

    /// Depth-first delete. SFTP has no recursive remove, so we walk it ourselves.
    func removeRecursively(_ path: String) async throws {
        if await isDirectory(path) {
            for child in try await list(path) {
                try Task.checkCancellation()
                try await removeRecursively(child.path)
            }
            try await sftp.rmdir(at: path)
        } else {
            try await sftp.remove(at: path)
        }
    }

    // MARK: - Transfers

    /// Streams a remote file to disk, reporting cumulative bytes written.
    ///
    /// Reads are pipelined: up to `maxOutstandingRequests` are in flight and
    /// results are written as they land, seeking to each chunk's offset because
    /// replies can arrive out of order.
    func download(
        remotePath: String,
        to localPath: String,
        progress: @escaping @Sendable (UInt64) -> Void
    ) async throws {
        let file = try await sftp.openFile(filePath: remotePath, flags: .read)
        let box = UncheckedFile(file)

        let directory = (localPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: localPath, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: localPath) else {
            throw SFTPSessionError.localFileUnavailable(localPath)
        }

        do {
            let size = try? await file.readAttributes().size
            if let size, size > 0 {
                try await pipelinedDownload(box: box, size: size, handle: handle, progress: progress)
            } else {
                // Size unknown (or empty): fall back to reading until EOF.
                try await sequentialDownload(file: file, handle: handle, progress: progress)
            }
        } catch {
            try? handle.close()
            try? await file.close()
            throw error
        }
        try? handle.close()
        try await file.close()
    }

    private func pipelinedDownload(
        box: UncheckedFile,
        size: UInt64,
        handle: FileHandle,
        progress: @escaping @Sendable (UInt64) -> Void
    ) async throws {
        let chunk = UInt64(Self.chunkSize)
        var nextOffset: UInt64 = 0
        var written: UInt64 = 0

        try await withThrowingTaskGroup(of: (UInt64, [UInt8]).self) { group in
            func scheduleNext() -> Bool {
                guard nextOffset < size else { return false }
                let offset = nextOffset
                let length = UInt32(min(chunk, size - offset))
                nextOffset += UInt64(length)
                group.addTask {
                    var buffer = try await box.file.read(from: offset, length: length)
                    return (offset, buffer.readBytes(length: buffer.readableBytes) ?? [])
                }
                return true
            }

            for _ in 0..<pipelineDepth where scheduleNext() {}

            while let (offset, bytes) = try await group.next() {
                try Task.checkCancellation()
                if !bytes.isEmpty {
                    try handle.seek(toOffset: offset)
                    try handle.write(contentsOf: bytes)
                    written += UInt64(bytes.count)
                    progress(written)
                }
                _ = scheduleNext()
            }
        }
    }

    private func sequentialDownload(
        file: SFTPFile,
        handle: FileHandle,
        progress: @escaping @Sendable (UInt64) -> Void
    ) async throws {
        var offset: UInt64 = 0
        while true {
            try Task.checkCancellation()
            var buffer = try await file.read(from: offset, length: UInt32(Self.chunkSize))
            let readable = buffer.readableBytes
            if readable == 0 { break }
            if let bytes = buffer.readBytes(length: readable) {
                try handle.write(contentsOf: bytes)
            }
            offset += UInt64(readable)
            progress(offset)
        }
    }

    /// Streams a local file to the server, reporting cumulative bytes sent.
    ///
    /// The local file is read serially — that part is cheap — while the remote
    /// writes are pipelined the same way downloads are.
    func upload(
        localPath: String,
        to remotePath: String,
        progress: @escaping @Sendable (UInt64) -> Void
    ) async throws {
        guard let handle = FileHandle(forReadingAtPath: localPath) else {
            throw SFTPSessionError.localFileUnavailable(localPath)
        }
        defer { try? handle.close() }

        let file = try await sftp.openFile(
            filePath: remotePath,
            flags: [.write, .create, .truncate]
        )
        let box = UncheckedFile(file)

        do {
            var offset: UInt64 = 0
            var sent: UInt64 = 0
            var reachedEnd = false

            try await withThrowingTaskGroup(of: Int.self) { group in
                func scheduleNext() throws -> Bool {
                    guard !reachedEnd else { return false }
                    guard let chunk = try handle.read(upToCount: Self.chunkSize), !chunk.isEmpty else {
                        reachedEnd = true
                        return false
                    }
                    let at = offset
                    offset += UInt64(chunk.count)
                    group.addTask {
                        try await box.file.write(ByteBuffer(bytes: chunk), at: at)
                        return chunk.count
                    }
                    return true
                }

                for _ in 0..<pipelineDepth where try scheduleNext() {}

                while let count = try await group.next() {
                    try Task.checkCancellation()
                    sent += UInt64(count)
                    progress(sent)
                    _ = try scheduleNext()
                }
            }
        } catch {
            try? await file.close()
            throw error
        }
        try await file.close()
    }

    /// Enumerates a remote directory tree as relative paths, so the transfer
    /// engine can mirror the structure locally.
    func walk(_ root: String) async throws -> [(relativePath: String, isDirectory: Bool, size: UInt64)] {
        var result: [(String, Bool, UInt64)] = []
        var queue: [(String, String)] = [(root, "")]
        while let (absolute, relative) = queue.first {
            queue.removeFirst()
            try Task.checkCancellation()
            for child in try await list(absolute) {
                let childRelative = relative.isEmpty ? child.name : relative + "/" + child.name
                if child.isDirectory {
                    result.append((childRelative, true, 0))
                    queue.append((child.path, childRelative))
                } else {
                    result.append((childRelative, false, child.size))
                }
            }
        }
        return result
    }
}
