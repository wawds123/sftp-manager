import SwiftUI
import AppKit

struct ConnectionSidebar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $model.selectedConnectionID) {
                Section(L.servers) {
                    ForEach(model.connections) { connection in
                        ConnectionRow(
                            connection: connection,
                            isActive: model.activeConnectionID == connection.id
                        )
                        .contentShape(Rectangle())
                        // A List row that carries its own tap gesture loses the
                        // built-in click-to-select, so selection is driven here.
                        .simultaneousGesture(TapGesture(count: 1).onEnded {
                            model.selectedConnectionID = connection.id
                        })
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            model.selectedConnectionID = connection.id
                            model.requestSession(for: connection.id)
                        })
                        .contextMenu {
                            if model.isConnected(to: connection.id) {
                                Button(L.disconnect) { model.disconnect() }
                            } else {
                                Button(L.connect) { model.requestSession(for: connection.id) }
                            }
                            Button(L.edit) { model.editingConnection = connection }
                            Divider()
                            Button(L.delete, role: .destructive) { model.deleteConnection(connection.id) }
                        }
                        .tag(connection.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if model.connections.isEmpty {
                    ContentUnavailableView {
                        Label(L.noServers, systemImage: "server.rack")
                    } description: {
                        Text(L.noServersDetail)
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button { model.newConnection() } label: {
                    Image(systemName: "plus")
                }
                .help(L.addServer)

                Button { model.editSelectedConnection() } label: {
                    Image(systemName: "pencil")
                }
                .disabled(model.selectedConnectionID == nil)
                .help(L.editServer)

                Button {
                    if let id = model.selectedConnectionID { model.deleteConnection(id) }
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(model.selectedConnectionID == nil)
                .help(L.deleteServer)

                Spacer()

                // The selected server is already the live one: offer the only
                // thing left to do with it rather than a second Connect.
                if model.isConnected(to: model.selectedConnectionID) {
                    Button {
                        model.disconnect()
                    } label: {
                        Label(L.disconnect, systemImage: "bolt.slash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button {
                        if let id = model.selectedConnectionID { model.requestSession(for: id) }
                    } label: {
                        Label(L.connect, systemImage: "bolt.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.selectedConnectionID == nil || model.status.isBusy)
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }
}

private struct ConnectionRow: View {
    let connection: Connection
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isActive ? "bolt.horizontal.circle.fill" : "server.rack")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? Color.green : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(connection.displayName)
                    .font(Style.itemName)
                    .lineLimit(1)
                Text(connection.subtitle)
                    .font(Style.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}
