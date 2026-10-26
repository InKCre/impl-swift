import Foundation
import PeerCore

public actor CaptureQueue {
    private let store: CaptureStore
    private let connections: ConnectionSettings
    private let credentials: CredentialStore
    private let client: any CaptureTransport
    private var running = false
    public private(set) var isStopped = false
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        store: CaptureStore, connections: ConnectionSettings, credentials: CredentialStore,
        client: any CaptureTransport = CaptureClient()
    ) {
        self.connections = connections
        self.store = store
        self.credentials = credentials
        self.client = client
    }

    public func resume() { isStopped = false }
    public func stop() async {
        isStopped = true
        if running { await withCheckedContinuation { idleWaiters.append($0) } }
    }

    @discardableResult
    public func process(force: Bool = false) async throws -> Bool {
        guard !isStopped, !Task.isCancelled, !running else { return false }
        running = true
        defer {
            running = false
            for waiter in idleWaiters { waiter.resume() }
            idleWaiters.removeAll()
        }
        let groups = Dictionary(grouping: try await store.pendingRecords()) { $0.target?.id }
        return try await withThrowingTaskGroup(of: Bool.self) { group in
            for records in groups.values {
                group.addTask { try await self.process(records, force: force) }
            }
            var changed = false
            for try await result in group { changed = changed || result }
            return changed
        }
    }

    private func process(_ records: [CaptureRecord], force: Bool) async throws -> Bool {
        var changed = false
        for item in records {
            guard !isStopped, !Task.isCancelled else { return changed }
            let delay = min(300.0, pow(2.0, Double(min(item.attempts, 8))) * 2)
            if !force && item.attempts > 0 && Date().timeIntervalSince(item.updatedAt) < delay {
                continue
            }
            guard let target = item.target else { continue }
            do {
                let connection = try await connections.resolve(target)
                let secret = try credentials.read(for: connection.id)
                var outgoing = item
                outgoing.target = connection
                if item.attempts > 0,
                    let result = try await client.recover(outgoing, secret: secret)
                {
                    try await store.confirm(item.id, result: result)
                    changed = true
                    continue
                }
                guard !isStopped, !Task.isCancelled else { return changed }
                var dispatched = try await store.markDispatch(item.id)
                dispatched.target = connection
                changed = true
                guard !isStopped, !Task.isCancelled else { return changed }
                let result = try await client.submit(dispatched, secret: secret)
                try await store.confirm(item.id, result: result)
            } catch let error as PeerError {
                let state: CaptureRecord.State
                switch error {
                case .needsAction, .invalid: state = .needsAction
                case .outcomeUnknown: state = .unknown
                case .connection: state = item.state == .unknown ? .unknown : .pending
                case .storage: throw error
                }
                try await store.report(item.id, state: state, message: error.localizedDescription)
                changed = true
            } catch {
                try await store.report(
                    item.id, state: .unknown,
                    message: "无法确认响应，原提交已保留。请检查服务版本后重试。"
                )
                changed = true
            }
        }
        return changed
    }
}
