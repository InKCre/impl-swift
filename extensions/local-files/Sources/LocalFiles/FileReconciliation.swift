import Foundation
import PeerCore
import PostgresNIO

extension LocalFileClient {
    public func submitScan(_ source: DirectorySource) async throws -> Int {
        return try await database.withConnection(for: target, password: password) { client in
            return try await client.withTransaction(logger: PeerDatabase.logger) { connection in
                _ = try await locked(source.id, on: connection, expected: source.config)
                return try await SourceJobs.submit(source: source.id, on: connection)
            }
        }
    }

    public func pendingScans(_ source: DirectorySource) async throws -> [Int] {
        return try await database.withConnection(for: target, password: password) { client in
            try await client.withTransaction(logger: PeerDatabase.logger) { connection in
                _ = try await locked(source.id, on: connection, expected: source.config)
                try await connection.query(
                    """
                    UPDATE inkcre.jobs SET status='failed',state='{"issue":"扫描参数不符合本地文件合同。"}'::jsonb
                    WHERE type=\(SourceJobs.type) AND status='pending' AND parameters->'source'=to_jsonb(\(source.id)::bigint)
                    AND (COALESCE(parameters->'config','{}'::jsonb)<>'{}'::jsonb OR parameters-'source'-'config'<>'{}'::jsonb)
                    """, logger: PeerDatabase.logger)
            }
            return try await SourceJobs.pending(source: source.id, on: client)
        }
    }

    public func reportIssue(_ message: String, source: DirectorySource) async throws {
        return try await database.withConnection(for: target, password: password) { client in
            try await client.withTransaction(logger: PeerDatabase.logger) { connection in
                let current = try await locked(source.id, on: connection, expected: source.config)
                var state = current.state
                state.issue = message
                let json = try FileJSON.encode(state)
                try await connection.query(
                    "UPDATE inkcre.sources SET state=\(json)::jsonb WHERE id=\(source.id)",
                    logger: PeerDatabase.logger)
            }
        }
    }

    public func claim(_ id: Int, source: DirectorySource) async throws -> SourceJob? {
        return try await database.withConnection(for: target, password: password) { client in
            return try await client.withTransaction(logger: PeerDatabase.logger) { connection in
                _ = try await locked(source.id, on: connection, expected: source.config)
                return try await SourceJobs.claim(id, source: source.id, on: connection)
            }
        }
    }

    public func check(_ job: SourceJob?) async throws {
        try Task.checkCancellation()
        return try await database.withConnection(for: target, password: password) { client in
            if let job { try await SourceJobs.check(job, on: client) }
        }
    }

    public func close(_ job: SourceJob, status: String, state: DirectoryState) async throws {
        return try await database.withConnection(for: target, password: password) { client in
            try await SourceJobs.close(
                job, status: status, state: FileJSON.encode(state), on: client)
        }
    }

    public func save(
        _ observation: FileObservation, replacing record: FileRecord?, source: DirectorySource
    ) async throws {
        if let record, !observation.changes(record.metadata) { return }
        return try await database.withConnection(for: target, password: password) { client in
            try await client.withTransaction(logger: PeerDatabase.logger) { connection in
                let source = try await locked(source.id, on: connection, expected: source.config)
                guard let anchor = source.block else { throw PeerError.invalid("目录来源缺少资料锚点。") }
                var metadata = observation.metadata
                if let record {
                    let current = try await currentRecord(record.id, anchor: anchor, on: connection)
                    if observation.text == nil { metadata.revision = current.metadata.revision }
                    if let text = observation.text {
                        if let body = current.bodyID {
                            try await InfoBase.updateBlock(body, content: text, on: connection)
                        } else {
                            let body = try await InfoBase.createBlock(
                                resolver: "core.text.v1", content: text, on: connection)
                            try await InfoBase.relate(
                                record.id, to: body, content: "body", on: connection)
                        }
                    }
                    try await InfoBase.updateBlock(
                        record.id, content: FileJSON.encode(metadata), on: connection)
                } else {
                    // The Source lock also protects a retry after a successful commit with a lost reply.
                    let existing = try await connection.query(
                        "SELECT b.id FROM inkcre.relations r JOIN inkcre.blocks b ON b.id=r.to_ WHERE r.from_=\(anchor) AND r.content='manages' AND b.resolver=\(LocalFilesContract.resolver) AND b.content::jsonb->>'location'=\(metadata.location)",
                        logger: PeerDatabase.logger)
                    for try await _ in existing.decode(Int.self) {
                        throw PeerError.needsAction("资料已存在，正在重新核对目录。")
                    }
                    let root = try await InfoBase.createBlock(
                        resolver: LocalFilesContract.resolver, content: FileJSON.encode(metadata),
                        on: connection)
                    if let text = observation.text {
                        let body = try await InfoBase.createBlock(
                            resolver: "core.text.v1", content: text, on: connection)
                        try await InfoBase.relate(root, to: body, content: "body", on: connection)
                    }
                    try await InfoBase.relate(anchor, to: root, content: "manages", on: connection)
                }
            }
        }
    }

    public func finishScan(source: DirectorySource, missing: [FileRecord], state: DirectoryState)
        async throws
    {
        return try await database.withConnection(for: target, password: password) { client in
            try await client.withTransaction(logger: PeerDatabase.logger) { connection in
                let source = try await locked(source.id, on: connection, expected: source.config)
                guard let anchor = source.block else { throw PeerError.invalid("目录来源缺少资料锚点。") }
                for record in missing {
                    var current = try await currentRecord(record.id, anchor: anchor, on: connection)
                    guard current.metadata.available,
                        current.metadata.location == record.metadata.location
                    else { continue }
                    current.metadata.available = false
                    current.metadata.observed_at = Date()
                    current.metadata.issue = nil
                    try await InfoBase.updateBlock(
                        record.id, content: FileJSON.encode(current.metadata), on: connection)
                }
                let json = try FileJSON.encode(state)
                try await connection.query(
                    "UPDATE inkcre.sources SET state=\(json)::jsonb WHERE id=\(source.id)",
                    logger: PeerDatabase.logger)
            }
        }
    }

    private func currentRecord(_ id: Int, anchor: Int, on connection: PostgresConnection)
        async throws
        -> FileRecord
    {
        let rows = try await connection.query(
            """
            SELECT b.content,t.id FROM inkcre.blocks b
            JOIN inkcre.relations managed ON managed.to_=b.id AND managed.from_=\(anchor) AND managed.content='manages'
            LEFT JOIN inkcre.relations body ON body.from_=b.id AND body.content='body'
            LEFT JOIN inkcre.blocks t ON t.id=body.to_ AND t.resolver='core.text.v1'
            WHERE b.id=\(id) AND b.resolver=\(LocalFilesContract.resolver) FOR UPDATE OF b
            """, logger: PeerDatabase.logger)
        var records: [FileRecord] = []
        for try await (content, body) in rows.decode((String, Int?).self) {
            records.append(
                FileRecord(
                    id: id, metadata: try FileJSON.decode(FileMetadata.self, content), bodyID: body)
            )
        }
        guard records.count == 1, let record = records.first else {
            throw PeerError.invalid("文件资料关系已改变，请重新扫描。")
        }
        return record
    }
}
