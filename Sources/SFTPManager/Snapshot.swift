import SwiftUI
import AppKit

/// Renders the real window offscreen and writes it to a PNG.
///
/// `screencapture` needs Screen Recording permission, which a headless build
/// session doesn't have; drawing the window's own layer sidesteps that and is
/// enough to verify that the UI lays out and paints.
///
/// Usage: SFTPManager --snapshot /path/to/out.png [--seconds 2] [--view app|sidebar]
///
/// `--view sidebar` renders the connection list on its own; NavigationSplitView's
/// sidebar sits in a vibrancy layer that offscreen rendering leaves blank, so it
/// has to be checked outside the split view.
enum Snapshot {
    /// Mirrors the modifiers `SFTPManagerApp` applies, so the snapshot lays out
    /// the same way the shipping window does.
    @MainActor
    private static func appRoot(_ model: AppModel) -> some View {
        ContentView()
            .environmentObject(model)
            .frame(minWidth: 1020, minHeight: 620)
    }

    @MainActor
    static func run(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else {
            print("사용법: SFTPManager --snapshot <출력.png> [--view NAME] [--lang ko|en] [--seconds N]")
            exit(2)
        }
        let output = arguments[index + 1]
        var seconds: Double = 2.5
        if let s = arguments.firstIndex(of: "--seconds"), s + 1 < arguments.count {
            seconds = Double(arguments[s + 1]) ?? seconds
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        var width = 1280.0
        var height = 800.0
        if let z = arguments.firstIndex(of: "--size"), z + 1 < arguments.count {
            let parts = arguments[z + 1].split(separator: "x")
            if parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]) {
                width = w; height = h
            }
        }
        var view = "app"
        if let v = arguments.firstIndex(of: "--view"), v + 1 < arguments.count {
            view = arguments[v + 1]
        }

        let model = AppModel()
        // Nothing this mode does may reach the real preferences: it flips the
        // theme, the language and the terminal lock to render them.
        model.isLoadingPreferences = true
        // `--demo` replaces every pane and server with fixed sample data, so a
        // published screenshot shows the app rather than whoever built it, and
        // anyone who clones the repo gets the same picture.
        let demo = arguments.contains("--demo")
        if demo { SampleWorkspace.install(into: model) }
        // Set before any view is built, so the whole tree reads this language.
        if let g = arguments.firstIndex(of: "--lang"), g + 1 < arguments.count,
           let parsed = AppLanguage(rawValue: arguments[g + 1]) {
            model.language = parsed
        }
        if !demo, let l = arguments.firstIndex(of: "--local"), l + 1 < arguments.count {
            model.navigate(.local, to: arguments[l + 1])
        }
        if !demo, arguments.contains("--connected"), let first = model.connections.first {
            model.selectedConnectionID = first.id
            model.previewConnected(first.id, name: first.displayName)
        }
        let hosting: NSView
        let size: NSSize
        switch view {
        case "transfers":
            model.showBottomPanel = true
            var rows = 5
            if let r = arguments.firstIndex(of: "--rows"), r + 1 < arguments.count {
                rows = Int(arguments[r + 1]) ?? rows
            }
            model.transfers = SampleTransfers.make(count: rows)
            hosting = NSHostingView(rootView: appRoot(model))
            size = NSSize(width: width, height: height)
        case "terminal":
            model.showBottomPanel = true
            model.bottomTab = .terminal
            // `--view terminal-empty` shows the not-connected placeholder.
            if !arguments.contains("--empty") {
                let shell = ShellSession(previewOutput: SampleTransfers.shellOutput)
                // `--view terminal --exited` is the panel after the user typed
                // `exit`: the scrollback stays, the live buttons do not.
                if arguments.contains("--exited") { shell.close() }
                model.shell = shell
            }
            hosting = NSHostingView(rootView: appRoot(model))
            size = NSSize(width: width, height: height)
        case "conflict":
            let incoming = FileItem(path: "/local/report.pdf", name: "report.pdf", kind: .file,
                                    size: 4_812_000, modified: Date(timeIntervalSince1970: 1_788_000_000),
                                    permissions: 0o644, owner: "me")
            let existing = FileItem(path: "/srv/app/report.pdf", name: "report.pdf", kind: .file,
                                    size: 3_140_000, modified: Date(timeIntervalSince1970: 1_780_000_000),
                                    permissions: 0o644, owner: "deploy")
            let request = ConflictRequest(
                direction: .upload,
                incoming: incoming,
                existing: existing,
                destination: "/srv/app/releases/current/public",
                renamedTo: "report 2.pdf",
                remaining: 3,
                respond: { _, _ in }
            )
            hosting = NSHostingView(rootView: ConflictSheet(request: request).environmentObject(model))
            size = NSSize(width: 460, height: 260)
        case "settings":
            var tab = SettingsView.Tab.general
            if let t = arguments.firstIndex(of: "--tab"), t + 1 < arguments.count,
               let parsed = SettingsView.Tab(rawValue: arguments[t + 1]) {
                tab = parsed
            }
            hosting = NSHostingView(rootView: SettingsView(initialTab: tab).environmentObject(model))
            size = NSSize(width: 560, height: 460)
        case "sidebar":
            hosting = NSHostingView(rootView: ConnectionSidebar().environmentObject(model))
            size = NSSize(width: 260, height: 420)
        case "help":
            var topic: String?
            if let h = arguments.firstIndex(of: "--topic"), h + 1 < arguments.count {
                topic = arguments[h + 1]
            }
            hosting = NSHostingView(rootView: HelpView(topic: topic).environmentObject(model))
            size = NSSize(width: 820, height: 580)
        case "about":
            hosting = NSHostingView(rootView: AboutView().frame(width: 420))
            size = NSSize(width: 420, height: 420)
        default:
            hosting = NSHostingView(rootView: appRoot(model))
            size = NSSize(width: width, height: height)
        }
        // A fixed-size clipping container, so the capture shows exactly what a
        // window of this size shows — including content that overflows it.
        // Handing the hosting view straight to the window let AppKit grow the
        // window to the view's fitting size, which hid layout overflow bugs.
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.clipsToBounds = true
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        let window = NSWindow(
            contentRect: container.frame,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "SFTP Manager"
        window.contentView = container
        window.setContentSize(size)
        window.orderFrontRegardless()

        // Applied after the views exist, so this exercises the same path as
        // flipping the theme in Settings rather than starting out dark.
        if let t = arguments.firstIndex(of: "--theme"), t + 1 < arguments.count,
           let parsed = AppTheme(rawValue: arguments[t + 1]) {
            model.theme = parsed
        }

        // Let SwiftUI settle: directory listings and layout both land async.
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        // The model kicks off a real read of the local directory on launch; for
        // an invented path that lands as an error after the sample data was put
        // in. Re-applying it here is what the picture actually shows.
        if demo {
            SampleWorkspace.install(into: model)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        }

        guard let contentView = window.contentView,
              let rep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            print("스냅샷 생성 실패")
            exit(1)
        }
        // Layer rendering picks up vibrancy/material backdrops that
        // cacheDisplay(in:to:) leaves blank; fall back when there is no layer.
        if let layer = contentView.layer, let context = NSGraphicsContext(bitmapImageRep: rep) {
            context.cgContext.setFillColor(NSColor.windowBackgroundColor.cgColor)
            context.cgContext.fill(contentView.bounds)
            context.cgContext.saveGState()
            // A flipped view's layer draws bottom-up relative to the bitmap rep.
            if contentView.isFlipped {
                context.cgContext.translateBy(x: 0, y: contentView.bounds.height)
                context.cgContext.scaleBy(x: 1, y: -1)
            }
            layer.render(in: context.cgContext)
            context.cgContext.restoreGState()
            // `layer.render` draws SwiftTerm's text with a left offset and puts
            // the caret somewhere else entirely, so the terminal is re-drawn on
            // top through the view's own (accurate) path.
            if let shell = model.shell {
                overlay(view: shell.view, in: contentView, context: context.cgContext)
            }
        } else {
            contentView.cacheDisplay(in: contentView.bounds, to: rep)
        }
        guard let data = rep.representation(using: .png, properties: [:]) else {
            print("PNG 인코딩 실패")
            exit(1)
        }
        do {
            try data.write(to: URL(fileURLWithPath: output))
            print("✓ \(output) (\(rep.pixelsWide)×\(rep.pixelsHigh)) · 저장된 연결 \(model.connections.count)개 · 로컬 항목 \(model.local.visibleItems.count)개")
            exit(0)
        } catch {
            print("쓰기 실패: \(error)")
            exit(1)
        }
    }
}


/// Redraws one subview into the capture through `cacheDisplay`, for views the
/// layer path renders wrong.
@MainActor
private func overlay(view: NSView, in contentView: NSView, context: CGContext) {
    guard view.superview != nil,
          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let image = rep.cgImage else { return }
    var rect = contentView.convert(view.bounds, from: view)
    if contentView.isFlipped {
        rect.origin.y = contentView.bounds.height - rect.maxY
    }
    // Paint over what the layer pass left there; the cached image is
    // transparent where the terminal background is. Resolved against the view's
    // own appearance — outside a drawing appearance this follows the system,
    // which paints a dark slab behind a light terminal.
    view.effectiveAppearance.performAsCurrentDrawingAppearance {
        context.setFillColor(NSColor.textBackgroundColor.cgColor)
        context.fill(rect)
    }
    context.draw(image, in: rect)
}

/// Sample rows for `--snapshot --view transfers`, so the queue's layout can be
/// inspected without a live server.
/// A fixed two-pane workspace for screenshots.
///
/// Everything here is invented. The snapshot mode otherwise renders the real
/// home directory and the real saved servers, which is fine while reviewing a
/// layout and wrong for an image that goes into the README.
private enum SampleWorkspace {
    private static func item(_ path: String, _ name: String, _ kind: FileItem.Kind,
                             _ size: UInt64, _ daysAgo: Double, _ owner: String,
                             _ mode: UInt32) -> FileItem {
        FileItem(path: path + "/" + name, name: name, kind: kind, size: size,
                 modified: Date(timeIntervalSince1970: 1_788_000_000 - daysAgo * 86_400),
                 permissions: mode, owner: owner)
    }

    @MainActor
    static func install(into model: AppModel) {
        var staging = Connection()
        staging.name = "Staging"
        staging.host = "staging.example.com"
        staging.username = "deploy"
        var production = Connection()
        production.name = "Production"
        production.host = "web-01.example.com"
        production.username = "deploy"
        model.connections = [staging, production]
        model.selectedConnectionID = production.id
        model.previewConnected(production.id, name: production.displayName)

        let local = "/Users/me/Projects/website"
        model.local.setPath(local, record: false)
        model.local.setItems([
            item(local, "assets", .directory, 0, 2, "me", 0o755),
            item(local, "build", .directory, 0, 0.2, "me", 0o755),
            item(local, "src", .directory, 0, 1, "me", 0o755),
            item(local, "deploy.sh", .file, 1_284, 3, "me", 0o755),
            item(local, "Dockerfile", .file, 640, 12, "me", 0o644),
            item(local, "index.html", .file, 4_918, 0.4, "me", 0o644),
            item(local, "logo.svg", .file, 12_004, 30, "me", 0o644),
            item(local, "package.json", .file, 2_140, 5, "me", 0o644),
            item(local, "README.md", .file, 8_760, 5, "me", 0o644),
            item(local, "release-4812.tar.gz", .file, 18_432_000, 0.1, "me", 0o644),
            item(local, "styles.css", .file, 22_310, 0.4, "me", 0o644),
        ])

        let remote = "/srv/app/releases"
        model.remote.setPath(remote, record: false)
        model.remote.setItems([
            item(remote, "current", .symlink, 0, 0.1, "deploy", 0o777),
            item(remote, "build-4810", .directory, 0, 9, "deploy", 0o755),
            item(remote, "build-4811", .directory, 0, 4, "deploy", 0o755),
            item(remote, "build-4812", .directory, 0, 0.1, "deploy", 0o755),
            item(remote, "deploy.log", .file, 96_320, 0.1, "deploy", 0o644),
            item(remote, "nginx.conf", .file, 3_180, 60, "root", 0o644),
            item(remote, "release-4812.tar.gz", .file, 18_432_000, 0.1, "deploy", 0o644),
            item(remote, "rollback.sh", .file, 2_048, 60, "root", 0o750),
        ])
        model.local.selection = [local + "/release-4812.tar.gz"]
        // The launch-time read of this invented path fails; the pane would then
        // show that error instead of the sample listing.
        model.local.error = nil
        model.remote.error = nil
        model.local.isLoading = false
        model.remote.isLoading = false

        model.showBottomPanel = true
        model.bottomTab = .transfers
        model.transfers = demoTransfers()
    }

    /// The queue the screenshot shows: one of each state, plausible names.
    private static func demoTransfers() -> [TransferItem] {
        var running = TransferItem(direction: .upload, displayName: "release-4812.tar.gz",
                                   source: "/l/a", destination: "/r/a", total: 18_432_000)
        running.state = .running
        running.transferred = 7_900_000
        running.startedAt = Date().addingTimeInterval(-4)

        var queued = TransferItem(direction: .upload, displayName: "assets/logo.svg",
                                  source: "/l/b", destination: "/r/b", total: 12_004)
        queued.state = .queued

        var done = TransferItem(direction: .download, displayName: "deploy.log",
                                source: "/r/c", destination: "/l/c", total: 96_320)
        done.state = .completed
        done.transferred = 96_320
        done.startedAt = Date().addingTimeInterval(-11)
        done.finishedAt = Date().addingTimeInterval(-9)

        return [running, queued, done]
    }
}

private enum SampleTransfers {
    /// Stand-in shell output, including colour, so the panel can be reviewed
    /// without a live server.
    static let shellOutput = """
    Last login: Wed Sep  3 14:02:11 2026 from 127.0.0.1\r
    \u{1b}[32mdeploy@web-01\u{1b}[0m:\u{1b}[34m~/srv/app\u{1b}[0m$ cd '/srv/app/releases'\r
    \u{1b}[32mdeploy@web-01\u{1b}[0m:\u{1b}[34m/srv/app/releases\u{1b}[0m$ tar xzf build-4812.tar.gz\r
    \u{1b}[32mdeploy@web-01\u{1b}[0m:\u{1b}[34m/srv/app/releases\u{1b}[0m$ ls -l\r
    total 24\r
    drwxr-xr-x  8 deploy deploy  4096 Sep  3 14:03 \u{1b}[1;34mbuild-4812\u{1b}[0m\r
    -rw-r--r--  1 deploy deploy 18432 Sep  3 14:02 build-4812.tar.gz\r
    \u{1b}[32mdeploy@web-01\u{1b}[0m:\u{1b}[34m/srv/app/releases\u{1b}[0m$ \u{1b}[7m \u{1b}[0m\r
    """

    static func make(count: Int = 5) -> [TransferItem] {
        var running = TransferItem(
            direction: .upload,
            displayName: "project/assets/images/very-long-file-name-that-should-truncate.psd",
            source: "/local/a", destination: "/remote/a", total: 48_000_000
        )
        running.state = .running
        running.transferred = 21_000_000
        running.startedAt = Date().addingTimeInterval(-6)

        var queued = TransferItem(
            direction: .upload,
            displayName: "project/assets/images/002.png",
            source: "/local/b", destination: "/remote/b", total: 2_400_000
        )
        queued.state = .queued

        var done = TransferItem(
            direction: .download,
            displayName: "logs/2026-09-02/application.log",
            source: "/remote/c", destination: "/local/c", total: 8_800_000
        )
        done.state = .completed
        done.transferred = 8_800_000
        done.startedAt = Date().addingTimeInterval(-12)
        done.finishedAt = Date().addingTimeInterval(-9)

        var failed = TransferItem(
            direction: .download,
            displayName: "backups/db.dump",
            source: "/remote/d", destination: "/local/d", total: 120_000_000
        )
        failed.state = .failed("권한이 없습니다: /local/d 에 쓸 수 없습니다")

        var cancelled = TransferItem(
            direction: .upload,
            displayName: "tmp/scratch.bin",
            source: "/local/e", destination: "/remote/e", total: 500_000
        )
        cancelled.state = .cancelled

        var pool = [failed, done, cancelled, queued, running]
        while pool.count < count {
            var extra = TransferItem(
                direction: .download,
                displayName: "logs/2026-09-02/rotated-\(pool.count).log",
                source: "/remote/x", destination: "/local/x", total: 1_000_000
            )
            extra.state = .completed
            extra.transferred = 1_000_000
            pool.insert(extra, at: 0)
        }
        return Array(pool.suffix(count))
    }
}
