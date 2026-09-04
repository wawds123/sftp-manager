import SwiftUI
import AppKit

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return L.themeSystem
        case .light: return L.themeLight
        case .dark: return L.themeDark
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Everything the Settings window can change, with the UserDefaults keys behind
/// it. Held on `AppModel` so views already reading the model see changes.
enum PreferenceKey {
    static let language = "language"
    static let theme = "theme"
    static let showHidden = "showHiddenByDefault"
    static let sortKey = "defaultSortKey"
    static let sortAscending = "defaultSortAscending"
    static let conflictPolicy = "conflictPolicy"
    static let doubleClick = "localDoubleClickAction"
    static let notifyOnFinish = "notifyOnTransferFinish"
    static let pipelineDepth = "pipelineDepth"
    static let editPollInterval = "editPollInterval"
    static let showTransfersAtLaunch = "showTransfersAtLaunch"
    static let panelHeight = "transferPanelHeight"
    static let purgedKeychain = "didPurgeKeychainCredentials"
}

extension AppModel {
    /// Reads every stored preference. Called from `init`, where property
    /// observers don't fire, so the setters' side effects are applied after.
    func loadPreferences() {
        isLoadingPreferences = true
        defer { isLoadingPreferences = false }
        let defaults = UserDefaults.standard
        // No stored choice means a first launch: follow the Mac's own language.
        if let raw = defaults.string(forKey: PreferenceKey.language),
           let value = AppLanguage(rawValue: raw) {
            language = value
        } else {
            language = AppLanguage.systemDefault
        }
        Lang.current = language
        if let raw = defaults.string(forKey: PreferenceKey.theme), let value = AppTheme(rawValue: raw) {
            theme = value
        }
        if let raw = defaults.string(forKey: PreferenceKey.doubleClick),
           let value = LocalDoubleClickAction(rawValue: raw) {
            localDoubleClickAction = value
        }
        if let raw = defaults.string(forKey: PreferenceKey.conflictPolicy),
           let value = ConflictPolicy(rawValue: raw) {
            conflictPolicy = value
        }
        if let raw = defaults.string(forKey: PreferenceKey.sortKey), let value = SortKey(rawValue: raw) {
            defaultSortKey = value
        }
        if defaults.object(forKey: PreferenceKey.sortAscending) != nil {
            defaultSortAscending = defaults.bool(forKey: PreferenceKey.sortAscending)
        }
        showHiddenByDefault = defaults.bool(forKey: PreferenceKey.showHidden)
        notifyOnTransferFinish = defaults.bool(forKey: PreferenceKey.notifyOnFinish)
        // Defaults to on, so an absent key must not read as `false`.
        if defaults.object(forKey: PreferenceKey.showTransfersAtLaunch) != nil {
            showTransfersAtLaunch = defaults.bool(forKey: PreferenceKey.showTransfersAtLaunch)
        }
        if let stored = defaults.object(forKey: PreferenceKey.pipelineDepth) as? Int {
            pipelineDepth = stored
        }
        if let stored = defaults.object(forKey: PreferenceKey.editPollInterval) as? Double {
            editPollInterval = stored
        }
        if let stored = defaults.object(forKey: PreferenceKey.panelHeight) as? Double {
            transferPanelHeight = CGFloat(stored)
        }
    }

    func savePreferences() {
        guard !isLoadingPreferences else { return }
        let defaults = UserDefaults.standard
        defaults.set(language.rawValue, forKey: PreferenceKey.language)
        defaults.set(theme.rawValue, forKey: PreferenceKey.theme)
        defaults.set(localDoubleClickAction.rawValue, forKey: PreferenceKey.doubleClick)
        defaults.set(conflictPolicy.rawValue, forKey: PreferenceKey.conflictPolicy)
        defaults.set(defaultSortKey.rawValue, forKey: PreferenceKey.sortKey)
        defaults.set(defaultSortAscending, forKey: PreferenceKey.sortAscending)
        defaults.set(showHiddenByDefault, forKey: PreferenceKey.showHidden)
        defaults.set(notifyOnTransferFinish, forKey: PreferenceKey.notifyOnFinish)
        defaults.set(showTransfersAtLaunch, forKey: PreferenceKey.showTransfersAtLaunch)
        defaults.set(pipelineDepth, forKey: PreferenceKey.pipelineDepth)
        defaults.set(editPollInterval, forKey: PreferenceKey.editPollInterval)
    }

    func applyTheme() {
        // Guard so headless modes (--selftest) don't spin up an NSApplication.
        guard NSApp != nil else { return }
        NSApp.appearance = theme.appearance
        // The terminal caches the colours it was given, so it has to be told.
        if let shell {
            DispatchQueue.main.async { shell.refreshAppearance() }
        }
    }

    /// Pane-level defaults are pushed to both panes so a change in Settings is
    /// visible straight away, and reused for the next launch.
    func applyListDefaults() {
        for pane in [local, remote] {
            pane.showHidden = showHiddenByDefault
            pane.sortKey = defaultSortKey
            pane.ascending = defaultSortAscending
        }
    }

    /// Restores the state a fresh install would have, without touching saved
    /// servers or `known_hosts`.
    func resetPreferences() {
        let defaults = UserDefaults.standard
        // `language` is deliberately absent: resetting the interface into a
        // language the user may not read is not a recoverable state.
        for key in [
            PreferenceKey.theme, PreferenceKey.showHidden, PreferenceKey.sortKey,
            PreferenceKey.sortAscending, PreferenceKey.conflictPolicy, PreferenceKey.doubleClick,
            PreferenceKey.notifyOnFinish, PreferenceKey.showTransfersAtLaunch,
            PreferenceKey.pipelineDepth,
            PreferenceKey.editPollInterval, PreferenceKey.panelHeight,
        ] {
            defaults.removeObject(forKey: key)
        }
        theme = .system
        showHiddenByDefault = false
        defaultSortKey = .name
        defaultSortAscending = true
        conflictPolicy = .ask
        localDoubleClickAction = .upload
        notifyOnTransferFinish = false
        showTransfersAtLaunch = true
        pipelineDepth = 64
        editPollInterval = 1.0
        transferPanelHeight = nil
    }

    /// Sound plus a Dock bounce — deliberately not a user notification, which
    /// would need a permission prompt that can be silently denied.
    func announceTransfersFinished(failed: Int) {
        guard notifyOnTransferFinish else { return }
        NSSound(named: failed > 0 ? "Basso" : "Glass")?.play()
        NSApp?.requestUserAttention(failed > 0 ? .criticalRequest : .informationalRequest)
    }
}
