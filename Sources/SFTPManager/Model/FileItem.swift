import Foundation

/// A single entry in either pane. Local and remote entries are normalised into
/// this one shape so the pane view doesn't care which side it is rendering.
struct FileItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case directory
        case file
        case symlink
        case other
    }

    /// Full path (POSIX) of the entry on its own side.
    let path: String
    let name: String
    let kind: Kind
    let size: UInt64
    let modified: Date?
    /// POSIX mode bits (permissions only), when known.
    let permissions: UInt32?
    /// Owner's account name. Remote servers report it in the `ls -l` line they
    /// send alongside each entry; nil when that line is missing or unusual.
    let owner: String?

    /// Written out so `owner` can default — the synthesised memberwise init
    /// would force every existing call site to pass it.
    init(
        path: String,
        name: String,
        kind: Kind,
        size: UInt64,
        modified: Date?,
        permissions: UInt32?,
        owner: String? = nil
    ) {
        self.path = path
        self.name = name
        self.kind = kind
        self.size = size
        self.modified = modified
        self.permissions = permissions
        self.owner = owner
    }

    var id: String { path }

    var isDirectory: Bool { kind == .directory }
    /// Symlinks are treated as navigable — the server resolves them for us.
    var isNavigable: Bool { kind == .directory || kind == .symlink }

    var isHidden: Bool { name.hasPrefix(".") }

    var ext: String {
        guard kind == .file else { return "" }
        let dot = name.lastIndex(of: ".")
        guard let dot, dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...]).lowercased()
    }

    var permissionString: String {
        guard let permissions else { return "—" }
        var out = ""
        let bits: [(UInt32, Character)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x"),
        ]
        for (mask, char) in bits {
            out.append(permissions & mask != 0 ? char : "-")
        }
        return out
    }
}

enum PathUtil {
    /// Joins POSIX path components without collapsing a leading root slash.
    static func join(_ base: String, _ component: String) -> String {
        if component.hasPrefix("/") { return normalize(component) }
        if base.hasSuffix("/") { return normalize(base + component) }
        return normalize(base + "/" + component)
    }

    /// Resolves `.`/`..` textually. Remote symlinks are resolved by the server,
    /// so purely lexical normalisation is what we want here.
    static func normalize(_ path: String) -> String {
        let isAbsolute = path.hasPrefix("/")
        var stack: [String] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".":
                continue
            case "..":
                if !stack.isEmpty && stack.last != ".." {
                    stack.removeLast()
                } else if !isAbsolute {
                    stack.append("..")
                }
            default:
                stack.append(String(part))
            }
        }
        let joined = stack.joined(separator: "/")
        if isAbsolute { return "/" + joined }
        return joined.isEmpty ? "." : joined
    }

    /// True for a directory-entry name that is safe to treat as one component.
    ///
    /// A listing's names are whatever the server chose to send. SFTP says they
    /// are single components, but nothing stops a hostile server from answering
    /// `../../../Library/LaunchAgents/x.plist`, which would escape the folder
    /// the user picked once it is joined onto a local download path.
    static func isSafeComponent(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.contains("\0")
    }

    /// Joins an untrusted relative path onto `base`, or nil if the result would
    /// not stay inside it.
    static func containedJoin(_ base: String, _ relative: String) -> String? {
        guard !relative.hasPrefix("/"), !relative.contains("\0") else { return nil }
        let root = normalize(base)
        let candidate = normalize(root + "/" + relative)
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard candidate != root, candidate.hasPrefix(prefix) else { return nil }
        return candidate
    }

    /// Pulls the owner out of the `ls -l` line an SFTP server sends with each
    /// entry: `-rw-r--r--  1 deploy staff 1234 Sep  3 14:00 name`.
    ///
    /// The protocol only guarantees numeric uids, so this line is the one place
    /// a *name* is available. Servers whose line looks different get nil rather
    /// than a wrong guess.
    static func owner(fromLongname longname: String) -> String? {
        let fields = longname.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 8 else { return nil }
        let mode = fields[0]
        guard mode.count == 10, "-dlbcps".contains(mode.first ?? "?") else { return nil }
        guard Int(fields[1]) != nil else { return nil }   // the hard-link count
        let owner = String(fields[2])
        return owner.isEmpty ? nil : owner
    }

    static func parent(of path: String) -> String {
        let normalized = normalize(path)
        guard normalized != "/" else { return "/" }
        guard let slash = normalized.lastIndex(of: "/") else { return "/" }
        if slash == normalized.startIndex { return "/" }
        return String(normalized[normalized.startIndex..<slash])
    }

    static func lastComponent(of path: String) -> String {
        let normalized = normalize(path)
        guard normalized != "/" else { return "/" }
        guard let slash = normalized.lastIndex(of: "/") else { return normalized }
        return String(normalized[normalized.index(after: slash)...])
    }

    /// Breadcrumb segments as (label, absolutePath) pairs.
    static func breadcrumbs(for path: String) -> [(String, String)] {
        let normalized = normalize(path)
        var result: [(String, String)] = [("/", "/")]
        var running = ""
        for part in normalized.split(separator: "/", omittingEmptySubsequences: true) {
            running += "/" + part
            result.append((String(part), running))
        }
        return result
    }
}

enum ByteFormat {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return f
    }()

    static func string(_ bytes: UInt64) -> String {
        formatter.string(fromByteCount: Int64(clamping: bytes))
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return "—" }
        return string(UInt64(bytesPerSecond)) + "/s"
    }
}
