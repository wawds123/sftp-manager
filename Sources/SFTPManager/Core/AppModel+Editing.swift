import Foundation
import AppKit

extension AppModel {
    var editsRoot: String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SFTPManager/edits", isDirectory: true)
        return support.path
    }

    /// Downloads a remote file to a scratch copy, opens it, and watches it.
    func editRemoteFile(_ item: FileItem) {
        guard let session else {
            alertMessage = L.connectFirst
            return
        }
        guard !item.isDirectory else { return }
        if let existing = edits.first(where: { $0.remotePath == item.path }) {
            NSWorkspace.shared.open(URL(fileURLWithPath: existing.localPath))
            return
        }

        let scratch = editsRoot + "/" + UUID().uuidString
        // The name comes from the server; it must not lead out of the scratch
        // folder, which is then handed to NSWorkspace to open.
        guard let localPath = PathUtil.containedJoin(scratch, item.name) else {
            alertMessage = L.editNameInvalid(item.name)
            return
        }
        let edit = RemoteEdit(
            remotePath: item.path,
            localPath: localPath,
            name: item.name,
            scratchDirectory: scratch
        )
        edits.append(edit)
        let id = edit.id

        Task {
            do {
                try FileManager.default.createDirectory(atPath: scratch, withIntermediateDirectories: true)
                try await session.download(remotePath: item.path, to: localPath) { _ in }
                updateEdit(id) {
                    $0.lastSeen = FileSignature.read(localPath)
                    $0.uploaded = $0.lastSeen
                    $0.status = .watching
                }
                NSWorkspace.shared.open(URL(fileURLWithPath: localPath))
                startEditWatcher()
            } catch {
                edits.removeAll { $0.id == id }
                try? FileManager.default.removeItem(atPath: scratch)
                alertMessage = L.editDownloadFailed(item.name, Self.describe(error))
            }
        }
    }

    func openEditLocally(_ edit: RemoteEdit) {
        NSWorkspace.shared.open(URL(fileURLWithPath: edit.localPath))
    }

    func revealEditInFinder(_ edit: RemoteEdit) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: edit.localPath)])
    }

    func stopEditing(_ edit: RemoteEdit) {
        edits.removeAll { $0.id == edit.id }
        try? FileManager.default.removeItem(atPath: edit.scratchDirectory)
        if edits.isEmpty { stopEditWatcher() }
    }

    func stopAllEditing() {
        for edit in edits {
            try? FileManager.default.removeItem(atPath: edit.scratchDirectory)
        }
        edits.removeAll()
        stopEditWatcher()
    }

    // MARK: - Watching

    /// Polls rather than using a vnode watch on purpose: many editors save by
    /// writing a new file and renaming it over the original, which kills a
    /// file-descriptor-based watch.
    func startEditWatcher() {
        guard editWatcher == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: editPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollEdits() }
        }
        timer.tolerance = 0.3
        editWatcher = timer
    }

    /// Picks up a changed poll interval without waiting for the next edit.
    func restartEditWatcher() {
        guard editWatcher != nil else { return }
        stopEditWatcher()
        startEditWatcher()
    }

    func stopEditWatcher() {
        editWatcher?.invalidate()
        editWatcher = nil
    }

    private func pollEdits() {
        guard !edits.isEmpty else {
            stopEditWatcher()
            return
        }
        for edit in edits {
            let current = FileSignature.read(edit.localPath)
            switch edit.pollAction(current: current) {
            case .ignore:
                continue
            case .record:
                updateEdit(edit.id) { $0.lastSeen = current }
            case .upload:
                updateEdit(edit.id) { $0.lastSeen = current }
                uploadEdit(edit.id)
            }
        }
    }

    /// Sends the scratch copy back, through the transfer queue so it shows up
    /// with the user's other transfers.
    func uploadEdit(_ id: UUID) {
        guard let edit = edits.first(where: { $0.id == id }) else { return }
        guard session != nil else {
            updateEdit(id) { $0.status = .failed(L.editUploadDisconnected) }
            return
        }
        let transfer = TransferItem(
            direction: .upload,
            displayName: L.editNamePrefix(edit.name),
            source: edit.localPath,
            destination: edit.remotePath,
            total: LocalFileSystem.size(of: edit.localPath)
        )
        updateEdit(id) {
            $0.status = .uploading
            $0.transferID = transfer.id
        }
        // Appended directly rather than through `startTransfer`, which would
        // apply the conflict policy — an edit must always overwrite its source.
        transfers.append(transfer)
        showBottomPanel = true
        bottomTab = .transfers
        pumpTransfers()
    }

    /// Called by the transfer worker so an edit can reflect its upload's result.
    func noteTransferFinished(_ transferID: UUID, state: TransferState) {
        guard let edit = edits.first(where: { $0.transferID == transferID }) else { return }
        switch state {
        case .completed:
            updateEdit(edit.id) {
                $0.status = .watching
                $0.uploaded = FileSignature.read(edit.localPath)
                $0.lastSeen = $0.uploaded
                $0.uploadCount += 1
                $0.lastUploadedAt = Date()
                $0.transferID = nil
            }
        case .failed(let message):
            updateEdit(edit.id) {
                $0.status = .failed(message)
                $0.transferID = nil
            }
        default:
            updateEdit(edit.id) {
                $0.status = .watching
                $0.transferID = nil
            }
        }
    }

    /// Puts a failed edit back into the watching state so a further save retries.
    func resumeEditing(_ edit: RemoteEdit) {
        updateEdit(edit.id) { $0.status = .watching }
        startEditWatcher()
    }

    private func updateEdit(_ id: UUID, _ mutate: (inout RemoteEdit) -> Void) {
        guard let index = edits.firstIndex(where: { $0.id == id }) else { return }
        mutate(&edits[index])
    }
}
