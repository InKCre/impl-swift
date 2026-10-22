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
    }
    private var pools: [UUID: Pool] = [:]

    public init() {}

    public func client(for target: ConnectionTarget, password: String) throws -> PostgresClient {
        try target.validate()
        if let pool = pools[target.id], pool.target == target, pool.password == password {
            return pool.client
        }
        pools.removeValue(forKey: target.id)?.task.cancel()
        var configuration = PostgresClient.Configuration(
            host: target.host, port: target.port, username: target.username, password: password,
            database: target.database,
            tls: target.tls == .require ? .require(.makeClientConfiguration()) : .disable
        )
        configuration.options.minimumConnections = 0
        configuration.options.maximumConnections = 2
        configuration.options.connectTimeout = .seconds(10)
        let client = PostgresClient(configuration: configuration, backgroundLogger: Self.logger)
        let task = Task { await client.run() }
        pools[target.id] = Pool(target: target, password: password, client: client, task: task)
        return client
    }

    public func shutdown() async {
        let tasks = pools.values.map(\.task)
        pools.removeAll()
        for task in tasks { task.cancel() }
        for task in tasks { await task.value }
    }

    public func register(_ target: ConnectionTarget, password: String) async throws -> Date {
        let client = try client(for: target, password: password)
        let name = Host.current().localizedName ?? "InKCre Mac"
        return try await client.withTransaction(logger: Self.logger) { connection in
            try await connection.query(
                """
                INSERT INTO inkcre.peers (id,name,application_version,capabilities,config_schema,config,labels)
                VALUES (\(target.peerID),\(name),'0.1.0','[]','{}','{}',ARRAY['macOS'])
                ON CONFLICT (id) DO UPDATE SET application_version=EXCLUDED.application_version
                """, logger: Self.logger)
            let rows = try await connection.query(
                "SELECT inkcre.renew_peer_lease(\(target.peerID),120)", logger: Self.logger)
            for try await expiry in rows.decode(Date.self) { return expiry.addingTimeInterval(-120) }
            throw PeerError.connection("信息库未返回 Peer 联络结果。")
        }
    }
}
