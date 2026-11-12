import Capture
import Foundation
import Security
import Testing

@testable import PeerCore

private actor PausedRecovery: CaptureWriting {
    private let pausedTarget: UUID?
    private let pausePreparation: Bool
    init(pausedTarget: UUID? = nil, pausePreparation: Bool = false) {
        self.pausedTarget = pausedTarget
        self.pausePreparation = pausePreparation
    }
    private var entered = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    private(set) var dispatches = 0
    func prepare(_ record: CaptureRecord, credentials: DatabaseCredentials) async throws {
        if pausePreparation { await pause() }
    }
    func recover(_ record: CaptureRecord, credentials: DatabaseCredentials) async throws
        -> CaptureResult?
    {
        if let pausedTarget, record.target?.id != pausedTarget {
            return CaptureResult(submissionID: record.id, rootBlockID: 123, committedAt: Date())
        }
        await pause()
        return nil
    }
    func submit(_ record: CaptureRecord, credentials: DatabaseCredentials) async throws
        -> CaptureResult
    {
        dispatches += 1
        throw PeerError.invalid("must not dispatch after stop")
    }
    private func pause() async {
        await withCheckedContinuation { continuation in
            release = continuation
            entered = true
            arrival?.resume()
            arrival = nil
        }
    }
    func waitForOperation() async {
        if !entered { await withCheckedContinuation { arrival = $0 } }
    }
    func finishOperation() {
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
    let writer = PausedRecovery()
    let queue = CaptureQueue(
        store: store, connections: connections, credentials: credentials, writer: writer)
    let processing = Task { try await queue.process(force: true) }
    await writer.waitForOperation()
    let stopped = Task { await queue.stop() }
    while !(await queue.isStopped) { await Task.yield() }
    await writer.finishOperation()
    _ = try await processing.value
    await stopped.value
    try await queue.process(force: true)
    #expect(await writer.dispatches == 0)
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
    let writer = PausedRecovery(pausedTarget: first.id)
    let queue = CaptureQueue(
        store: store, connections: connections, credentials: credentials, writer: writer)
    let processing = Task { try await queue.process(force: true) }
    await writer.waitForOperation()
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while try await store.record(ids[1])?.result == nil, ContinuousClock.now < deadline {
        await Task.yield()
    }
    #expect(try await store.record(ids[1])?.result != nil)
    #expect(try await store.record(ids[0])?.payload != nil)
    let stopped = Task { await queue.stop() }
    while !(await queue.isStopped) { await Task.yield() }
    await writer.finishOperation()
    _ = try await processing.value
    await stopped.value
    #expect(try await store.record(ids[0])?.state == .unknown)
}

private actor PreparedCaptureWriter: CaptureWriting {
    let writer: CaptureWriter
    private(set) var dispatches = 0
    private(set) var recoveries = 0
    init(database: PeerDatabase) { writer = CaptureWriter(database: database) }
    func prepare(_ record: CaptureRecord, credentials: DatabaseCredentials) async throws {
        try await writer.prepare(record, credentials: credentials)
    }
    func recover(_ record: CaptureRecord, credentials: DatabaseCredentials) async throws
        -> CaptureResult?
    {
        recoveries += 1
        return nil
    }
    func submit(_ record: CaptureRecord, credentials: DatabaseCredentials) async throws
        -> CaptureResult
    {
        dispatches += 1
        return CaptureResult(submissionID: record.id, rootBlockID: 42, committedAt: Date())
    }
}

@Test func unavailableFirstAuthenticationPreservesAnUnsentCaptureAndRetryIdentity() async throws {
    let fixture = try CredentialStoreTests.Fixture()
    let credentials = CredentialStore(
        service: "dev.inkcre.first-attempt.\(UUID())", keychain: fixture.keychain)
    let target = ConnectionTarget(host: "localhost", database: "unused", username: "peer")
    try credentials.save("fixture", for: target.id)
    #expect(
        try CredentialStore.withAccess(allowInteraction: false) {
            SecKeychainLock(fixture.keychain)
        } == errSecSuccess)
    let connections = ConnectionSettings(
        url: fixture.directory.appendingPathComponent("connection.json"))
    try await connections.save(target)
    let store = try CaptureStore(url: fixture.directory.appendingPathComponent("capture.sqlite"))
    let frozen = try await store.freeze(
        CaptureRecord(payload: CapturePayload(materials: [Material(text: "首次不可用仍未发送")])),
        target: target)
    let database = PeerDatabase()
    let writer = PreparedCaptureWriter(database: database)
    let queue = CaptureQueue(
        store: store, connections: connections, credentials: credentials, writer: writer)
    try await queue.process(force: true)
    let failed = try #require(try await store.record(frozen.id))
    #expect(failed.state == .needsAction && failed.attempts == 0)
    #expect(failed.id == frozen.id && failed.target == frozen.target)
    #expect(try CaptureJSON.encode(failed.payload) == CaptureJSON.encode(frozen.payload))
    #expect(await writer.dispatches == 0)
    #expect(await writer.recoveries == 0)
    let cancelled = try await store.cancel(frozen.id)
    #expect(cancelled.attempts == 0 && cancelled.message?.contains("尚未发送") == true)
    try await store.retry(frozen.id)
    #expect(try await store.record(frozen.id)?.state == .pending)
    try fixture.unlock()
    try await queue.process(force: true)
    let confirmed = try #require(try await store.record(frozen.id))
    #expect(confirmed.state == .confirmed && confirmed.attempts == 1)
    #expect(confirmed.result?.submissionID == frozen.id && confirmed.target == frozen.target)
    #expect(await writer.dispatches == 1)
    #expect(await writer.recoveries == 0)
    await database.shutdown()
}

@Test(arguments: [false, true])
func stoppingOrCancellingDuringFirstAuthenticationLeavesCaptureUnsent(cancel: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = ConnectionTarget(host: "localhost", database: "unused", username: "peer")
    let connections = ConnectionSettings(url: directory.appendingPathComponent("connection.json"))
    try await connections.save(target)
    let store = try CaptureStore(url: directory.appendingPathComponent("capture.sqlite"))
    let frozen = try await store.freeze(
        CaptureRecord(payload: CapturePayload(materials: [Material(text: "停止首次发送")])),
        target: target)
    let writer = PausedRecovery(pausePreparation: true)
    let queue = CaptureQueue(
        store: store, connections: connections,
        credentials: CredentialStore(service: "unused-first-attempt"), writer: writer)
    let processing = Task { try await queue.process(force: true) }
    await writer.waitForOperation()
    let stopped: Task<Void, Never>?
    if cancel {
        processing.cancel()
        stopped = nil
    } else {
        stopped = Task { await queue.stop() }
        while !(await queue.isStopped) { await Task.yield() }
    }
    await writer.finishOperation()
    _ = try await processing.value
    await stopped?.value
    #expect(await writer.dispatches == 0)
    let unsent = try #require(try await store.record(frozen.id))
    #expect(unsent.state == .pending && unsent.attempts == 0)
    #expect(unsent.id == frozen.id && unsent.target == frozen.target)
    #expect(try CaptureJSON.encode(unsent.payload) == CaptureJSON.encode(frozen.payload))
}
