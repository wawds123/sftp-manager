import SwiftUI
import AppKit

struct ConnectionEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Connection
    private let isNew: Bool

    init(connection: Connection) {
        _draft = State(initialValue: connection)
        isNew = connection.host.isEmpty && connection.name.isEmpty
    }

    private var secretNote: String {
        switch draft.authMethod {
        case .password:
            return L.passwordNotStoredNote
        case .privateKey, .agentKeyFile:
            return L.passphraseNotStoredNote
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isNew ? L.newServer : L.editServerTitle)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Form {
                Section {
                    TextField(L.fieldName, text: $draft.name, prompt: Text(L.fieldNamePrompt))
                    TextField(L.fieldHost, text: $draft.host, prompt: Text("example.com"))
                    TextField(L.fieldPort, value: $draft.port, format: .number.grouping(.never))
                    TextField(L.fieldUser, text: $draft.username)
                }

                Section(L.sectionAuth) {
                    Picker(L.authMethod, selection: $draft.authMethod) {
                        ForEach(AuthMethod.selectable) { method in
                            Text(method.label).tag(method)
                        }
                        // A legacy profile keeps its own tag so the picker has
                        // something to show instead of falling back to blank.
                        if draft.authMethod == .agentKeyFile {
                            Text(AuthMethod.agentKeyFile.label).tag(AuthMethod.agentKeyFile)
                        }
                    }
                    if draft.authMethod.usesPrivateKey {
                        HStack {
                            TextField(L.privateKeyPath, text: $draft.privateKeyPath, prompt: Text("~/.ssh/id_ed25519"))
                            Button(L.choose) { pickKeyFile() }
                        }
                    }
                    Label(secretNote, systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(L.sectionStartPaths) {
                    TextField(L.remotePath, text: $draft.remoteStartPath, prompt: Text(L.remotePathPrompt))
                    HStack {
                        TextField(L.localPath, text: $draft.localStartPath, prompt: Text(L.localPathPrompt))
                        Button(L.choose) { pickLocalFolder() }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if !isNew {
                    Button(L.delete, role: .destructive) {
                        model.deleteConnection(draft.id)
                        dismiss()
                    }
                }
                Spacer()
                Button(L.cancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L.save) {
                    model.save(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.host.trimmingCharacters(in: .whitespaces).isEmpty
                          || draft.username.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 480, height: 540)
    }

    private func pickKeyFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh")
        if panel.runModal() == .OK, let url = panel.url {
            draft.privateKeyPath = url.path
        }
    }

    private func pickLocalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            draft.localStartPath = url.path
        }
    }
}

struct PromptSheet: View {
    let request: PromptRequest
    @Environment(\.dismiss) private var dismiss
    @State private var value: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(request.title)
                .font(.headline)
            if !request.message.isEmpty {
                Text(request.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let placeholder = request.placeholder {
                Group {
                    if request.isSecret {
                        SecureField(placeholder, text: $value)
                    } else {
                        TextField(placeholder, text: $value)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit(confirm)
            }
            HStack {
                Spacer()
                Button(L.cancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(request.confirmTitle, role: request.destructive ? .destructive : nil, action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(request.placeholder != nil && value.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            value = request.initialValue
            fieldFocused = true
        }
    }

    private func confirm() {
        request.action(value)
        dismiss()
    }
}
