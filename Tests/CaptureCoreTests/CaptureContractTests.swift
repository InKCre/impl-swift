import CaptureCore
import Foundation
import Testing

@Test func pythonAndSwiftAgreeOnFrozenPayloadDigest() throws {
    struct Fixture: Decodable { let payload: CapturePayload; let digest: String }
    let url = try #require(Bundle.module.url(forResource: "capture-v1", withExtension: "json", subdirectory: "Fixtures"))
    let fixtures = try CaptureJSON.decode([Fixture].self, from: Data(contentsOf: url))
    for fixture in fixtures {
        #expect(try fixture.payload.canonicalDigest() == fixture.digest)
        var changed = fixture.payload
        changed.annotation = "不同的意图"
        #expect(try changed.canonicalDigest() != fixture.digest)
    }
}
