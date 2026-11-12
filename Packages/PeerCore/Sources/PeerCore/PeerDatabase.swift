import Foundation
import Logging
import PostgresNIO

public actor PeerDatabase {
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
    private let name: String
    private let labels: [String]
    public init(
        applicationVersion: String = "development",
        name: String = "InKCre Peer", labels: [String] = []
    ) {
        self.applicationVersion = applicationVersion
        self.name = name
        self.labels = labels
    }

    public func client(for target: ConnectionTarget, password: String) throws -> PostgresClient {
        try client(for: target, credentials: .password(password))
    }

    /// Bootstrap credentials are ignored once a session exists; only authorize changes its password.
    public func client(for target: ConnectionTarget, credentials: DatabaseCredentials) throws
        -> PostgresClient
    {
        try target.validate()
        // An established session owns authentication. Old repositories may still carry old
        // bootstrap credentials; ordinary work must never turn those into an authentication update.
        if let pool = pools[target.id] {
            guard pool.target.hasSameDestination(as: target) else {
                throw PeerError.invalid("已授权连接不能改投另一个信息库，请创建新连接。")
            }
            return pool.client
        }
        return try authorize(target, password: credentials.read(for: target.id))
    }

    /// Explicitly replace session authentication. Reusing the same password preserves the client.
    @discardableResult
    public func authorize(_ target: ConnectionTarget, password: String) throws -> PostgresClient {
        try target.validate()
        let previous = pools[target.id]
        if let pool = previous, pool.target.host == target.host,
            pool.target.port == target.port, pool.target.database == target.database,
            pool.target.username == target.username, pool.target.tls == target.tls,
            pool.password == password
        {
            pools[target.id] = Pool(
                target: target,
                password: password, client: pool.client, task: pool.task,
                registered: pool.registered)
            return pool.client
        }
        pools.removeValue(forKey: target.id)
        previous?.task.cancel()
        var configuration = PostgresClient.Configuration(
            host: target.host, port: target.port, username: target.username, password: password,
            database: target.database,
            tls: target.tls == .require ? .require(.makeClientConfiguration()) : .disable
        )
        configuration.options.minimumConnections = 0
        configuration.options.maximumConnections = 2
        configuration.options.connectTimeout = .seconds(10)
        // Bound server work too when a disconnected client cannot deliver cancellation.
        configuration.options.additionalStartupParameters = [
            ("options", "-c statement_timeout=30000")
        ]
        let client = PostgresClient(configuration: configuration, backgroundLogger: Self.logger)
        let task = Task { await client.run() }
        pools[target.id] = Pool(
            target: target,
            password: password, client: client, task: task,
            registered: previous?.registered == true
                && previous?.target.hasSameDestination(as: target) == true)
        return client
    }

    /// End this owner's authorization. The next operation must obtain credentials again.
    public func invalidate(_ connection: UUID) {
        pools.removeValue(forKey: connection)?.task.cancel()
    }

    public func shutdown() async {
        let tasks = pools.values.map(\.task)
        pools.removeAll()
        for task in tasks { task.cancel() }
        for task in tasks { await task.value }
    }

    public func register(_ target: ConnectionTarget, password: String) async throws {
        try await register(target, credentials: .password(password))
    }

    public func register(_ target: ConnectionTarget, credentials: DatabaseCredentials) async throws
    {
        let client = try client(for: target, credentials: credentials)
        if pools[target.id]?.registered == true { return }
        let name = self.name
        let labels = self.labels
        let applicationVersion = self.applicationVersion
        try await withConnection(for: target, credentials: credentials) { connection in
            try await connection.withTransaction(logger: Self.logger) { connection in
                try await connection.query(
                    """
                    INSERT INTO inkcre.peers (id,name,application_version,capabilities,config_schema,config,labels)
                    VALUES (\(target.peerID),\(name),\(applicationVersion),'[]','{}','{}',\(labels))
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
        _ operation: @escaping @Sendable (PostgresConnection) async throws -> Result
    ) async throws -> Result {
        try await withConnection(for: target, credentials: .password(password), operation)
    }

    public nonisolated func withConnection<Result: Sendable>(
        for target: ConnectionTarget, credentials: DatabaseCredentials,
        _ operation: @escaping @Sendable (PostgresConnection) async throws -> Result
    ) async throws -> Result {
        let client = try await client(for: target, credentials: credentials)
        return try await withConnection(client: client, operation)
    }

    private nonisolated func withConnection<Result: Sendable>(
        client: PostgresClient,
        _ operation: @escaping @Sendable (PostgresConnection) async throws -> Result
    ) async throws -> Result {
        return try await withThrowingTaskGroup(of: Result.self) { group in
            group.addTask {
                try await client.withConnection { connection in
                    try await withTaskCancellationHandler {
                        try Task.checkCancellation()
                        do { return try await operation(connection) } catch {
                            if Task.isCancelled { throw CancellationError() }
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
                        try await self.withConnection(client: pool.client) {
                            connection in
                            let rows = try await connection.query(
                                "SELECT inkcre.renew_peer_lease(\(pool.target.peerID),120)",
                                logger: Self.logger)
                            for try await _ in rows {}
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
