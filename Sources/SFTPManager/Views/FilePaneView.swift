import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Internal drag payload. Encoded as plain text so it survives the pasteboard
/// without registering a custom UTI.
enum DragPayload {
    static let prefix = "sftp-manager-v1"

    static func encode(side: PaneSide, paths: [String]) -> String {
        ([prefix, side.rawValue] + paths).joined(separator: "\n")
    }

    static func decode(_ string: String) -> (side: PaneSide, paths: [String])? {
        var lines = string.components(separatedBy: "\n")
        guard lines.count >= 3, lines.removeFirst() == prefix,
              let side = PaneSide(rawValue: lines.removeFirst()) else { return nil }
        let paths = lines.filter { !$0.isEmpty }
        return paths.isEmpty ? nil : (side, paths)
    }
}

struct FilePaneView: View {
    /// Observed directly: `PaneState` publishes its own changes, so reaching it
    /// through `AppModel` would leave the pane stale after a refresh.
    @ObservedObject var pane: PaneState

    @EnvironmentObject private var model: AppModel
    @State private var pathDraft: String = ""
    @State private var editingPath = false
    @State private var isDropTargeted = false
    @FocusState private var listFocused: Bool

    private var side: PaneSide { pane.side }
    private var isRemoteBlocked: Bool { side == .remote && !model.status.isConnected }
    /// The pane ⌘R and other pane-agnostic commands currently target.
    private var isActive: Bool { model.activePane == side }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ColumnHeader(pane: pane)
            Divider()
            content
                // Right-clicking empty space acts on the folder being shown.
                // Rows carry their own menu, which takes precedence there.
                .contextMenu { backgroundMenu }
            Divider()
            footer
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            // Doubles as the drop target ring and the "this pane has focus"
            // marker, so the two never fight over the same border.
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.accentColor.opacity(isDropTargeted ? 1 : 0.5),
                              lineWidth: isDropTargeted ? 3 : (isActive ? 2 : 0))
                .allowsHitTesting(false)
        }
        // Clicking anywhere in the pane makes it the target of ⌘R. Simultaneous
        // so it never swallows row selection, buttons or the path field.
        .simultaneousGesture(TapGesture().onEnded { model.activate(side) })
        .onDrop(of: [.text, .fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .onAppear { pathDraft = pane.path }
        .onChange(of: pane.path) { _, newValue in pathDraft = newValue }
        .onChange(of: listFocused) { _, focused in if focused { model.activate(side) } }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Label(side.title, systemImage: side == .local ? "desktopcomputer" : "server.rack")
                    .font(.headline)
                    .labelStyle(.titleAndIcon)

                Spacer()

                if pane.isLoading {
                    ProgressView().controlSize(.small).scaleEffect(0.6)
                }

                transferButton
            }

            HStack(spacing: 4) {
                Button { model.goBack(side) } label: { Image(systemName: "chevron.left") }
                    .disabled(!pane.canGoBack)
                    .help(L.back)
                Button { model.goForward(side) } label: { Image(systemName: "chevron.right") }
                    .disabled(!pane.canGoForward)
                    .help(L.forward)
                Button { model.goUp(side) } label: { Image(systemName: "chevron.up") }
                    .disabled(!pane.canGoUp)
                    .help(L.goUp)
                Button { model.goHome(side) } label: { Image(systemName: "house") }
                    .help(L.home)

                TextField(L.path, text: $pathDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit {
                        model.navigate(side, to: pathDraft)
                    }

                Button { Task { await model.refresh(side) } } label: { Image(systemName: "arrow.clockwise") }
                    .help(L.refresh)

                Menu {
                    Toggle(L.showHidden, isOn: Binding(
                        get: { pane.showHidden },
                        set: { pane.showHidden = $0 }
                    ))
                    Divider()
                    Button(L.newFolder) { model.promptNewFolder(side) }
                    Button(L.syncOppositePane) { model.syncPanes(from: side) }
                    if side == .local {
                        Divider()
                        Picker(L.localFileDoubleClick, selection: $model.localDoubleClickAction) {
                            ForEach(LocalDoubleClickAction.allCases) { action in
                                Text(action.label).tag(action)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                TextField(L.filterInFolder, text: Binding(
                    get: { pane.filter },
                    set: { pane.filter = $0 }
                ))
                .textFieldStyle(.plain)
                if !pane.filter.isEmpty {
                    Button { pane.filter = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var transferButton: some View {
        Group {
            if side == .local {
                Button {
                    model.startTransfer(direction: .upload, items: pane.selectedItems)
                } label: {
                    Label(L.upload, systemImage: "arrow.right.circle.fill")
                }
                .disabled(pane.selection.isEmpty || !model.status.isConnected)
                .help(L.uploadHelp)
            } else {
                Button {
                    model.startTransfer(direction: .download, items: pane.selectedItems)
                } label: {
                    Label(L.download, systemImage: "arrow.left.circle.fill")
                }
                .disabled(pane.selection.isEmpty)
                .help(L.downloadHelp)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isRemoteBlocked {
            unavailable(L.notConnected, "bolt.slash", L.notConnectedDetail)
        } else if let error = pane.error {
            unavailable(L.folderUnavailable, "exclamationmark.triangle", error)
        } else {
            ZStack {
                List(selection: Binding(
                    get: { pane.selection },
                    set: { pane.selection = $0 }
                )) {
                    ForEach(pane.visibleItems) { item in
                        FileRow(item: item)
                            .contentShape(Rectangle())
                            // These two gestures replace the List's own click
                            // handling, which row-level gestures/onDrag disable.
                            .simultaneousGesture(TapGesture(count: 1).onEnded {
                                handleClick(item)
                                listFocused = true
                            })
                            .simultaneousGesture(TapGesture(count: 2).onEnded {
                                model.open(item, in: side)
                            })
                            .onDrag { makeDragProvider(for: item) }
                            .contextMenu { contextMenu(for: item) }
                            .tag(item.id)
                    }
                }
                .focused($listFocused)
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .onDeleteCommand { model.promptDelete(side) }
                .onKeyPress(.return) {
                    guard let item = pane.selectedItems.first else { return .ignored }
                    model.open(item, in: side)
                    return .handled
                }

                if pane.visibleItems.isEmpty && !pane.isLoading {
                    unavailable(
                        pane.filter.isEmpty ? L.emptyFolder : L.noMatches,
                        "folder",
                        pane.filter.isEmpty ? L.emptyFolderDetail : L.noMatchesDetail
                    )
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private func unavailable(_ title: String, _ symbol: String, _ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Menu for the pane's empty space — everything here acts on `pane.path`.
    @ViewBuilder
    private var backgroundMenu: some View {
        Button(L.newFolder) { model.promptNewFolder(side) }
        Button(L.refresh) { Task { await model.refresh(side) } }
        Divider()
        if side == .local {
            Button(L.openInFinder) { model.openInFinder(directory: pane.path) }
            Button(L.uploadSelection) {
                model.startTransfer(direction: .upload, items: pane.selectedItems)
            }
            .disabled(pane.selection.isEmpty || !model.status.isConnected)
        } else {
            Button(L.downloadSelection) {
                model.startTransfer(direction: .download, items: pane.selectedItems)
            }
            .disabled(pane.selection.isEmpty)
            Button(L.openTerminalHere) {
                model.runInTerminal("cd \(ShellQuote.singleQuoted(pane.path))")
            }
            .disabled(!model.status.isConnected)
        }
        Button(L.copyFolderPath) { model.copyPath(pane.path) }
        Divider()
        Button(L.goUp) { model.goUp(side) }
            .disabled(!pane.canGoUp)
        Button(L.home) { model.goHome(side) }
        Button(L.syncOppositePane) { model.syncPanes(from: side) }
        Divider()
        Toggle(L.showHidden, isOn: Binding(
            get: { pane.showHidden },
            set: { pane.showHidden = $0 }
        ))
        Button(L.selectAll) { pane.selection = Set(pane.visibleItems.map(\.id)) }
        Button(L.deselectAll) { pane.selection.removeAll() }
            .disabled(pane.selection.isEmpty)
    }

    @ViewBuilder
    private func contextMenu(for item: FileItem) -> some View {
        // Both actions stay listed explicitly, so the double-click preference
        // only decides the default — it never hides the other one.
        if item.isNavigable {
            Button(L.open) { model.open(item, in: side) }
        }
        if side == .local {
            Button(L.upload) {
                model.startTransfer(direction: .upload, items: selectionIncluding(item))
            }
            .disabled(!model.status.isConnected)
            if !item.isNavigable {
                Button(L.openInDefaultApp) { model.openInDefaultApp(item) }
            }
            Button(L.revealInFinder) { model.revealInFinder(item) }
        } else {
            Button(L.download) {
                model.startTransfer(direction: .download, items: selectionIncluding(item))
            }
            if !item.isDirectory {
                Button(L.openInEditor) { model.editRemoteFile(item) }
                    .help(L.openInEditorHelp)
            }
        }
        Divider()
        Button(L.copyPath) { model.copyPath(item) }
        Button(L.renameEllipsis) {
            pane.selection = [item.id]
            model.promptRename(side)
        }
        Button(L.delete, role: .destructive) {
            if !pane.selection.contains(item.id) { pane.selection = [item.id] }
            model.promptDelete(side)
        }
        Divider()
        Button(L.newFolder) { model.promptNewFolder(side) }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(pane.statusText)
            Spacer()
            if side == .remote, case .connected(let name) = model.status {
                Text(name).lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    // MARK: - Interaction

    private func handleClick(_ item: FileItem) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if pane.selection.contains(item.id) {
                pane.selection.remove(item.id)
            } else {
                pane.selection.insert(item.id)
            }
        } else if flags.contains(.shift), let anchor = pane.selection.first {
            let visible = pane.visibleItems.map(\.id)
            if let start = visible.firstIndex(of: anchor), let end = visible.firstIndex(of: item.id) {
                let range = start <= end ? start...end : end...start
                pane.selection.formUnion(visible[range])
            }
        } else {
            pane.selection = [item.id]
        }
    }

    private func selectionIncluding(_ item: FileItem) -> [FileItem] {
        pane.selection.contains(item.id) ? pane.selectedItems : [item]
    }

    private func makeDragProvider(for item: FileItem) -> NSItemProvider {
        let items = selectionIncluding(item)
        let payload = DragPayload.encode(side: side, paths: items.map(\.path))
        let provider = NSItemProvider(object: payload as NSString)
        provider.suggestedName = item.name
        return provider
    }

    // MARK: - Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let destination = pane.path
        let targetSide = side
        Task { @MainActor in
            var paths: [String] = []
            var sourceSide: PaneSide?

            for provider in providers {
                if let text = await provider.loadText(), let decoded = DragPayload.decode(text) {
                    sourceSide = decoded.side
                    paths.append(contentsOf: decoded.paths)
                } else if let url = await provider.loadFileURL() {
                    sourceSide = .local
                    paths.append(url.path)
                }
            }

            guard let sourceSide, sourceSide != targetSide, !paths.isEmpty else { return }
            let direction: TransferDirection = targetSide == .remote ? .upload : .download
            let items = await resolveItems(paths: paths, on: sourceSide)
            guard !items.isEmpty else { return }
            model.startTransfer(direction: direction, items: items, into: destination)
        }
        return true
    }

    /// Turns dropped paths back into `FileItem`s. Entries dragged from the other
    /// pane are already loaded; anything dropped from Finder is stat'ed here.
    private func resolveItems(paths: [String], on sourceSide: PaneSide) async -> [FileItem] {
        let known = model.pane(sourceSide).items
        var result: [FileItem] = []
        for path in paths {
            if let match = known.first(where: { $0.path == path }) {
                result.append(match)
            } else if sourceSide == .local, LocalFileSystem.exists(path) {
                let isDirectory = LocalFileSystem.isDirectory(path)
                result.append(FileItem(
                    path: path,
                    name: PathUtil.lastComponent(of: path),
                    kind: isDirectory ? .directory : .file,
                    size: isDirectory ? 0 : LocalFileSystem.size(of: path),
                    modified: nil,
                    permissions: nil
                ))
            }
        }
        return result
    }
}

// MARK: - Rows

private struct ColumnHeader: View {
    @ObservedObject var pane: PaneState

    var body: some View {
        HStack(spacing: 0) {
            ColumnHeaderButton(pane: pane, key: .name, title: L.columnName, width: nil)
            ColumnHeaderButton(pane: pane, key: .size, title: L.columnSize, width: 78)
            ColumnHeaderButton(pane: pane, key: .modified, title: L.columnModified, width: 130)
            ColumnHeaderButton(pane: pane, key: .owner, title: L.columnOwner, width: 88)
            ColumnHeaderButton(pane: pane, key: .permissions, title: L.columnPermissions, width: 84)
        }
        .font(.caption.weight(.medium))
        // Matches the insets `.listStyle(.inset(alternatesRowBackgrounds:))`
        // applies to the rows, so each heading sits over its own column.
        .padding(.leading, 17)
        .padding(.trailing, 32)
        .padding(.vertical, 2)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// One clickable column heading.
///
/// The frame belongs *inside* the button's label: applied outside it, the button
/// stayed the size of its text and only the characters themselves responded to
/// a click, which is not where people aim.
private struct ColumnHeaderButton: View {
    @ObservedObject var pane: PaneState
    let key: SortKey
    let title: String
    /// Nil means the column takes the remaining width.
    let width: CGFloat?

    @State private var isHovering = false

    private var isActive: Bool { pane.sortKey == key }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 2) {
                Text(title)
                arrow
                Spacer(minLength: 0)
            }
            .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.vertical, 3)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(isHovering ? 0.07 : 0))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(L.sortByColumn(title))
    }

    /// The slot is always reserved so headings don't shift when the sort column
    /// changes.
    private var arrow: some View {
        Image(systemName: pane.ascending ? "chevron.up" : "chevron.down")
            .font(.system(size: 7, weight: .bold))
            .opacity(isActive ? 1 : 0)
    }

    private func toggle() {
        if isActive {
            pane.ascending.toggle()
        } else {
            pane.sortKey = key
            pane.ascending = true
        }
    }
}

private struct FileRow: View {
    let item: FileItem

    private var glyph: FileGlyph.Glyph { FileGlyph.glyph(for: item) }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yy-MM-dd HH:mm"
        return f
    }()

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: glyph.symbol)
                    .foregroundStyle(glyph.tint)
                    .frame(width: 16)
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .opacity(item.isHidden ? 0.55 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.isDirectory ? "—" : ByteFormat.string(item.size))
                .frame(width: 78, alignment: .leading)
                .foregroundStyle(.secondary)

            Text(item.modified.map { Self.dateFormatter.string(from: $0) } ?? "—")
                .frame(width: 130, alignment: .leading)
                .foregroundStyle(.secondary)

            Text(item.owner ?? "—")
                .frame(width: 88, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)

            Text(item.permissionString)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 84, alignment: .leading)
                .foregroundStyle(.tertiary)
        }
        .font(.callout)
        .padding(.vertical, 1)
    }
}

// MARK: - NSItemProvider helpers

private extension NSItemProvider {
    func loadText() async -> String? {
        guard hasItemConformingToTypeIdentifier(UTType.text.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: NSString.self) { object, _ in
                continuation.resume(returning: (object as? NSString) as String?)
            }
        }
    }

    func loadFileURL() async -> URL? {
        guard hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}
