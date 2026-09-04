import Foundation

enum PaneSide: String {
    case local
    case remote

    var title: String { self == .local ? L.local : L.remote }
}

/// Which of the two stacked panels the bottom area is showing.
enum BottomTab: String, CaseIterable, Identifiable {
    case transfers, terminal

    var id: String { rawValue }

    var label: String { self == .transfers ? L.transfers : L.terminal }
    var symbol: String { self == .transfers ? "arrow.up.arrow.down" : "terminal" }
}

enum SortKey: String, CaseIterable, Identifiable {
    case name, size, modified, kind, owner, permissions

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: return L.columnName
        case .size: return L.columnSize
        case .modified: return L.columnModified
        case .kind: return L.columnKind
        case .owner: return L.columnOwner
        case .permissions: return L.columnPermissions
        }
    }
}

/// Everything one pane owns: where it is, what it shows, and how it is sorted.
@MainActor
final class PaneState: ObservableObject {
    let side: PaneSide

    @Published var path: String = "/"
    @Published private(set) var items: [FileItem] = []
    @Published var selection: Set<String> = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var filter: String = ""
    @Published var sortKey: SortKey = .name
    @Published var ascending = true
    @Published var showHidden = false

    private var back: [String] = []
    private var forward: [String] = []

    init(side: PaneSide) {
        self.side = side
    }

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }
    var canGoUp: Bool { path != "/" && !path.isEmpty }

    func setItems(_ newItems: [FileItem]) {
        items = newItems
        // Drop selections that no longer exist after a refresh.
        let ids = Set(newItems.map(\.id))
        selection = selection.intersection(ids)
    }

    /// Records history. `record: false` is used by back/forward themselves.
    func setPath(_ newPath: String, record: Bool = true) {
        let normalized = PathUtil.normalize(newPath)
        guard normalized != path else { return }
        if record {
            back.append(path)
            forward.removeAll()
        }
        path = normalized
        selection.removeAll()
        filter = ""
    }

    func popBack() -> String? {
        guard let previous = back.popLast() else { return nil }
        forward.append(path)
        return previous
    }

    func popForward() -> String? {
        guard let next = forward.popLast() else { return nil }
        back.append(path)
        return next
    }

    func resetHistory() {
        back.removeAll()
        forward.removeAll()
    }

    var visibleItems: [FileItem] {
        var result = items
        if !showHidden {
            result = result.filter { !$0.isHidden }
        }
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter { $0.name.lowercased().contains(query) }
        }
        let direction = ascending ? 1 : -1
        result.sort { lhs, rhs in
            // Folders always lead, regardless of the sort direction.
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            let order: ComparisonResult
            switch sortKey {
            case .name:
                order = lhs.name.localizedStandardCompare(rhs.name)
            case .size:
                order = lhs.size == rhs.size ? .orderedSame : (lhs.size < rhs.size ? .orderedAscending : .orderedDescending)
            case .modified:
                let l = lhs.modified ?? .distantPast
                let r = rhs.modified ?? .distantPast
                order = l == r ? .orderedSame : (l < r ? .orderedAscending : .orderedDescending)
            case .kind:
                order = lhs.ext.localizedStandardCompare(rhs.ext)
            case .owner:
                // Unknown owners sort together at the start.
                order = (lhs.owner ?? "").localizedStandardCompare(rhs.owner ?? "")
            case .permissions:
                // Entries with unknown permissions sort together at the start.
                let l = lhs.permissions ?? 0
                let r = rhs.permissions ?? 0
                order = l == r ? .orderedSame : (l < r ? .orderedAscending : .orderedDescending)
            }
            if order == .orderedSame {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return direction == 1 ? order == .orderedAscending : order == .orderedDescending
        }
        return result
    }

    var selectedItems: [FileItem] {
        items.filter { selection.contains($0.id) }
    }

    var statusText: String {
        let visible = visibleItems
        let folders = visible.filter(\.isDirectory).count
        let files = visible.count - folders
        var parts: [String] = []
        if folders > 0 { parts.append(L.folderCount(folders)) }
        parts.append(L.fileCount(files))
        if !selection.isEmpty {
            let bytes = selectedItems.reduce(UInt64(0)) { $0 + $1.size }
            parts.append(L.selectionCount(selection.count, ByteFormat.string(bytes)))
        }
        return parts.joined(separator: " · ")
    }
}
