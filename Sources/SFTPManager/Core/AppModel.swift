import AppKit
import Foundation
import SwiftUI

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting(String)
    case connected(String)
    case failed(String)

    var isConnected: Bool { if case .connected = self { return true }; return false }
    var isBusy: Bool { if case .connecting = self { return true }; return false }
}

@MainActor
final class AppModel: ObservableObject {
    // MARK: Panes
    let local = PaneState(side: .local)
    let remote = PaneState(side: .remote)
    /// The pane the user last clicked into. Pane-agnostic commands (⌘R and
    /// friends) act on this one, so it is also shown in the UI.
    @Published var activePane: PaneSide = .local

    // MARK: Connections
    @Published var connections: [Connection] = []
    @Published var selectedConnectionID: UUID?
    @Published var status: ConnectionStatus = .disconnected
    @Published private(set) var activeConnectionID: UUID?

    // MARK: Transfers
    @Published var transfers: [TransferItem] = []
    /// Height the user dragged the queue to; nil means "size to contents".
    ///
    /// Deliberately not persisted in a `didSet` — that fired on every frame of
    /// the drag and wrote to disk each time.
    @Published var transferPanelHeight: CGFloat?

    // MARK: Preferences (see Preferences.swift)
    /// Kept in step with `Lang.current`, which is what `t(_:_:)` actually reads.
    /// Views pick the change up because the scene is keyed on this value.
    @Published var language: AppLanguage = .korean {
        didSet { Lang.current = language; savePreferences() }
    }
    @Published var theme: AppTheme = .system {
        didSet { applyTheme(); savePreferences() }
    }
    @Published var conflictPolicy: ConflictPolicy = .ask {
        didSet { savePreferences() }
    }
    @Published var localDoubleClickAction: LocalDoubleClickAction = .upload {
        didSet { savePreferences() }
    }
    @Published var showHiddenByDefault = false {
        didSet { applyListDefaults(); savePreferences() }
    }
    @Published var defaultSortKey: SortKey = .name {
        didSet { applyListDefaults(); savePreferences() }
    }
    @Published var defaultSortAscending = true {
        didSet { applyListDefaults(); savePreferences() }
    }
    @Published var notifyOnTransferFinish = false {
        didSet { savePreferences() }
    }
    /// How many SFTP requests may be in flight per transfer.
    @Published var pipelineDepth = 64 {
        didSet { savePreferences() }
    }
    /// Seconds between checks of a file opened for editing.
    @Published var editPollInterval: Double = 1.0 {
        didSet { restartEditWatcher(); savePreferences() }
    }
    /// Whether the queue starts out expanded. The panel itself is transient
    /// state; this is the preference behind it.
    @Published var showTransfersAtLaunch = true {
        didSet { savePreferences() }
    }
    /// Font choices. Views read them through `Style`, which is not observable,
    /// so the scene is keyed on `uiIdentity`.
    @Published var uiFontFamily: String? {
        didSet { applyFonts(); savePreferences() }
    }
    @Published var uiFontSizeDelta: Double = 0 {
        didSet { applyFonts(); savePreferences() }
    }
    @Published var terminalFontFamily: String? {
        didSet { applyFonts(); savePreferences() }
    }
    @Published var terminalFontSize: Double = FontPreferences.standard.terminalSize {
        didSet { applyFonts(); savePreferences() }
    }

    /// Everything a view would have to be rebuilt for: the strings it draws and
    /// the interface font it draws them in. The terminal font is deliberately
    /// absent — it is pushed to the live shell instead of rebuilding the tree.
    var uiIdentity: String {
        "\(language.rawValue)|\(uiFontFamily ?? "-")|\(uiFontSizeDelta)"
    }

    @Published var showBottomPanel = true
    @Published var bottomTab: BottomTab = .transfers

    // MARK: Remote shell
    /// Non-nil once a terminal has been opened on the current connection.
    /// Kept after the shell ends so its scrollback survives a tab switch.
    @Published var shell: ShellSession?
    /// True while a channel is being opened, so two clicks make one shell.
    private var isOpeningShell = false

    // MARK: Remote editing
    @Published var edits: [RemoteEdit] = []
    var editWatcher: Timer?

    // MARK: Sheets & alerts
    @Published var editingConnection: Connection?
    @Published var alertMessage: String?
    @Published var conflictRequest: ConflictRequest?
    @Published var promptRequest: PromptRequest?
    @Published var hostKeyRequest: HostKeyRequest?

    var session: SFTPSession?
    let store = ConnectionStore()
    private var connectTask: Task<Void, Never>?
    /// Set while `loadPreferences()` runs. Assigning a preference fires its
    /// `didSet`, which would otherwise write every *other* preference back at
    /// its default before it has been read.
    var isLoadingPreferences = false
    var transferWorker: Task<Void, Never>?
    var runningTransfer: (id: UUID, task: Task<Void, Error>)?

    init() {
        loadPreferences()
        showBottomPanel = showTransfersAtLaunch
        // Earlier builds saved passwords to the Keychain; clear them out once so
        // nothing is left behind now that secrets are only kept in memory.
        if !UserDefaults.standard.bool(forKey: PreferenceKey.purgedKeychain) {
            Keychain.purgeStoredCredentials()
            UserDefaults.standard.set(true, forKey: PreferenceKey.purgedKeychain)
        }
        connections = store.load()
        selectedConnectionID = connections.first?.id
        local.setPath(LocalFileSystem.home, record: false)
        local.resetHistory()
        applyTheme()
        applyListDefaults()
        Task { await refresh(.local) }
    }

    // MARK: - Connection management

    func persistConnections() {
        store.save(connections)
    }

    func newConnection() {
        editingConnection = Connection()
    }

    func editSelectedConnection() {
        guard let id = selectedConnectionID,
              let connection = connections.first(where: { $0.id == id }) else { return }
        editingConnection = connection
    }

    func save(_ connection: Connection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
            selectedConnectionID = connection.id
        }
        persistConnections()
    }

    func deleteConnection(_ id: UUID) {
        guard let index = connections.firstIndex(where: { $0.id == id }) else { return }
        let connection = connections[index]
        if activeConnectionID == connection.id { disconnect() }
        connections.remove(at: index)
        if selectedConnectionID == id { selectedConnectionID = connections.first?.id }
        persistConnections()
    }

    /// Secrets are never persisted, so anything the connection needs is asked
    /// for here and handed straight to the session attempt.
    func connect(_ connection: Connection) {
        switch connection.authMethod {
        case .password:
            promptRequest = PromptRequest(
                title: L.passwordPromptTitle(connection.displayName),
                message: "\(connection.username)@\(connection.host):\(connection.port)\n\n" + L.passwordPromptMessage,
                placeholder: L.password,
                initialValue: "",
                confirmTitle: L.connect,
                isSecret: true
            ) { [weak self] secret in
                self?.performConnect(connection, secret: secret)
            }

        case .privateKey, .agentKeyFile:
            // Only encrypted keys need a passphrase; plain ones connect straight away.
            guard OpenSSHKeyInspector.isEncrypted(atPath: connection.privateKeyPath) else {
                performConnect(connection, secret: nil)
                return
            }
            promptRequest = PromptRequest(
                title: L.passphrasePromptTitle,
                message: "\(connection.privateKeyPath)\n\n" + L.passphrasePromptMessage,
                placeholder: L.passphrase,
                initialValue: "",
                confirmTitle: L.connect,
                isSecret: true
            ) { [weak self] secret in
                self?.performConnect(connection, secret: secret)
            }
        }
    }

    private func performConnect(_ connection: Connection, secret: String?) {
        connectTask?.cancel()
        disconnect()
        status = .connecting(connection.displayName)
        let depth = pipelineDepth
        connectTask = Task { [weak self] in
            do {
                let session = try await SFTPSession.connect(
                    connection,
                    secret: secret,
                    pipelineDepth: depth
                )
                guard let self, !Task.isCancelled else {
                    await session.disconnect()
                    return
                }
                self.session = session
                self.activeConnectionID = connection.id
                self.status = .connected(connection.displayName)
                let start = connection.remoteStartPath.trimmingCharacters(in: .whitespaces)
                let home = session.homePath
                self.remote.setPath(start.isEmpty ? home : start, record: false)
                self.remote.resetHistory()
                if !connection.localStartPath.isEmpty {
                    self.local.setPath(connection.localStartPath)
                    await self.refresh(.local)
                }
                await self.refresh(.remote)
                // Left on the terminal tab from a previous session: open the
                // shell now rather than sitting on the placeholder.
                if self.bottomTab == .terminal {
                    self.openTerminal()
                }
            } catch let hostKey as HostKeyError {
                guard let self, !Task.isCancelled else { return }
                self.status = .failed(Self.describe(hostKey))
                // Nothing was sent to the server: the key is checked during key
                // exchange, before authentication.
                self.hostKeyRequest = HostKeyRequest(error: hostKey) { [weak self] in
                    self?.trustHostKey(hostKey, connection: connection, secret: secret)
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.status = .failed(Self.describe(error))
                self.alertMessage = L.connectFailedMessage(connection.displayName, Self.describe(error))
            }
        }
    }

    /// Records the server's key in `~/.ssh/known_hosts`, then retries. Only
    /// reached after the user confirmed the fingerprint.
    private func trustHostKey(_ error: HostKeyError, connection: Connection, secret: String?) {
        do {
            if error.kind == .changed {
                try KnownHosts.removeEntries(
                    host: error.host,
                    port: error.port,
                    algorithm: error.algorithm,
                    path: error.knownHostsPath
                )
            }
            try KnownHosts.append(line: error.knownHostsLine, path: error.knownHostsPath)
        } catch {
            alertMessage = L.knownHostsWriteFailed(Self.describe(error))
            return
        }
        performConnect(connection, secret: secret)
    }

    func disconnect() {
        connectTask?.cancel()
        connectTask = nil
        // The shell lives on this connection; it cannot outlive it.
        shell?.close()
        shell = nil
        bottomTab = .transfers
        transferWorker?.cancel()
        transferWorker = nil
        if let session {
            Task { await session.disconnect() }
        }
        session = nil
        activeConnectionID = nil
        status = .disconnected
        remote.setItems([])
        remote.selection.removeAll()
    }

    func requestSession(for id: UUID) {
        guard let connection = connections.first(where: { $0.id == id }) else { return }
        // Already on this server: reconnecting would drop the session and ask
        // for the password again for nothing.
        guard activeConnectionID != id else { return }
        connect(connection)
    }

    /// Marks a server as connected without a network round trip, so
    /// `--snapshot` can render the connected chrome. Never used by the app.
    func previewConnected(_ id: UUID, name: String) {
        activeConnectionID = id
        status = .connected(name)
    }

    /// True when this server is the one the file panes are talking to.
    func isConnected(to id: UUID?) -> Bool {
        guard let id else { return false }
        return activeConnectionID == id && status.isConnected
    }

    // MARK: - Remote shell

    /// Opens the shell panel, starting a session if one isn't already running.
    ///
    /// The shell is a second channel on the connection the file panes use, so
    /// there is nothing to authenticate again.
    func openTerminal(running command: String? = nil) {
        guard status.isConnected, let session else {
            alertMessage = L.openTerminalNeedsConnection
            return
        }
        showBottomPanel = true
        bottomTab = .terminal

        if let shell, !shell.state.isClosed {
            if let command { shell.run(command) }
            return
        }
        // Opening the channel is asynchronous, so a second click that lands
        // before it finishes would start a whole extra shell and orphan one.
        guard !isOpeningShell else { return }
        isOpeningShell = true

        let startPath = remote.path
        Task {
            defer { self.isOpeningShell = false }
            let handle = await session.clientHandle()
            let home = session.homePath
            // The command rides along with the session so it is not dropped
            // while the channel is still opening.
            let shell = ShellSession(handle: handle, home: home, startIn: startPath, then: command)
            shell.onCommandFinished = { [weak self] in
                Task { await self?.refresh(.remote) }
            }
            shell.onDirectoryChanged = { [weak self] path in
                guard let self, self.remote.path != path else { return }
                self.navigate(.remote, to: path)
            }
            // The one being replaced has already ended, but say so anyway: a
            // session that still held a channel would keep it forever.
            self.shell?.close()
            self.shell = shell
        }
    }

    /// Switching to the terminal tab starts the shell, the way clicking the
    /// toolbar button does. Without a connection the tab still opens and its
    /// placeholder explains why there is nothing there.
    func showTerminalTab() {
        showBottomPanel = true
        bottomTab = .terminal
        // A shell that has ended — the user typed `exit`, or the server hung up
        // — stays on screen with its scrollback and a 다시 열기 button. Merely
        // looking at the tab must not open a new channel behind the user's back.
        guard status.isConnected, shell == nil else { return }
        openTerminal()
    }

    func toggleTerminal() {
        if showBottomPanel && bottomTab == .terminal {
            showBottomPanel = false
        } else {
            openTerminal()
        }
    }

    /// Ends the shell without touching the file connection.
    func closeTerminal() {
        shell?.close()
        shell = nil
        if bottomTab == .terminal { bottomTab = .transfers }
    }

    /// Moves the remote pane to wherever the shell says it is.
    func syncRemotePaneToShell() {
        guard let shell, shell.state == .running else { return }
        guard let directory = shell.currentDirectory else {
            alertMessage = L.terminalCwdUnknown
            return
        }
        guard directory != remote.path else { return }
        navigate(.remote, to: directory)
    }

    /// Sends a command to the shell panel, opening it first if needed.
    func runInTerminal(_ command: String) {
        if let shell, shell.state == .running, !shell.isAtPrompt {
            alertMessage = L.terminalBusyWithFullScreen
            return
        }
        openTerminal(running: command)
    }

    // MARK: - Browsing

    func pane(_ side: PaneSide) -> PaneState { side == .local ? local : remote }

    /// Called whenever a pane is clicked or takes keyboard focus.
    func activate(_ side: PaneSide) {
        guard activePane != side else { return }
        activePane = side
    }

    func refreshActivePane() {
        Task { await refresh(activePane) }
    }

    func refreshBothPanes() {
        Task {
            await refresh(.local)
            await refresh(.remote)
        }
    }

    func refresh(_ side: PaneSide) async {
        let pane = pane(side)
        let path = pane.path
        pane.isLoading = true
        pane.error = nil
        defer { pane.isLoading = false }
        do {
            let items: [FileItem]
            switch side {
            case .local:
                items = try await Task.detached(priority: .userInitiated) {
                    try LocalFileSystem.list(path)
                }.value
            case .remote:
                guard let session else {
                    pane.setItems([])
                    return
                }
                items = try await session.list(path)
            }
            guard pane.path == path else { return }  // user navigated away mid-load
            pane.setItems(items)
        } catch {
            pane.setItems([])
            pane.error = Self.describe(error)
        }
    }

    func navigate(_ side: PaneSide, to path: String) {
        let pane = pane(side)
        pane.setPath(path)
        Task { await refresh(side) }
    }

    /// The double-click action: navigate into folders, otherwise transfer or
    /// hand the file to its default app depending on the pane and preference.
    func open(_ item: FileItem, in side: PaneSide) {
        guard !item.isNavigable else {
            navigate(side, to: item.path)
            return
        }
        switch side {
        case .local:
            switch localDoubleClickAction {
            case .upload:
                startTransfer(direction: .upload, items: [item])
            case .openInDefaultApp:
                openInDefaultApp(item)
            }
        case .remote:
            // Remote files have no local representation yet — fetch them first.
            startTransfer(direction: .download, items: [item])
        }
    }

    func openInDefaultApp(_ item: FileItem) {
        NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
    }

    func goUp(_ side: PaneSide) {
        let pane = pane(side)
        guard pane.canGoUp else { return }
        navigate(side, to: PathUtil.parent(of: pane.path))
    }

    func goBack(_ side: PaneSide) {
        let pane = pane(side)
        guard let previous = pane.popBack() else { return }
        pane.setPath(previous, record: false)
        Task { await refresh(side) }
    }

    func goForward(_ side: PaneSide) {
        let pane = pane(side)
        guard let next = pane.popForward() else { return }
        pane.setPath(next, record: false)
        Task { await refresh(side) }
    }

    func goHome(_ side: PaneSide) {
        switch side {
        case .local:
            navigate(.local, to: LocalFileSystem.home)
        case .remote:
            guard let session else { return }
            navigate(.remote, to: session.homePath)
        }
    }

    /// Points the other pane at the same relative folder name, when one exists.
    func syncPanes(from side: PaneSide) {
        let source = pane(side)
        let target = pane(side == .local ? .remote : .local)
        guard side == .local || session != nil else { return }
        let name = PathUtil.lastComponent(of: source.path)
        guard name != "/" else { return }
        navigate(target.side, to: PathUtil.join(target.path, name))
    }

    // MARK: - File operations

    func promptNewFolder(_ side: PaneSide) {
        promptRequest = PromptRequest(
            title: L.newFolderTitle(pane(side).side.title),
            message: pane(side).path,
            placeholder: L.folderName,
            initialValue: L.untitledFolder,
            confirmTitle: L.create
        ) { [weak self] name in
            self?.createDirectory(side, named: name)
        }
    }

    func createDirectory(_ side: PaneSide, named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // A name, not a path: "../x" in the dialog would quietly act somewhere
        // other than the folder on screen.
        guard PathUtil.isSafeComponent(trimmed) else {
            alertMessage = L.slashNotAllowedInFolder
            return
        }
        let target = PathUtil.join(pane(side).path, trimmed)
        Task {
            do {
                switch side {
                case .local:
                    try await Task.detached { try LocalFileSystem.createDirectory(at: target) }.value
                case .remote:
                    guard let session else { return }
                    try await session.makeDirectory(target)
                }
                await refresh(side)
            } catch {
                alertMessage = L.createFolderFailed(Self.describe(error))
            }
        }
    }

    func promptRename(_ side: PaneSide) {
        let pane = pane(side)
        guard let item = pane.selectedItems.first else { return }
        promptRequest = PromptRequest(
            title: L.renameTitle,
            message: item.path,
            placeholder: L.newName,
            initialValue: item.name,
            confirmTitle: L.rename
        ) { [weak self] name in
            self?.rename(side, item: item, to: name)
        }
    }

    func rename(_ side: PaneSide, item: FileItem, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.name else { return }
        guard PathUtil.isSafeComponent(trimmed) else {
            alertMessage = L.slashNotAllowedInName
            return
        }
        let destination = PathUtil.join(PathUtil.parent(of: item.path), trimmed)
        Task {
            do {
                switch side {
                case .local:
                    try await Task.detached { try LocalFileSystem.move(from: item.path, to: destination) }.value
                case .remote:
                    guard let session else { return }
                    try await session.rename(from: item.path, to: destination)
                }
                await refresh(side)
            } catch {
                alertMessage = L.renameFailed(Self.describe(error))
            }
        }
    }

    func promptDelete(_ side: PaneSide) {
        let items = pane(side).selectedItems
        guard !items.isEmpty else { return }
        let names = items.prefix(5).map(\.name).joined(separator: ", ")
        let suffix = items.count > 5 ? L.andMore(items.count - 5) : ""
        promptRequest = PromptRequest(
            title: L.deleteTitle(items.count),
            message: L.deleteMessage(names + suffix),
            placeholder: nil,
            initialValue: "",
            confirmTitle: L.delete,
            destructive: true
        ) { [weak self] _ in
            self?.delete(side, items: items)
        }
    }

    func delete(_ side: PaneSide, items: [FileItem]) {
        Task {
            do {
                for item in items {
                    switch side {
                    case .local:
                        let path = item.path
                        try await Task.detached { try LocalFileSystem.remove(at: path) }.value
                    case .remote:
                        guard let session else { return }
                        try await session.removeRecursively(item.path)
                    }
                }
                await refresh(side)
            } catch {
                alertMessage = L.deleteFailed(Self.describe(error))
                await refresh(side)
            }
        }
    }

    /// Called when a resize drag finishes, not while it is in progress.
    func persistPanelHeight() {
        let defaults = UserDefaults.standard
        if let transferPanelHeight {
            defaults.set(Double(transferPanelHeight), forKey: PreferenceKey.panelHeight)
        } else {
            defaults.removeObject(forKey: PreferenceKey.panelHeight)
        }
    }

    func revealInFinder(_ item: FileItem) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
    }

    /// Opens a local directory as a Finder window (as opposed to revealing an
    /// item inside its parent).
    /// Selects a file or folder in Finder, creating it first if it's one of the
    /// app's own directories that hasn't been used yet.
    func revealPathInFinder(_ path: String) {
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            alertMessage = L.pathDoesNotExist(path)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Removes scratch directories left behind by edits that are no longer open.
    @discardableResult
    func cleanUpEditScratch() -> Int {
        let active = Set(edits.map(\.scratchDirectory))
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: editsRoot) else { return 0 }
        var removed = 0
        for name in names {
            let path = editsRoot + "/" + name
            guard !active.contains(path) else { continue }
            if (try? FileManager.default.removeItem(atPath: path)) != nil { removed += 1 }
        }
        return removed
    }

    func openInFinder(directory path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    func copyPath(_ item: FileItem) {
        copyPath(item.path)
    }

    // MARK: - Errors

    nonisolated static func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

/// A one-shot text prompt (or confirmation, when `placeholder` is nil).
struct PromptRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let placeholder: String?
    let initialValue: String
    let confirmTitle: String
    var destructive: Bool = false
    /// Renders the field as a `SecureField` — used for passwords and passphrases.
    var isSecret: Bool = false
    let action: (String) -> Void

    init(
        title: String,
        message: String,
        placeholder: String?,
        initialValue: String,
        confirmTitle: String,
        destructive: Bool = false,
        isSecret: Bool = false,
        action: @escaping (String) -> Void
    ) {
        self.title = title
        self.message = message
        self.placeholder = placeholder
        self.initialValue = initialValue
        self.confirmTitle = confirmTitle
        self.destructive = destructive
        self.isSecret = isSecret
        self.action = action
    }
}
