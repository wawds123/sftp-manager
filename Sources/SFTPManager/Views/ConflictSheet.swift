import SwiftUI

/// Asks what to do about a name that already exists on the far side.
///
/// Every button answers the waiting transfer, so the sheet must never close
/// without one — dismissing it counts as 취소.
struct ConflictSheet: View {
    let request: ConflictRequest

    @State private var applyToAll = false
    @State private var answered = false

    private var isDirectory: Bool { request.incoming.isDirectory }

    private var headline: String {
        isDirectory ? L.conflictFolderHeadline : L.conflictFileHeadline
    }

    private var whereText: String {
        let side = request.direction == .upload ? L.remote : L.local
        return "\(side) · \(request.destination)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline).font(.headline)
                    Text(request.name)
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text(whereText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            if !isDirectory {
                HStack(alignment: .top, spacing: 0) {
                    detail(L.conflictIncoming, request.incoming)
                    Divider().frame(height: 40)
                    detail(L.conflictExisting, request.existing)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }

            if request.remaining > 0 {
                Toggle(L.conflictApplyToRest(request.remaining), isOn: $applyToAll)
                    .toggleStyle(.checkbox)
            }

            HStack(spacing: 8) {
                Button(L.cancel) { answer(.cancel) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L.conflictSkip) { answer(.skip) }
                Button(L.conflictRename) { answer(.rename) }
                    .help(L.conflictRenameHelp(request.renamedTo))
                Button(L.conflictOverwrite) { answer(.overwrite) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        // Esc or any other dismissal must still free the waiting transfer.
        .onDisappear { answer(.cancel) }
    }

    private func detail(_ title: String, _ item: FileItem?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let item {
                Text(ByteFormat.string(item.size)).font(.callout)
                Text(item.modified.map { Self.dateFormatter.string(from: $0) } ?? L.modifiedUnknown)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(L.unknown).font(.callout).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    private func answer(_ choice: ConflictChoice) {
        guard !answered else { return }
        answered = true
        request.respond(choice, applyToAll)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yy-MM-dd HH:mm"
        return f
    }()
}
