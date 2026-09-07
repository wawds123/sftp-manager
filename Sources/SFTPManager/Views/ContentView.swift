import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            ConnectionSidebar()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 320)
        } detail: {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    HSplitView {
                        FilePaneView(pane: model.local)
                            .frame(minWidth: 320)
                        FilePaneView(pane: model.remote)
                            .frame(minWidth: 320)
                    }

                    if model.showBottomPanel {
                        ResizableBottomPanel(available: proxy.size.height)
                    }
                }
            }
            .toolbar { toolbarContent }
        }
        .sheet(item: $model.editingConnection) { connection in
            ConnectionEditorView(connection: connection)
                .environmentObject(model)
        }
        .sheet(item: $model.promptRequest) { request in
            PromptSheet(request: request)
        }
        .sheet(item: $model.hostKeyRequest) { request in
            HostKeySheet(request: request)
        }
        .sheet(item: $model.conflictRequest) { request in
            ConflictSheet(request: request)
        }
        .alert(
            L.error,
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            ),
            presenting: model.alertMessage
        ) { _ in
            Button(L.ok, role: .cancel) { model.alertMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            StatusPill(status: model.status)
        }
        ToolbarItemGroup {
            if !model.edits.isEmpty {
                Menu {
                    ForEach(model.edits) { edit in
                        Menu(edit.name) {
                            Text(edit.remotePath)
                            Text(edit.status.label)
                            if edit.uploadCount > 0 {
                                Text(L.uploadCount(edit.uploadCount))
                            }
                            Divider()
                            Button(L.openInEditorApp) { model.openEditLocally(edit) }
                            Button(L.revealInFinder) { model.revealEditInFinder(edit) }
                            Button(L.uploadNow) { model.uploadEdit(edit.id) }
                            if case .failed = edit.status {
                                Button(L.resumeWatching) { model.resumeEditing(edit) }
                            }
                            Divider()
                            Button(L.stopEditing, role: .destructive) { model.stopEditing(edit) }
                        }
                    }
                    Divider()
                    Button(L.stopAllEditing, role: .destructive) { model.stopAllEditing() }
                } label: {
                    Label(L.editingCount(model.edits.count), systemImage: "square.and.pencil")
                }
                .help(L.editingHelp)
            }

            Picker(L.conflictPolicyLabel, selection: $model.conflictPolicy) {
                ForEach(ConflictPolicy.allCases) { policy in
                    Text(policy.label).tag(policy)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)
            .help(L.conflictPolicyHelp)

            Button {
                if model.showBottomPanel && model.bottomTab == .transfers {
                    model.showBottomPanel = false
                } else {
                    model.showBottomPanel = true
                    model.bottomTab = .transfers
                }
            } label: {
                Label(L.transfers, systemImage: model.activeTransferCount > 0 ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
            }
            .help(L.transfersHelp)

            Button {
                model.toggleTerminal()
            } label: {
                Label(L.terminal, systemImage: "terminal")
            }
            .disabled(!model.status.isConnected)
            .help(L.terminalHelp)

            if model.status.isConnected {
                Button {
                    model.disconnect()
                } label: {
                    Label(L.disconnect, systemImage: "bolt.slash")
                }
            }
        }
    }
}

struct StatusPill: View {
    let status: ConnectionStatus

    private var color: Color {
        switch status {
        case .connected: return .green
        case .connecting: return .orange
        case .failed: return .red
        case .disconnected: return .secondary
        }
    }

    private var text: String {
        switch status {
        case .disconnected: return L.notConnected
        case .connecting(let name): return L.connecting(name)
        case .connected(let name): return name
        case .failed: return L.connectionFailed
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if status.isBusy {
                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 10, height: 10)
            } else {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(text)
                .font(Style.itemName)
                .lineLimit(1)
        }
        // An actual pill: in a unified toolbar the dot and the name otherwise
        // float loose among the buttons.
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.07)))
    }
}


/// The transfer queue plus its drag handle.
///
/// The height lives here as `@State`, not on `AppModel`: writing the model on
/// every frame of a drag re-rendered `ContentView` — both file panes included —
/// which made the resize stutter. The model is updated once, when the drag ends.
private struct ResizableBottomPanel: View {
    @EnvironmentObject private var model: AppModel

    /// Height of the whole detail area, used to keep room for the file panes.
    let available: CGFloat

    @State private var draggedHeight: CGFloat?
    @State private var isHovering = false
    @State private var isDragging = false

    private var limit: ClosedRange<CGFloat> {
        let floor: CGFloat = model.bottomTab == .terminal ? 160 : 120
        return floor...max(floor, available - 220)
    }

    /// The dragged height, or a size that fits what the panel is showing.
    private var height: CGFloat {
        if let draggedHeight {
            return min(max(draggedHeight, limit.lowerBound), limit.upperBound)
        }
        // A shell needs room for a usable number of rows; the queue only needs
        // room for the transfers it actually has.
        let wanted: CGFloat
        if model.bottomTab == .terminal {
            wanted = 300
        } else {
            let rows = CGFloat(max(model.transfers.count, 1))
            wanted = BottomPanelView.headerHeight + rows * TransferQueueView.rowHeight
        }
        return min(max(wanted, limit.lowerBound), min(340, limit.upperBound))
    }

    var body: some View {
        VStack(spacing: 0) {
            handle
            BottomPanelView()
                .frame(height: height)
        }
        .onAppear { draggedHeight = model.transferPanelHeight }
    }

    private var handle: some View {
        ZStack {
            Divider()
            Capsule()
                .fill(Color.secondary.opacity(isHovering || isDragging ? 0.55 : 0.28))
                .frame(width: 36, height: 4)

            ResizeHandle(
                currentHeight: { height },
                onDrag: { target in
                    isDragging = true
                    draggedHeight = min(max(target, limit.lowerBound), limit.upperBound).rounded()
                },
                onDragEnded: {
                    isDragging = false
                    commit()
                },
                onReset: {
                    draggedHeight = nil
                    commit()
                },
                onHover: { isHovering = $0 }
            )
        }
        .frame(height: 11)
        .frame(maxWidth: .infinity)
        .help(L.resizeHandleHelp)
    }

    private func commit() {
        model.transferPanelHeight = draggedHeight
        model.persistPanelHeight()
    }
}
