import Foundation
import PeerCore
import PostgresNIO

public protocol CaptureTransport: Sendable {
    func recover(_ record: CaptureRecord, secret: String) async throws -> CaptureResult?
    func submit(_ record: CaptureRecord, secret: String) async throws -> CaptureResult
}

public struct CaptureClient: CaptureTransport {
    public static let descriptor = NativeExtensionDescriptor.bundled(
        resourceBundle: "InKCreCapture_Capture", developmentBundle: .module)
    private let database: PeerDatabase
    public init(database: PeerDatabase = .shared) { self.database = database }

    public func recover(_ record: CaptureRecord, secret: String) async throws -> CaptureResult? {
        guard let target = record.target, let payload = record.payload else {
            throw PeerError.invalid("待办缺少材料或目标。")
        }
        do {
            return try await database.withConnection(for: target, password: secret) { connection in
                try await Self.result(
                    from: connection.query(Self.lookup(record.id), logger: PeerDatabase.logger),
                    id: record.id, digest: payload.canonicalDigest())
            }
        } catch { throw PeerDatabase.failure(error, dispatched: false) }
    }

    private static func lookup(_ id: UUID) -> PostgresQuery {
        """
        SELECT content::jsonb->>'payload_digest',id,created_at FROM inkcre.blocks
        WHERE CASE WHEN resolver='extensions.capture.capture.v1'
          THEN content::jsonb->>'submission_id' END=\(id.uuidString.lowercased())
        """
    }

    private static func result(from rows: [PostgresRow], id: UUID, digest: String)
        throws
        -> CaptureResult?
    {
        for row in rows {
            try Task.checkCancellation()
            let (saved, root, date) = try row.decode((String, Int, Date).self)

            guard saved == digest else { throw PeerError.needsAction("提交身份与已保存材料冲突，原材料已保留。") }
            return CaptureResult(submissionID: id, rootBlockID: root, committedAt: date)
        }
        return nil
    }

    public func submit(_ record: CaptureRecord, secret: String) async throws -> CaptureResult {
        guard let target = record.target, let payload = record.payload else {
            throw PeerError.invalid("待办缺少冻结材料或目标。")
        }
        let command = try CaptureCommit(payload)
        do {
            try await database.register(target, password: secret)
            try await database.join(target, password: secret, extension: Self.descriptor)
            return try await database.withConnection(for: target, password: secret) { connection in
                try await connection.withTransaction(logger: PeerDatabase.logger) { connection in
                    try await PeerDatabase.requireSelection(
                        Self.descriptor, peerID: target.peerID, on: connection)
                    // Serialize retries of this submission before checking or writing its graph.
                    try await connection.query(
                        "SELECT pg_advisory_xact_lock(hashtextextended(\(record.id.uuidString.lowercased()),0))",
                        logger: PeerDatabase.logger)
                    if let existing = try await Self.result(
                        from: connection.query(Self.lookup(record.id), logger: PeerDatabase.logger),
                        id: record.id, digest: command.payload_digest)
                    {
                        return existing
                    }
                    let ids = try await InfoBase.persist(
                        blocks: command.graph.blocks, relations: command.graph.relations,
                        blobs: command.graph.blobs,
                        on: connection)
                    guard let root = ids[command.graph.root_local_id] else {
                        throw PeerError.invalid("采集图缺少根。")
                    }
                    let rows = try await connection.query(
                        "SELECT created_at FROM inkcre.blocks WHERE id=\(root)",
                        logger: PeerDatabase.logger)
                    for row in rows {
                        try Task.checkCancellation()
                        let date = try row.decode(Date.self)

                        return CaptureResult(
                            submissionID: record.id, rootBlockID: root, committedAt: date)
                    }
                    throw PeerError.outcomeUnknown
                }
            }
        } catch { throw PeerDatabase.failure(error, dispatched: true) }
    }
}
