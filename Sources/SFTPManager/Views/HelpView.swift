import SwiftUI

/// The Help window: topics on the left, the selected topic on the right.
///
/// A plain `HStack` rather than a `NavigationSplitView` — the split view needs a
/// real window controller and renders as an empty page in the offscreen
/// `--snapshot` harness, which would leave this window unverifiable.
struct HelpView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selected: String

    init(topic: String? = nil) {
        _selected = State(initialValue: topic ?? HelpBook.topics.first?.id ?? "")
    }

    private var topics: [HelpBook.Topic] { HelpBook.topics }

    private var current: HelpBook.Topic? {
        topics.first { $0.id == selected } ?? topics.first
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .navigationTitle(L.menuHelp)
        .frame(minWidth: 720, minHeight: 460)
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(topics) { topic in
                    Button {
                        selected = topic.id
                    } label: {
                        Label(topic.title, systemImage: topic.symbol)
                            .font(.callout)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(topic.id == selected ? Color.accentColor : .clear)
                            )
                            .foregroundStyle(topic.id == selected ? Color.white : Color.primary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
        .frame(width: 196)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var detail: some View {
        if let topic = current {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(topic.title)
                        .font(.title2.weight(.semibold))
                    ForEach(topic.entries) { entry in
                        entryRow(entry)
                    }
                }
                .frame(maxWidth: 540, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Scrolls back to the top when another topic is picked.
            .id(topic.id)
        }
    }

    private func entryRow(_ entry: HelpBook.Entry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if let term = entry.term {
                    Text(term).font(.headline)
                }
                // `.init` so `code` and **bold** inside the text render.
                Text(.init(entry.detail))
                    .font(.callout)
                    .foregroundStyle(entry.term == nil ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let shortcut = entry.shortcut {
                Text(shortcut)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.primary.opacity(0.12))
                    )
                    .layoutPriority(1)
            }
        }
    }
}
