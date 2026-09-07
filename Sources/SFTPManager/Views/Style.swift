import SwiftUI
import AppKit

/// The type scale and the few metrics the window shares.
///
/// Every piece of text in the app goes through one of these, which is what lets
/// Settings swap the interface font and nudge its size: the tokens are computed,
/// not constant, and the scene is rebuilt when `AppModel.uiIdentity` changes.
/// Icon glyphs deliberately do *not* come from here — a symbol is not text.
enum Style {

    // MARK: Building blocks

    /// The point size macOS gives each text style. Spelled out because a custom
    /// family has no notion of "callout", and because the size offset from
    /// Settings has to be added somewhere.
    static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 26
        case .title: return 22
        case .title2: return 17
        case .title3: return 15
        case .headline, .body: return 13
        case .callout: return 12
        case .subheadline: return 11
        case .footnote, .caption, .caption2: return 10
        @unknown default: return 13
        }
    }

    /// One interface font: the chosen family if it is installed, the system
    /// font otherwise.
    static func ui(_ style: Font.TextStyle,
                   weight: Font.Weight = .regular,
                   monospacedDigit: Bool = false) -> Font {
        let size = baseSize(style) + Fonts.current.uiSizeDelta
        var font: Font
        if let custom = Fonts.ui(size: size, weight: weight) {
            font = Font(custom as CTFont)
        } else {
            font = .system(size: size, weight: weight)
        }
        if monospacedDigit { font = font.monospacedDigit() }
        return font
    }

    /// Fixed-pitch text inside the interface — permission bits, a path, a
    /// fingerprint. Follows the size offset but never the interface family:
    /// these are lined up character by character.
    static func mono(_ style: Font.TextStyle) -> Font {
        .system(size: baseSize(style) + Fonts.current.uiSizeDelta, design: .monospaced)
    }

    // MARK: The scale

    static var largeTitle: Font { ui(.title) }
    static var title2: Font { ui(.title2, weight: .semibold) }
    static var title3: Font { ui(.title3, weight: .semibold) }
    static var headline: Font { ui(.headline, weight: .semibold) }
    static var body: Font { ui(.body) }
    static var callout: Font { ui(.callout) }
    static var caption: Font { ui(.caption) }

    // MARK: Named for their job

    /// Pane titles and anything of the same rank.
    static var title: Font { headline }
    /// Sortable column headings.
    static var columnHeader: Font { ui(.caption, weight: .semibold) }
    /// A file name, a server name — the thing a row is *about*.
    static var rowName: Font { callout }
    /// A name that needs to win over its own subtitle.
    static var itemName: Font { ui(.callout, weight: .medium) }
    /// Size, date, owner: anything that lines up in a column. Tabular figures
    /// keep the digits from shifting as rows scroll past.
    static var rowMeta: Font { ui(.callout, monospacedDigit: true) }
    /// Permission bits, which are a fixed-width string by nature.
    static var rowMono: Font { mono(.caption) }
    /// Footers and quiet counters.
    static var footnote: Font { ui(.caption, monospacedDigit: true) }

    // MARK: Metrics

    /// Corner radius of the ring drawn around the active pane.
    static let paneCorner: CGFloat = 6

    /// Column widths, shared by the headings and the rows so the two cannot
    /// fall out of step.
    static let sizeColumn: CGFloat = 82
    static let dateColumn: CGFloat = 128
    static let ownerColumn: CGFloat = 86
    static let permissionColumn: CGFloat = 84
    /// What `.listStyle(.inset(alternatesRowBackgrounds:))` insets a row by.
    /// The column headings live outside that list and have to be padded by hand
    /// to sit over the values; these two are measured from a snapshot, not
    /// guessed.
    static let listInsetLeading: CGFloat = 13
    static let listInsetTrailing: CGFloat = 14
    /// Breathing room after a right-aligned column, taken out of the column's
    /// own width so heading and row still end at the same x.
    static let columnGap: CGFloat = 10
}
