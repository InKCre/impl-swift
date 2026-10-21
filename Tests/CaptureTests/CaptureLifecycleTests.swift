import Capture
import Foundation
import PeerCore
import Security
import Testing

private actor PausedRecovery: CaptureTransport {
    private var entered = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    private(set) var dispatches = 0
    func recover(_ record: CaptureRecord, secret: String) async throws -> CaptureResult? {
        await withCheckedContinuation { continuation in
            release = continuation
            entered = true
            arrival?.resume()
            arrival = nil
        }
        return nil
    }
    func submit(_ record: CaptureRecord, secret: String) async throws -> CaptureResult {
        dispatches += 1
        throw PeerError.invalid("must not dispatch after stop")
    }
    func waitForRecovery() async {
        if !entered { await withCheckedContinuation { arrival = $0 } }
    }
    func finishRecovery() {
        release?.resume()
        release = nil
    }
}

@Test func stoppingCaptureWaitsForRecoveryAndPreventsFurtherDispatch() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let service = "dev.inkcre.lifecycle.\(UUID().uuidString)"
    defer {
        SecItemDelete(
            [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
                as CFDictionary)
        try? FileManager.default.removeItem(at: directory)
    }
    let target = ConnectionTarget(host: "localhost", database: "inkcre", username: "test")
    let credentials = CredentialStore(service: service)
    try credentials.save("test-password", for: target.id)
    let store = try CaptureStore(url: directory.appendingPathComponent("capture.sqlite"))
    for text in ["第一份", "第二份"] {
        _ = try await store.freeze(
            CaptureRecord(payload: CapturePayload(materials: [Material(text: text)])), target: target)
    }
    let transport = PausedRecovery()
    let queue = CaptureQueue(store: store, credentials: credentials, client: transport)
    let processing = Task { try await queue.process(force: true) }
    await transport.waitForRecovery()
    let stopped = Task { await queue.stop() }
    while !(await queue.isStopped) { await Task.yield() }
    await transport.finishRecovery()
    try await processing.value
    await stopped.value
    try await queue.process(force: true)
    #expect(await transport.dispatches == 0)
    #expect(try await store.records().allSatisfy { $0.state == .pending && $0.attempts == 0 })
}
