import CryptoKit
import Foundation
import PeerCore
import PostgresNIO

public protocol CaptureTransport: Sendable {
    func recover(_ record: CaptureRecord, secret: String) async throws -> CaptureResult?
    func submit(_ record: CaptureRecord, secret: String) async throws -> CaptureResult
}

public struct CaptureClient: CaptureTransport {
    public static let descriptor: NativeExtensionDescriptor = {
        let bundle: Bundle
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let url = Bundle.main.url(forResource: "InKCreCapture_Capture", withExtension: "bundle"),
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
    public init(database: PeerDatabase = .shared) { self.database = database }

    public func checkConnection(_ target: ConnectionTarget, secret: String) async throws {
        do {
            _ = try await database.register(target, password: secret)
            try await database.join(target, password: secret, extension: Self.descriptor)
            let client = try await database.client(for: target, password: secret)
            _ = try await client.query(
                "SELECT submission_id,payload_digest,graph_digest FROM inkcre.capture_receipts LIMIT 0")
        } catch { throw PeerDatabase.failure(error, dispatched: false) }
    }

    public func recover(_ record: CaptureRecord, secret: String) async throws -> CaptureResult? {
        guard let target = record.target, let payload = record.payload else {
            throw PeerError.invalid("待办缺少材料或目标。")
        }
        do {
            let client = try await database.client(for: target, password: secret)
            return try await Self.receipt(record.id, digest: payload.canonicalDigest(), client: client)
        } catch { throw PeerDatabase.failure(error, dispatched: false) }
    }

    private static func receipt(_ id: UUID, digest: String, client: PostgresClient) async throws
        -> CaptureResult?
    {
        let rows = try await client.query(
            """
            SELECT r.payload_digest,r.root_block_id,r.committed_at,EXISTS(SELECT 1 FROM inkcre.blocks b WHERE b.id=r.root_block_id)
            FROM inkcre.capture_receipts r WHERE r.submission_id=\(id)
            """)
        for try await (saved, root, date, exists) in rows.decode((String, Int, Date, Bool).self) {
            guard saved == digest else { throw PeerError.needsAction("提交身份与已保存材料冲突，原材料已保留。") }
            return CaptureResult(
                submissionID: id, rootBlockID: root, committedAt: date,
                availability: exists ? .available : .deleted)
        }
        return nil
    }

    public func submit(_ record: CaptureRecord, secret: String) async throws -> CaptureResult {
        guard let target = record.target, let payload = record.payload else {
            throw PeerError.invalid("待办缺少冻结材料或目标。")
        }
        let command = try CaptureCommit(payload)
        let graphDigest = SHA256.hash(data: try CaptureJSON.encode(command.graph)).map {
            String(format: "%02x", $0)
        }.joined()
        do {
            let client = try await database.client(for: target, password: secret)
            let result = try await client.withTransaction(logger: PeerDatabase.logger) { connection in
                try await PeerDatabase.requireSelection(
                    Self.descriptor, peerID: target.peerID, on: connection)
                // The UUID lock covers receipt lookup, graph writes and the receipt itself.
                try await connection.query(
                    "SELECT pg_advisory_xact_lock(hashtextextended(\(record.id.uuidString.lowercased()),0))",
                    logger: PeerDatabase.logger)
                let rows = try await connection.query(
                    """
                    SELECT r.payload_digest,r.graph_digest,r.root_block_id,r.committed_at,EXISTS(SELECT 1 FROM inkcre.blocks b WHERE b.id=r.root_block_id)
                    FROM inkcre.capture_receipts r WHERE r.submission_id=\(record.id)
                    """, logger: PeerDatabase.logger)
                for try await (saved, graph, root, date, exists) in rows.decode(
                    (String, String, Int, Date, Bool).self)
                {
                    guard saved == command.payload_digest, graph == graphDigest else {
                        throw PeerError.needsAction("提交身份与已保存材料或图冲突。")
                    }
                    return CaptureResult(
                        submissionID: record.id, rootBlockID: root, committedAt: date,
                        availability: exists ? .available : .deleted)
                }
                let ids = try await InfoBase.persist(
                    blocks: command.graph.blocks, relations: command.graph.relations,
                    blobs: Dictionary(
                        uniqueKeysWithValues: command.graph.blobs.map { ($0.block_id, $0.data_base64) }),
                    on: connection
                )
                guard let root = ids[command.graph.root_local_id] else { throw PeerError.invalid("采集图缺少根。") }
                let inserted = try await connection.query(
                    """
                    INSERT INTO inkcre.capture_receipts(submission_id,payload_digest,graph_digest,root_block_id)
                    VALUES (\(record.id),\(command.payload_digest),\(graphDigest),\(root)) RETURNING committed_at
                    """, logger: PeerDatabase.logger)
                for try await date in inserted.decode(Date.self) {
                    return CaptureResult(
                        submissionID: record.id, rootBlockID: root, committedAt: date,
                        availability: .available)
                }
                throw PeerError.outcomeUnknown
            }
            guard let persisted = try await recover(record, secret: secret),
                persisted.rootBlockID == result.rootBlockID
            else { throw PeerError.outcomeUnknown }
            return persisted
        } catch { throw PeerDatabase.failure(error, dispatched: true) }
    }

}
