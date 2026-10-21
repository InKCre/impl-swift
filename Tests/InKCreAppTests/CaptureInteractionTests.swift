import AppKit
import CaptureCore
import Testing
@testable import InKCreApp

@Suite(.serialized) @MainActor
struct CaptureInteractionTests {
    @Test func emptyCaptureShortcutDoesNotOpenConnectionOrStartSubmission() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(directory: directory, identity: "dev.inkcre.test.\(UUID().uuidString)")
        defer { model.stop() }
        var mainOpened = false
        model.showMain = { mainOpened = true }
        model.submit()
        #expect(!model.hasContent)
        #expect(!model.submitting)
        #expect(!mainOpened)
        #expect(!model.showingConnectionEditor)
        #expect(model.pane == .capture)
        #expect(model.error == nil)
    }

    @Test func backgroundQueueRefreshCannotReplaceNewDraftFeedbackWithAnOldRecord() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(directory: directory, identity: "dev.inkcre.test.\(UUID().uuidString)")
        defer { model.stop() }
        let old = CaptureRecord(payload: CapturePayload(materials: [Material(text: "旧的已收入记录")]))
        try await model.store.saveDraft(old)
        _ = try await model.store.freeze(old, target: ConnectionTarget(postgrestURL: URL(string: "https://fixture.test")!))
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
        defer { model.stop() }
        model.thought = "主窗口中未提交的草稿"
        let previousID = model.draft.id
        model.pane = .settings
        model.editorOwner = .quick
        var presented: CaptureModel.EditorOwner?
        model.presentEditor = { presented = model.editorOwner }
        let payload = CapturePayload(entry: .selection, materials: [Material(text: "快捷采集的新材料")])
        await model.receive(payload)
        #expect(model.pane == .settings)
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

    @Test func mainCaptureRevealsEditorAndMissingConnectionOpensMainSettings() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(directory: directory, identity: "dev.inkcre.test.\(UUID().uuidString)")
        defer { model.stop() }
        model.pane = .queue
        await model.receive(CapturePayload(materials: [Material(text: "回到主窗口采集")]))
        #expect(model.pane == .capture)
        model.editorOwner = .quick
        var mainOpened = false
        model.showMain = { mainOpened = true; model.editorOwner = .main }
        model.submit()
        #expect(mainOpened)
        #expect(model.editorOwner == .main)
        #expect(model.pane == .settings)
        #expect(model.hasContent)
        #expect(model.lastContactAt == nil)
    }

    @Test func materialRemovalRequiresConfirmationAndPreservesOtherContent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try CaptureModel(directory: directory, identity: "dev.inkcre.test.\(UUID().uuidString)")
        defer { model.stop() }
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
        defer { model.stop() }
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
        defer { model.stop() }
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
        defer { model.stop() }
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
