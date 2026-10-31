import Foundation
import PeerCore
import PostgresNIO

public struct LocalFileClient: Sendable {
    public let target: ConnectionTarget
    let password: String
    let database: PeerDatabase
    public init(target: ConnectionTarget, password: String, database: PeerDatabase = .shared) {
        self.target = target
        self.password = password
        self.database = database
    }

    public func prepare() async throws {
        try await database.register(target, password: password)
        try await database.join(
            target, password: password, extension: LocalFilesContract.descriptor)
        return try await database.withConnection(for: target, password: password) { client in
            let config =
                #"{"type":"object","additionalProperties":false,"properties":{"peer":{"type":"string","format":"uuid"},"path":{"type":"string","pattern":"^/"},"enabled":{"type":"boolean"}},"required":["peer","path","enabled"]}"#
            try await client.query(
                """
                INSERT INTO inkcre.sources_types(id,description,config_schema,collect_config_schema)
                VALUES (\(LocalFilesContract.sourceType),'本地文件目录',\(config)::jsonb,'{"type":"object","additionalProperties":false}')
                ON CONFLICT(id) DO UPDATE SET config_schema=EXCLUDED.config_schema,collect_config_schema=EXCLUDED.collect_config_schema
                """, logger: PeerDatabase.logger)
            let parameters =
                #"{"type":"object","additionalProperties":false,"properties":{"source":{"type":"integer"},"config":{"type":"object","default":{}}},"required":["source"]}"#
            try await client.query(
                """
                INSERT INTO inkcre.job_types(id,description,parameters_schema,default_timeout_seconds)
                VALUES (\(SourceJobs.type),'Run one ordinary collection command for a configured Source.',\(parameters)::jsonb,300)
                ON CONFLICT(id) DO NOTHING
                """, logger: PeerDatabase.logger)
        }
    }

    public func checkParticipation() async throws {
        return try await database.withConnection(for: target, password: password) { client in
            try await client.withTransaction(logger: PeerDatabase.logger) { connection in
                try await PeerDatabase.requireSelection(
                    LocalFilesContract.descriptor, peerID: target.peerID, on: connection)
            }
        }
    }

    public func sources() async throws -> [DirectorySource] {
        return try await database.withConnection(for: target, password: password) { client in
            let rows = try await client.query(
                "SELECT id,config::text,block,state::text FROM inkcre.sources WHERE type=\(LocalFilesContract.sourceType) AND config->>'peer'=\(target.peerID.uuidString.lowercased()) ORDER BY id",
                logger: PeerDatabase.logger)
            var sources: [DirectorySource] = []
            for row in rows {
                try Task.checkCancellation()
                let (id, config, block, state) = try row.decode(
                    (Int, String, Int?, String).self)

                sources.append(try decodeSource(id: id, config: config, block: block, state: state))
            }
            return sources
        }
    }

    public func createDirectory(path: String) async throws -> DirectorySource {
        let config = DirectoryConfig(peer: target.peerID, path: path)
        _ = try PeerFileLocation(peer: config.peer, path: path)
        let serialized = try FileJSON.encode(config)
        return try await database.withConnection(for: target, password: password) { client in
            return try await client.withTransaction(logger: PeerDatabase.logger) { connection in
                try await PeerDatabase.requireSelection(
                    LocalFilesContract.descriptor, peerID: target.peerID, on: connection)
                try await connection.query(
                    "SELECT pg_advisory_xact_lock(hashtextextended(\(target.peerID.uuidString + path),0))",
                    logger: PeerDatabase.logger)
                let existing = try await connection.query(
                    "SELECT id FROM inkcre.sources WHERE type=\(LocalFilesContract.sourceType) AND config->>'peer'=\(target.peerID.uuidString.lowercased()) AND config->>'path'=\(path)",
                    logger: PeerDatabase.logger)
                for row in existing {
                    try Task.checkCancellation()
                    let _ = try row.decode(Int.self)

                    throw PeerError.needsAction("这个目录已经添加。")
                }
                let rows = try await connection.query(
                    "INSERT INTO inkcre.sources(type,nickname,config) VALUES (\(LocalFilesContract.sourceType),\(URL(fileURLWithPath: path).lastPathComponent),\(serialized)::jsonb) RETURNING id",
                    logger: PeerDatabase.logger)
                for row in rows {
                    try Task.checkCancellation()
                    let id = try row.decode(Int.self)

                    struct Anchor: Encodable {
                        let id: Int
                        let type: String
                        let nickname: String
                    }
                    let content = try FileJSON.encode(
                        Anchor(id: id, type: LocalFilesContract.sourceType, nickname: path))
                    let block = try await InfoBase.createBlock(
                        resolver: "core.source.v1", content: content, on: connection)
                    try await connection.query(
                        "UPDATE inkcre.sources SET block=\(block) WHERE id=\(id)",
                        logger: PeerDatabase.logger)
                    return DirectorySource(
                        id: id, config: config, block: block, state: DirectoryState())
                }
                throw PeerError.connection("目录未能保存。")
            }
        }
    }

    public func setEnabled(_ enabled: Bool, source: DirectorySource) async throws {
        return try await database.withConnection(for: target, password: password) { client in
            try await client.withTransaction(logger: PeerDatabase.logger) { connection in
                var current = try await locked(
                    source.id, on: connection, expected: source.config, requireEnabled: false)
                current.config.enabled = enabled
                let config = try FileJSON.encode(current.config)
                try await connection.query(
                    "UPDATE inkcre.sources SET config=\(config)::jsonb WHERE id=\(source.id)",
                    logger: PeerDatabase.logger)
            }
        }
    }

    public func remove(_ source: DirectorySource) async throws {
        return try await database.withConnection(for: target, password: password) { client in
            try await client.withTransaction(logger: PeerDatabase.logger) { connection in
                _ = try await locked(
                    source.id, on: connection, expected: source.config, requireEnabled: false)
                try await connection.query(
                    "DELETE FROM inkcre.sources WHERE id=\(source.id)", logger: PeerDatabase.logger)
            }
        }
    }

    public func records(source: DirectorySource) async throws -> [FileRecord] {
        guard source.config.peer == target.peerID else { throw PeerError.invalid("目录不属于当前 Peer。") }
        guard let block = source.block else { return [] }
        return try await database.withConnection(for: target, password: password) { client in
            let rows = try await client.query(
                """
                SELECT b.id,b.resolver,b.content,t.id,t.resolver,t.storage FROM inkcre.relations managed JOIN inkcre.blocks b ON b.id=managed.to_
                LEFT JOIN inkcre.relations body ON body.from_=b.id AND body.content='body'
                LEFT JOIN inkcre.blocks t ON t.id=body.to_
                WHERE managed.from_=\(block) AND managed.content='manages' AND b.resolver IN (\(LocalFilesContract.resolver),\(LocalFilesContract.legacyResolver)) ORDER BY b.id
                """, logger: PeerDatabase.logger)
            var records: [FileRecord] = []
            var seen: Set<Int> = []
            for row in rows {
                try Task.checkCancellation()
                let (id, resolver, content, bodyID, bodyResolver, storage) = try row.decode(
                    (Int, String, String, Int?, String?, Int?).self)

                guard seen.insert(id).inserted else { throw PeerError.invalid("文件资料存在重复正文关系。") }
                records.append(
                    try storedFile(
                        id: id, resolver: resolver, content: content, bodyID: bodyID,
                        bodyResolver: bodyResolver, storage: storage))
            }
            return records
        }
    }

    public func content(for record: FileRecord) async throws -> String? {
        guard let body = record.bodyID else { return nil }
        return try await database.withConnection(for: target, password: password) { client in
            let rows = try await client.query(
                "SELECT content FROM inkcre.blocks WHERE id=\(body) AND resolver=\(record.bodyResolver) AND storage IS NULL",
                logger: PeerDatabase.logger)
            for row in rows {
                try Task.checkCancellation()
                let text = try row.decode(String.self)
                return text
            }
            throw PeerError.needsAction("正文已移除，请刷新文件列表。")
        }
    }

    func locked(
        _ id: Int, on connection: PeerConnection, expected: DirectoryConfig? = nil,
        requireEnabled: Bool = true
    ) async throws -> DirectorySource {
        try await PeerDatabase.requireSelection(
            LocalFilesContract.descriptor, peerID: target.peerID, on: connection)
        let rows = try await connection.query(
            "SELECT id,config::text,block,state::text FROM inkcre.sources WHERE id=\(id) AND type=\(LocalFilesContract.sourceType) FOR UPDATE",
            logger: PeerDatabase.logger)
        for row in rows {
            try Task.checkCancellation()
            let (id, config, block, state) = try row.decode((Int, String, Int?, String).self)

            let source = try decodeSource(id: id, config: config, block: block, state: state)
            if let expected, source.config != expected || (requireEnabled && !source.config.enabled)
            {
                throw CancellationError()
            }
            return source
        }
        throw PeerError.needsAction("目录来源已移除。")
    }

    private func decodeSource(id: Int, config: String, block: Int?, state: String) throws
        -> DirectorySource
    {
        let config = try FileJSON.decode(DirectoryConfig.self, config)
        guard config.peer == target.peerID else { throw PeerError.needsAction("目录属于另一个 Peer。") }
        _ = try PeerFileLocation(peer: config.peer, path: config.path)
        let status =
            state == "{}" ? DirectoryState() : try FileJSON.decode(DirectoryState.self, state)
        return DirectorySource(id: id, config: config, block: block, state: status)
    }
}
