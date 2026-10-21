import CaptureCore
import Foundation
import Synchronization
import Testing

private final class StubTransport: URLProtocol, @unchecked Sendable {
    static let handler = Mutex<(@Sendable (URLRequest) throws -> Data)?>(nil)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let callback = Self.handler.withLock { $0 }
            let unwrapped = try #require(callback)
            let data = try unwrapped(request)
            let response = try #require(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct PeerClientTests {
    private func client() -> PeerClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubTransport.self]
        return PeerClient(session: URLSession(configuration: configuration))
    }

    @Test func recoveryRejectsSameIdentityWithDifferentMaterials() async throws {
        var record = CaptureRecord(payload: CapturePayload(materials: [Material(text: "本机原材料")]))
        record.target = ConnectionTarget(postgrestURL: URL(string: "https://fixture.test")!)
        let identity = record.id.uuidString
        StubTransport.handler.withLock { handler in
            handler = { request in
                #expect(request.url?.path == "/capture_receipts")
                return Data("""
                    [{"submission_id":"\(identity)","payload_digest":"\(String(repeating: "0", count: 64))",
                      "root_block_id":42,"committed_at":"2026-10-21T01:02:03Z"}]
                    """.utf8)
            }
        }
        defer { StubTransport.handler.withLock { $0 = nil } }
        do {
            _ = try await client().recover(record, secret: String(repeating: "s", count: 32))
            Issue.record("冲突回执不能确认本机材料")
        } catch CaptureError.needsAction(let message) {
            #expect(message.contains("指纹"))
        }
    }

    @Test func anotherExecutorCanAcceptTheSameFrozenIntentAfterUnknownOutcome() async throws {
        var record = CaptureRecord(payload: CapturePayload(materials: [Material(text: "保持同一份材料")]))
        record.target = ConnectionTarget(postgrestURL: URL(string: "https://fixture.test")!)
        let identity = record.id.uuidString
        let received = Mutex<[String]>([])
        let receiptPublished = Mutex(false)
        let payload = try #require(record.payload)
        let digest = try payload.canonicalDigest()
        StubTransport.handler.withLock { handler in
            handler = { request in
                switch request.url?.path {
                case "/rpc/renew_peer_lease": return Data("\"2026-10-21T01:04:03Z\"".utf8)
                case "/peers" where request.httpMethod == "GET":
                    return Data("""
                        [{"id":"00000000-0000-4000-8000-000000000001","capabilities":[
                          {"id":"unrelated","inbound":{"protocol":"other.v1","parameters":{"method":42}}},
                          {"id":"extensions.capture.submit.v1","inbound":{"protocol":"core.peer.protocol.http.v1","parameters":{"method":"POST","url":"https://first.test/capture"}}}]},
                         {"id":"00000000-0000-4000-8000-000000000002","capabilities":[
                          {"id":"extensions.capture.submit.v1","inbound":{"protocol":"core.peer.protocol.http.v1","parameters":{"method":"POST","url":"https://second.test/capture"}}}]}]
                        """.utf8)
                case "/capture":
                    let host = request.url!.host!
                    received.withLock { $0.append(host) }
                    if host == "first.test" { throw URLError(.networkConnectionLost) }
                    return Data("""
                        {"submission_id":"\(identity)","root_block_id":42,"committed_at":"2026-10-21T01:02:03Z","availability":"available"}
                        """.utf8)
                case "/capture_receipts":
                    guard receiptPublished.withLock({ $0 }) else { return Data("[]".utf8) }
                    return Data("""
                        [{"submission_id":"\(identity)","payload_digest":"\(digest)","root_block_id":42,
                          "committed_at":"2026-10-21T01:02:03Z"}]
                        """.utf8)
                case "/blocks": return Data("[{\"id\":42}]".utf8)
                default: return Data()
                }
            }
        }
        defer { StubTransport.handler.withLock { $0 = nil } }
        let peer = client()
        record.attempts = 1
        await #expect(throws: CaptureError.self) {
            _ = try await peer.submit(record, secret: String(repeating: "s", count: 32))
        }
        record.attempts = 2
        // An HTTP success without its durable shared receipt must not release local material.
        await #expect(throws: CaptureError.self) {
            _ = try await peer.submit(record, secret: String(repeating: "s", count: 32))
        }
        receiptPublished.withLock { $0 = true }
        let result = try await peer.submit(record, secret: String(repeating: "s", count: 32))
        #expect(result.submissionID == record.id)
        #expect(received.withLock { $0 } == ["first.test", "second.test", "second.test"])
    }
}
