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
    didSet { if oldValue != selectedFile { loadText() } }
  }
  @Published public private(set) var selectedText: String?
  @Published public private(set) var textIssue: String?
  @Published public private(set) var loadingText = false
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
  private var monitors: [String: Monitor] = [:]
  private var timer: Task<Void, Never>?
  private var recordsTask: Task<Void, Never>?
  private var textTask: Task<Void, Never>?
  private var refreshTask: Task<Void, Never>?
  private var actionTask: Task<Void, Never>?
  private var directoryPanel: NSOpenPanel?

  private final class Monitor {
    let source: DirectorySource
    let target: ConnectionTarget
    let root: URL
    let scoped: Bool
    var watcher: DirectoryWatcher?
    var task: Task<Void, Never>?
    var dirty = false
    init(source: DirectorySource, target: ConnectionTarget, root: URL, scoped: Bool) {
      self.source = source
      self.target = target
      self.root = root
      self.scoped = scoped
    }
  }

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
    return bindings.contains { $0.source == source.id && $0.target.peerID == target.peerID }
  }

  public func start() throws {
    if FileManager.default.fileExists(atPath: bindingURL.path) {
      bindings = try JSONDecoder().decode(
        [DirectoryBinding].self, from: Data(contentsOf: bindingURL))
    }
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
    await actionTask?.value
    await refreshTask?.value
    await timer?.value
    timer = nil
    recordsTask?.cancel()
    await recordsTask?.value
    textTask?.cancel()
    await textTask?.value
    loadingText = false
    for id in Array(monitors.keys) { await stopMonitor(id) }
  }

  public func connectionDidChange(_ connection: ConnectionTarget) async {
    directoryPanel?.cancel(nil)
    directoryPanel = nil
    removal = nil
    recordsTask?.cancel()
    textTask?.cancel()
    target = connection
    selectedSource = nil
    selectedFile = nil
    selectedText = nil
    textIssue = nil
    sources = []
    records = []
    issue = nil
    // A coalesced old refresh must settle before the new selection is refreshed.
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
    do {
      let current = try await context.connections.load()
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
    var targets = Dictionary(
      bindings.map { ($0.target.id, $0.target) }, uniquingKeysWith: { _, newer in newer })
    if let target { targets[target.id] = target }
    if target == nil {
      sources = []
      records = []
    }
    for connection in targets.values {
      guard running, !Task.isCancelled else { return }
      do {
        let client = try client(connection)
        try await client.prepare()
        let found = try await client.sources()
        guard running, !Task.isCancelled else { return }
        if target?.id == connection.id {
          let old = selectedSource
          sources = found
          selectedSource = found.contains(where: { $0.id == old }) ? old : found.first?.id
          issue = nil
        }
        for binding in bindings.filter({ $0.target.id == connection.id }) {
          guard let source = found.first(where: { $0.id == binding.source }), source.config.enabled
          else {
            await stopMonitor(binding.id)
            continue
          }
          if monitors[binding.id]?.source.config != source.config { await stopMonitor(binding.id) }
          if monitors[binding.id] == nil {
            do { try startMonitor(binding, source: source) } catch {
              statuses[binding.id] = error.localizedDescription
              continue
            }
          }
          if let monitor = monitors[binding.id], monitor.task == nil {
            let jobs = try await client.pendingScans(source)
            if !jobs.isEmpty || monitor.dirty { schedule(binding.id) }
          }
        }
        for source in found where !bindings.contains(where: { $0.id == key(source.id, connection) })
        {
          statuses[key(source.id, connection)] = "需要选择目录以恢复访问"
        }
      } catch {
        let message = PeerDatabase.failure(error).localizedDescription
        if target?.id == connection.id { issue = message }
        for binding in bindings.filter({ $0.target.id == connection.id }) {
          await stopMonitor(binding.id)
          statuses[binding.id] = message
        }
      }
    }
    loadRecords()
  }

  private func startMonitor(_ binding: DirectoryBinding, source: DirectorySource) throws {
    guard running, !Task.isCancelled else { throw CancellationError() }
    var stale = false
    let root = try URL(
      resolvingBookmarkData: binding.bookmark, options: [.withSecurityScope, .withoutUI],
      relativeTo: nil, bookmarkDataIsStale: &stale)
    guard
      root.resolvingSymlinksInPath().path
        == URL(fileURLWithPath: source.config.path).resolvingSymlinksInPath().path
    else { throw PeerError.needsAction("目录位置已改变，请重新选择目录。") }
    let scoped = root.startAccessingSecurityScopedResource()
    let monitor = Monitor(source: source, target: binding.target, root: root, scoped: scoped)
    do {
      if stale, let index = bindings.firstIndex(where: { $0.id == binding.id }) {
        bindings[index].bookmark = try root.bookmarkData(
          options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        try saveBindings()
      }
      monitor.watcher = try DirectoryWatcher(path: root.path) { [weak self] in
        self?.schedule(binding.id)
      }
      monitors[binding.id] = monitor
      schedule(binding.id)
    } catch {
      if scoped { root.stopAccessingSecurityScopedResource() }
      throw error
    }
  }

  private func stopMonitor(_ id: String) async {
    guard let monitor = monitors.removeValue(forKey: id) else { return }
    monitor.watcher?.stop()
    monitor.task?.cancel()
    await monitor.task?.value
    if monitor.scoped { monitor.root.stopAccessingSecurityScopedResource() }
    scanning.remove(id)
  }

  private func schedule(_ id: String) {
    guard running, let monitor = monitors[id] else { return }
    monitor.dirty = true
    guard monitor.task == nil else { return }
    monitor.task = Task { [weak self, weak monitor] in
      guard let self, let monitor else { return }
      defer {
        monitor.task = nil
        scanning.remove(id)
      }
      while monitor.dirty, running, !Task.isCancelled {
        monitor.dirty = false
        scanning.insert(id)
        statuses[id] = "正在扫描…"
        var job: SourceJob?
        let client: LocalFileClient
        do { client = try self.client(monitor.target) } catch {
          statuses[id] = error.localizedDescription
          monitor.dirty = true
          break
        }
        do {
          let pending = try await client.pendingScans(monitor.source)
          for candidate in pending {
            if let claimed = try await client.claim(candidate, source: monitor.source) {
              job = claimed
              break
            }
          }
          let state = try await DirectoryScanner.scan(
            source: monitor.source, client: client, job: job
          ) { [weak self] progress in
            await self?.report(progress, id: id)
          }
          if let job {
            try await client.close(
              job, status: state.errors == 0 ? "finished" : "failed", state: state)
          }
          statuses[id] = state.errors == 0 ? "正在监视" : "\(state.errors) 个文件需要处理"
          let updated = try await client.sources()
          if target?.peerID == monitor.source.config.peer, running, !Task.isCancelled {
            sources = updated
            loadRecords()
          }
          if !(try await client.pendingScans(monitor.source)).isEmpty { monitor.dirty = true }
        } catch {
          let message =
            PeerDatabase.isCancellation(error)
            ? "扫描已停止" : PeerDatabase.failure(error).localizedDescription
          statuses[id] = message
          if !PeerDatabase.isCancellation(error), running {
            do { try await client.reportIssue(message, source: monitor.source) } catch {
              statuses[id] = "\(message)；状态暂未写回信息库"
            }
          }
          if let job {
            let status =
              Date() >= job.deadline
              ? "timed_out" : PeerDatabase.isCancellation(error) ? "aborted" : "failed"
            let closing = Task {
              try await client.close(job, status: status, state: DirectoryState(issue: message))
            }
            do { try await closing.value } catch { statuses[id] = "\(message)；任务终态待信息库核对" }
          }
          // Reconnection reconciles current files, without an outbox.
          monitor.dirty = true
          break
        }
      }
    }
  }

  private func report(_ progress: ScanProgress, id: String) {
    statuses[id] = "\(progress.completed)/\(progress.total) · \(progress.filename)"
  }

  private func client(_ target: ConnectionTarget) throws -> LocalFileClient {
    let active = self.target
    let connection =
      active?.peerID == target.peerID && active?.host == target.host && active?.port == target.port
        && active?.database == target.database ? active! : target
    return LocalFileClient(
      target: connection, password: try context.credentials.read(for: connection.id))
  }

  private func saveBindings() throws {
    try FileManager.default.createDirectory(
      at: bindingURL.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try JSONEncoder().encode(bindings).write(to: bindingURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: bindingURL.path)
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
        guard !Task.isCancelled, selectedSource == source.id, self.target?.id == target.id else {
          return
        }
        let previous = file
        records = result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let selectedFile, !records.contains(where: { $0.id == selectedFile }) {
          self.selectedFile = nil
        } else if previous?.bodyID != file?.bodyID || previous?.metadata.revision != file?.metadata.revision || textIssue != nil
          || (file?.bodyID != nil && selectedText == nil && !loadingText) {
          loadText()
        }
      } catch { if !Task.isCancelled { issue = PeerDatabase.failure(error).localizedDescription } }
    }
  }

  public func loadText() {
    textTask?.cancel()
    selectedText = nil
    textIssue = nil
    loadingText = false
    guard let file, file.bodyID != nil, let target else { return }
    loadingText = true
    textTask = Task {
      defer { if !Task.isCancelled { loadingText = false } }
      do {
        let text = try await client(target).text(for: file)
        guard !Task.isCancelled else { return }
        selectedText = text
      } catch {
        if !Task.isCancelled { textIssue = PeerDatabase.failure(error).localizedDescription }
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
      let client = try client(target)
      try await client.prepare()
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
      self.schedule(self.key(source.id, target))
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
      let url = try PeerFileLocation(uri: record.metadata.location).localURL(for: target.peerID)
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
