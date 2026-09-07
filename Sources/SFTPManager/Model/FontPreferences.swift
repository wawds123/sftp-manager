import SwiftUI
import AppKit

/// The four font choices Settings can make.
///
/// A family is stored by name rather than by anything derived from it, so a
/// font that is uninstalled later degrades to the system font instead of to
/// whatever macOS would have substituted.
struct FontPreferences: Equatable, Sendable {
    /// `nil` means the system font — the default, and the only choice that is
    /// guaranteed to cover every script the interface is translated into.
    var uiFamily: String?
    /// Points added to every interface text size.
    var uiSizeDelta: Double
    /// `nil` means the system's own fixed-pitch font.
    var terminalFamily: String?
    var terminalSize: Double

    static let standard = FontPreferences(uiFamily: nil, uiSizeDelta: 0,
                                          terminalFamily: nil, terminalSize: 12)

    static let uiSizeDeltaRange: ClosedRange<Double> = -1...5
    static let terminalSizeRange: ClosedRange<Double> = 9...24

    /// Values from disk are clamped rather than rejected: a stored 400pt would
    /// otherwise make the app unusable with no way back to Settings.
    var clamped: FontPreferences {
        FontPreferences(
            uiFamily: uiFamily,
            uiSizeDelta: min(max(uiSizeDelta, Self.uiSizeDeltaRange.lowerBound),
                             Self.uiSizeDeltaRange.upperBound),
            terminalFamily: terminalFamily,
            terminalSize: min(max(terminalSize, Self.terminalSizeRange.lowerBound),
                              Self.terminalSizeRange.upperBound)
        )
    }
}

/// The current font choices, and the lookups that turn a family name into a
/// font.
///
/// `Style` reads this from view bodies, which are neither observable nor
/// confined to one actor, so it uses the same lock-guarded global the language
/// switch does. The scene is keyed on `AppModel.uiIdentity`, which is what
/// actually rebuilds the tree when a choice changes.
enum Fonts {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored = FontPreferences.standard

    static var current: FontPreferences {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue.clamped; lock.unlock() }
    }

    // MARK: Installed families

    /// Enumerating the installed fonts takes long enough to be worth doing once;
    /// a font installed while the app is running is rare enough to need a
    /// relaunch.
    nonisolated(unsafe) private static var familyCache: [String]?
    nonisolated(unsafe) private static var monospacedCache: [String]?

    static var families: [String] {
        lock.lock(); defer { lock.unlock() }
        if let familyCache { return familyCache }
        let found = NSFontManager.shared.availableFontFamilies.sorted()
        familyCache = found
        return found
    }

    /// Fixed-pitch families only. A terminal in a proportional font cannot draw
    /// a column of anything, so the picker never offers one.
    static var monospacedFamilies: [String] {
        lock.lock()
        if let monospacedCache { lock.unlock(); return monospacedCache }
        lock.unlock()
        let manager = NSFontManager.shared
        let found = manager.availableFontFamilies.filter { family in
            // `availableMembers` reports the traits without instantiating the
            // font, which matters when there are several hundred families.
            guard let members = manager.availableMembers(ofFontFamily: family) else { return false }
            return members.contains { member in
                guard member.count >= 3, let traits = member[3] as? UInt else { return false }
                return NSFontTraitMask(rawValue: traits).contains(.fixedPitchFontMask)
            }
        }.sorted()
        lock.lock(); monospacedCache = found; lock.unlock()
        return found
    }

    /// A family the user picked, or nil if it is no longer installed.
    static func resolve(_ family: String?) -> String? {
        guard let family, !family.isEmpty else { return nil }
        return families.contains(family) ? family : nil
    }

    // MARK: Fonts

    /// Maps SwiftUI's weights onto the 0...15 scale `NSFontManager` uses.
    private static func managerWeight(_ weight: Font.Weight) -> Int {
        switch weight {
        case .ultraLight, .thin: return 2
        case .light: return 3
        case .medium: return 6
        case .semibold: return 8
        case .bold: return 9
        case .heavy, .black: return 11
        default: return 5
        }
    }

    /// The interface font at one size, or nil to mean "use the system font".
    static func ui(size: CGFloat, weight: Font.Weight) -> NSFont? {
        guard let family = resolve(current.uiFamily) else { return nil }
        return NSFontManager.shared.font(withFamily: family, traits: [],
                                         weight: managerWeight(weight), size: size)
    }

    /// What the terminal draws with. Falls back to the system's fixed-pitch
    /// font, which is what SwiftTerm was given before this was a setting.
    static func terminal() -> NSFont {
        let settings = current
        let size = settings.terminalSize
        if let family = resolve(settings.terminalFamily),
           let font = NSFontManager.shared.font(withFamily: family, traits: [],
                                                weight: 5, size: size) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
