import Capture
import Foundation
import PeerCore
import Security
import Testing

private actor PausedRecovery: CaptureTransport {
    private let pausedTarget: UUID?
    init(pausedTarget: UUID? = nil) { self.pausedTarget = pausedTarget }
    private var entered = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    private(set) var dispatches = 0
    func recover(_ record: CaptureRecord, secret: String) async throws -> CaptureResult? {
        if let pausedTarget, record.target?.id != pausedTarget {
            return CaptureResult(submissionID: record.id, rootBlockID: 123, committedAt: Date())
        }
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

private actor RecordingSubmissions: CaptureTransport {
    private(set) var submitted: [UUID] = []
    func recover(_ record: CaptureRecord, secret: String) async throws -> CaptureResult? { nil }
    func submit(_ record: CaptureRecord, secret: String) async throws -> CaptureResult {
        submitted.append(record.id)
        return CaptureResult(submissionID: record.id, rootBlockID: 123, committedAt: Date())
    }
}

@Test func captureQueueKeepsSubmissionOrderAfterRetryAndReopening() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let service = "dev.inkcre.queue-order.\(UUID())"
    defer {
        SecItemDelete(
            [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
                as CFDictionary)
        try? FileManager.default.removeItem(at: directory)
    }
    let target = ConnectionTarget(host: "localhost", database: "inkcre", username: "test")
    let credentials = CredentialStore(service: service)
    let connections = ConnectionSettings(url: directory.appendingPathComponent("connection.json"))
    try await connections.save(target)
    try credentials.save("test-password", for: target.id)
    let url = directory.appendingPathComponent("capture.sqlite")
    let store = try CaptureStore(url: url)
    var drafts: [CaptureRecord] = []
    for index in 0..<3 {
        let draft = CaptureRecord(
            payload: CapturePayload(
                capturedAt: Date(timeIntervalSince1970: 1_780_000_000 + Double(index)),
                materials: [Material(text: "第 \(index + 1) 份材料")]))
        try await store.saveDraft(draft)
        drafts.append(draft)
    }
    // Capture and draft creation order are independent from submission order.
    var ids: [UUID] = []
    for draft in [drafts[2], drafts[0], drafts[1]] {
        _ = try await store.freeze(draft, target: target)
        ids.append(draft.id)
    }
    // Updating the middle record must affect its retry delay, never its position.
    _ = try await store.markDispatch(ids[1])
    try await store.retry(ids[1])
    let reopened = try CaptureStore(url: url)
    let transport = RecordingSubmissions()
    let queue = CaptureQueue(
        store: reopened, connections: connections, credentials: credentials, client: transport)
    try await queue.process(force: true)
    #expect(await transport.submitted == ids)
    #expect(try await reopened.records().allSatisfy { $0.state == .confirmed })
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
    let connections = ConnectionSettings(url: directory.appendingPathComponent("connection.json"))
    try await connections.save(target)
    try credentials.save("test-password", for: target.id)
    let store = try CaptureStore(url: directory.appendingPathComponent("capture.sqlite"))
    for text in ["第一份", "第二份"] {
        let frozen = try await store.freeze(
            CaptureRecord(payload: CapturePayload(materials: [Material(text: text)])),
            target: target)
        _ = try await store.markDispatch(frozen.id)
    }
    let transport = PausedRecovery()
    let queue = CaptureQueue(
        store: store, connections: connections, credentials: credentials, client: transport)
    let processing = Task { try await queue.process(force: true) }
    await transport.waitForRecovery()
    let stopped = Task { await queue.stop() }
    while !(await queue.isStopped) { await Task.yield() }
    await transport.finishRecovery()
    _ = try await processing.value
    await stopped.value
    try await queue.process(force: true)
    #expect(await transport.dispatches == 0)
    #expect(try await store.records().allSatisfy { $0.state == .unknown && $0.attempts == 1 })
}

@Test func aStalledInfoBaseDoesNotBlockAnotherCaptureDestination() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let service = "dev.inkcre.independent.\(UUID().uuidString)"
    defer {
        SecItemDelete(
            [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
                as CFDictionary)
        try? FileManager.default.removeItem(at: directory)
    }
    let first = ConnectionTarget(host: "localhost", database: "first", username: "test")
    let second = ConnectionTarget(host: "localhost", database: "second", username: "test")
    let credentials = CredentialStore(service: service)
    let connections = ConnectionSettings(url: directory.appendingPathComponent("connection.json"))
    let store = try CaptureStore(url: directory.appendingPathComponent("capture.sqlite"))
    var ids: [UUID] = []
    for target in [first, second] {
        try await connections.save(target)
        try credentials.save("test-password", for: target.id)
        let frozen = try await store.freeze(
            CaptureRecord(payload: CapturePayload(materials: [Material(text: target.database)])),
            target: target)
        _ = try await store.markDispatch(frozen.id)
        ids.append(frozen.id)
    }
    let transport = PausedRecovery(pausedTarget: first.id)
    let queue = CaptureQueue(
        store: store, connections: connections, credentials: credentials, client: transport)
    let processing = Task { try await queue.process(force: true) }
    await transport.waitForRecovery()
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while try await store.record(ids[1])?.result == nil, ContinuousClock.now < deadline {
        await Task.yield()
    }
    #expect(try await store.record(ids[1])?.result != nil)
    #expect(try await store.record(ids[0])?.payload != nil)
    let stopped = Task { await queue.stop() }
    while !(await queue.isStopped) { await Task.yield() }
    await transport.finishRecovery()
    _ = try await processing.value
    await stopped.value
    #expect(try await store.record(ids[0])?.state == .unknown)
}
