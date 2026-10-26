import Foundation
import PeerCore

/// Capture owns this graph; the Host supplies transaction and storage mechanics.
// Capture 的序列化字段遵循跨端图协议。
// swift-format-ignore: AlwaysUseLowerCamelCase
struct CaptureCommit: Sendable {
    struct Graph: Sendable {
        let root_local_id = -1
        var blocks: [GraphBlock]
        var relations: [GraphRelation] = []
        var blobs: [Int: Data] = [:]
    }

    let payload_digest: String
    let graph: Graph

    init(_ payload: CapturePayload) throws {
        try payload.validate()
        let digest = try payload.canonicalDigest()
        struct Metadata: Encodable {
            let submission_id: String
            let payload_digest: String
            let captured_at: Date
            let entry: CaptureEntry
            let origin: CaptureOrigin?
        }
        struct Attachment: Encodable {
            let mime_type: String
            let filename: String?
        }
        func json<T: Encodable>(_ value: T) throws -> String {
            String(decoding: try CaptureJSON.encode(value), as: UTF8.self)
        }
        var graph = Graph(blocks: [
            GraphBlock(
                id: -1, resolver: "extensions.capture.capture.v1",
                content: try json(
                    Metadata(
                        submission_id: payload.submissionID.uuidString.lowercased(),
                        payload_digest: digest,
                        captured_at: payload.capturedAt, entry: payload.entry,
                        origin: payload.origin))
            )
        ])
        for (index, material) in payload.materials.enumerated() {
            let id = -(graph.blocks.count + 1)
            switch material.kind {
            case .text:
                guard let text = material.text else { throw PeerError.invalid("文字材料格式不正确。") }
                graph.blocks.append(GraphBlock(id: id, resolver: "core.text.v1", content: text))
            case .image:
                guard let bytes = material.data, let mime = material.mimeType else {
                    throw PeerError.invalid("图片材料格式不正确。")
                }
                graph.blocks.append(
                    GraphBlock(
                        id: id, resolver: "extensions.capture.attachment.v1",
                        content: try json(Attachment(mime_type: mime, filename: material.filename))
                    ))
                graph.blocks.append(GraphBlock(id: id - 1, resolver: "core.image.v1", content: ""))
                graph.blobs[id - 1] = bytes
                graph.relations.append(GraphRelation(from_: id, to_: id - 1, content: "content"))
            }
            graph.relations.append(GraphRelation(from_: -1, to_: id, content: "material:\(index)"))
        }
        if let annotation = payload.annotation, !annotation.isEmpty {
            let id = -(graph.blocks.count + 1)
            graph.blocks.append(GraphBlock(id: id, resolver: "core.text.v1", content: annotation))
            graph.relations.append(GraphRelation(from_: -1, to_: id, content: "annotation"))
        }
        payload_digest = digest
        self.graph = graph
    }
}
