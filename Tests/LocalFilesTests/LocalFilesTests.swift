import AppKit
import CoreText
import Foundation
import PeerCore
import Testing

@testable import LocalFiles

func fileFixtures(_ directory: URL) throws {
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  for (name, text) in [
    ("note.md", "# 标题\n\n第一段。\n\n- 列表\n"),
    ("note.org", "* 标题\n:PROPERTIES:\n:ID: sample\n:END:\n正文\n"),
    ("note.html", "<h1>标题</h1><p>第一段<br>第二行</p><script>not_body</script><style>not_style</style>"),
    ("note.txt", "原始文字\n第二行\n"),
  ] { try Data(text.utf8).write(to: directory.appendingPathComponent(name)) }
  let document = NSAttributedString(string: "主文档正文\n表格内容")
  let docx = try document.data(
    from: NSRange(location: 0, length: document.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
  try docx.write(to: directory.appendingPathComponent("note.docx"))
  let data = NSMutableData()
  var box = CGRect(x: 0, y: 0, width: 600, height: 800)
  let consumer = try #require(CGDataConsumer(data: data))
  let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
  for text in ["第一页中文", "第二页文字"] {
    context.beginPDFPage(nil)
    context.textPosition = CGPoint(x: 50, y: 700)
    CTLineDraw(
      CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 18)])),
      context)
    context.endPDFPage()
  }
  context.closePDF()
  try (data as Data).write(to: directory.appendingPathComponent("note.pdf"))
}

@Test func locationAndSixExtractorsPreserveMeaning() throws {
  let peer = UUID()
  let path = "/Users/test/中文 空格/#note?.md"
  let location = try PeerFileLocation(peer: peer, path: path)
  #expect(try PeerFileLocation(uri: location.uri) == location)
  #expect(throws: PeerError.self) { try location.localURL(for: UUID()) }
  for invalid in [
    "file:///Users/a", "inkcre-peer-file://not-peer/a", "\(location.uri)?query",
    "\(location.uri)#fragment",
  ] {
    #expect(throws: PeerError.self) { try PeerFileLocation(uri: invalid) }
  }
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  try fileFixtures(directory)
  let files = try FileExtractor.files(in: directory)
  #expect(files.count == 6)
  for file in files {
    let observation = try FileExtractor.observe(file, peer: peer)
    #expect(observation.metadata.issue == nil)
    let text = try #require(observation.text)
    #expect(!text.isEmpty)
    if file.pathExtension == "md" || file.pathExtension == "org" || file.pathExtension == "txt" {
      #expect(text == String(data: try Data(contentsOf: file), encoding: .utf8))
    }
    if file.pathExtension == "html" {
      #expect(
        !text.contains("not_body") && !text.contains("not_style") && text.contains("第一段\n第二行"))
    }
    if file.pathExtension == "pdf" { #expect(text.contains("第一页中文\n\n第二页文字")) }
    if file.pathExtension == "docx" {
      #expect(observation.metadata.revision?.scope == "main_document")
    }
    let serialized = try FileJSON.encode(observation.metadata)
    #expect(
      try FileJSON.decode(FileMetadata.self, serialized).identity == observation.metadata.identity)
  }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["INKCRE_FILES_TEST_DATABASE"] != nil))
func nativeSourceUpdatesCurrentGraphAndPreservesFailedAndDeletedBodies() async throws {
  let env = ProcessInfo.processInfo.environment
  let target = ConnectionTarget(
    host: "127.0.0.1", port: Int(env["INKCRE_FILES_TEST_PORT"] ?? "55483")!,
    database: try #require(env["INKCRE_FILES_TEST_DATABASE"]), username: "inkcre_core",
    tls: .disable)
  let database = PeerDatabase()
  let client = LocalFileClient(
    target: target, password: try #require(env["INKCRE_FILES_TEST_PASSWORD"]), database: database)
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  try fileFixtures(directory)
  try await client.prepare()
  let source = try await client.createDirectory(path: directory.path)
  #expect(try await client.sources().contains { $0.id == source.id })
  let otherTarget = ConnectionTarget(
    host: target.host, port: target.port, database: target.database, username: target.username,
    tls: .disable)
  let otherClient = LocalFileClient(
    target: otherTarget, password: try #require(env["INKCRE_FILES_TEST_PASSWORD"]),
    database: database)
  try await otherClient.prepare()
  let otherSource = try await otherClient.createDirectory(path: directory.path)
  let staleRow = DirectorySource(
    id: otherSource.id, config: source.config, block: source.block, state: source.state)
  await #expect(throws: (any Error).self) { try await otherClient.remove(staleRow) }
  #expect(try await otherClient.sources().count == 1)
  try await otherClient.remove(otherSource)
  let first = try await DirectoryScanner.scan(source: source, client: client)
  #expect(first.errors == 0)
  let original = try await client.records(source: source)
  #expect(original.count == 6 && original.allSatisfy { $0.bodyID != nil && $0.metadata.available })
  let note = try #require(original.first { $0.name == "note.md" })
  let url = directory.appendingPathComponent("note.md")
  try Data("# 修改后\n\n当前正文".utf8).write(to: url, options: .atomic)
  _ = try await DirectoryScanner.scan(source: source, client: client)
  var records = try await client.records(source: source)
  #expect(records.count == 6)
  #expect(try await client.text(for: #require(records.first { $0.id == note.id })) == "# 修改后\n\n当前正文")
  try FileManager.default.moveItem(at: url, to: directory.appendingPathComponent("renamed.md"))
  _ = try await DirectoryScanner.scan(source: source, client: client)
  records = try await client.records(source: source)
  #expect(records.first { $0.id == note.id }?.name == "renamed.md")
  let pdf = try #require(records.first { $0.name == "note.pdf" })
  let pdfText = try await client.text(for: pdf)
  try Data("broken pdf".utf8).write(
    to: directory.appendingPathComponent("note.pdf"), options: .atomic)
  let failed = try await DirectoryScanner.scan(source: source, client: client)
  #expect(failed.errors == 1)
  records = try await client.records(source: source)
  #expect(try await client.text(for: #require(records.first { $0.id == pdf.id })) == pdfText)
  #expect(records.first { $0.id == pdf.id }?.metadata.revision == pdf.metadata.revision)
  try FileManager.default.removeItem(at: directory.appendingPathComponent("renamed.md"))
  _ = try await DirectoryScanner.scan(source: source, client: client)
  records = try await client.records(source: source)
  #expect(records.first { $0.id == note.id }?.metadata.available == false)
  #expect(try await client.text(for: #require(records.first { $0.id == note.id })) == "# 修改后\n\n当前正文")
  let moved = directory.appendingPathExtension("offline")
  try FileManager.default.moveItem(at: directory, to: moved)
  await #expect(throws: (any Error).self) {
    try await DirectoryScanner.scan(source: source, client: client)
  }
  try FileManager.default.moveItem(at: moved, to: directory)
  #expect(try await client.records(source: source).filter { $0.metadata.available }.count == 5)
  try await client.reportIssue("合成目录暂时离线", source: source)
  #expect(try await client.sources().first { $0.id == source.id }?.state.issue == "合成目录暂时离线")
  let pool = try await database.client(for: target, password: try #require(env["INKCRE_FILES_TEST_PASSWORD"]))
  let invalidParameters = "{\"source\":\(source.id),\"config\":{\"unsupported\":true}}"
  let invalidRows = try await pool.query("INSERT INTO inkcre.jobs(type,parameters,timeout_seconds,status) VALUES (\(SourceJobs.type),\(invalidParameters)::jsonb,300,'pending') RETURNING id")
  let invalidID = try #require(try await invalidRows.decode(Int.self).first { _ in true })
  #expect(try await client.pendingScans(source).isEmpty)
  let invalidStatus = try await pool.query("SELECT status::text FROM inkcre.jobs WHERE id=\(invalidID)")
  #expect(try await invalidStatus.decode(String.self).first { _ in true } == "failed")
  let jobID = try await client.submitScan(source)
  let job = try #require(try await client.claim(jobID, source: source))
  #expect(try await client.claim(jobID, source: source) == nil)
  let result = try await DirectoryScanner.scan(source: source, client: client, job: job)
  try await client.close(job, status: "failed", state: result)
  try await client.setEnabled(false, source: source)
  await #expect(throws: (any Error).self) {
    try await DirectoryScanner.scan(source: source, client: client)
  }
  await #expect(throws: (any Error).self) { try await client.remove(source) }
  try await client.remove(try #require(try await client.sources().first { $0.id == source.id }))
  #expect(try await client.sources().isEmpty)
  #expect(try await client.records(source: source).count == 6)
  await database.shutdown()
}

@Test func unchangedObservationNeedsNoDatabaseWriteButSourceChangesStillMatter() async throws {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: folder) }
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let url = folder.appendingPathComponent("note.txt")
  try Data("已收入正文".utf8).write(to: url)
  let target = ConnectionTarget(host: "unused.invalid", database: "unused", username: "unused")
  let original = try FileExtractor.observe(url, peer: target.peerID)
  let unchanged = try FileExtractor.observe(url, peer: target.peerID, previous: original.metadata.revision)
  let record = FileRecord(id: 1, metadata: original.metadata, bodyID: 2)
  let source = DirectorySource(id: 1, config: DirectoryConfig(peer: target.peerID, path: folder.path), block: 3, state: DirectoryState())
  #expect(unchanged.text == nil && !unchanged.changes(original.metadata))
  try await LocalFileClient(target: target, password: "unused").save(unchanged, replacing: record, source: source)
  var missing = original.metadata
  missing.available = false
  #expect(unchanged.changes(missing))
  var failed = original.metadata
  failed.issue = "上次读取失败"
  #expect(unchanged.changes(failed))
  var moved = unchanged
  moved.metadata.location = try PeerFileLocation(peer: target.peerID, path: folder.appendingPathComponent("renamed.txt").path).uri
  #expect(moved.changes(original.metadata))
}
