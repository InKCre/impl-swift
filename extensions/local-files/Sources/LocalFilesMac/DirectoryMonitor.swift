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
    private(set) var needsScan = false
    var isScanning: Bool { task != nil }

    init(
        source: DirectorySource, target: ConnectionTarget, context: PeerHostContext,
        root: URL, scoped: Bool,
        onState: @escaping (String, Bool) -> Void,
        onSources: @escaping ([DirectorySource]) -> Void
    ) throws {
        self.source = source
        self.target = target
        self.context = context
        self.root = root
        self.scoped = scoped
        self.onState = onState
        self.onSources = onSources
        watcher = try DirectoryWatcher(path: root.path) { [weak self] in self?.schedule() }
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
        guard task == nil else { return }
        task = Task {
            var status = "正在扫描…"
            defer {
                task = nil
                if !stopped { onState(status, false) }
            }
            guard !stopped, !Task.isCancelled else { return }
            onState(status, true)
            while needsScan, !stopped, !Task.isCancelled {
                needsScan = false
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
                    for candidate in pending {
                        if let claimed = try await client.claim(candidate, source: source) {
                            job = claimed
                            break
                        }
                    }
                    let state = try await DirectoryScanner.scan(
                        source: source, client: client, job: job
                    ) { [weak self] progress in
                        await self?.report(progress)
                    }
                    if let job {
                        try await client.close(
                            job, status: state.errors == 0 ? "finished" : "failed", state: state)
                    }
                    status = state.errors == 0 ? "正在监视" : "\(state.errors) 个文件需要处理"
                    let updated = try await client.sources()
                    if !stopped, !Task.isCancelled { onSources(updated) }
                    if !(try await client.pendingScans(source)).isEmpty { needsScan = true }
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
