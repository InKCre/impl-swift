import AppKit
import Capture
import PeerCore
import Testing
import Security
@testable import CaptureMac

@Suite(.serialized) @MainActor
struct CaptureInteractionTests {
    @Test func emptyCaptureShortcutDoesNotOpenConnectionOrStartSubmission() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(directory: directory, identity: "dev.inkcre.test.\(UUID().uuidString)")
        defer { model.cancelWork() }
        var mainOpened = false
        model.editConnection = { _, _ in mainOpened = true }
        model.submit()
        #expect(!model.hasContent)
        #expect(!model.submitting)
        #expect(!mainOpened)
        #expect(model.pane == .capture)
        #expect(model.error == nil)
    }

    @Test func backgroundQueueRefreshCannotReplaceNewDraftFeedbackWithAnOldRecord() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(directory: directory, identity: "dev.inkcre.test.\(UUID().uuidString)")
        defer { model.cancelWork() }
        let old = CaptureRecord(payload: CapturePayload(materials: [Material(text: "旧的已收入记录")]))
        try await model.store.saveDraft(old)
        _ = try await model.store.freeze(old, target: ConnectionTarget(host: "fixture.test", database: "inkcre", username: "inkcre_core"))
        try await model.store.confirm(old.id, result: CaptureResult(
            submissionID: old.id, rootBlockID: 42, committedAt: Date(), availability: .available
        ))
        model.newThought()
        for _ in 0..<100 where model.submitting { try await Task.sleep(for: .milliseconds(10)) }
        let newDraftID = model.draft.id
        let feedback = model.saveStatus
        await model.sendPending()
        #expect(model.draft.id == newDraftID)
        #expect(model.saveStatus == feedback)
        #expect(model.error == nil)
    }

    @Test func quickCaptureDoesNotChangeMainWindowNavigationAndUsesTheSameDraft() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(directory: directory, identity: "dev.inkcre.test.\(UUID().uuidString)")
        defer { model.cancelWork() }
        model.thought = "主窗口中未提交的草稿"
        let previousID = model.draft.id
        model.pane = .peer
        model.editorOwner = .quick
        var presented: CaptureModel.EditorOwner?
        model.presentEditor = { presented = model.editorOwner }
        let payload = CapturePayload(entry: .selection, materials: [Material(text: "快捷采集的新材料")])
        await model.receive(payload)
        #expect(model.pane == .peer)
        #expect(presented == .quick)
        #expect(model.draft.id == payload.submissionID)
        #expect(try await model.store.record(previousID)?.payload?.materials.first?.text == "主窗口中未提交的草稿")
        let currentID = model.draft.id
        model.editorOwner = .main
        #expect(model.draft.id == currentID)
        #expect(model.thought == "快捷采集的新材料")
        var mainOpened = false
        model.showMain = { mainOpened = true }
        model.continueInMain()
        #expect(mainOpened)
        #expect(model.pane == .capture)
        #expect(model.draft.id == currentID)
    }

    @Test(arguments: [false, true])
    func missingConnectionReturnsToTheOriginalDraftWithoutSubmitting(saved: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(directory: directory, identity: "dev.inkcre.test.\(UUID().uuidString)")
        defer { model.cancelWork() }
        await model.receive(CapturePayload(materials: [Material(text: "连接后继续收入的原文")], annotation: "原附注"))
        let original = model.draft
        model.editorOwner = .quick
        var completion: (@MainActor () -> Void)?
        model.editConnection = { target, callback in
            #expect(target == nil)
            completion = callback
            model.editorOwner = .main
        }
        var returnedTo: CaptureModel.EditorOwner?
        model.presentEditor = { returnedTo = model.editorOwner }
        model.submit()
        #expect(returnedTo == nil)
        if saved { model.connection = ConnectionTarget(host: "fixture.test", database: "inkcre", username: "test") }
        let finish = try #require(completion)
        finish()
        #expect(returnedTo == .quick)
        #expect(model.draft.id == original.id)
        #expect(try CaptureJSON.encode(model.draft.payload) == CaptureJSON.encode(original.payload))
        #expect(model.draft.state == .draft && !model.submitting)
        #expect(try await model.store.record(original.id)?.state == .draft)
        #expect(model.submittedRecord == nil)
        returnedTo = nil
        model.draft = CaptureRecord()
        completion?()
        #expect(returnedTo == nil)
    }

    @Test func passwordRepairRetriesTheFrozenTargetWhileKeepingTheActiveConnection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let identity = "dev.inkcre.password.\(UUID().uuidString)"
        defer {
            SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                           kSecAttrService as String: "\(identity).connections"] as CFDictionary)
            try? FileManager.default.removeItem(at: directory)
        }
        let transport = JourneyTransport()
        let model = try CaptureModel(directory: directory, identity: identity, client: transport)
        defer { model.cancelWork() }
        let originalTarget = ConnectionTarget(host: "original.test", database: "original", username: "test")
        let active = ConnectionTarget(host: "active.test", database: "active", username: "test")
        model.connection = active
        try await model.connections.save(active)
        let draft = CaptureRecord(payload: CapturePayload(materials: [Material(text: "原提交材料")]))
        _ = try await model.store.freeze(draft, target: originalTarget)
        let cancelled = try await model.store.cancel(draft.id)
        // Merely opening and cancelling the editor must leave cancelled work dormant.
        await model.sendPending(force: true)
        #expect(await transport.calls.isEmpty)
        try await model.updatePassword("new-fixture-password", for: cancelled)
        for _ in 0..<100 where model.records.first?.state != .confirmed { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.connection == active)
        #expect(try await model.connections.load() == active)
        let calls = await transport.calls
        #expect(calls.map(\.kind) == ["recover", "submit"])
        for call in calls {
            #expect(call.record.id == draft.id && call.record.target == originalTarget && call.secret == "new-fixture-password")
            #expect(try CaptureJSON.encode(call.record.payload) == CaptureJSON.encode(draft.payload))
        }
        #expect(model.records.first?.state == .confirmed)
    }

    @Test func submittedFeedbackRemainsFindableWhileWritingTheNextDraft() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let identity = "dev.inkcre.feedback.\(UUID().uuidString)"
        defer {
            SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                           kSecAttrService as String: "\(identity).connections"] as CFDictionary)
            try? FileManager.default.removeItem(at: directory)
        }
        let model = try CaptureModel(directory: directory, identity: identity, client: JourneyTransport())
        defer { model.cancelWork() }
        let target = ConnectionTarget(host: "fixture.test", database: "inkcre", username: "test")
        model.connection = target
        try model.credentials.save("fixture", for: target.id)
        model.thought = "第一条想法"
        let submittedID = model.draft.id
        model.submit()
        for _ in 0..<100 where model.submittedRecord?.state != .confirmed { try await Task.sleep(for: .milliseconds(10)) }
        let record = try #require(model.submittedRecord)
        #expect(record.id == submittedID && record.state == .confirmed)
        model.thought = "下一条尚未收入的想法"
        let nextID = model.draft.id
        try await model.flush()
        #expect(model.saveStatus == "草稿已保留在本机")
        #expect(model.submittedRecord?.id == submittedID)
        var mainOpened = false
        model.showMain = { mainOpened = true }
        model.showRecord(record)
        #expect(mainOpened && model.pane == .queue && model.selectedRecordID == submittedID)
        #expect(model.draft.id == nextID && model.thought == "下一条尚未收入的想法")
    }

    @Test func historicalWebAddressUpdatesOnlyThatRecordsDisplayMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(directory: directory, identity: "dev.inkcre.web.\(UUID().uuidString)")
        defer { model.cancelWork() }
        let original = ConnectionTarget(host: "original.test", database: "original", username: "test")
        let active = ConnectionTarget(host: "active.test", database: "active", username: "test")
        model.connection = active
        try await model.connections.save(active)
        let draft = CaptureRecord(payload: CapturePayload(materials: [Material(text: "历史记录")]))
        _ = try await model.store.freeze(draft, target: original)
        let receipt = CaptureResult(submissionID: draft.id, rootBlockID: 42, committedAt: Date(), availability: .available)
        try await model.store.confirm(draft.id, result: receipt)
        let confirmed = try #require(try await model.store.record(draft.id))
        let updated = try await model.updateWebAddress("https://original-web.test", for: confirmed)
        var expected = original
        expected.webURL = URL(string: "https://original-web.test")
        #expect(updated.target == expected && updated.id == confirmed.id && updated.result == receipt)
        #expect(updated.payload == nil && updated.updatedAt == confirmed.updatedAt)
        #expect(model.connection == active)
        #expect(try await model.connections.load() == active)
        #expect(model.resultURL(for: updated)?.host == "original-web.test")
        model.connection = original
        #expect(model.resultURL(for: updated)?.host == "original-web.test")
        await #expect(throws: PeerError.self) { _ = try await model.updateWebAddress("javascript:alert(1)", for: confirmed) }
        #expect(try await model.store.record(draft.id)?.target == expected)
    }

    @Test func configuringWebAddressMakesExistingResultsOpenableWithoutRetargetingThem() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(directory: directory, identity: "dev.inkcre.result.\(UUID().uuidString)")
        defer { model.cancelWork() }
        let target = ConnectionTarget(host: "fixture.test", database: "inkcre", username: "inkcre_core")
        var record = CaptureRecord()
        record.target = target
        record.state = .confirmed
        record.result = CaptureResult(submissionID: record.id, rootBlockID: 42, committedAt: Date(), availability: .available)
        #expect(model.resultURL(for: record) == nil)
        var configured = target
        configured.webURL = URL(string: "https://fixture.test")
        model.connection = configured
        #expect(model.resultURL(for: record)?.absoluteString == "https://fixture.test/info-base/list/blocks/42/content")
        #expect(record.target == target)
        model.connection = ConnectionTarget(host: "other.test", database: "other", username: "inkcre_core", webURL: URL(string: "https://other.test"))
        #expect(model.resultURL(for: record) == nil)
        model.connection = configured
        record.result = CaptureResult(submissionID: record.id, rootBlockID: 42, committedAt: Date(), availability: .deleted)
        #expect(model.resultURL(for: record) == nil)
    }

    @Test func commandAvailabilityFollowsEditorContentAndPresentation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(directory: directory, identity: "dev.inkcre.commands.\(UUID().uuidString)")
        defer { model.cancelWork() }
        #expect(!model.canPerform(.submit, isEditor: true, isQuickPanel: false))
        model.thought = "待收入的内容"
        #expect(model.canPerform(.submit, isEditor: true, isQuickPanel: false))
        #expect(!model.canPerform(.submit, isEditor: false, isQuickPanel: false))
        #expect(!model.canPerform(.paste, isEditor: false, isQuickPanel: false))
        #expect(!model.canPerform(.hide, isEditor: true, isQuickPanel: false))
        #expect(model.canPerform(.hide, isEditor: true, isQuickPanel: true))
        model.requestDiscard(model.draft)
        for action in ShortcutAction.allCases {
            #expect(!model.canPerform(action, isEditor: true, isQuickPanel: true))
        }
        model.removalRequest = nil
        model.submitting = true
        #expect(!model.canPerform(.screenshot, isEditor: true, isQuickPanel: true))
    }

    @Test func materialRemovalRequiresConfirmationAndPreservesOtherContent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(directory: directory, identity: "dev.inkcre.test.\(UUID().uuidString)")
        defer { model.cancelWork() }
        let material = Material(text: "误采的材料")
        let kept = Material(text: "保留的材料")
        model.draft = CaptureRecord(payload: CapturePayload(entry: .paste, materials: [material, kept], annotation: "附注"))
        try await model.flush()
        model.requestRemoveMaterial(material.id)
        #expect(model.draft.payload?.materials == [material, kept])
        model.removalRequest = nil
        #expect(model.draft.payload?.materials == [material, kept])
        model.requestRemoveMaterial(material.id)
        model.confirmRemoval(try #require(model.removalRequest))
        try await model.flush()
        let saved = try #require(try await model.store.record(model.draft.id))
        #expect(saved.payload?.materials.map(\.text) == [kept.text])
        #expect(saved.payload?.annotation == "附注")
    }

    @Test func deletingBeforeDebounceRequiresConfirmationAndDoesNotReappear() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(directory: directory, identity: "dev.inkcre.test.\(UUID().uuidString)")
        defer { model.cancelWork() }
        model.thought = "尚未等到自动保存的中文 👩🏽‍💻"
        model.annotation = "最后一次附注"
        let id = model.draft.id
        let request = model.selectionRequest
        model.requestDiscard(model.draft)
        #expect(model.draft.id == id)
        #expect(model.thought == "尚未等到自动保存的中文 👩🏽‍💻")
        model.removalRequest = nil
        #expect(model.draft.id == id)
        model.requestDiscard(model.draft)
        model.confirmRemoval(try #require(model.removalRequest))
        for _ in 0..<100 where model.submitting { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!model.submitting)
        #expect(model.error == nil)
        #expect(model.selectionRequest != request)
        #expect(model.draft.id != id)
        let reopened = try CaptureStore(url: directory.appendingPathComponent("capture.sqlite"))
        #expect(try await reopened.record(id) == nil)
        #expect(try await reopened.records().isEmpty)
    }

    @Test func cancellingQuickCaptureOnlyDiscardsContentAfterConfirmation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(directory: directory, identity: "dev.inkcre.test.\(UUID().uuidString)")
        defer { model.cancelWork() }
        var closed = false
        model.dismissQuickCapture = { closed = true }
        model.cancelCapture()
        #expect(closed && model.removalRequest == nil)
        closed = false
        model.thought = "尚未确认丢弃的想法"
        model.cancelCapture()
        #expect(!closed && model.hasContent)
        model.removalRequest = nil
        #expect(model.thought == "尚未确认丢弃的想法")
        model.cancelCapture()
        model.confirmRemoval(try #require(model.removalRequest))
        for _ in 0..<100 where model.submitting { try await Task.sleep(for: .milliseconds(10)) }
        #expect(closed && !model.hasContent)
        #expect(model.error == nil)
    }

    @Test func deletingAnotherRecordKeepsTheCurrentUnsavedDraft() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(directory: directory, identity: "dev.inkcre.test.\(UUID().uuidString)")
        defer { model.cancelWork() }
        let other = CaptureRecord(payload: CapturePayload(materials: [Material(text: "另一份草稿")]))
        try await model.store.saveDraft(other)
        model.thought = "当前尚未等到自动保存的内容"
        let currentID = model.draft.id
        model.requestDiscard(other)
        model.confirmRemoval(try #require(model.removalRequest))
        for _ in 0..<100 where model.submitting { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.draft.id == currentID)
        #expect(try await model.store.record(currentID)?.payload?.materials.first?.text == "当前尚未等到自动保存的内容")
        #expect(try await model.store.record(other.id) == nil)
        #expect(model.error == nil)
    }
}

private actor JourneyTransport: CaptureTransport {
    struct Call: Sendable {
        let kind: String
        let record: CaptureRecord
        let secret: String
    }
    private(set) var calls: [Call] = []
    func recover(_ record: CaptureRecord, secret: String) async throws -> CaptureResult? {
        calls.append(Call(kind: "recover", record: record, secret: secret))
        return nil
    }
    func submit(_ record: CaptureRecord, secret: String) async throws -> CaptureResult {
        calls.append(Call(kind: "submit", record: record, secret: secret))
        return CaptureResult(submissionID: record.id, rootBlockID: 42, committedAt: Date(), availability: .available)
    }
}
