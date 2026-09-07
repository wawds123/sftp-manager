import SwiftUI

/// The queue itself. The surrounding chrome (tabs, buttons, collapse) belongs to
/// `BottomPanelView`, which shares this space with the terminal.
struct TransferQueueView: View {
    static let rowHeight: CGFloat = 42

    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.transfers.isEmpty {
            Text(L.emptyQueue)
                .font(Style.callout)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // A ScrollView, not a List: `List` reports an ideal height as
            // tall as its contents, so inside a split pane it grew past the
            // window instead of scrolling. A ScrollView takes the height it
            // is offered and scrolls the overflow.
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.transfers.reversed().enumerated()), id: \.element.id) { index, item in
                        TransferRow(item: item)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.04))
                            .contentShape(Rectangle())
                            .contextMenu {
                                if item.state == .queued || item.state == .running {
                                    Button(L.cancel) { model.cancelTransfer(item.id) }
                                } else {
                                    Button(L.retry) { model.retryTransfer(item.id) }
                                }
                            }
                    }
                }
            }
        }
    }
}

private struct TransferRow: View {
    let item: TransferItem

    private var stateColor: Color {
        switch item.state {
        case .completed: return .green
        case .failed: return .red
        case .cancelled, .skipped: return .orange
        case .running: return .accentColor
        case .queued: return .secondary
        }
    }

    private var stateText: String {
        switch item.state {
        case .queued: return L.queued
        case .running: return "\(ByteFormat.string(item.transferred)) / \(ByteFormat.string(item.total)) · \(ByteFormat.rate(item.throughput))"
        case .completed: return L.completed(ByteFormat.string(item.total))
        case .skipped: return L.skipped
        case .cancelled: return L.cancelled
        case .failed(let message): return message
        }
    }

    private var percent: String {
        "\(Int((item.fraction * 100).rounded()))%"
    }

    private var stateIcon: String {
        switch item.state {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled, .skipped: return "minus.circle.fill"
        default: return item.direction.symbol
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: stateIcon)
                .foregroundStyle(stateColor)
                // A fixed slot, so a checkmark and a warning triangle leave the
                // names under them at the same x.
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(Style.itemName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(stateText)
                    .font(Style.footnote)
                    .foregroundStyle(item.state == .running ? .secondary : stateColor.opacity(0.9))
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if item.state == .running {
                HStack(spacing: 8) {
                    ProgressView(value: item.fraction)
                    // The bar alone makes people estimate; the number is what
                    // they were estimating.
                    Text(percent)
                        .font(Style.footnote)
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                .frame(width: 140)
            } else {
                Text(item.direction.label)
                    .font(Style.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 140, alignment: .trailing)
            }
        }
    }
}
