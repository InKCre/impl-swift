import Foundation
import PeerCore
import Testing

@testable import Capture

@Test func sharedMaterialFingerprintMatchesCrossDistributionFixtures() throws {
    struct Fixture: Decodable {
        let payload: CapturePayload
        let digest: String
    }
    let url = try #require(
        Bundle.module.url(
            forResource: "capture-v1", withExtension: "json", subdirectory: "Fixtures"))
    let fixtures = try CaptureJSON.decode([Fixture].self, from: Data(contentsOf: url))
    for fixture in fixtures {
        #expect(try fixture.payload.canonicalDigest() == fixture.digest)
        var changed = fixture.payload
        changed.annotation = "不同的意图"
        #expect(try changed.canonicalDigest() != fixture.digest)
    }
}

@Test func nativeGraphSeparatesOriginalsImageSourceAndAnnotation() throws {
    struct Fixture: Decodable {
        let payload: CapturePayload
        let digest: String
    }
    let url = try #require(
        Bundle.module.url(
            forResource: "capture-v1", withExtension: "json", subdirectory: "Fixtures"))
    let fixture = try CaptureJSON.decode([Fixture].self, from: Data(contentsOf: url))[1]
    let command = try CaptureCommit(fixture.payload)
    let graph = command.graph
    #expect(command.payload_digest == fixture.digest)
    #expect(graph.blocks.map(\.id) == [-1, -2, -3, -4, -5])
    #expect(
        graph.blocks.map(\.resolver) == [
            "extensions.capture.capture.v1", "core.text.v1",
            "extensions.capture.attachment.v1", "core.image.v1", "core.text.v1",
        ])
    let root = try #require(
        JSONSerialization.jsonObject(with: Data(graph.blocks[0].content.utf8)) as? [String: Any])
    #expect(
        root["submission_id"] as? String == fixture.payload.submissionID.uuidString.lowercased())
    #expect(root["payload_digest"] as? String == fixture.digest)
    #expect(graph.blocks[1].content == fixture.payload.materials[0].text)
    #expect(graph.blocks[4].content == fixture.payload.annotation)
    #expect(
        graph.relations.map(\.content) == ["material:0", "content", "material:1", "annotation"])
    #expect(graph.blobs.count == 1 && graph.blobs[-4] == fixture.payload.materials[1].data)
}

@Test func nativeValidationRejectsMismatchedImagesAndCountsUTF8Bytes() throws {
    struct Fixture: Decodable { let payload: CapturePayload }
    let url = try #require(
        Bundle.module.url(
            forResource: "capture-v1", withExtension: "json", subdirectory: "Fixtures"))
    let image = try #require(
        CaptureJSON.decode([Fixture].self, from: Data(contentsOf: url))[1].payload.materials[1].data
    )
    #expect(throws: PeerError.self) {
        try CapturePayload(materials: [Material(image: image, mimeType: "image/jpeg")]).validate()
    }
    #expect(throws: PeerError.self) {
        try CapturePayload(materials: [Material(image: Data("broken".utf8), mimeType: "image/png")])
            .validate()
    }
    let text = String(repeating: "x", count: 32 * 1024 * 1024 - 3)
    try CapturePayload(materials: [Material(text: text)], annotation: "中").validate()
    #expect(throws: PeerError.self) {
        try CapturePayload(materials: [Material(text: text)], annotation: "中文").validate()
    }
}
