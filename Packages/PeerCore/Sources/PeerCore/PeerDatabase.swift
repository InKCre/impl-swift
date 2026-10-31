import Foundation
import Logging
import PostgresNIO

public actor PeerDatabase {
    public static let shared = PeerDatabase()
    public static let logger = Logger(label: "dev.inkcre.database")
    private struct Pool {
        let target: ConnectionTarget
        let password: String
        let client: PostgresClient
        let task: Task<Void, Never>
        var registered = false
    }
    private var pools: [UUID: Pool] = [:]

    private let applicationVersion: String
    public init(
        applicationVersion: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "development"
    ) {
        self.applicationVersion = applicationVersion
    }

    public func client(for target: ConnectionTarget, password: String) throws -> PostgresClient {
        try target.validate()
        if let pool = pools[target.id], pool.target.host == target.host,
            pool.target.port == target.port, pool.target.database == target.database,
            pool.target.username == target.username, pool.target.tls == target.tls,
            pool.password == password
        {
            return pool.client
        }
        let previous = pools.removeValue(forKey: target.id)
        previous?.task.cancel()
        var configuration = PostgresClient.Configuration(
            host: target.host, port: target.port, username: target.username, password: password,
            database: target.database,
            tls: target.tls == .require ? .require(.makeClientConfiguration()) : .disable
        )
        configuration.options.minimumConnections = 0
        configuration.options.maximumConnections = 2
        configuration.options.connectTimeout = .seconds(10)
        // Detect a closed client during long queries; bound server work if a lost network hides it.
        configuration.options.additionalStartupParameters = [
            ("options", "-c statement_timeout=30000 -c client_connection_check_interval=1000")
        ]
        let client = PostgresClient(configuration: configuration, backgroundLogger: Self.logger)
        let task = Task { await client.run() }
        pools[target.id] = Pool(
            target: target, password: password, client: client, task: task,
            registered: previous?.registered == true
                && previous?.target.hasSameDestination(as: target) == true)
        return client
    }

    public func shutdown() async {
        let tasks = pools.values.map(\.task)
        pools.removeAll()
        for task in tasks { task.cancel() }
        for task in tasks { await task.value }
    }

    public func register(_ target: ConnectionTarget, password: String) async throws {
        let client = try client(for: target, password: password)
        if pools[target.id]?.registered == true { return }
        let name = Host.current().localizedName ?? "InKCre Mac"
        let applicationVersion = self.applicationVersion
        try await withConnection(for: target, password: password) { connection in
            try await connection.withTransaction(logger: Self.logger) { connection in
                try await connection.query(
                    """
                    INSERT INTO inkcre.peers (id,name,application_version,capabilities,config_schema,config,labels)
                    VALUES (\(target.peerID),\(name),\(applicationVersion),'[]','{}','{}',ARRAY['macOS'])
                    ON CONFLICT (id) DO UPDATE SET application_version=EXCLUDED.application_version
                    """, logger: Self.logger)
                try await connection.query(
                    "SELECT inkcre.renew_peer_lease(\(target.peerID),120)", logger: Self.logger)
            }
        }
        if pools[target.id]?.client === client { pools[target.id]?.registered = true }
    }

    /// Keep row consumption and transactions inside this scope so cancellation closes their lease.
    public nonisolated func withConnection<Result: Sendable>(
        for target: ConnectionTarget, password: String,
        _ operation: @escaping @Sendable (PeerConnection) async throws -> Result
    ) async throws -> Result {
        let client = try await client(for: target, password: password)
        return try await withThrowingTaskGroup(of: Result.self) { group in
            group.addTask {
                try await client.withConnection { connection in
                    let borrowed = PeerConnection(connection: connection)
                    return try await withTaskCancellationHandler {
                        do {
                            try Task.checkCancellation()
                            let result = try await operation(borrowed)
                            try Task.checkCancellation()
                            return result
                        } catch {
                            if Task.isCancelled {
                                await borrowed.close()
                                throw CancellationError()
                            }
                            throw error
                        }
                    } onCancel: {
                        // Closing the socket also interrupts queries whose driver future ignores cancellation.
                        connection.close().whenFailure { _ in }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    public func renewLeases() async -> [UUID: String] {
        await withTaskGroup(of: (UUID, String?).self) { group in
            for (id, pool) in pools where pool.registered {
                group.addTask {
                    do {
                        try await self.withConnection(for: pool.target, password: pool.password) {
                            connection in
                            try await connection.query(
                                "SELECT inkcre.renew_peer_lease(\(pool.target.peerID),120)",
                                logger: Self.logger)
                        }
                        return (id, nil)
                    } catch { return (id, Self.failure(error).localizedDescription) }
                }
            }
            var failures: [UUID: String] = [:]
            for await (id, message) in group { failures[id] = message }
            return failures
        }
    }
}
