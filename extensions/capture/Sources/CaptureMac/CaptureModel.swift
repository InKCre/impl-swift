import AppKit
import Capture
import Combine
import Foundation
import PeerCore
import SwiftUI

@MainActor
final class CaptureModel: ObservableObject {
    typealias Pane = CapturePage
    enum EditorOwner { case main, quick }
    enum RemovalRequest {
        case material(draftID: UUID, materialID: UUID)
        case record(CaptureRecord, close: Bool)

        var title: String {
            switch self {
            case .material: return "移除这项材料？"
            case .record(let record, let close):
                if close { return "取消本次采集？" }
                return record.state == .draft ? "删除这份草稿？" : "删除本机记录？"
            }
        }

        var actionTitle: String {
            switch self {
            case .material: "移除"
            case .record(_, let close): close ? "丢弃并关闭" : "删除"
            }
        }

        var message: String {
            switch self {
            case .material: "移除后无法撤销，补充想法会保留。"
            case .record(let record, _):
                switch record.state {
                case .draft: "这份草稿和材料将从本机删除，无法恢复。"
                case .confirmed: "仅删除此 Mac 的记录，信息库中的内容保持不变。删除后无法恢复。"
                default: "停止后续发送并删除本机材料，无法恢复。已发出的请求可能已经收入，无法撤回。"
                }
            }
        }
    }
    @Published var pane = Pane.capture
    @Published var editorOwner = EditorOwner.main
    @Published var draft = CaptureRecord()
    @Published var records: [CaptureRecord] = []
    @Published var connection: ConnectionTarget?
    @Published var error: String?
    @Published var saveStatus = "随时写下想法，或加入材料"
    @Published var submitting = false
    @Published var captureNotice: String?
    @Published var screenCaptureNotice: String?
    @Published var removalRequest: RemovalRequest?
    let shortcuts: GlobalShortcuts
    var takeScreenshot: (() -> Void)?
    var selectionRequest = UUID()
    var presentEditor: (() -> Void)?
    var dismissQuickCapture: (() -> Void)?
    var showMain: (() -> Void)?
    var showQuick: (() -> Void)?
    var editConnection: ((ConnectionTarget?, (@MainActor () -> Void)?) -> Void)?
    let store: CaptureStore
    let credentials: CredentialStore
    let connections: ConnectionSettings
    private let queue: CaptureQueue
    private var saveTask: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    @Published private(set) var submissionStatusID: UUID?
    @Published var selectedRecordID: UUID?
    private var editRevision = 0
    private var actions: [UUID: Task<Void, Never>] = [:]
    private var stopping = false

    init(directory: URL, identity: String, connections: ConnectionSettings? = nil,
         client: any CaptureTransport = CaptureClient()) throws {
        self.connections =
            connections ?? ConnectionSettings(url: directory.appendingPathComponent("connection.json"))
        shortcuts = try GlobalShortcuts()
        store = try CaptureStore(url: directory.appendingPathComponent("capture.sqlite"))
        credentials = CredentialStore(service: "\(identity).connections")
        queue = CaptureQueue(store: store, credentials: credentials, client: client)
    }

    func canPerform(_ action: ShortcutAction, isEditor: Bool, isQuickPanel: Bool) -> Bool {
        guard !submitting, error == nil, removalRequest == nil else { return false }
        switch action {
        case .capture, .screenshot: return true
        case .paste: return isEditor
        case .submit: return isEditor && hasContent
        case .hide: return isQuickPanel
        }
    }

    var pendingCount: Int {
        records.filter { [.pending, .unknown, .needsAction].contains($0.state) }.count
    }
    var hasContent: Bool {
        !(draft.payload?.materials.isEmpty ?? true) || !(draft.payload?.annotation ?? "").isEmpty
    }
    var thought: String {
        get { draft.payload?.materials.first(where: { $0.kind == .text })?.text ?? "" }
        set {
            guard var payload = draft.payload else { return }
            if let index = payload.materials.firstIndex(where: { $0.kind == .text }) {
                if newValue.isEmpty {
                    payload.materials.remove(at: index)
                } else {
                    payload.materials[index].text = newValue
                }
            } else if !newValue.isEmpty {
                payload.materials.insert(Material(text: newValue), at: 0)
            }
            draft.payload = payload
            saveSoon()
        }
    }
    var annotation: String {
        get { draft.payload?.annotation ?? "" }
        set {
            draft.payload?.annotation = newValue.isEmpty ? nil : newValue
            saveSoon()
        }
    }

    func start(restore: Bool = true) {
        stopping = false
        submitting = true
        heartbeat = Task {
            await queue.resume()
            if restore {
                do {
                    connection = try await connections.load()
                    try await refresh()
                    if let latest = records.first(where: { $0.state == .draft }) {
                        draft = latest
                        saveStatus = "已恢复本机草稿"
                    }
                } catch { self.error = error.localizedDescription }
            }
            submitting = false
            while !Task.isCancelled {
                await sendPending()
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
            }
        }
    }

    func cancelWork() {
        stopping = true
        selectionRequest = UUID()
        heartbeat?.cancel()
        saveTask?.cancel()
        for task in actions.values { task.cancel() }
    }

    func stop() async {
        cancelWork()
        await queue.stop()
        for task in Array(actions.values) { await task.value }
        await heartbeat?.value
        await saveTask?.value
        await queue.stop()
    }

    func perform(_ operation: @escaping @MainActor () async -> Void) {
        guard !stopping else { return }
        let id = UUID()
        actions[id] = Task {
            await operation()
            actions.removeValue(forKey: id)
        }
    }

    func saveSoon() {
        guard !stopping else { return }
        editRevision += 1
        saveTask?.cancel()
        saveStatus = "正在保留草稿…"
        saveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                try await flush()
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                saveStatus = "尚未保留，请勿退出"
            }
        }
    }

    func flush() async throws {
        guard draft.state == .draft else { return }
        if !hasContent {
            let id = draft.id
            let revision = editRevision
            try await store.discardDraft(id)
            if draft.id == id, revision == editRevision { saveStatus = "随时写下想法，或加入材料" }
            try await refreshRecord(id)
            return
        }
        draft.updatedAt = Date()
        let value = draft
        let revision = editRevision
        saveStatus = "正在保留草稿…"
        do { try await store.saveDraft(value) } catch {
            if draft.id == value.id, revision == editRevision { saveStatus = "尚未保留，请勿退出" }
            throw error
        }
        if draft.id == value.id, revision == editRevision { saveStatus = "草稿已保留在本机" }
        try await refreshRecord(value.id)
    }

    func newThought(notice: String? = nil) {
        guard !submitting else { return }
        submitting = true
        selectionRequest = UUID()
        perform { [self] in
            defer { submitting = false }
            do {
                saveTask?.cancel()
                try await flush()
                draft = CaptureRecord()
                captureNotice = notice
                saveStatus = "写下此刻的想法"
                revealEditor()
            } catch { self.error = error.localizedDescription }
        }
    }

    func pasteMaterial() {
        guard !submitting else { return }
        submitting = true
        selectionRequest = UUID()
        perform { [self] in
            defer { submitting = false }
            do {
                let materials = try ClipboardReader.materials()
                guard !materials.isEmpty else { throw PeerError.invalid("剪贴板没有可用的文字、链接或图片。") }
                saveTask?.cancel()
                try await flush()
                draft = CaptureRecord(payload: CapturePayload(entry: .paste, materials: materials))
                captureNotice = nil
                try await flush()
                revealEditor()
            } catch {
                self.error = error.localizedDescription
                presentEditor?()
            }
        }
    }

    func receive(_ payload: CapturePayload, request: UUID? = nil, notice: String? = nil) async {
        if let request, request != selectionRequest { return }
        guard !submitting else {
            error = "上一份材料正在保留，请稍后重新采集。"
            presentEditor?()
            return
        }
        submitting = true
        defer { submitting = false }
        do {
            try payload.validate()
            saveTask?.cancel()
            try await flush()
            if let request, request != selectionRequest { return }
            draft = CaptureRecord(payload: payload)
            captureNotice = notice
            try await flush()
            revealEditor()
        } catch {
            self.error = error.localizedDescription
            presentEditor?()
        }
    }

    func submit() {
        guard !submitting, hasContent else { return }
        guard let connection else {
            let draftID = draft.id
            let owner = editorOwner
            editConnection?(nil, { [weak self] in
                guard let self, !self.stopping, self.draft.id == draftID else { return }
                self.editorOwner = owner
                self.captureNotice = self.connection == nil
                    ? "连接信息库后即可收入，也可以继续编辑。"
                    : "连接已配置，请确认内容后点击收入。"
                self.revealEditor()
            })
            return
        }
        // An input method owns Return until its marked text is committed.
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.hasMarkedText() { return }
        submitting = true
        saveTask?.cancel()
        perform { [self] in
            do {
                let frozen = try await store.freeze(draft, target: connection)
                draft = CaptureRecord()
                submissionStatusID = frozen.id
                captureNotice = nil
                saveStatus = "随时写下想法，或加入材料"
                try await refresh()
                submitting = false
                await sendPending(force: true)
            } catch {
                submitting = false
                self.error = error.localizedDescription
            }
        }
    }

    func sendPending(force: Bool = false) async {
        do {
            if try await queue.process(force: force) { try await refresh() }
        } catch { self.error = error.localizedDescription }
    }

    func refresh() async throws {
        records = try await store.records()
    }

    private func refreshRecord(_ id: UUID) async throws {
        let record = try await store.record(id)
        records.removeAll { $0.id == id }
        if let record { records.append(record) }
        records.sort { $0.updatedAt > $1.updatedAt }
    }

    func resume(_ record: CaptureRecord) {
        guard record.state == .draft, !submitting else { return }
        submitting = true
        selectionRequest = UUID()
        perform { [self] in
            defer { submitting = false }
            do {
                saveTask?.cancel()
                try await flush()
                guard let current = try await store.record(record.id),
                    current.state == .draft
                else {
                    throw PeerError.invalid("这份草稿已变更，请刷新记录后再打开。")
                }
                draft = current
                saveStatus = "已恢复本机草稿"
                revealEditor()
            } catch { self.error = error.localizedDescription }
        }
    }

    func retry(_ record: CaptureRecord) {
        perform { [self] in
            do {
                try await store.retry(record.id)
                await sendPending(force: true)
            } catch { self.error = error.localizedDescription }
        }
    }

    func requestRemoveMaterial(_ id: UUID) {
        guard !submitting, let materials = draft.payload?.materials,
            materials.contains(where: { $0.id == id })
        else { return }
        removalRequest = .material(draftID: draft.id, materialID: id)
    }

    func requestDiscard(_ record: CaptureRecord, close: Bool = false) {
        guard !submitting else { return }
        if record.id == draft.id && !hasContent {
            if close { dismissQuickCapture?() }
            return
        }
        removalRequest = .record(record, close: close)
    }

    func confirmRemoval(_ request: RemovalRequest) {
        removalRequest = nil
        guard !submitting else { return }
        switch request {
        case .material(let draftID, let materialID):
            guard draft.id == draftID else { return }
            draft.payload?.materials.removeAll { $0.id == materialID }
            saveSoon()
        case .record(let record, let close): discard(record, close: close)
        }
    }

    func cancelCapture(close: Bool = true) { requestDiscard(draft, close: close) }

    func cancel(_ record: CaptureRecord) {
        perform { [self] in
            do {
                try await store.cancel(record.id)
                try await refresh()
            } catch { self.error = error.localizedDescription }
        }
    }

    private func discard(_ record: CaptureRecord, close: Bool) {
        guard !submitting else { return }
        submitting = true
        selectionRequest = UUID()
        saveTask?.cancel()
        perform { [self] in
            defer { submitting = false }
            do {
                if draft.id != record.id { try await flush() }
                try await store.deleteRecord(record.id)
                if draft.id == record.id {
                    draft = CaptureRecord()
                    captureNotice = nil
                    saveStatus = "本机草稿已删除"
                }
                try await refresh()
                if close { dismissQuickCapture?() }
            } catch { self.error = error.localizedDescription }
        }
    }

    func openConnectionSettings() {
        editConnection?(connection, nil)
    }

    var submittedRecord: CaptureRecord? {
        records.first { $0.id == submissionStatusID }
    }

    func showRecord(_ record: CaptureRecord) {
        selectedRecordID = record.id
        pane = .queue
        showMain?()
    }

    func updatePassword(_ password: String, for record: CaptureRecord) async throws {
        guard !password.isEmpty,
              let current = try await store.record(record.id),
              let target = current.target, current.state != .draft, current.state != .confirmed
        else { throw PeerError.invalid("这条记录已变更，请关闭后重新查看。") }
        try credentials.save(password, for: target.id)
        try await store.retry(current.id)
        try await refresh()
        perform { [self] in await sendPending(force: true) }
    }

    func updateWebAddress(_ address: String, for record: CaptureRecord) async throws -> CaptureRecord {
        let updated = try await store.updateWebAddress(record.id, address: address)
        try await refresh()
        return updated
    }

    func continueInMain() {
        pane = .capture
        showMain?()
    }

    private func revealEditor() {
        if editorOwner == .main { pane = .capture }
        presentEditor?()
    }

    func requestScreenRecordingAccess() {
        if CGRequestScreenCaptureAccess() {
            screenCaptureNotice = nil
        } else {
            screenCaptureNotice = "授权后请完全退出并重新打开 InKCre。若系统开关已开启，也请检查当前应用是否需要重新授权。"
        }
    }

    func openScreenRecordingSettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        {
            NSWorkspace.shared.open(url)
        }
    }

    func resultURL(for record: CaptureRecord) -> URL? {
        guard let result = record.result, result.availability == .available, let target = record.target else { return nil }
        let base = target.webURL ?? (connection?.peerID == target.peerID ? connection?.webURL : nil)
        guard var url = base else { return nil }
        for part in ["info-base", "list", "blocks", String(result.rootBlockID), "content"] {
            url.appendPathComponent(part)
        }
        return url
    }

    func openResult(_ record: CaptureRecord) {
        guard let url = resultURL(for: record) else {
            error = "未配置可用的 Web 地址，或共享内容已删除。"
            return
        }
        NSWorkspace.shared.open(url)
    }

    func export(_ record: CaptureRecord) {
        guard record.payload != nil else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "capture-\(record.id.uuidString).json"
        if panel.runModal() == .OK, let url = panel.url {
            do { try CaptureJSON.encode(record).write(to: url, options: .atomic) } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
