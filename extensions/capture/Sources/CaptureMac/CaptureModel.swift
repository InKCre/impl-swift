import AppKit
import Capture
import Combine
import Foundation
import PeerCore

@MainActor
final class CaptureModel: ObservableObject {
    enum Pane: Hashable { case capture, queue, settings }
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
    @Published var editingConnection: ConnectionTarget?
    @Published var showingConnectionEditor = false
    @Published var error: String?
    @Published var saveStatus = "随时写下想法，或加入材料"
    @Published var submitting = false
    @Published var lastContactAt: Date?
    @Published var peerConnectionIssue: String?
    @Published private(set) var checkingConnection = false
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
    let store: CaptureStore
    let credentials: CredentialStore
    let connections: ConnectionSettings
    private let queue: CaptureQueue
    private var saveTask: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var connectionCheck: Task<Void, Never>?
    private var connectionRevision = UUID()
    private var submissionStatusID: UUID?
    private var editRevision = 0
    private var actions: [UUID: Task<Void, Never>] = [:]
    private var stopping = false

    init(directory: URL, identity: String, connections: ConnectionSettings? = nil) throws {
        self.connections =
            connections ?? ConnectionSettings(url: directory.appendingPathComponent("connection.json"))
        shortcuts = try GlobalShortcuts()
        store = try CaptureStore(url: directory.appendingPathComponent("capture.sqlite"))
        credentials = CredentialStore(service: "\(identity).connections")
        queue = CaptureQueue(store: store, credentials: credentials)
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
            var cycle = 0
            while !Task.isCancelled {
                await sendPending()
                if cycle % 4 == 0, !checkingConnection, let connection {
                    let revision = connectionRevision
                    do {
                        try await CaptureClient().checkConnection(
                            connection, secret: credentials.read(for: connection.id)
                        )
                        if connectionRevision == revision && !checkingConnection {
                            lastContactAt = Date()
                            peerConnectionIssue = nil
                        }
                    } catch {
                        if connectionRevision == revision && !checkingConnection {
                            peerConnectionIssue = error.localizedDescription
                        }
                    }
                }
                cycle += 1
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
            }
        }
    }

    func cancelWork() {
        stopping = true
        selectionRequest = UUID()
        heartbeat?.cancel()
        saveTask?.cancel()
        connectionCheck?.cancel()
        for task in actions.values { task.cancel() }
    }

    func stop() async {
        cancelWork()
        await queue.stop()
        for task in Array(actions.values) { await task.value }
        await heartbeat?.value
        await connectionCheck?.value
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
        submissionStatusID = nil
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
            if try await store.record(id) != nil { try await store.discardDraft(id) }
            if draft.id == id, revision == editRevision { saveStatus = "随时写下想法，或加入材料" }
            try await refresh()
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
        try await refresh()
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
                submissionStatusID = nil
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
                submissionStatusID = nil
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
            submissionStatusID = nil
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
            openSettings()
            showingConnectionEditor = true
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
                saveStatus = frozen.statusLabel
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
            try await queue.process(force: force)
            try await refresh()
        } catch { self.error = error.localizedDescription }
    }

    func refresh() async throws {
        records = try await store.records()
        if !hasContent, let id = submissionStatusID, let record = records.first(where: { $0.id == id }) {
            saveStatus = record.statusLabel
        }
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
                submissionStatusID = nil
                saveStatus = "已恢复本机草稿"
                pane = .capture
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
                    submissionStatusID = nil
                    captureNotice = nil
                    saveStatus = "本机草稿已删除"
                }
                try await refresh()
                if close { dismissQuickCapture?() }
            } catch { self.error = error.localizedDescription }
        }
    }

    func openSettings(target: ConnectionTarget? = nil) {
        editingConnection = target ?? connection
        pane = .settings
        showMain?()
        if target != nil { showingConnectionEditor = true }
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

    func connectionSaved(_ target: ConnectionTarget) {
        connection = target
        editingConnection = target
        connectionRevision = UUID()
        lastContactAt = nil
        peerConnectionIssue = nil
        checkConnection()
    }

    func checkConnection() {
        guard let target = connection else { return }
        do { checkConnection(target, secret: try credentials.read(for: target.id)) } catch {
            peerConnectionIssue = error.localizedDescription
        }
    }

    private func checkConnection(_ target: ConnectionTarget, secret: String) {
        connectionCheck?.cancel()
        checkingConnection = true
        let revision = connectionRevision
        connectionCheck = Task {
            defer { if !Task.isCancelled && connectionRevision == revision { checkingConnection = false } }
            do {
                try await CaptureClient().checkConnection(target, secret: secret)
                guard !Task.isCancelled, connectionRevision == revision else { return }
                lastContactAt = Date()
                peerConnectionIssue = nil
            } catch {
                guard !Task.isCancelled, connectionRevision == revision else { return }
                peerConnectionIssue = error.localizedDescription
            }
        }
    }

    func openResult(_ record: CaptureRecord) {
        guard let result = record.result, result.availability == .available,
            var url = record.target?.webURL
        else {
            error = "未配置 Web 地址；提交引用仍保留在此。"
            return
        }
        for part in ["info-base", "list", "blocks", String(result.rootBlockID), "content"] {
            url.appendPathComponent(part)
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
