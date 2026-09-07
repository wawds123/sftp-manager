import SwiftUI
import AppKit

/// The ⌘, window. Every control writes straight through to `AppModel`, which
/// persists it — there is no separate apply step.
struct SettingsView: View {
    enum Tab: String, CaseIterable {
        case general, fonts, files, transfers, advanced, about
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
            FontSettings()
                .tabItem { Label(L.settingsFonts, systemImage: "textformat.size") }
                .tag(Tab.fonts)
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
        // Tall enough for the longest tab (fonts) to show its last control
        // without scrolling; the rest simply have room to spare.
        .frame(width: 560, height: 520)
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
                    .font(Style.caption)
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
                    .font(Style.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L.sectionConnection) {
                LabeledContent(L.password) {
                    Text(L.notStored)
                        .foregroundStyle(.secondary)
                }
                Text(L.passwordPolicyFooter)
                    .font(Style.caption)
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
                    .font(Style.caption)
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
                    .font(Style.caption)
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
                    .font(Style.caption)
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
                    .font(Style.caption)
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
                            .font(Style.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(L.remoteEditingTitle)
            } footer: {
                Text(L.remoteEditingFooter)
                    .font(Style.caption)
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
                    .font(Style.caption)
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
                    .font(Style.rowMono)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .textSelection(.enabled)
                Button(L.reveal) { model.revealPathInFinder(path) }
                    .controlSize(.small)
            }
        }
    }
}

/// Interface and terminal fonts.
///
/// Families are listed by name and nothing is bundled: a font the Mac already
/// has is one the person already reads comfortably, and it keeps the app clear
/// of redistributing anyone's typeface.
private struct FontSettings: View {
    @EnvironmentObject private var model: AppModel

    /// SwiftUI needs a non-optional tag, so "no family chosen" travels as an
    /// empty string and is mapped back at the binding.
    private func familyBinding(_ keyPath: ReferenceWritableKeyPath<AppModel, String?>) -> Binding<String> {
        Binding(
            get: { model[keyPath: keyPath] ?? "" },
            set: { model[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker(L.uiFontLabel, selection: familyBinding(\.uiFontFamily)) {
                    Text(L.systemFont).tag("")
                    Divider()
                    ForEach(Fonts.families, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                Stepper(value: $model.uiFontSizeDelta,
                        in: FontPreferences.uiSizeDeltaRange, step: 1) {
                    LabeledContent(L.uiFontSizeLabel) {
                        Text(L.fontSizeOffset(Int(model.uiFontSizeDelta)))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(L.sectionInterface)
            } footer: {
                Text(L.uiFontFooter)
                    .font(Style.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(L.terminalFontLabel, selection: familyBinding(\.terminalFontFamily)) {
                    Text(L.systemMonoFont).tag("")
                    Divider()
                    ForEach(Fonts.monospacedFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                Stepper(value: $model.terminalFontSize,
                        in: FontPreferences.terminalSizeRange, step: 1) {
                    LabeledContent(L.terminalFontSizeLabel) {
                        Text("\(Int(model.terminalFontSize))pt")
                            .foregroundStyle(.secondary)
                    }
                }
                // Drawn with the very font the terminal will use — this window
                // is already in the interface font, so that one needs no
                // sample, but the terminal is not on screen to judge.
                Text(Self.terminalSample)
                    .font(Font(Fonts.terminal() as CTFont))
                    .lineLimit(2)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 6))
            } header: {
                Text(L.terminal)
            } footer: {
                Text(L.terminalFontFooter)
                    .font(Style.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(L.resetFonts) { model.resetFonts() }
            }
        }
        .formStyle(.grouped)
    }

    /// Deliberately ASCII with a couple of box-drawing characters: it shows the
    /// figures and the alignment a terminal font is picked for.
    private static let terminalSample = """
    deploy@web-01:~$ ls -lh
    -rw-r--r--  1 deploy  18.4M  releases/build-4812.tar.gz
    """
}
