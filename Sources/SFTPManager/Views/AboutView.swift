import SwiftUI
import AppKit

/// Who made this, what it is, and what it is built on.
struct AboutView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var copiedEmail = false

    /// The one place the author is written down in code; `Info.plist` carries
    /// the same line for the Finder's Get Info panel.
    static let authorName = "jackson"
    static let authorEmail = "wawds123@gmail.com"

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1"
    }

    private var icon: NSImage? {
        NSImage(named: "AppIcon") ?? NSApp?.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 84, height: 84)
                } else {
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .font(.system(size: 60))
                        .foregroundStyle(.tint)
                }
                Text("SFTP Manager")
                    .font(.title2.weight(.semibold))
                Text("\(L.version) \(Self.version)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(L.aboutTagline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 20)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                row(L.madeBy) {
                    HStack(spacing: 6) {
                        Text(Self.authorName)
                        Text(Self.authorEmail)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button {
                            copyEmail()
                        } label: {
                            Image(systemName: copiedEmail ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help(L.copyEmail)
                    }
                }
                row(L.builtWith) {
                    Text("Swift 6 · SwiftUI · Citadel · SwiftTerm")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .font(.callout)
            .padding(.horizontal, 28)
            .padding(.vertical, 18)

            Divider()

            HStack {
                Button(L.openHelpFromAbout) { openWindow(id: "help") }
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
        }
        // No fixed width here: this view is both a standalone window (sized by
        // the scene) and a tab in the 560pt Settings window.
        .frame(maxWidth: .infinity)
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .trailing)
            content()
            Spacer(minLength: 0)
        }
    }

    private func copyEmail() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.authorEmail, forType: .string)
        copiedEmail = true
        // Long enough to read the checkmark, short enough to not look stuck.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedEmail = false }
    }
}
