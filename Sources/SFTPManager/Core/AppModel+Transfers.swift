import Foundation

/// Guarantees the conflict sheet resumes its continuation exactly once, however
/// it is dismissed.
@MainActor
final class ConflictResponder {
    private var continuation: CheckedContinuation<(ConflictChoice, Bool), Never>?

    init(_ continuation: CheckedContinuation<(ConflictChoice, Bool), Never>) {
        self.continuation = continuation
    }

    func resume(_ choice: ConflictChoice, _ applyToAll: Bool) {
        continuation?.resume(returning: (choice, applyToAll))
        continuation = nil
    }
}

extension AppModel {
    // MARK: - Enqueueing

    /// Transfers the given entries into the opposite pane's current directory.
    func startTransfer(direction: TransferDirection, items: [FileItem]) {
        let destination = direction == .upload ? remote.path : local.path
        startTransfer(direction: direction, items: items, into: destination)
    }

    func startTransfer(direction: TransferDirection, items: [FileItem], into destination: String) {
        guard !items.isEmpty else { return }
        guard session != nil else {
            alertMessage = L.connectFirst
            return
        }
        showBottomPanel = true
        bottomTab = .transfers
        Task { await enqueue(direction: direction, items: items, into: destination) }
    }

    private func enqueue(direction: TransferDirection, items: [FileItem], into destination: String) async {
        guard let session else { return }
        let existing = await existingItems(for: direction, in: destination)
        var taken = Set(existing.keys)
        var queued: [TransferItem] = []
        // nil means "ask about the next one too"; the sheet's apply-to-all fills it in.
        var batchPolicy: ConflictPolicy? = conflictPolicy == .ask ? nil : conflictPolicy

        for (index, item) in items.enumerated() {
            var name = item.name
            if taken.contains(name) {
                let policy: ConflictPolicy
                if let batchPolicy {
                    policy = batchPolicy
                } else {
                    let remaining = items[(index + 1)...].filter { taken.contains($0.name) }.count
                    let (choice, applyToAll) = await askAboutConflict(
                        direction: direction,
                        incoming: item,
                        existing: existing[name],
                        destination: destination,
                        renamedTo: Self.uniqueName(for: name, taken: taken),
                        remaining: remaining
                    )
                    switch choice {
                    case .cancel:
                        // Nothing queued so far is started either — the user
                        // asked to stop, not to half-transfer.
                        return
                    case .overwrite: policy = .overwrite
                    case .rename: policy = .rename
                    case .skip: policy = .skip
                    }
                    if applyToAll { batchPolicy = policy }
                }
                switch policy {
                case .skip: continue
                case .rename: name = Self.uniqueName(for: name, taken: taken)
                case .overwrite, .ask: break
                }
            }
            taken.insert(name)
            // Never write outside the folder the user picked, whatever the other
            // side called the entry.
            guard let target = PathUtil.containedJoin(destination, name) else {
                queued.append(Self.rejected(direction: direction, name: item.name, source: item.path))
                continue
            }

            if item.isDirectory {
                do {
                    let entries = try await expandDirectory(direction: direction, source: item.path, target: target, session: session)
                    queued.append(contentsOf: entries)
                } catch {
                    alertMessage = L.readFolderFailed(item.name, Self.describe(error))
                }
            } else {
                let size = direction == .upload ? LocalFileSystem.size(of: item.path) : item.size
                queued.append(TransferItem(
                    direction: direction,
                    displayName: name,
                    source: item.path,
                    destination: target,
                    total: size
                ))
            }
        }

        guard !queued.isEmpty else { return }
        transfers.append(contentsOf: queued)
        pumpTransfers()
    }

    /// Mirrors a directory tree on the destination side and returns one queue
    /// entry per file inside it.
    private func expandDirectory(
        direction: TransferDirection,
        source: String,
        target: String,
        session: SFTPSession
    ) async throws -> [TransferItem] {
        var result: [TransferItem] = []
        let rootName = PathUtil.lastComponent(of: target)

        switch direction {
        case .upload:
            try? await session.makeDirectory(target)
            let tree = try await Task.detached(priority: .userInitiated) { () -> [(String, Bool, UInt64)] in
                var out: [(String, Bool, UInt64)] = []
                var queue = [(source, "")]
                while let (absolute, relative) = queue.first {
                    queue.removeFirst()
                    for child in try LocalFileSystem.list(absolute) {
                        let childRelative = relative.isEmpty ? child.name : relative + "/" + child.name
                        if child.isDirectory {
                            out.append((childRelative, true, 0))
                            queue.append((child.path, childRelative))
                        } else {
                            out.append((childRelative, false, LocalFileSystem.size(of: child.path)))
                        }
                    }
                }
                return out
            }.value
            for (relative, isDirectory, size) in tree {
                guard let destinationPath = PathUtil.containedJoin(target, relative) else {
                    result.append(Self.rejected(direction: .upload, name: relative,
                                                source: PathUtil.join(source, relative)))
                    continue
                }
                if isDirectory {
                    try? await session.makeDirectory(destinationPath)
                } else {
                    result.append(TransferItem(
                        direction: .upload,
                        displayName: rootName + "/" + relative,
                        source: PathUtil.join(source, relative),
                        destination: destinationPath,
                        total: size
                    ))
                }
            }

        case .download:
            try? FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
            let tree = try await session.walk(source)
            for entry in tree {
                guard let destinationPath = PathUtil.containedJoin(target, entry.relativePath) else {
                    result.append(Self.rejected(direction: .download, name: entry.relativePath,
                                                source: PathUtil.join(source, entry.relativePath)))
                    continue
                }
                if entry.isDirectory {
                    try? FileManager.default.createDirectory(atPath: destinationPath, withIntermediateDirectories: true)
                } else {
                    result.append(TransferItem(
                        direction: .download,
                        displayName: rootName + "/" + entry.relativePath,
                        source: PathUtil.join(source, entry.relativePath),
                        destination: destinationPath,
                        total: entry.size
                    ))
                }
            }
        }
        return result
    }

    /// A queue row for an entry whose name would have escaped the destination.
    /// Shown as a failure rather than dropped, so it is never silent.
    nonisolated static func rejected(direction: TransferDirection, name: String, source: String) -> TransferItem {
        var item = TransferItem(
            direction: direction,
            displayName: name,
            source: source,
            destination: "",
            total: 0
        )
        item.state = .failed(L.escapedDestination)
        return item
    }

    /// What is already at the destination, by name — kept as whole entries so
    /// the conflict sheet can show sizes and dates side by side.
    private func existingItems(for direction: TransferDirection, in destination: String) async -> [String: FileItem] {
        let items: [FileItem]
        switch direction {
        case .upload:
            guard let session else { return [:] }
            items = (try? await session.list(destination)) ?? []
        case .download:
            items = (try? LocalFileSystem.list(destination)) ?? []
        }
        return Dictionary(items.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The name the keep-both choice would use: `report 2.pdf`, then `report 3.pdf`.
    nonisolated static func uniqueName(for name: String, taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }
        let url = URL(fileURLWithPath: name)
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            if !taken.contains(candidate) { return candidate }
            index += 1
        }
    }

    /// Puts the question on screen and waits for the answer.
    private func askAboutConflict(
        direction: TransferDirection,
        incoming: FileItem,
        existing: FileItem?,
        destination: String,
        renamedTo: String,
        remaining: Int
    ) async -> (ConflictChoice, Bool) {
        await withCheckedContinuation { continuation in
            let responder = ConflictResponder(continuation)
            conflictRequest = ConflictRequest(
                direction: direction,
                incoming: incoming,
                existing: existing,
                destination: destination,
                renamedTo: renamedTo,
                remaining: remaining,
                respond: { [weak self] choice, applyToAll in
                    self?.conflictRequest = nil
                    responder.resume(choice, applyToAll)
                }
            )
        }
    }

    // MARK: - Running

    func pumpTransfers() {
        guard transferWorker == nil else { return }
        transferWorker = Task { @MainActor [weak self] in
            while let self, let next = self.transfers.first(where: { $0.state == .queued }) {
                await self.run(next.id)
            }
            self?.transferWorker = nil
            self?.finishBatch()
        }
    }

    private func run(_ id: UUID) async {
        guard let session, let index = transfers.firstIndex(where: { $0.id == id }) else { return }
        let item = transfers[index]
        transfers[index].state = .running
        transfers[index].startedAt = Date()

        let throttle = ProgressThrottle()
        let progress: @Sendable (UInt64) -> Void = { [weak self] bytes in
            guard throttle.shouldPublish() else { return }
            Task { @MainActor in self?.update(id) { $0.transferred = bytes } }
        }

        let task = Task<Void, Error> {
            switch item.direction {
            case .upload:
                try await session.upload(localPath: item.source, to: item.destination, progress: progress)
            case .download:
                try await session.download(remotePath: item.source, to: item.destination, progress: progress)
            }
        }
        runningTransfer = (id, task)
        defer { runningTransfer = nil }

        var outcome: TransferState = .completed
        do {
            try await task.value
            update(id) {
                $0.transferred = $0.total
                $0.state = .completed
                $0.finishedAt = Date()
            }
        } catch is CancellationError {
            outcome = .cancelled
            update(id) {
                $0.state = .cancelled
                $0.finishedAt = Date()
            }
        } catch {
            outcome = .failed(Self.describe(error))
            update(id) {
                $0.state = outcome
                $0.finishedAt = Date()
            }
        }
        noteTransferFinished(id, state: outcome)
    }

    private func update(_ id: UUID, _ mutate: (inout TransferItem) -> Void) {
        guard let index = transfers.firstIndex(where: { $0.id == id }) else { return }
        mutate(&transfers[index])
    }

    private func finishBatch() {
        let failed = transfers.filter {
            if case .failed = $0.state { return true }
            return false
        }.count
        announceTransfersFinished(failed: failed)
        Task {
            await refresh(.remote)
            await refresh(.local)
        }
    }

    // MARK: - Queue control

    func cancelTransfer(_ id: UUID) {
        if runningTransfer?.id == id {
            runningTransfer?.task.cancel()
        } else {
            update(id) { item in
                if item.state == .queued { item.state = .cancelled }
            }
        }
    }

    func cancelAllTransfers() {
        runningTransfer?.task.cancel()
        for index in transfers.indices where transfers[index].state == .queued {
            transfers[index].state = .cancelled
        }
    }

    func clearFinishedTransfers() {
        transfers.removeAll { $0.state.isFinished }
    }

    func retryTransfer(_ id: UUID) {
        update(id) { item in
            item.transferred = 0
            item.startedAt = nil
            item.finishedAt = nil
            item.state = .queued
        }
        pumpTransfers()
    }

    // MARK: - Summary

    var activeTransferCount: Int {
        transfers.filter { !$0.state.isFinished }.count
    }

    var overallProgress: Double {
        let active = transfers.filter { !$0.state.isFinished || $0.state == .completed }
        let total = active.reduce(UInt64(0)) { $0 + $1.total }
        guard total > 0 else { return 0 }
        let done = active.reduce(UInt64(0)) { $0 + $1.transferred }
        return min(1, Double(done) / Double(total))
    }
}
