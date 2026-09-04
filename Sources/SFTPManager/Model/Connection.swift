import Foundation

enum AuthMethod: String, Codable, CaseIterable, Identifiable {
    case password
    case privateKey
    /// Legacy alias for `.privateKey`, kept so older profiles still decode.
    /// Not offered in the picker — see `selectable`.
    case agentKeyFile

    var id: String { rawValue }

    static var selectable: [AuthMethod] { [.password, .privateKey] }

    var label: String {
        switch self {
        case .password: return L.password
        case .privateKey, .agentKeyFile: return L.privateKey
        }
    }

    var usesPrivateKey: Bool { self != .password }
}

/// A saved server profile. Secrets are never stored — not here, not in the
/// Keychain; they are asked for at connect time and kept only in memory.
struct Connection: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = ""
    var host: String = ""
    var port: Int = 22
    var username: String = NSUserName()
    var authMethod: AuthMethod = .password
    /// Path to an OpenSSH private key, used by `.privateKey` / `.agentKeyFile`.
    var privateKeyPath: String = ""
    /// Directory to open on the remote side after connecting. Empty = home.
    var remoteStartPath: String = ""
    /// Directory to open in the local pane when this profile is activated.
    var localStartPath: String = ""

    var displayName: String {
        if !name.isEmpty { return name }
        if host.isEmpty { return L.newConnection }
        return "\(username)@\(host)"
    }

    var subtitle: String {
        guard !host.isEmpty else { return L.notConfigured }
        return port == 22 ? "\(username)@\(host)" : "\(username)@\(host):\(port)"
    }

    /// Declaring `init(from:)` suppresses the memberwise initialiser; every
    /// property already carries a default, so an empty one is enough.
    init() {}

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, host, port, username, authMethod
        case privateKeyPath, remoteStartPath, localStartPath
        /// Pre-1.0 profiles stored a single start path under this name.
        case initialPath
    }

    /// Decoded leniently so a profile written by an older build — or one missing
    /// a field added later — still loads instead of taking the whole file down.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 22
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? NSUserName()
        authMethod = try container.decodeIfPresent(AuthMethod.self, forKey: .authMethod) ?? .password
        privateKeyPath = try container.decodeIfPresent(String.self, forKey: .privateKeyPath) ?? ""
        remoteStartPath = try container.decodeIfPresent(String.self, forKey: .remoteStartPath)
            ?? container.decodeIfPresent(String.self, forKey: .initialPath)
            ?? ""
        localStartPath = try container.decodeIfPresent(String.self, forKey: .localStartPath) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(username, forKey: .username)
        try container.encode(authMethod, forKey: .authMethod)
        try container.encode(privateKeyPath, forKey: .privateKeyPath)
        try container.encode(remoteStartPath, forKey: .remoteStartPath)
        try container.encode(localStartPath, forKey: .localStartPath)
    }
}

/// On-disk store for connection profiles.
@MainActor
final class ConnectionStore {
    private let url: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SFTPManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        url = support.appendingPathComponent("connections.json")
    }

    /// Where the profiles live, surfaced in Settings.
    var fileURL: URL { url }

    func load() -> [Connection] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Connection].self, from: data)) ?? []
    }


    func save(_ connections: [Connection]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(connections) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
