import Foundation
import PostgresNIO

extension PeerDatabase {
    /// First joining may create a selection; subsequent reconnects never recreate removed participation.
    public func join(
        _ target: ConnectionTarget, password: String,
        extension descriptor: NativeExtensionDescriptor
    ) async throws {
        let defaults = UserDefaults(suiteName: "dev.inkcre.native-participation")!
        let key = "\(target.peerID).\(descriptor.name)"
        let firstJoin = !defaults.bool(forKey: key)
        let client = try client(for: target, password: password)
        let issue: String? = try await client.withTransaction(logger: Self.logger) { connection in
            if firstJoin {
                try await connection.query(
                    "INSERT INTO inkcre.extensions(name) VALUES (\(descriptor.name)) ON CONFLICT (name) DO NOTHING",
                    logger: Self.logger)
                try await connection.query(
                    """
                    INSERT INTO inkcre.extension_peer_participations(name,peer_id,distribution,version,enabled)
                    VALUES (\(descriptor.name),\(target.peerID),\(descriptor.distribution),\(descriptor.version),true)
                    ON CONFLICT (name,peer_id) DO NOTHING
                    """, logger: Self.logger)
            }
            do {
                try await Self.requireSelection(descriptor, peerID: target.peerID, on: connection)
                return nil
            } catch PeerError.needsAction(let message) { return message }
        }
        defaults.set(true, forKey: key)
        if let issue { throw PeerError.needsAction(issue) }
    }

    public static func requireSelection(
        _ descriptor: NativeExtensionDescriptor, peerID: UUID, on connection: PostgresConnection
    ) async throws {
        let rows = try await connection.query(
            """
            SELECT distribution,version,enabled FROM inkcre.extension_peer_participations
            WHERE name=\(descriptor.name) AND peer_id=\(peerID) FOR SHARE
            """, logger: Self.logger)
        for try await (distribution, version, enabled) in rows.decode((String?, String, Bool).self)
        {
            guard distribution == descriptor.distribution, version == descriptor.version else {
                throw PeerError.needsAction("此 Peer 选择的扩展版本不在当前应用中，请核对扩展选择。")
            }
            guard enabled else { throw PeerError.needsAction("信息库中的扩展参与已停用；本机材料保留，请在线明确启用后继续。") }
            return
        }
        throw PeerError.needsAction("此 Peer 的扩展参与已移除；不会在重连时自动重建。")
    }

    public func setEnabled(
        _ enabled: Bool, target: ConnectionTarget, password: String,
        extension descriptor: NativeExtensionDescriptor
    ) async throws {
        _ = try await register(target, password: password)
        let client = try client(for: target, password: password)
        try await client.withTransaction(logger: Self.logger) { connection in
            if enabled {
                try await connection.query(
                    "INSERT INTO inkcre.extensions(name) VALUES (\(descriptor.name)) ON CONFLICT (name) DO NOTHING",
                    logger: Self.logger)
                try await connection.query(
                    """
                    INSERT INTO inkcre.extension_peer_participations(name,peer_id,distribution,version,enabled)
                    VALUES (\(descriptor.name),\(target.peerID),\(descriptor.distribution),\(descriptor.version),true)
                    ON CONFLICT (name,peer_id) DO NOTHING
                    """, logger: Self.logger)
            }
            let rows = try await connection.query(
                """
                UPDATE inkcre.extension_peer_participations SET enabled=\(enabled)
                WHERE name=\(descriptor.name) AND peer_id=\(target.peerID)
                  AND distribution=\(descriptor.distribution) AND version=\(descriptor.version)
                RETURNING name
                """, logger: Self.logger)
            for try await _ in rows.decode(String.self) { return }
            if enabled { throw PeerError.needsAction("信息库中没有与本机匹配的扩展选择。") }
        }
        let defaults = UserDefaults(suiteName: "dev.inkcre.native-participation")!
        defaults.set(true, forKey: "\(target.peerID).\(descriptor.name)")
    }
}
