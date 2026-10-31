import Foundation
import LocalFiles
import PeerCore

/// One directory owns its watcher, coalesced changes, scan task and scoped access together.
@MainActor
final class DirectoryMonitor {
    let source: DirectorySource
    private let target: ConnectionTarget
    private let context: PeerHostContext
    private let root: URL
    private var scoped: Bool
    private let onState: (String, Bool) -> Void
    private let onSources: ([DirectorySource]) -> Void
    private var watcher: DirectoryWatcher?
    private var task: Task<Void, Never>?
    private var stopped = false
    private var needsScan = false
    typealias Scan =
        @Sendable (
            DirectorySource, LocalFileClient, SourceJob?,
            @escaping @Sendable (ScanProgress) async -> Void
        ) async throws -> DirectoryState
    private let scan: Scan

    init(
        source: DirectorySource, target: ConnectionTarget, context: PeerHostContext,
        bookmark: Data, onBookmarkRenewed: (Data) throws -> Void,
        onState: @escaping (String, Bool) -> Void,
        onSources: @escaping ([DirectorySource]) -> Void,
        scan: @escaping Scan = { source, client, job, progress in
            try await DirectoryScanner.scan(
                source: source, client: client, job: job, progress: progress)
        }
    ) throws {
        self.source = source
        self.target = target
        self.context = context
        self.onState = onState
        self.onSources = onSources
        self.scan = scan
        var stale = false
        root = try URL(
            resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
            relativeTo: nil, bookmarkDataIsStale: &stale)
        guard
            root.resolvingSymlinksInPath().path
                == URL(fileURLWithPath: source.config.path).resolvingSymlinksInPath().path
        else { throw PeerError.needsAction("目录位置已改变，请重新选择目录。") }
        scoped = root.startAccessingSecurityScopedResource()
        do {
            if stale {
                try onBookmarkRenewed(
                    root.bookmarkData(
                        options: [.withSecurityScope], includingResourceValuesForKeys: nil,
                        relativeTo: nil))
            }
            watcher = try DirectoryWatcher(path: root.path) { [weak self] in self?.schedule() }
        } catch {
            if scoped { root.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    func stop() async {
        stopped = true
        watcher?.stop()
        watcher = nil
        task?.cancel()
        // Every caller waits for the same scan before scoped access is released.
        await task?.value
        if scoped {
            scoped = false
            root.stopAccessingSecurityScopedResource()
        }
    }

    func schedule() {
        guard !stopped, !Task.isCancelled else { return }
        needsScan = true
        refresh()
    }

    /// Poll shared work and retry failed reconciliation without exposing scheduling state.
    func refresh() {
        guard !stopped, !Task.isCancelled, task == nil else { return }
        task = Task {
            var status = ""
            defer {
                task = nil
                if !stopped, !status.isEmpty { onState(status, false) }
            }
            guard !stopped, !Task.isCancelled else { return }
            while !stopped, !Task.isCancelled {
                var job: SourceJob?
                let client: LocalFileClient
                do {
                    let connection = try await context.connections.resolve(target)
                    client = LocalFileClient(
                        target: connection,
                        password: try context.credentials.read(for: connection.id)
                    )
                } catch {
                    status = error.localizedDescription
                    needsScan = true
                    break
                }
                do {
                    let pending = try await client.pendingScans(source)
                    try Task.checkCancellation()
                    guard needsScan || !pending.isEmpty else { break }
                    needsScan = false
                    onState("正在扫描…", true)
                    for candidate in pending {
                        if let claimed = try await client.claim(candidate, source: source) {
                            job = claimed
                            break
                        }
                    }
                    let state = try await scan(source, client, job) { [weak self] progress in
                        await self?.report(progress)
                    }
                    try Task.checkCancellation()
                    if let job {
                        try await client.close(
                            job, status: state.errors == 0 ? "finished" : "failed", state: state)
                    }
                    status = state.errors == 0 ? "正在监视" : "\(state.errors) 个文件需要处理"
                    let updated = try await client.sources()
                    if !stopped, !Task.isCancelled { onSources(updated) }
                } catch {
                    status =
                        PeerDatabase.isCancellation(error)
                        ? "扫描已停止" : PeerDatabase.failure(error).localizedDescription
                    if !PeerDatabase.isCancellation(error), !stopped {
                        do { try await client.reportIssue(status, source: source) } catch {
                            status += "；状态暂未写回信息库"
                        }
                    }
                    if let job, !Task.isCancelled, !stopped {
                        let terminal =
                            Date() >= job.deadline
                            ? "timed_out"
                            : PeerDatabase.isCancellation(error) ? "aborted" : "failed"
                        do {
                            try await client.close(
                                job, status: terminal, state: DirectoryState(issue: status))
                        } catch {
                            status += "；任务终态待信息库核对"
                        }
                    }
                    // Reconnection reconciles current files, without an outbox.
                    needsScan = true
                    break
                }
            }
        }
    }

    private func report(_ progress: ScanProgress) {
        guard !stopped else { return }
        onState("\(progress.completed)/\(progress.total) · \(progress.filename)", true)
    }
}
