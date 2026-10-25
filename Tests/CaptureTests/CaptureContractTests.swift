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
    let data = try CaptureJSON.encode(CaptureCommit(fixture.payload))
    #expect(data == (try CaptureJSON.encode(CaptureCommit(fixture.payload))))
    let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(document["payload_digest"] as? String == fixture.digest)
    let graph = try #require(document["graph"] as? [String: Any])
    let blocks = try #require(graph["blocks"] as? [[String: Any]])
    let relations = try #require(graph["relations"] as? [[String: Any]])
    let blobs = try #require(graph["blobs"] as? [[String: Any]])
    #expect(blocks.map { $0["id"] as? Int } == [-1, -2, -3, -4, -5])
    #expect(
        blocks.map { $0["resolver"] as? String } == [
            "extensions.capture.capture.v1", "core.text.v1",
            "extensions.capture.attachment.v1", "core.image.v1", "core.text.v1",
        ])
    #expect(blocks[1]["content"] as? String == fixture.payload.materials[0].text)
    #expect(blocks[4]["content"] as? String == fixture.payload.annotation)
    #expect(
        relations.map { $0["content"] as? String } == [
            "material:0", "content", "material:1", "annotation",
        ])
    #expect(blobs.count == 1 && blobs[0]["block_id"] as? Int == -4)
    #expect(
        Data(base64Encoded: try #require(blobs[0]["data_base64"] as? String))
            == fixture.payload.materials[1].data)
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
