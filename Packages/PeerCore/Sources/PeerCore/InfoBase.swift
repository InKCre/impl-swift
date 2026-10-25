import Foundation
import PostgresNIO

public struct GraphBlock: Sendable, Encodable {
    public let id: Int
    public let resolver: String
    public let content: String
    public init(id: Int, resolver: String, content: String) {
        self.id = id
        self.resolver = resolver
        self.content = content
    }
}
// 数据库图协议直接使用 from_／to_ 字段。
// swift-format-ignore: AlwaysUseLowerCamelCase
public struct GraphRelation: Sendable, Encodable {
    public let from_: Int
    public let to_: Int
    public let content: String
    public init(from_: Int, to_: Int, content: String) {
        self.from_ = from_
        self.to_ = to_
        self.content = content
    }
}

/// Uses the caller's transaction; storage pointers and byte mechanics belong to the Host.
public enum InfoBase {
    public static func persist(
        blocks: [GraphBlock], relations: [GraphRelation],
        blobs: [Int: Data], on connection: PostgresConnection
    ) async throws -> [Int: Int] {
        var ids: [Int: Int] = [:]
        for block in blocks {
            var content = block.content
            var storage: Int? = nil
            if let bytes = blobs[block.id] {
                let blobID = UUID()
                try await connection.query(
                    "INSERT INTO inkcre.storage_blobs(id,data) VALUES (\(blobID),\(bytes))",
                    logger: PeerDatabase.logger)
                content = "{\"blob_id\":\"\(blobID.uuidString.lowercased())\"}"
                storage = -4
            }
            let rows = try await connection.query(
                """
                INSERT INTO inkcre.blocks(resolver,content,storage) VALUES (\(block.resolver),\(content),\(storage)) RETURNING id
                """, logger: PeerDatabase.logger)
            for try await id in rows.decode(Int.self) { ids[block.id] = id }
        }
        for relation in relations {
            guard let from = ids[relation.from_], let to = ids[relation.to_] else {
                throw PeerError.invalid("图关系引用了本次提交以外的 Block。")
            }
            try await connection.query(
                "INSERT INTO inkcre.relations(from_,to_,content) VALUES (\(from),\(to),\(relation.content))",
                logger: PeerDatabase.logger)
        }
        return ids
    }
}
