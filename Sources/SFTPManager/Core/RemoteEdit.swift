import Foundation

/// A remote file opened for editing: downloaded to a scratch copy, watched, and
/// uploaded back whenever the editor saves it.
struct RemoteEdit: Identifiable, Equatable {
    enum Status: Equatable {
        case preparing
        case watching
        case uploading
        case failed(String)

        var label: String {
            switch self {
            case .preparing: return L.editPreparing
            case .watching: return L.editWatching
            case .uploading: return L.editUploading
            case .failed(let message): return message
            }
        }
    }

    let id = UUID()
    let remotePath: String
    let localPath: String
    let name: String
    /// Directory holding the scratch copy; removed when editing stops.
    let scratchDirectory: String

    /// What the file looked like at the previous poll, used to detect a save
    /// that has finished being written.
    var lastSeen: FileSignature?
    /// What was last sent to the server.
    var uploaded: FileSignature?
    var uploadCount = 0
    var lastUploadedAt: Date?
    var status: Status = .preparing
    /// Transfer currently carrying this file back to the server.
    var transferID: UUID?

    /// What a poll should do, given what the scratch file looks like right now.
    enum PollAction: Equatable {
        /// Nothing to do — or the file is momentarily absent, which happens
        /// while an editor renames a temporary file over the original.
        case ignore
        /// Remember this signature; the file is still being written.
        case record
        /// The file has stopped changing since the last poll: send it.
        case upload
    }

    func pollAction(current: FileSignature?) -> PollAction {
        guard status == .watching else { return .ignore }
        guard let current else { return .ignore }
        if current == uploaded { return .record }
        return current == lastSeen ? .upload : .record
    }

    static func == (lhs: RemoteEdit, rhs: RemoteEdit) -> Bool {
        lhs.id == rhs.id
            && lhs.status == rhs.status
            && lhs.uploadCount == rhs.uploadCount
            && lhs.lastUploadedAt == rhs.lastUploadedAt
    }
}

/// Modification date plus size — enough to spot a save without hashing.
struct FileSignature: Equatable {
    let modified: Date
    let size: UInt64

    /// Nil when the file is missing, which happens mid-save for editors that
    /// write to a temporary file and rename over the original.
    static func read(_ path: String) -> FileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attributes[.modificationDate] as? Date,
              let size = (attributes[.size] as? NSNumber)?.uint64Value else { return nil }
        return FileSignature(modified: modified, size: size)
    }
}
