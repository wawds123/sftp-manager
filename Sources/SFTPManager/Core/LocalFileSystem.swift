import Foundation

/// Local-side filesystem operations. All calls are blocking and are expected to
/// run off the main actor (they are invoked from detached tasks).
enum LocalFileSystem {
    static let fm = FileManager.default

    static var home: String { NSHomeDirectory() }

    static func list(_ path: String) throws -> [FileItem] {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let keys: [URLResourceKey] = [
            .nameKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
            .contentModificationDateKey, .isRegularFileKey,
        ]
        let entries = try fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: []
        )
        return entries.map { entry -> FileItem in
            let values = try? entry.resourceValues(forKeys: Set(keys))
            let isSymlink = values?.isSymbolicLink ?? false
            // Resolve symlinks so a link to a directory behaves like a directory.
            let isDirectory: Bool
            if isSymlink {
                var dir: ObjCBool = false
                isDirectory = fm.fileExists(atPath: entry.path, isDirectory: &dir) && dir.boolValue
            } else {
                isDirectory = values?.isDirectory ?? false
            }
            let attrs = try? fm.attributesOfItem(atPath: entry.path)
            let mode = (attrs?[.posixPermissions] as? NSNumber)?.uint32Value
            return FileItem(
                path: entry.path,
                name: entry.lastPathComponent,
                kind: isDirectory ? .directory : (isSymlink ? .symlink : .file),
                size: UInt64(values?.fileSize ?? 0),
                modified: values?.contentModificationDate,
                permissions: mode,
                owner: attrs?[.ownerAccountName] as? String
            )
        }
    }

    static func createDirectory(at path: String) throws {
        try fm.createDirectory(atPath: path, withIntermediateDirectories: false)
    }

    static func remove(at path: String) throws {
        try fm.removeItem(atPath: path)
    }

    static func move(from: String, to: String) throws {
        try fm.moveItem(atPath: from, toPath: to)
    }

    static func isDirectory(_ path: String) -> Bool {
        var dir: ObjCBool = false
        return fm.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue
    }

    static func exists(_ path: String) -> Bool {
        fm.fileExists(atPath: path)
    }

    static func size(of path: String) -> UInt64 {
        let attrs = try? fm.attributesOfItem(atPath: path)
        return (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    /// Appends " 2", " 3", … before the extension until the path is free.
    static func uniquePath(for path: String) -> String {
        guard exists(path) else { return path }
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension
        let base = url.deletingPathExtension().path
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            if !exists(candidate) { return candidate }
            index += 1
        }
    }
}
