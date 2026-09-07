import SwiftUI
import AppKit

struct SFTPManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("SFTP Manager") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1020, minHeight: 620)
                // Strings come from `L` and fonts from `Style`, neither of
                // which is observable, so the whole tree is rebuilt when either
                // changes.
                .id(model.uiIdentity)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L.menuAbout) { openWindow(id: "about") }
            }
            CommandGroup(replacing: .newItem) {
                Button(L.menuNewConnection) { model.newConnection() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu(L.menuGo) {
                Button(L.menuLocalParent) { model.goUp(.local) }
                    .keyboardShortcut(.upArrow, modifiers: [.command])
                Button(L.menuRemoteParent) { model.goUp(.remote) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .shift])
                Divider()
                // ⌘R follows the pane the user last clicked into; the title
                // names it so the menu says which one will reload.
                Button(L.menuRefreshActive(model.activePane.title)) { model.refreshActivePane() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button(L.menuRefreshBoth) { model.refreshBothPanes() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandMenu(L.transfers) {
                Button(L.upload) { model.startTransfer(direction: .upload, items: model.local.selectedItems) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command])
                    .disabled(model.local.selection.isEmpty)
                Button(L.download) { model.startTransfer(direction: .download, items: model.remote.selectedItems) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
                    .disabled(model.remote.selection.isEmpty)
                Divider()
                Picker(L.doubleClickLabel, selection: $model.localDoubleClickAction) {
                    ForEach(LocalDoubleClickAction.allCases) { action in
                        Text(action.label).tag(action)
                    }
                }
            }
            CommandMenu(L.menuView) {
                Button(L.transferList) {
                    if model.showBottomPanel && model.bottomTab == .transfers {
                        model.showBottomPanel = false
                    } else {
                        model.showBottomPanel = true
                        model.bottomTab = .transfers
                    }
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
                Button(L.terminal) { model.toggleTerminal() }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                    .disabled(!model.status.isConnected)
            }
            CommandGroup(replacing: .help) {
                Button(L.menuHelp) { openWindow(id: "help") }
                    .keyboardShortcut("?", modifiers: .command)
            }
        }

        Window(L.menuHelp, id: "help") {
            HelpView()
                .environmentObject(model)
                .id(model.uiIdentity)
        }
        .defaultSize(width: 820, height: 580)

        Window(L.menuAbout, id: "about") {
            AboutView()
                .frame(width: 420)
                .id(model.uiIdentity)
        }
        // A fixed-size panel: the content sizes itself, so no resize handles.
        .windowResizability(.contentSize)

        // Adds the standard Settings item and ⌘, to the app menu.
        Settings {
            SettingsView()
                .environmentObject(model)
                .id(model.language)
        }
    }
}

/// SwiftPM-built apps do not get an activation policy for free; without this the
/// window can launch behind whatever was frontmost.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The Help and About windows must not keep the app alive on their own, but
    /// closing the last file-browser window should still quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
