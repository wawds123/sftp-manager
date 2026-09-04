import SwiftUI
import AppKit

/// The ⌘, window. Every control writes straight through to `AppModel`, which
/// persists it — there is no separate apply step.
struct SettingsView: View {
    enum Tab: String, CaseIterable {
        case general, files, transfers, advanced, about
    }

    /// Selectable so each tab can be rendered on its own for review.
    @State private var selection: Tab

    init(initialTab: Tab = .general) {
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettings()
                .tabItem { Label(L.settingsGeneral, systemImage: "gearshape") }
                .tag(Tab.general)
            FileListSettings()
                .tabItem { Label(L.settingsFileList, systemImage: "list.bullet") }
                .tag(Tab.files)
            TransferSettings()
                .tabItem { Label(L.transfers, systemImage: "arrow.up.arrow.down") }
                .tag(Tab.transfers)
            AdvancedSettings()
                .tabItem { Label(L.settingsAdvanced, systemImage: "wrench.and.screwdriver") }
                .tag(Tab.advanced)
            AboutView()
                .tabItem { Label(L.settingsAbout, systemImage: "info.circle") }
                .tag(Tab.about)
        }
        .frame(width: 560, height: 460)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                // Each option names itself in its own language, so it stays
                // readable to someone who can't read the current one.
                Picker(L.languageLabel, selection: $model.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }
            } footer: {
                Text(L.languageFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(L.themeLabel, selection: $model.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text(L.appearance)
            } footer: {
                Text(L.themeFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L.sectionConnection) {
                LabeledContent(L.password) {
                    Text(L.notStored)
                        .foregroundStyle(.secondary)
                }
                Text(L.passwordPolicyFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct FileListSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section(L.sectionDisplay) {
                Toggle(L.showHiddenDefault, isOn: $model.showHiddenByDefault)
                Picker(L.sortKeyLabel, selection: $model.defaultSortKey) {
                    ForEach(SortKey.allCases) { key in
                        Text(key.label).tag(key)
                    }
                }
                Picker(L.sortDirectionLabel, selection: $model.defaultSortAscending) {
                    Text(L.ascending).tag(true)
                    Text(L.descending).tag(false)
                }
                Text(L.displayFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(L.doubleClickLabel, selection: $model.localDoubleClickAction) {
                    ForEach(LocalDoubleClickAction.allCases) { action in
                        Text(action.label).tag(action)
                    }
                }
            } footer: {
                Text(L.doubleClickFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct TransferSettings: View {
    @EnvironmentObject private var model: AppModel

    private let depths = [8, 16, 32, 64, 128]

    var body: some View {
        Form {
            Section {
                Picker(L.conflictSettingLabel, selection: $model.conflictPolicy) {
                    ForEach(ConflictPolicy.allCases) { policy in
                        Text(policy.label).tag(policy)
                    }
                }
                Toggle(L.showTransfersAtLaunchLabel, isOn: $model.showTransfersAtLaunch)
                Toggle(L.notifyOnFinishLabel, isOn: $model.notifyOnTransferFinish)
            } footer: {
                Text(L.transferFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(L.pipelineDepthLabel, selection: $model.pipelineDepth) {
                    ForEach(depths, id: \.self) { depth in
                        Text(depth == SFTPSession.defaultPipelineDepth ? L.recommended(depth) : "\(depth)")
                            .tag(depth)
                    }
                }
            } header: {
                Text(L.speed)
            } footer: {
                Text(L.pipelineFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AdvancedSettings: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmingReset = false
    @State private var cleanedMessage: String?

    private let intervals: [Double] = [0.5, 1, 2, 5]

    var body: some View {
        Form {
            Section {
                Picker(L.pollIntervalLabel, selection: $model.editPollInterval) {
                    ForEach(intervals, id: \.self) { seconds in
                        Text(L.seconds(seconds)).tag(seconds)
                    }
                }
                HStack {
                    Button(L.showScratchFolder) { model.revealPathInFinder(model.editsRoot) }
                    Button(L.cleanScratchFiles) {
                        let count = model.cleanUpEditScratch()
                        cleanedMessage = count == 0 ? L.nothingToClean : L.cleanedCount(count)
                    }
                    if let cleanedMessage {
                        Text(cleanedMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(L.remoteEditingTitle)
            } footer: {
                Text(L.remoteEditingFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L.sectionFileLocations) {
                pathRow(L.hostKeysPath, KnownHosts.defaultPath)
                pathRow(L.serverListPath, model.store.fileURL.path)
            }

            Section {
                Button(L.resetSettings, role: .destructive) { confirmingReset = true }
            } footer: {
                Text(L.resetFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(L.resetConfirmTitle, isPresented: $confirmingReset) {
            Button(L.reset, role: .destructive) { model.resetPreferences() }
            Button(L.cancel, role: .cancel) {}
        }
    }

    private func pathRow(_ label: String, _ path: String) -> some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                Text(path)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.head)
                    .textSelection(.enabled)
                Button(L.reveal) { model.revealPathInFinder(path) }
                    .controlSize(.small)
            }
        }
    }
}
