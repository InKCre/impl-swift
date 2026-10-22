import Foundation
import PeerCore

public actor CaptureQueue {
    private let store: CaptureStore
    private let credentials: CredentialStore
    private let client: any CaptureTransport
    private var running = false
    public private(set) var isStopped = false
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        store: CaptureStore, credentials: CredentialStore, client: any CaptureTransport = CaptureClient()
    ) {
        self.store = store
        self.credentials = credentials
        self.client = client
    }

    public func resume() { isStopped = false }
    public func stop() async {
        isStopped = true
        if running { await withCheckedContinuation { idleWaiters.append($0) } }
    }

    public func process(force: Bool = false) async throws {
        guard !isStopped, !Task.isCancelled, !running else { return }
        running = true
        defer {
            running = false
            for waiter in idleWaiters { waiter.resume() }
            idleWaiters.removeAll()
        }
        for item in try await store.records() where [.pending, .unknown].contains(item.state) {
            guard !isStopped, !Task.isCancelled else { return }
            let delay = min(300.0, pow(2.0, Double(min(item.attempts, 8))) * 2)
            if !force && item.attempts > 0 && Date().timeIntervalSince(item.updatedAt) < delay { continue }
            guard let target = item.target else { continue }
            do {
                let secret = try credentials.read(for: target.id)
                if let result = try await client.recover(item, secret: secret) {
                    try await store.confirm(item.id, result: result)
                    continue
                }
                guard !isStopped, !Task.isCancelled else { return }
                let dispatched = try await store.markDispatch(item.id)
                guard !isStopped, !Task.isCancelled else { return }
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
            } catch {
                try await store.report(
                    item.id, state: .unknown,
                    message: "无法确认响应，原提交已保留。请检查服务版本后重试。"
                )
            }
        }
    }
}
