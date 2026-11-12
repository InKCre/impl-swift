import Foundation
import PeerCore
import PostgresNIO

public protocol CaptureWriting: Sendable {
    /// Prepare authentication before the queue records a possible dispatch.
    func prepare(_ record: CaptureRecord, credentials: DatabaseCredentials) async throws
    func recover(_ record: CaptureRecord, credentials: DatabaseCredentials) async throws
        -> CaptureResult?
    func submit(_ record: CaptureRecord, credentials: DatabaseCredentials) async throws
        -> CaptureResult
}

public struct CaptureWriter: CaptureWriting {
    public static let descriptor: NativeExtensionDescriptor = {
        let bundle: Bundle
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard
                let url = Bundle.main.url(
                    forResource: "InKCreCapture_Capture", withExtension: "bundle"),
                let packaged = Bundle(url: url)
            else {
                preconditionFailure("Missing packaged Capture distribution")
            }
            bundle = packaged
        } else {
            bundle = .module
        }
        guard let url = bundle.url(forResource: "extension", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let descriptor = try? JSONDecoder().decode(NativeExtensionDescriptor.self, from: data)
        else {
            preconditionFailure("Invalid bundled Capture manifest")
        }
        return descriptor
    }()
    private let database: PeerDatabase
    public init(database: PeerDatabase) { self.database = database }

    public func prepare(_ record: CaptureRecord, credentials: DatabaseCredentials) async throws {
        guard let target = record.target else { throw PeerError.invalid("待办缺少目标。") }
        _ = try await database.client(for: target, credentials: credentials)
    }

    public func recover(_ record: CaptureRecord, secret: String) async throws -> CaptureResult? {
        try await recover(record, credentials: .password(secret))
    }

    public func recover(_ record: CaptureRecord, credentials: DatabaseCredentials) async throws
        -> CaptureResult?
    {
        guard let target = record.target, let payload = record.payload else {
            throw PeerError.invalid("待办缺少材料或目标。")
        }
        do {
            return try await database.withConnection(for: target, credentials: credentials) {
                connection in
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

    private static func result(from rows: PostgresRowSequence, id: UUID, digest: String)
        async throws
        -> CaptureResult?
    {
        for try await (saved, root, date) in rows.decode((String, Int, Date).self) {
            guard saved == digest else { throw PeerError.needsAction("提交身份与已保存材料冲突，原材料已保留。") }
            return CaptureResult(submissionID: id, rootBlockID: root, committedAt: date)
        }
        return nil
    }

    public func submit(_ record: CaptureRecord, secret: String) async throws -> CaptureResult {
        try await submit(record, credentials: .password(secret))
    }

    public func submit(_ record: CaptureRecord, credentials: DatabaseCredentials) async throws
        -> CaptureResult
    {
        guard let target = record.target, let payload = record.payload else {
            throw PeerError.invalid("待办缺少冻结材料或目标。")
        }
        let command = try CaptureCommit(payload)
        do {
            try await database.register(target, credentials: credentials)
            try await database.join(target, credentials: credentials, extension: Self.descriptor)
            return try await database.withConnection(for: target, credentials: credentials) {
                connection in
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
                    for try await date in rows.decode(Date.self) {
                        return CaptureResult(
                            submissionID: record.id, rootBlockID: root, committedAt: date)
                    }
                    throw PeerError.outcomeUnknown
                }
            }
        } catch { throw PeerDatabase.failure(error, dispatched: true) }
    }
}
