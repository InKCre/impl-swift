import Foundation

@MainActor
public final class BundledExtensionRuntime {
    public let module: any NativeExtension
    public private(set) var running = false
    public private(set) var applying = false
    public private(set) var syncIssue: String?
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private let defaults: UserDefaults
    private var key: String { "extensions.\(module.descriptor.name).enabled" }
    public var enabled: Bool { defaults.object(forKey: key) as? Bool != false }

    public init(module: any NativeExtension, defaults: UserDefaults = .standard) {
        self.module = module
        self.defaults = defaults
    }
    public func startIfEnabled() throws {
        if enabled && !running {
            try module.start()
            running = true
        }
    }
    public func setEnabled(_ enabled: Bool) async throws {
        guard !applying else { throw PeerError.needsAction("扩展正在应用上一次操作。") }
        applying = true
        defer {
            applying = false
            for waiter in idleWaiters { waiter.resume() }
            idleWaiters.removeAll()
        }
        syncIssue = nil
        if !enabled {
            defaults.set(false, forKey: key)
            try await stop()
        }
        do { try await module.setEnabled(enabled) } catch {
            if enabled {
                guard case PeerError.connection = error else { throw error }
            }
            syncIssue = "共享状态未同步：\(error.localizedDescription)"
        }
        if enabled {
            defaults.set(true, forKey: key)
            try startIfEnabled()
        }
    }
    public func waitUntilIdle() async {
        if applying { await withCheckedContinuation { idleWaiters.append($0) } }
    }

    /// Process shutdown changes runtime facts, not durable enabled intent.
    public func stop() async throws {
        defer { running = false }
        try await module.stop()
    }
}
