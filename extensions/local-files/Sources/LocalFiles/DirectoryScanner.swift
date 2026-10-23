import Foundation
import PeerCore

public struct ScanProgress: Sendable {
  public let completed: Int
  public let total: Int
  public let filename: String
}

public enum DirectoryScanner {
  public static func scan(
    source: DirectorySource, client: LocalFileClient, job: SourceJob? = nil,
    progress: @escaping @Sendable (ScanProgress) async -> Void = { _ in }
  ) async throws -> DirectoryState {
    let root = URL(fileURLWithPath: source.config.path, isDirectory: true)
    let identity: String
    let files: [URL]
    do {
      identity = try rootIdentity(root)
      files = try await background { try FileExtractor.files(in: root) }
    } catch is CancellationError { throw CancellationError() } catch {
      throw PeerError.needsAction("无法完整读取目录：\(error.localizedDescription)")
    }
    let records = try await client.records(source: source)
    let paths = Set(files.map(\.path))
    let byPath = Dictionary(grouping: records, by: \.path)
    guard byPath.values.allSatisfy({ $0.count == 1 }) else {
      throw PeerError.invalid("目录中存在重复的文件资料位置。")
    }
    var used: Set<Int> = []
    var errors = 0
    for (index, url) in files.enumerated() {
      try await client.check(job)
      var record = byPath[url.path]?.first
      let previous = record?.metadata.revision
      let observation = try await background {
        try FileExtractor.observe(url, peer: source.config.peer, previous: previous)
      }
      if record == nil, let identity = observation.metadata.identity {
        let candidates = records.filter {
          !paths.contains($0.path) && !used.contains($0.id) && $0.metadata.identity == identity
        }
        if candidates.count == 1 { record = candidates[0] }
      }
      if let record { used.insert(record.id) }
      try await client.check(job)
      try await client.save(observation, replacing: record, source: source)
      if observation.metadata.issue != nil { errors += 1 }
      await progress(
        ScanProgress(completed: index + 1, total: files.count, filename: url.lastPathComponent))
    }
    try await client.check(job)
    guard try rootIdentity(root) == identity else {
      throw PeerError.needsAction("目录在扫描中变更，等待重新核对。")
    }
    let state = DirectoryState(scanned_at: Date(), errors: errors)
    try await client.finishScan(
      source: source, missing: records.filter { !used.contains($0.id) }, state: state)
    return state
  }

  private static func rootIdentity(_ root: URL) throws -> String {
    let values = try URL(fileURLWithPath: root.path).resourceValues(forKeys: [
      .isDirectoryKey, .isSymbolicLinkKey, .volumeUUIDStringKey,
    ])
    guard values.isDirectory == true, values.isSymbolicLink != true,
      let volume = values.volumeUUIDString,
      let inode = try FileManager.default.attributesOfItem(atPath: root.path)[.systemFileNumber]
        as? NSNumber
    else { throw PeerError.needsAction("目录当前不可访问。") }
    return "\(volume):\(inode)"
  }

  private static func background<T: Sendable>(_ work: @escaping @Sendable () throws -> T)
    async throws -> T
  {
    let task = Task.detached(priority: .utility, operation: work)
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }
}
