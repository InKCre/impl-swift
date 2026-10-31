import AppKit
import Combine
import LocalFiles
import PeerCore

@MainActor
public final class LocalFilesModel: ObservableObject {
    @Published public private(set) var sources: [DirectorySource] = []
    @Published public private(set) var records: [FileRecord] = []
    @Published public var selectedSource: Int? {
        didSet {
            if oldValue != selectedSource {
                selectedFile = nil
                records = []
                loadRecords()
            }
        }
    }
    @Published public var selectedFile: Int? {
        didSet { if oldValue != selectedFile { loadContent() } }
    }
    @Published public private(set) var selectedContent: String?
    @Published public private(set) var contentIssue: String?
    @Published public private(set) var loadingContent = false
    @Published public private(set) var target: ConnectionTarget?
    @Published public private(set) var issue: String?
    @Published public private(set) var loading = false
    @Published public private(set) var working = false
    @Published public private(set) var running = false
    @Published public var removal: DirectorySource?
    @Published private var statuses: [String: String] = [:]
    @Published private var scanning: Set<String> = []
    public var editConnection: (() -> Void)?

    private let context: PeerHostContext
    private var bindings: [DirectoryBinding] = []
    private var monitors: [String: DirectoryMonitor] = [:]
    private var prepared: Set<UUID> = []
    private var timer: Task<Void, Never>?
    private var recordsTask: Task<Void, Never>?
    private var contentTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var directoryPanel: NSOpenPanel?

    public init(context: PeerHostContext) { self.context = context }
    private var bindingURL: URL {
        context.directory.appendingPathComponent("extensions/inkcre-local-files/directories.json")
    }
    public var source: DirectorySource? { sources.first { $0.id == selectedSource } }
    public var file: FileRecord? { records.first { $0.id == selectedFile } }
    private func key(_ source: Int, _ target: ConnectionTarget) -> String {
        "\(target.peerID).\(source)"
    }
    public func isScanning(_ source: DirectorySource) -> Bool {
        target.map { scanning.contains(key(source.id, $0)) } ?? false
    }
    public func status(_ source: DirectorySource) -> String {
        if !source.config.enabled { return "已暂停" }
        guard running else { return "扩展已停用" }
        if let target, let status = statuses[key(source.id, target)] { return status }
        return source.state.issue
            ?? (source.state.errors > 0 ? "\(source.state.errors) 个文件需要处理" : "正在监视")
    }
    public func hasAccess(_ source: DirectorySource) -> Bool {
        guard let target else { return false }
        return bindings.contains { $0.source == source.id && $0.peerID == target.peerID }
    }

    public func start() throws {
        if FileManager.default.fileExists(atPath: bindingURL.path) {
            bindings = try JSONDecoder().decode(
                [DirectoryBinding].self, from: Data(contentsOf: bindingURL))
        }
        prepared.removeAll()
        running = true
        timer = Task {
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
    }

    public func stop() async {
        running = false
        directoryPanel?.cancel(nil)
        directoryPanel = nil
        actionTask?.cancel()
        refreshTask?.cancel()
        timer?.cancel()
        recordsTask?.cancel()
        contentTask?.cancel()
        await withTaskGroup(of: Void.self) { group in
            for id in Array(monitors.keys) {
                group.addTask { await self.stopMonitor(id) }
            }
        }
        await actionTask?.value
        await refreshTask?.value
        await timer?.value
        timer = nil
        recordsTask?.cancel()
        await recordsTask?.value
        contentTask?.cancel()
        await contentTask?.value
        loadingContent = false
    }

    public func connectionDidChange(_ connection: ConnectionTarget) async {
        directoryPanel?.cancel(nil)
        directoryPanel = nil
        removal = nil
        recordsTask?.cancel()
        contentTask?.cancel()
        target = connection
        selectedSource = nil
        selectedFile = nil
        selectedContent = nil
        contentIssue = nil
        sources = []
        records = []
        issue = nil
        // Cancel old reads before refreshing the new selection.
        refreshTask?.cancel()
        await refreshTask?.value
        await refresh()
    }

    public func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        guard running else { return }
        let task = Task {
            defer { refreshTask = nil }
            await performRefresh()
        }
        refreshTask = task
        await task.value
    }

    private func performRefresh() async {
        guard running else { return }
        loading = sources.isEmpty
        defer { loading = false }
        let saved: ConnectionSettings.SavedConnections
        do {
            saved = try await context.connections.loadAll()
            let current = saved.current
            if current != target {
                recordsTask?.cancel()
                selectedSource = nil
                selectedFile = nil
                sources = []
                records = []
            }
            target = current
        } catch {
            issue = error.localizedDescription
            return
        }
        let targets = saved.connections.filter { connection in
            connection.id == target?.id
                || bindings.contains {
                    $0.connectionID == connection.id && $0.peerID == connection.peerID
                }
        }
        for binding in bindings
        where !targets.contains(where: {
            $0.id == binding.connectionID && $0.peerID == binding.peerID
        }) {
            await stopMonitor(binding.id)
            statuses[binding.id] = "原目标连接不可用，请恢复该信息库的连接。"
        }
        if target == nil {
            sources = []
            records = []
        }
        await withTaskGroup(of: Void.self) { group in
            for connection in targets {
                group.addTask { await self.refresh(connection) }
            }
        }
    }

    private func refresh(_ connection: ConnectionTarget) async {
        guard running, !Task.isCancelled else { return }
        defer { if target?.id == connection.id { loading = false } }
        do {
            let client = try await client(connection)
            try await prepare(client)
            try await client.checkParticipation()
            let found = try await client.sources()
            guard running, !Task.isCancelled else { return }
            if target?.id == connection.id {
                let old = selectedSource
                sources = found
                selectedSource = found.contains(where: { $0.id == old }) ? old : found.first?.id
                issue = nil
                loadRecords()
            }
            for binding in bindings.filter({ $0.connectionID == connection.id }) {
                guard let source = found.first(where: { $0.id == binding.source }),
                    source.config.enabled
                else {
                    await stopMonitor(binding.id)
                    continue
                }
                if monitors[binding.id]?.source.config != source.config {
                    await stopMonitor(binding.id)
                }
                if monitors[binding.id] == nil {
                    do { try startMonitor(binding, source: source, target: connection) } catch {
                        statuses[binding.id] = error.localizedDescription
                        continue
                    }
                }
                monitors[binding.id]?.refresh()
            }
            for source in found
            where !bindings.contains(where: { $0.id == key(source.id, connection) }) {
                statuses[key(source.id, connection)] = "需要选择目录以恢复访问"
            }
        } catch {
            guard running, !Task.isCancelled else { return }
            let message = PeerDatabase.failure(error).localizedDescription
            if target?.id == connection.id { issue = message }
            for binding in bindings.filter({ $0.connectionID == connection.id }) {
                await stopMonitor(binding.id)
                statuses[binding.id] = message
            }
        }
    }

    private func startMonitor(
        _ binding: DirectoryBinding, source: DirectorySource, target: ConnectionTarget
    ) throws {
        guard running, !Task.isCancelled else { throw CancellationError() }
        let id = binding.id
        let monitor = try DirectoryMonitor(
            source: source, target: target, context: context, bookmark: binding.bookmark,
            onBookmarkRenewed: { bookmark in
                if let index = bindings.firstIndex(where: { $0.id == id }) {
                    bindings[index].bookmark = bookmark
                    try saveBindings()
                }
            },
            onState: { [weak self] message, active in
                guard let self else { return }
                statuses[id] = message
                if active { scanning.insert(id) } else { scanning.remove(id) }
            },
            onSources: { [weak self] updated in
                guard let self, running, self.target?.id == target.id else { return }
                sources = updated
                loadRecords()
            })
        monitors[id] = monitor
        monitor.schedule()
    }

    private func stopMonitor(_ id: String) async {
        guard let monitor = monitors[id] else { return }
        await monitor.stop()
        // A concurrent stop must await this monitor too, without removing its replacement.
        if monitors[id] === monitor {
            monitors.removeValue(forKey: id)
            scanning.remove(id)
        }
    }

    private func prepare(_ client: LocalFileClient) async throws {
        guard !prepared.contains(client.target.id) else { return }
        try await client.prepare()
        prepared.insert(client.target.id)
    }

    private func client(_ target: ConnectionTarget) async throws -> LocalFileClient {
        let connection = try await context.connections.resolve(target)
        return LocalFileClient(
            target: connection, password: try context.credentials.read(for: connection.id))
    }

    private func saveBindings() throws {
        try FileManager.default.createDirectory(
            at: bindingURL.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(bindings).write(to: bindingURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: bindingURL.path)
    }

    private func loadRecords() {
        recordsTask?.cancel()
        guard let source, let target else {
            records = []
            return
        }
        recordsTask = Task {
            do {
                let result = try await client(target).records(source: source)
                guard !Task.isCancelled, selectedSource == source.id, self.target?.id == target.id
                else {
                    return
                }
                let previous = file
                records = result.sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                if let selectedFile, !records.contains(where: { $0.id == selectedFile }) {
                    self.selectedFile = nil
                } else if previous?.bodyID != file?.bodyID
                    || previous?.bodyResolver != file?.bodyResolver
                    || previous?.metadata.revision != file?.metadata.revision || contentIssue != nil
                    || (file?.bodyID != nil && selectedContent == nil && !loadingContent)
                {
                    loadContent()
                }
            } catch {
                if !Task.isCancelled { issue = PeerDatabase.failure(error).localizedDescription }
            }
        }
    }

    public func loadContent() {
        contentTask?.cancel()
        selectedContent = nil
        contentIssue = nil
        loadingContent = false
        guard let file, file.bodyID != nil, let target else { return }
        loadingContent = true
        contentTask = Task {
            defer { if !Task.isCancelled { loadingContent = false } }
            do {
                let text = try await client(target).content(for: file)
                guard !Task.isCancelled else { return }
                selectedContent = text
            } catch {
                if !Task.isCancelled {
                    contentIssue = PeerDatabase.failure(error).localizedDescription
                }
            }
        }
    }

    public func chooseDirectory(restoring source: DirectorySource? = nil) {
        guard !working, running else { return }
        guard let target else {
            editConnection?()
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = source == nil ? "监视目录" : "恢复访问"
        if let source { panel.directoryURL = URL(fileURLWithPath: source.config.path) }
        guard let window = NSApp.keyWindow else { return }
        directoryPanel = panel
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.directoryPanel = nil
            guard self.running, response == .OK, let url = panel.url else { return }
            Task { await self.addDirectory(url, target: target, restoring: source) }
        }
    }

    public func addDirectory(
        _ url: URL, target: ConnectionTarget, restoring source: DirectorySource? = nil
    ) async {
        guard running, !working else { return }
        working = true
        let task = Task { await addDirectoryImpl(url, target: target, restoring: source) }
        actionTask = task
        await task.value
        actionTask = nil
    }

    private func addDirectoryImpl(
        _ url: URL, target: ConnectionTarget, restoring source: DirectorySource?
    ) async {
        defer { working = false }
        let url = url.resolvingSymlinksInPath()
        do {
            if let source, source.config.path != url.path {
                throw PeerError.needsAction("请选择原目录：\(source.config.path)")
            }
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            let client = try await client(target)
            try await prepare(client)
            guard running, !Task.isCancelled else { throw CancellationError() }
            let directory: DirectorySource
            if let source {
                directory = source
            } else {
                directory = try await client.createDirectory(path: url.path)
            }
            let binding = DirectoryBinding(source: directory.id, target: target, bookmark: bookmark)
            bindings.removeAll { $0.id == binding.id }
            bindings.append(binding)
            try saveBindings()
            selectedSource = directory.id
            await refresh()
        } catch { issue = error.localizedDescription }
    }

    public func toggle(_ source: DirectorySource) {
        perform { target in
            let id = self.key(source.id, target)
            await self.stopMonitor(id)
            try await self.client(target).setEnabled(!source.config.enabled, source: source)
        }
    }

    public func rescan(_ source: DirectorySource) {
        perform { target in
            _ = try await self.client(target).submitScan(source)
            self.monitors[self.key(source.id, target)]?.schedule()
        }
    }

    public func remove(_ source: DirectorySource) {
        removal = nil
        perform { target in
            let id = self.key(source.id, target)
            await self.stopMonitor(id)
            try await self.client(target).remove(source)
            self.bindings.removeAll { $0.id == id }
            try self.saveBindings()
        }
    }

    private func perform(_ action: @escaping @MainActor (ConnectionTarget) async throws -> Void) {
        guard running, !working, let target else { return }
        working = true
        actionTask = Task {
            defer {
                working = false
                actionTask = nil
            }
            var failure: String?
            do {
                try Task.checkCancellation()
                try await action(target)
            } catch {
                failure =
                    PeerDatabase.isCancellation(error)
                    ? "目录状态已改变，请重新核对。" : PeerDatabase.failure(error).localizedDescription
            }
            await refresh()
            if let failure { issue = failure }
        }
    }

    public func openOriginal(_ record: FileRecord, reveal: Bool = false) {
        do {
            guard let target else { return }
            let url = try PeerFileLocation(uri: record.metadata.location).localURL(
                for: target.peerID)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw PeerError.needsAction("原件已不在这个位置。")
            }
            if reveal {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else if !NSWorkspace.shared.open(url) {
                throw PeerError.needsAction("没有可打开此文件的应用。")
            }
        } catch { issue = error.localizedDescription }
    }
}
