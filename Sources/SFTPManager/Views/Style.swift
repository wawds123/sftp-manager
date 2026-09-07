import SwiftUI

/// The type scale and the few metrics the main window shares.
///
/// These live in one place rather than at each call site so a heading in one
/// pane cannot drift a point away from the same heading in the next one, and so
/// the tabular figures every numeric column needs are impossible to forget.
enum Style {
    /// Pane titles and anything of the same rank.
    static let title = Font.headline
    /// Sortable column headings.
    static let columnHeader = Font.caption.weight(.semibold)
    /// A file name, a server name — the thing a row is *about*.
    static let rowName = Font.callout
    /// A name that needs to win over its own subtitle.
    static let itemName = Font.callout.weight(.medium)
    /// Size, date, owner: anything that lines up in a column. Tabular figures
    /// keep the digits from shifting as rows scroll past.
    static let rowMeta = Font.callout.monospacedDigit()
    /// Permission bits, which are a fixed-width string by nature.
    static let rowMono = Font.system(.caption, design: .monospaced)
    /// Footers and quiet counters.
    static let footnote = Font.caption.monospacedDigit()

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
