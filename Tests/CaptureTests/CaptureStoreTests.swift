import CSQLite
import Foundation
import PeerCore
import Testing

@testable import Capture

struct CaptureStoreTests {
    @Test func deletedDraftIsAbsentAfterRestartAndLateAutosaveCannotRecreateIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("capture.sqlite")
        let store = try CaptureStore(url: url)
        let draft = CaptureRecord(
            payload: CapturePayload(materials: [Material(text: "最后一次编辑")], annotation: "保留附注"))
        try await store.deleteRecord(draft.id)
        try await store.saveDraft(draft)
        await #expect(throws: PeerError.self) {
            _ = try await store.freeze(
                draft,
                target: ConnectionTarget(
                    host: "example.test", database: "inkcre", username: "inkcre_core"))
        }
        let reopened = try CaptureStore(url: url)
        #expect(try await reopened.record(draft.id) == nil)
        #expect(try await reopened.records().isEmpty)
    }

    @Test func cancelledIntentNeverAutomaticallyDispatches() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CaptureStore(url: directory.appendingPathComponent("capture.sqlite"))
        let target = ConnectionTarget(
            host: "example.test", database: "inkcre", username: "inkcre_core")
        let draft = CaptureRecord(payload: CapturePayload(materials: [Material(text: "尚未发送")]))
        _ = try await store.freeze(draft, target: target)
        try await store.cancel(draft.id)
        await #expect(throws: PeerError.self) { _ = try await store.markDispatch(draft.id) }
        try await store.report(draft.id, state: .pending, message: "迟到的错误")
        // No credential exists: an accidental dispatch would change the state to needsAction.
        let credentials = CredentialStore(service: "dev.inkcre.test.\(UUID().uuidString)")
        try await CaptureQueue(store: store, credentials: credentials).process(force: true)
        let retained = try #require(try await store.record(draft.id))
        #expect(retained.state == .cancelled)
        #expect(retained.attempts == 0)
        #expect(retained.target == target)
        #expect(retained.payload?.submissionID == draft.id)
        try await store.retry(draft.id)
        #expect(try await store.markDispatch(draft.id).id == draft.id)
    }

    @Test func cancellationKeepsUnknownOutcomeButDeletionIgnoresLateCallbacks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CaptureStore(url: directory.appendingPathComponent("capture.sqlite"))
        let draft = CaptureRecord(payload: CapturePayload(materials: [Material(text: "在途材料")]))
        _ = try await store.freeze(
            draft,
            target: ConnectionTarget(
                host: "example.test", database: "inkcre", username: "inkcre_core")
        )
        _ = try await store.markDispatch(draft.id)
        try await store.cancel(draft.id)
        try await store.report(draft.id, state: .unknown, message: "迟到的失败")
        let cancelled = try #require(try await store.record(draft.id))
        #expect(cancelled.state == .cancelled)
        #expect(cancelled.payload != nil)
        #expect(cancelled.message?.contains("可能已收入") == true)
        try await store.deleteRecord(draft.id)
        let result = CaptureResult(
            submissionID: draft.id, rootBlockID: 42,
            committedAt: Date(timeIntervalSince1970: 1_780_000_000), availability: .available)
        try await store.confirm(draft.id, result: result)
        try await store.report(draft.id, state: .unknown, message: "删除后的迟到失败")
        #expect(try await store.record(draft.id) == nil)
        #expect(try await store.records().isEmpty)
    }

    @Test func clearingDraftAndContinuingToTypeKeepsTheSameIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CaptureStore(url: directory.appendingPathComponent("capture.sqlite"))
        var draft = CaptureRecord(payload: CapturePayload(materials: [Material(text: "清空前")]))
        try await store.saveDraft(draft)
        try await store.discardDraft(draft.id)
        try await store.discardDraft(draft.id)
        draft.payload?.materials = [Material(text: "清空后继续输入")]
        try await store.saveDraft(draft)
        #expect(try await store.record(draft.id)?.payload?.materials.first?.text == "清空后继续输入")
    }

    @Test func failedFreezeRetainsTheSavedDraftAndCannotDispatch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("capture.sqlite")
        let store = try CaptureStore(url: url)
        let draft = CaptureRecord(payload: CapturePayload(materials: [Material(text: "保存失败仍须保留")]))
        try await store.saveDraft(draft)
        var connection: OpaquePointer?
        #expect(sqlite3_open(url.path, &connection) == SQLITE_OK)
        let db = try #require(connection)
        defer { sqlite3_close(db) }
        #expect(
            sqlite3_exec(
                db,
                """
                CREATE TRIGGER fail_write BEFORE INSERT ON records
                BEGIN SELECT RAISE(ABORT, 'acceptance storage failure'); END;
                """, nil, nil, nil) == SQLITE_OK)
        await #expect(throws: PeerError.self) {
            _ = try await store.freeze(
                draft,
                target: ConnectionTarget(
                    host: "example.test", database: "inkcre", username: "inkcre_core"))
        }
        let retained = try #require(try await store.record(draft.id))
        #expect(retained.state == .draft)
        #expect(retained.payload?.materials[0].text == "保存失败仍须保留")
        await #expect(throws: PeerError.self) { _ = try await store.markDispatch(draft.id) }
    }

    @Test func frozenMaterialSurvivesReopeningAndTargetChanges() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("capture.sqlite")
        let store = try CaptureStore(url: url)
        let target = ConnectionTarget(
            host: "one.example", database: "inkcre", username: "inkcre_core")
        let image = try #require(
            Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAUAAAAHCAIAAABPxRC5AAAAE0lEQVR4nGPkUbJgQAJMyBwa8AEvKAB0sOhdcgAAAABJRU5ErkJggg=="
            ))
        let draft = CaptureRecord(
            payload: CapturePayload(
                entry: .paste,
                materials: [
                    Material(text: "原文\n中文 👩🏽‍💻 e\u{301}"),
                    Material(image: image, mimeType: "image/png"),
                ],
                annotation: "自己的想法"
            ))
        try await store.saveDraft(draft)
        _ = try await store.freeze(draft, target: target)
        _ = try await store.markDispatch(draft.id)
        try await ConnectionSettings(url: directory.appendingPathComponent("connection.json")).save(
            ConnectionTarget(host: "two.example", database: "inkcre", username: "inkcre_core"))
        let reopened = try CaptureStore(url: url)
        let recovered = try #require(try await reopened.record(draft.id))
        #expect(recovered.state == .unknown)
        #expect(recovered.target == target)
        #expect(recovered.payload?.materials[0].text == draft.payload?.materials[0].text)
        #expect(recovered.payload?.materials[1].data == image)
        #expect(recovered.payload?.annotation == "自己的想法")
        await #expect(throws: PeerError.self) { try await reopened.saveDraft(draft) }
        await #expect(throws: PeerError.self) {
            _ = try await reopened.freeze(draft, target: target)
        }
    }

    @Test func confirmationAtomicallyRetainsIdentityAndClearsMaterial() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("capture.sqlite")
        let store = try CaptureStore(url: url)
        let draft = CaptureRecord(payload: CapturePayload(materials: [Material(text: "一次意图")]))
        _ = try await store.freeze(
            draft,
            target: ConnectionTarget(
                host: "example.test", database: "inkcre", username: "inkcre_core")
        )
        _ = try await store.markDispatch(draft.id)
        let result = CaptureResult(
            submissionID: draft.id, rootBlockID: 123,
            committedAt: Date(timeIntervalSince1970: 1_780_000_000),
            availability: .deleted
        )
        try await store.confirm(draft.id, result: result)
        let reopened = try CaptureStore(url: url)
        let recovered = try #require(try await reopened.record(draft.id))
        #expect(recovered.state == .confirmed)
        #expect(recovered.payload == nil)
        #expect(recovered.result == result)
        await #expect(throws: PeerError.self) { try await reopened.retry(draft.id) }
    }

    @Test func emptyDraftCannotEraseAnAlreadyFrozenIntention() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CaptureStore(url: directory.appendingPathComponent("capture.sqlite"))
        let target = ConnectionTarget(
            host: "example.test", database: "inkcre", username: "inkcre_core")
        await #expect(throws: PeerError.self) {
            _ = try await store.freeze(CaptureRecord(), target: target)
        }
        let first = CaptureRecord(payload: CapturePayload(materials: [Material(text: "相同内容")]))
        let second = CaptureRecord(payload: CapturePayload(materials: [Material(text: "相同内容")]))
        _ = try await store.freeze(first, target: target)
        _ = try await store.freeze(second, target: target)
        #expect(try await store.records().count == 2)
        #expect(first.id != second.id)
    }
}
