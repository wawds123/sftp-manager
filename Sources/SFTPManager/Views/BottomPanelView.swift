import SwiftUI
import SwiftTerm

/// The stacked area under the two file panes. Both the transfer queue and the
/// remote shell live here, one at a time, so neither squeezes the file lists.
struct BottomPanelView: View {
    @EnvironmentObject private var model: AppModel

    /// Shared with the resizer so it can size the panel to its contents.
    static let headerHeight: CGFloat = 45

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch model.bottomTab {
            case .transfers:
                TransferQueueView()
            case .terminal:
                TerminalPanel()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Picker("", selection: Binding(
                get: { model.bottomTab },
                // Picking the tab has to start the shell, not just reveal an
                // empty panel.
                set: { tab in
                    if tab == .terminal { model.showTerminalTab() } else { model.bottomTab = tab }
                }
            )) {
                ForEach(BottomTab.allCases) { tab in
                    Label(tab.label, systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            // Exactly one `Spacer` in the whole header. Two would split the
            // slack evenly and let a long shell title push the buttons right;
            // none would leave the tabs floating in the middle.
            switch model.bottomTab {
            case .transfers:
                transferStatus
            case .terminal:
                terminalStatus
            }

            Spacer()

            switch model.bottomTab {
            case .transfers:
                transferActions
            case .terminal:
                terminalActions
            }

            Button {
                model.showBottomPanel = false
            } label: {
                Image(systemName: "chevron.down")
            }
            .help(L.collapsePanel)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var transferStatus: some View {
        if model.activeTransferCount > 0 {
            ProgressView(value: model.overallProgress)
                .frame(width: 140)
            Text(L.remainingItems(model.activeTransferCount))
                .font(Style.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var transferActions: some View {
        Button(L.cancelAll) { model.cancelAllTransfers() }
            .disabled(model.activeTransferCount == 0)
        Button(L.clearFinished) { model.clearFinishedTransfers() }
            .disabled(!model.transfers.contains { $0.state.isFinished })
    }

    @ViewBuilder
    private var terminalStatus: some View {
        if let shell = model.shell {
            TerminalStatus(shell: shell)
        }
    }

    @ViewBuilder
    private var terminalActions: some View {
        if let shell = model.shell {
            TerminalActions(shell: shell)
        }
    }
}

/// Split out so the header re-renders when the shell's title changes.
private struct TerminalStatus: View {
    @ObservedObject var shell: ShellSession

    var body: some View {
        if !shell.title.isEmpty, shell.state == .running {
            // Yields space before anything else, so a deep path truncates
            // instead of shoving the buttons around.
            Text(shell.title)
                // It is a path, so it gets the font paths get.
                .font(Style.rowMono)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: 150, alignment: .leading)
                .layoutPriority(-1)
        }
    }
}

/// Split out so the header re-renders when the shell's state changes.
private struct TerminalActions: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var shell: ShellSession

    var body: some View {
        switch shell.state {
        case .starting:
            Text(L.shellOpening)
                .font(Style.caption)
                .foregroundStyle(.secondary)
        case .running:
            // The two arrows point at whichever half moves, and the halves are
            // literally stacked: the remote pane above, the terminal below.
            Button {
                model.runInTerminal("cd \(ShellQuote.singleQuoted(model.remote.path))")
            } label: {
                Label(L.terminalToPane, systemImage: "arrow.down")
            }
            .help(L.terminalToPaneHelp)
            Button {
                model.syncRemotePaneToShell()
            } label: {
                Label(L.paneToTerminal, systemImage: "arrow.up")
            }
            .help(L.paneToTerminalHelp)
            Button(L.closeSession) { model.closeTerminal() }
        case .closed:
            Text(L.sessionEnded)
                .font(Style.caption)
                .foregroundStyle(.secondary)
            Button(L.reopen) { model.openTerminal() }
                .disabled(!model.status.isConnected)
            Button(L.clearSession) { model.closeTerminal() }
                .help(L.clearSessionHelp)
        }
    }
}

private struct TerminalPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let shell = model.shell {
            // The terminal view reports its own intrinsic size; without this it
            // sits centred at that size instead of filling the panel.
            TerminalHost(session: shell)
                // `updateNSView` cannot swap the view it was handed, so without
                // an identity tied to the session a replacement shell would run
                // behind the previous session's dead screen.
                .id(ObjectIdentifier(shell))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.leading, 8)
                .padding(.vertical, 4)
                // The terminal paints its own (text) background; matching it
                // here keeps the inset from reading as a border.
                .background(Color(nsColor: .textBackgroundColor))
        } else if !model.status.isConnected {
            message(L.notConnected, L.shellNeedsConnectionDetail)
        } else {
            message(L.shellOpening, L.shellOpeningDetail)
        }
    }

    private func message(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(Style.callout)
            Text(detail).font(Style.caption).foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Hands SwiftUI the terminal view the session already owns, so scrollback and
/// the running shell survive tab switches and collapsing the panel.
private struct TerminalHost: NSViewRepresentable {
    let session: ShellSession

    func makeNSView(context: Context) -> TerminalView {
        let view = session.view
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {}
}
