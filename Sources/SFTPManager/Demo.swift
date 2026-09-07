import Foundation
import AppKit

/// `--demo` opens the ordinary window filled with invented servers, listings,
/// transfers and shell output, so the app can be photographed without a real
/// host, account or home directory in the picture.
///
/// It is a display mode, not a sandbox for using the app: the panes hold made-up
/// entries and there is no connection behind them. What it does guarantee is
/// that nothing it shows can leak into the real state — the connection store
/// points at a scratch file (`ConnectionStore.scratch()`) and preferences are
/// not written, so switching the theme or the language to set a screenshot up
/// leaves the settings alone.
///
/// The same sample data is what `--snapshot --demo` renders offscreen; this is
/// the version you can point a screen capture at, which is the way to get a
/// dark-theme picture the offscreen renderer cannot draw faithfully.
enum Demo {
    /// Set once from `main.swift`, before any model exists. The self-test flips
    /// it too, and puts it back.
    nonisolated(unsafe) static var isOn = false

    @MainActor
    static func install(into model: AppModel) {
        SampleWorkspace.install(into: model)
        // A shell the Terminal tab can show. It has no channel behind it, so it
        // prints its scrollback and ignores what is typed. It draws an AppKit
        // view, so it is only built when there is an application to draw into —
        // the headless self-test constructs this model too.
        if model.shell == nil, NSApp != nil {
            model.shell = ShellSession(previewOutput: SampleTransfers.shellOutput)
        }
    }
}
