import CaptureCore
import Foundation
import Security
import Testing

@Test(.enabled(if: ProcessInfo.processInfo.environment["INKCRE_CAPTURE_TEST_POSTGREST"] != nil))
func liveQueueConfirmsOriginalImageAndRecoversReceiptAfterRestart() async throws {
    let environment = ProcessInfo.processInfo.environment
    let address = try #require(environment["INKCRE_CAPTURE_TEST_POSTGREST"])
    let target = ConnectionTarget(postgrestURL: try #require(URL(string: address)))
    let secret = try #require(environment["INKCRE_CAPTURE_TEST_SECRET"])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let service = "dev.inkcre.capture.acceptance.\(UUID().uuidString)"
    let credentials = CredentialStore(service: service)
    try credentials.save(secret, for: target.id)
    defer {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: target.id.uuidString,
        ] as CFDictionary)
        try? FileManager.default.removeItem(at: directory)
    }
    struct Fixture: Decodable { let payload: CapturePayload }
    let fixtureURL = try #require(Bundle.module.url(forResource: "capture-v1", withExtension: "json", subdirectory: "Fixtures"))
    let fixture = try CaptureJSON.decode([Fixture].self, from: Data(contentsOf: fixtureURL))[1]
    let payload = CapturePayload(entry: .paste, origin: fixture.payload.origin,
                                 materials: fixture.payload.materials, annotation: fixture.payload.annotation)
    let store = try CaptureStore(url: directory.appendingPathComponent("capture.sqlite"))
    let frozen = try await store.freeze(CaptureRecord(payload: payload), target: target)
    let queue = CaptureQueue(store: store, credentials: credentials)
    try await queue.process(force: true)
    if environment["INKCRE_CAPTURE_TEST_DROP_RESPONSE"] == "1" {
        let uncertain = try #require(try await store.record(frozen.id))
        #expect(uncertain.state == .unknown)
        #expect(uncertain.payload?.materials[1].data == payload.materials[1].data)
        let reopened = try CaptureStore(url: directory.appendingPathComponent("capture.sqlite"))
        try await CaptureQueue(store: reopened, credentials: credentials).process(force: true)
    }
    let confirmed = try #require(try await store.record(frozen.id))
    #expect(confirmed.state == .confirmed, Comment(rawValue: confirmed.message ?? ""))
    #expect(confirmed.payload == nil)
    let result = try #require(confirmed.result)

    // A second local database represents a process that lost its success response.
    let recoveredStore = try CaptureStore(url: directory.appendingPathComponent("recovered.sqlite"))
    _ = try await recoveredStore.freeze(CaptureRecord(payload: payload), target: target)
    _ = try await recoveredStore.markDispatch(frozen.id)
    try await CaptureQueue(store: recoveredStore, credentials: credentials).process(force: true)
    let recovered = try #require(try await recoveredStore.record(frozen.id))
    #expect(recovered.result == result)
    #expect(recovered.payload == nil)
    var conflictingPayload = payload
    conflictingPayload.annotation = "同一身份，错误的其他材料"
    let conflictStore = try CaptureStore(url: directory.appendingPathComponent("conflict.sqlite"))
    _ = try await conflictStore.freeze(CaptureRecord(payload: conflictingPayload), target: target)
    try await CaptureQueue(store: conflictStore, credentials: credentials).process(force: true)
    let conflict = try #require(try await conflictStore.record(frozen.id))
    #expect(conflict.state == .needsAction)
    #expect(conflict.payload?.annotation == conflictingPayload.annotation)
    if let resultPath = environment["INKCRE_CAPTURE_TEST_RESULT"] {
        try CaptureJSON.encode(result).write(to: URL(fileURLWithPath: resultPath), options: .atomic)
    }
}
