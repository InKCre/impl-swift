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

    @Test func writesDirectlyToDatabaseAndRetriesIdenticalGraphAfterUnknownOutcome() async throws {
        var record = CaptureRecord(payload: CapturePayload(materials: [Material(text: "保持同一份材料")]))
        record.target = ConnectionTarget(postgrestURL: URL(string: "https://fixture.test")!)
        let identity = record.id.uuidString
        let received = Mutex<[String]>([])
        let receiptPublished = Mutex(false)
        let digest = try #require(record.payload).canonicalDigest()
        StubTransport.handler.withLock { handler in
            handler = { request in
                #expect(request.url?.host == "fixture.test")
                #expect(request.value(forHTTPHeaderField: "Accept-Profile") == "inkcre")
                switch request.url?.path {
                case "/rpc/commit_capture":
                    #expect(request.httpMethod == "POST")
                    let attempt = received.withLock { $0.append(request.url!.path); return $0.count }
                    if attempt == 1 { throw URLError(.networkConnectionLost) }
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
                default:
                    Issue.record("写入不能发现或调用其他 Peer：\(request.url?.path ?? "")")
                    throw URLError(.unsupportedURL)
                }
            }
        }
        defer { StubTransport.handler.withLock { $0 = nil } }
        let peer = client()
        await #expect(throws: CaptureError.self) {
            _ = try await peer.submit(record, secret: String(repeating: "s", count: 32))
        }
        // An HTTP success without its durable shared receipt must not release local material.
        await #expect(throws: CaptureError.self) {
            _ = try await peer.submit(record, secret: String(repeating: "s", count: 32))
        }
        receiptPublished.withLock { $0 = true }
        let result = try await peer.submit(record, secret: String(repeating: "s", count: 32))
        #expect(result.submissionID == record.id)
        #expect(received.withLock { $0.count == 3 })
    }
}
