import Foundation
import Dispatch

enum TransferDirection {
    case upload
    case download

    var symbol: String { self == .upload ? "arrow.up.circle.fill" : "arrow.down.circle.fill" }
    var label: String { self == .upload ? L.upload : L.download }
}

enum TransferState: Equatable {
    case queued
    case running
    case completed
    case skipped
    case failed(String)
    case cancelled

    var isFinished: Bool {
        switch self {
        case .queued, .running: return false
        default: return true
        }
    }
}

struct TransferItem: Identifiable, Equatable {
    let id = UUID()
    let direction: TransferDirection
    /// Path shown in the queue — relative when part of a folder transfer.
    let displayName: String
    let source: String
    let destination: String
    var total: UInt64
    var transferred: UInt64 = 0
    var state: TransferState = .queued
    var startedAt: Date?
    var finishedAt: Date?

    var fraction: Double {
        guard total > 0 else { return state == .completed ? 1 : 0 }
        return min(1, Double(transferred) / Double(total))
    }

    var throughput: Double {
        guard let startedAt, transferred > 0 else { return 0 }
        let elapsed = (finishedAt ?? Date()).timeIntervalSince(startedAt)
        guard elapsed > 0.05 else { return 0 }
        return Double(transferred) / elapsed
    }

    static func == (lhs: TransferItem, rhs: TransferItem) -> Bool {
        lhs.id == rhs.id
            && lhs.transferred == rhs.transferred
            && lhs.total == rhs.total
            && lhs.state == rhs.state
    }
}

/// What to do when the destination already has a file with the same name.
enum ConflictPolicy: String, CaseIterable, Identifiable {
    /// Stop and ask, once per conflicting name.
    case ask
    case overwrite
    case rename
    case skip

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ask: return L.conflictAsk
        case .overwrite: return L.conflictOverwrite
        case .rename: return L.conflictRename
        case .skip: return L.conflictSkip
        }
    }
}

/// What the user picked in the conflict sheet.
enum ConflictChoice {
    case overwrite
    case rename
    case skip
    /// Abandon the whole batch.
    case cancel
}

/// One "this name is already there" question, and the way back.
struct ConflictRequest: Identifiable {
    let id = UUID()
    let direction: TransferDirection
    /// The entry being transferred.
    let incoming: FileItem
    /// What is already sitting at the destination, when it could be read.
    let existing: FileItem?
    let destination: String
    /// The name `L.conflictRename` would produce.
    let renamedTo: String
    /// How many more conflicts are waiting behind this one.
    let remaining: Int
    let respond: (ConflictChoice, Bool) -> Void

    var name: String { incoming.name }
}

/// What double-clicking a *file* in the local pane does. Folders always open.
/// Defaults to `.upload` so both panes behave the same way — double-clicking a
/// remote file already transfers it.
enum LocalDoubleClickAction: String, CaseIterable, Identifiable {
    case upload
    case openInDefaultApp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .upload: return L.upload
        case .openInDefaultApp: return L.openInDefaultApp
        }
    }
}

/// Coalesces progress callbacks before they hop to the main actor.
///
/// A pipelined transfer reports every 32KB chunk — thousands of times a second
/// on a fast link. Spawning a `Task { @MainActor … }` for each would cost more
/// than the transfer itself, so callers ask this first and drop the update when
/// the previous one is still recent.
final class ProgressThrottle: @unchecked Sendable {
    private let interval: UInt64
    private let lock = NSLock()
    private var lastPublished: UInt64 = 0

    init(minimumInterval: Double = 0.1) {
        interval = UInt64(minimumInterval * 1_000_000_000)
    }

    func shouldPublish() -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        defer { lock.unlock() }
        guard now &- lastPublished >= interval else { return false }
        lastPublished = now
        return true
    }
}
