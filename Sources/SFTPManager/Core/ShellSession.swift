import AppKit
import Citadel
import Foundation
import NIOCore
import NIOSSH
import SwiftTerm

/// Wraps a path so a shell reads it as one literal argument.
enum ShellQuote {
    /// Single-quoted, with embedded quotes closed and reopened the POSIX way.
    static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Reads the path out of an OSC 7 report, which shells send as a `file://` URI.
enum HostDirectoryURI {
    /// Returns an absolute path, or nil if the report is not one.
    static func path(from report: String) -> String? {
        var rest = Substring(report)
        if rest.hasPrefix("file://") {
            rest = rest.dropFirst("file://".count)
            // What follows is the hostname, up to the first slash. An empty
            // hostname (file:///srv) is normal and leaves the path intact.
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            rest = rest[slash...]
        }
        guard rest.hasPrefix("/") else { return nil }
        return String(rest).removingPercentEncoding ?? String(rest)
    }
}

/// Pulls a working directory out of the window title a shell sets on its prompt
/// (`\e]0;user@host:dir\a`), which is how most distributions ship bash and zsh.
///
/// A heuristic, unlike OSC 7 — so it is only used when the user asks for it, not
/// to move the file pane on its own.
enum ShellTitlePath {
    static func path(from title: String, home: String) -> String? {
        var candidate = title.trimmingCharacters(in: .whitespaces)
        // "user@host:/srv/app" — the path starts after the colon that follows
        // the host. Search from the "@" because a path may contain colons.
        if let at = candidate.firstIndex(of: "@"),
           let colon = candidate[at...].firstIndex(of: ":") {
            candidate = String(candidate[candidate.index(after: colon)...])
        }
        candidate = candidate.trimmingCharacters(in: .whitespaces)
        if candidate == "~" { return home }
        if candidate.hasPrefix("~/") {
            candidate = PathUtil.join(home, String(candidate.dropFirst(2)))
        }
        guard candidate.hasPrefix("/") else { return nil }
        return PathUtil.normalize(candidate)
    }
}

/// Decides when the shell has gone quiet after a command, so the remote listing
/// can be reloaded without the user asking for it.
///
/// A PTY gives no "command finished" signal — the shell just stops writing — so
/// this watches for silence instead. Pure logic, so `--selftest` can check it.
struct ShellIdleRefresh {
    /// Silence, in seconds, that counts as "whatever ran has finished".
    var quietPeriod: TimeInterval = 0.7

    private var armed = false
    private var lastActivity = Date.distantPast

    init(quietPeriod: TimeInterval = 0.7) {
        self.quietPeriod = quietPeriod
    }

    /// The user pressed Return: something is about to run.
    mutating func noteSubmit(at now: Date) {
        armed = true
        lastActivity = now
    }

    /// The shell wrote something. Only interesting while a command is pending.
    mutating func noteOutput(at now: Date) {
        guard armed else { return }
        lastActivity = now
    }

    /// True once per command, after the shell has been quiet long enough.
    mutating func consumeRefresh(at now: Date) -> Bool {
        guard armed, now.timeIntervalSince(lastActivity) >= quietPeriod else { return false }
        armed = false
        return true
    }
}

/// A terminal that re-reads the system colours whenever the appearance changes.
///
/// `configureNativeColors()` resolves `NSColor.textColor` once and hands the
/// result to the emulator as a fixed colour, so without this the shell keeps the
/// palette it was born with when the theme is switched.
final class ThemedTerminalView: TerminalView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyNativeColors()
    }

    func applyNativeColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            configureNativeColors()
            caretColor = NSColor.textColor
        }
        needsDisplay = true
    }
}

/// One interactive shell riding on the connection the file panes already use.
///
/// Everything runs on the main actor: the terminal view has to be fed there
/// anyway, and keeping the read loop there preserves the order of the bytes.
@MainActor
final class ShellSession: NSObject, ObservableObject, TerminalViewDelegate {
    enum State: Equatable {
        case starting
        case running
        /// `nil` means the shell exited on its own or the user closed it.
        case closed(String?)

        var isClosed: Bool { if case .closed = self { return true }; return false }
    }

    @Published private(set) var state: State = .starting
    @Published private(set) var title = ""

    /// Owned here, not rebuilt by the SwiftUI wrapper: hiding the panel or
    /// switching tabs must not throw away scrollback or the running shell.
    let view: ThemedTerminalView

    /// Fired when the shell falls silent after a command, so the remote pane can
    /// pick up whatever the command did to the filesystem.
    var onCommandFinished: (() -> Void)?
    /// Fired when the shell reports a new directory over OSC 7.
    var onDirectoryChanged: ((String) -> Void)?

    /// Where the shell appears to be, read from what it volunteers: OSC 7 if it
    /// sends it, otherwise the path in its window title. Nil when it says
    /// neither — nothing is ever typed into the shell to find out.
    private(set) var currentDirectory: String?

    private let handle: SFTPSession.ClientHandle?
    /// The remote home directory, for expanding a `~` in the shell's title.
    private let home: String
    /// Run once the channel is up, so a command issued while it was still
    /// opening is not lost.
    private var initialCommand: String?
    private var writer: WriterBox?
    private var task: Task<Void, Never>?

    /// Keystrokes are queued rather than written straight through: each write is
    /// an `await`, and firing one Task per key would reorder them.
    private var outbox: [UInt8] = []
    private var writeInFlight = false

    private var idle = ShellIdleRefresh()
    private var idleTimer: Timer?

    /// The screen size the far side believes in.
    ///
    /// The PTY is requested with whatever the view measures at init, but SwiftUI
    /// lays the panel out the moment it goes on screen — while that request is
    /// still in flight. A resize arriving then has no channel to travel down, so
    /// `attach` compares this against the view and sends the difference. Without
    /// it the server keeps drawing to the wrong screen: a full-screen program
    /// addresses rows that are not where it thinks they are, which is why `less`
    /// left the same text stamped twice after a redraw.
    private var channelSize: (cols: Int, rows: Int)?


    private struct WriterBox: @unchecked Sendable {
        let writer: TTYStdinWriter
    }

    init(handle: SFTPSession.ClientHandle, home: String, startIn path: String?, then command: String? = nil) {
        self.handle = handle
        self.home = home
        initialCommand = command
        currentDirectory = path
        view = ThemedTerminalView(frame: CGRect(x: 0, y: 0, width: 720, height: 320))
        super.init()
        view.applyNativeColors()
        view.font = Fonts.terminal()
        view.terminalDelegate = self
        start(in: path)
    }

    /// Builds a session with no channel behind it, so `--snapshot` can render
    /// the terminal panel offscreen. Never used by the running app.
    init(previewOutput text: String) {
        handle = nil
        home = "/"
        initialCommand = nil
        view = ThemedTerminalView(frame: CGRect(x: 0, y: 0, width: 720, height: 320))
        super.init()
        view.applyNativeColors()
        view.font = Fonts.terminal()
        view.terminalDelegate = self
        view.feed(text: text)
        state = .running
        title = "deploy@web-01:/srv/app/releases/current/public/assets/images"
    }

    // MARK: - Lifecycle

    private func start(in path: String?) {
        guard let handle else { return }
        let terminal = view.getTerminal()
        let request = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: terminal.cols,
            terminalRowHeight: terminal.rows,
            terminalPixelWidth: Int(view.bounds.width),
            terminalPixelHeight: Int(view.bounds.height),
            terminalModes: SSHTerminalModes([:])
        )
        channelSize = (cols: terminal.cols, rows: terminal.rows)

        // Inherits the main actor, and so does the non-Sendable `perform`
        // closure — which is what keeps the output in order.
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await handle.client.withPTY(request) { inbound, outbound in
                    self.attach(writer: outbound, startIn: path)
                    for try await chunk in inbound {
                        self.receive(chunk)
                    }
                }
                self.finish(error: nil)
            } catch {
                // Cancellation is how `close()` gets out of the read loop, and a
                // shell that exits non-zero is a normal way to end a session.
                let expected = Task.isCancelled || error is SSHClient.CommandFailed
                self.finish(error: expected ? nil : AppModel.describe(error))
            }
        }

        idleTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.idle.consumeRefresh(at: Date()) else { return }
                self.onCommandFinished?()
            }
        }
    }

    private func attach(writer: TTYStdinWriter, startIn path: String?) {
        self.writer = WriterBox(writer: writer)
        state = .running
        sendSize()
        if let path, !path.isEmpty, path != "/" {
            // Start where the remote pane is looking, and let the user see it.
            run("cd \(ShellQuote.singleQuoted(path))")
        }
        if let initialCommand {
            self.initialCommand = nil
            run(initialCommand)
        }
        drain()
    }

    private func receive(_ output: ExecCommandOutput) {
        switch output {
        case .stdout(let buffer), .stderr(let buffer):
            let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) ?? []
            view.feed(byteArray: bytes[...])
        }
        idle.noteOutput(at: Date())
    }

    private func finish(error: String?) {
        guard !state.isClosed else { return }
        idleTimer?.invalidate()
        idleTimer = nil
        writer = nil
        state = .closed(error)
        view.feed(text: "\r\n[" + (error.map { L.shellErrorBanner($0) } ?? L.shellDisconnectedBanner) + "]\r\n")
    }

    /// Cancels the read loop, which unwinds `withPTY` and closes the channel.
    func close() {
        task?.cancel()
        task = nil
        finish(error: nil)
    }

    // MARK: - Writing

    private func enqueue(_ bytes: ArraySlice<UInt8>) {
        outbox.append(contentsOf: bytes)
        drain()
    }

    private func drain() {
        guard !writeInFlight, !outbox.isEmpty, let writer else { return }
        writeInFlight = true
        let pending = outbox
        outbox.removeAll(keepingCapacity: true)
        Task { [weak self] in
            try? await writer.writer.write(ByteBuffer(bytes: pending))
            guard let self else { return }
            self.writeInFlight = false
            self.drain()
        }
    }

    /// True while the shell is sitting at a prompt.
    ///
    /// A full-screen program (vim, less, top) switches the terminal to its
    /// alternate buffer; keystrokes sent then go to that program, not to a
    /// shell, so nothing may be typed for the user while it is up.
    var isAtPrompt: Bool {
        state == .running && !view.getTerminal().isCurrentBufferAlternate
    }

    /// Ctrl-E then Ctrl-U: go to the end of the line, then kill it.
    ///
    /// Whatever the user had half-typed would otherwise be *prefixed* onto the
    /// injected command and run as one line. The killed text goes to the shell's
    /// kill ring, so Ctrl-Y brings it back.
    private static let clearInputLine: [UInt8] = [0x05, 0x15]

    /// Types a line into the shell as if the user had entered it.
    func run(_ command: String) {
        guard !state.isClosed else { return }
        idle.noteSubmit(at: Date())
        enqueue(Self.clearInputLine[...])
        enqueue(Array((command + "\n").utf8)[...])
    }

    // MARK: - TerminalViewDelegate

    nonisolated func send(source: TerminalView, data: ArraySlice<UInt8>) {
        MainActor.assumeIsolated {
            // Return means a command is on its way; the pane reloads once the
            // output stops.
            if data.contains(0x0d) || data.contains(0x0a) {
                idle.noteSubmit(at: Date())
            }
            enqueue(data)
        }
    }

    nonisolated func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        MainActor.assumeIsolated {
            // Nothing to do while the channel is opening: `attach` reads the
            // view's size itself once there is somewhere to send it.
            sendSize()
        }
    }

    /// Tells the far side how big the screen is now, if that has changed.
    private func sendSize() {
        guard let writer else { return }
        let terminal = view.getTerminal()
        let size = (cols: terminal.cols, rows: terminal.rows)
        guard channelSize == nil || channelSize! != size else { return }
        channelSize = size
        let width = Int(view.bounds.width)
        let height = Int(view.bounds.height)
        Task {
            try? await writer.writer.changeSize(
                cols: size.cols, rows: size.rows,
                pixelWidth: width, pixelHeight: height
            )
        }
    }

    nonisolated func setTerminalTitle(source: TerminalView, title: String) {
        MainActor.assumeIsolated {
            self.title = title
            // Only a hint for the "move the pane here" button; the pane is not
            // moved on a guess.
            if let path = ShellTitlePath.path(from: title, home: home) {
                currentDirectory = path
            }
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        MainActor.assumeIsolated {
            guard let directory, let path = HostDirectoryURI.path(from: directory) else { return }
            currentDirectory = path
            onDirectoryChanged?(path)
        }
    }

    /// Re-reads the palette after the app theme changes; `NSApp.appearance` is
    /// applied to windows asynchronously, so the view may not have been told yet.
    func refreshAppearance() {
        view.applyNativeColors()
    }

    /// Settings changed the terminal font. SwiftTerm reflows the screen to the
    /// new cell size on its own.
    func refreshFont() {
        view.font = Fonts.terminal()
    }

    nonisolated func scrolled(source: TerminalView, position: Double) {}

    nonisolated func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
