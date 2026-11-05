import AppKit
import CoreText
import Foundation
import PeerCore
import SwiftSoup
import Testing

@testable import LocalFiles

@Test func localHTMLPreservesAcquiredPostsAndRejectsEmptyShell() throws {
    let source = """
        <link rel="canonical" href="https://bsky.app/profile/a.test">
        <script type="application/ld+json">{"@type":"ProfilePage","hasPart":[
        {"@type":"DiscussionForumPosting","url":"https://bsky.app/profile/a.test/post/one","author":{"name":"Alice"},"datePublished":"2025-01-01","text":"First <node>\\nnext line","sharedContent":{"@type":"DiscussionForumPosting","url":"https://bsky.app/profile/b.test/post/quote","author":{"name":"Bob"},"text":"Quoted post"}},
        {"@type":"DiscussionForumPosting","url":"https://bsky.app/profile/a.test/post/two","author":{"name":"Alice"},"text":"Thanks!"}]}</script>
        """
    let html = try FileExtractor.extract(Data(source.utf8), format: "html")
    let document = try SwiftSoup.parse(html)
    #expect(try document.select("body > article").size() == 2)
    #expect(try document.select("blockquote article").size() == 1)
    #expect(try document.select("time").text() == "2025-01-01")
    #expect(try document.text().contains("First <node>"))
    #expect(try document.select("blockquote header").text() == "Bob")
    #expect(try document.text().contains("Thanks!"))
    #expect(try document.select("script,node").isEmpty())
    let visible =
        "<main><a href=\"https://bsky.app/profile/a.test/post/visible\">Alice</a><p>Already loaded</p></main>"
    let preferred = try FileExtractor.extract(Data((source + visible).utf8), format: "html")
    #expect(preferred.contains("Already loaded") && !preferred.contains("First &lt;node&gt;"))
    let conversation =
        "<main><div data-message-id=one data-message-author-role=user><p>Question</p></div><div data-message-id=two data-message-author-role=assistant><p>Answer</p></div></main>"
    let messages = try FileExtractor.extract(Data(conversation.utf8), format: "html")
    #expect(
        try SwiftSoup.parse(messages).select("header").array().map { try $0.text() } == [
            "user", "assistant",
        ])
    for shell in [
        "<main></main><script>bootstrap()</script>",
        "<link rel=canonical href=https://chatgpt.com/share/unloaded><nav>Home Sign in</nav><main></main>",
    ] {
        #expect(throws: PeerError.self) {
            try FileExtractor.extract(Data(shell.utf8), format: "html")
        }
    }
    #expect(try FileExtractor.extract(Data("<p>Hi</p>".utf8), format: "html").contains("Hi"))
}

func fileFixtures(_ directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for (name, text) in [
        ("note.md", "# 标题\n\n第一段。\n\n- 列表\n"),
        ("note.org", "* 标题\n:PROPERTIES:\n:ID: sample\n:END:\n正文\n"),
        (
            "note.html",
            """
            <h1>标题</h1><p>第一段<br>第二行</p>
            <table><tr><th>名称</th><th>数值</th></tr><tr><td>A</td><td>12</td></tr></table>
            <pre><code>&lt;node&gt;&amp; value
              indented
            </code></pre><a href="https://example.org/source">原文</a>
            <video src="https://example.org/video.mp4"><track src="https://example.org/captions.vtt" label="字幕"></video>
            <script>window.not_body = true</script><style>not_style</style>
            """
        ),
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
                NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 18)])
            ),
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
        let text = try #require(observation.content)
        #expect(!text.isEmpty)
        if file.pathExtension == "md" || file.pathExtension == "org" || file.pathExtension == "txt"
        {
            #expect(text == String(data: try Data(contentsOf: file), encoding: .utf8))
        }
        if file.pathExtension == "html" {
            #expect(
                !text.contains("not_body") && !text.contains("not_style")
                    && text.contains("第一段") && text.contains("第二行") && text.contains("<h"))
        }
        if file.pathExtension == "pdf" { #expect(text.contains("第一页中文\n\n第二页文字")) }
        if file.pathExtension == "docx" {
            #expect(observation.metadata.revision?.scope == "main_document")
        }
        let serialized = try FileJSON.encode(observation.metadata)
        #expect(
            try FileJSON.decode(FileMetadata.self, serialized).identity
                == observation.metadata.identity)
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
    let repository = LocalFilesRepository(
        target: target, password: try #require(env["INKCRE_FILES_TEST_PASSWORD"]),
        database: database)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try fileFixtures(directory)
    try await repository.prepare()
    let source = try await repository.createDirectory(path: directory.path)
    #expect(try await repository.sources().contains { $0.id == source.id })
    let otherTarget = ConnectionTarget(
        host: target.host, port: target.port, database: target.database, username: target.username,
        tls: .disable)
    let otherRepository = LocalFilesRepository(
        target: otherTarget, password: try #require(env["INKCRE_FILES_TEST_PASSWORD"]),
        database: database)
    try await otherRepository.prepare()
    let otherSource = try await otherRepository.createDirectory(path: directory.path)
    let staleRow = DirectorySource(
        id: otherSource.id, config: source.config, block: source.block, state: source.state)
    await #expect(throws: (any Error).self) { try await otherRepository.remove(staleRow) }
    #expect(try await otherRepository.sources().count == 1)
    try await otherRepository.remove(otherSource)
    let first = try await DirectoryScanner.scan(source: source, repository: repository)
    #expect(first.errors == 0)
    let original = try await repository.records(source: source)
    #expect(
        original.count == 6 && original.allSatisfy { $0.bodyID != nil && $0.metadata.available })
    let note = try #require(original.first { $0.name == "note.md" })
    let pool = try await database.client(
        for: target, password: try #require(env["INKCRE_FILES_TEST_PASSWORD"]))
    // Reconstruct a previously released v1 graph, then re-extract unchanged bytes.
    var legacy = note.metadata
    let revision = try #require(legacy.revision)
    legacy.revision = FileRevision(
        sha256: revision.sha256, extractor: "mac-native-text.v1",
        extracted_at: revision.extracted_at, scope: revision.scope)
    try await pool.query(
        "UPDATE inkcre.blocks SET resolver=\(LocalFilesContract.legacyResolver),content=\(try FileJSON.encode(legacy)) WHERE id=\(note.id)"
    )
    try await pool.query("UPDATE inkcre.blocks SET resolver='core.text.v1' WHERE id=\(note.bodyID)")
    let reference = try await pool.query(
        "INSERT INTO inkcre.relations(from_,to_,content) VALUES (\(source.block),\(note.bodyID),'synthetic-reference') RETURNING id"
    )
    let referenceID = try #require(try await reference.decode(Int.self).first { _ in true })
    let noteURL = directory.appendingPathComponent("note.md")
    let originalBytes = try Data(contentsOf: noteURL)
    try Data([0xff, 0x00, 0x13]).write(to: noteURL, options: .atomic)
    _ = try await DirectoryScanner.scan(source: source, repository: repository)
    let failedLegacy = try #require(
        try await repository.records(source: source).first { $0.id == note.id })
    #expect(failedLegacy.bodyID == note.bodyID && failedLegacy.bodyResolver == "core.text.v1")
    #expect(failedLegacy.metadata.revision == legacy.revision)
    let legacyRoot = try await pool.query("SELECT resolver FROM inkcre.blocks WHERE id=\(note.id)")
    #expect(
        try await legacyRoot.decode(String.self).first { _ in true }
            == LocalFilesContract.legacyResolver)
    try originalBytes.write(to: noteURL, options: .atomic)
    _ = try await DirectoryScanner.scan(source: source, repository: repository)
    let upgraded = try #require(
        try await repository.records(source: source).first { $0.id == note.id })
    #expect(upgraded.bodyID == note.bodyID && upgraded.bodyResolver == "core.markdown.v1")
    #expect(upgraded.metadata.revision?.extractor == LocalFilesContract.extractor)
    let keptReference = try await pool.query(
        "SELECT to_ FROM inkcre.relations WHERE id=\(referenceID)")
    #expect(try await keptReference.decode(Int.self).first { _ in true } == note.bodyID)
    let url = directory.appendingPathComponent("note.md")
    try Data("# 修改后\n\n当前正文".utf8).write(to: url, options: .atomic)
    _ = try await DirectoryScanner.scan(source: source, repository: repository)
    var records = try await repository.records(source: source)
    #expect(records.count == 6)
    #expect(
        try await repository.content(for: #require(records.first { $0.id == note.id }))
            == "# 修改后\n\n当前正文")
    try FileManager.default.moveItem(at: url, to: directory.appendingPathComponent("renamed.md"))
    _ = try await DirectoryScanner.scan(source: source, repository: repository)
    records = try await repository.records(source: source)
    #expect(records.first { $0.id == note.id }?.name == "renamed.md")
    let pdf = try #require(records.first { $0.name == "note.pdf" })
    let pdfText = try await repository.content(for: pdf)
    try Data("broken pdf".utf8).write(
        to: directory.appendingPathComponent("note.pdf"), options: .atomic)
    let failed = try await DirectoryScanner.scan(source: source, repository: repository)
    #expect(failed.errors == 1)
    records = try await repository.records(source: source)
    #expect(
        try await repository.content(for: #require(records.first { $0.id == pdf.id })) == pdfText)
    #expect(records.first { $0.id == pdf.id }?.metadata.revision == pdf.metadata.revision)
    try FileManager.default.removeItem(at: directory.appendingPathComponent("renamed.md"))
    _ = try await DirectoryScanner.scan(source: source, repository: repository)
    records = try await repository.records(source: source)
    #expect(records.first { $0.id == note.id }?.metadata.available == false)
    #expect(
        try await repository.content(for: #require(records.first { $0.id == note.id }))
            == "# 修改后\n\n当前正文")
    let moved = directory.appendingPathExtension("offline")
    try FileManager.default.moveItem(at: directory, to: moved)
    await #expect(throws: (any Error).self) {
        try await DirectoryScanner.scan(source: source, repository: repository)
    }
    try FileManager.default.moveItem(at: moved, to: directory)
    #expect(
        try await repository.records(source: source).filter { $0.metadata.available }.count == 5)
    try await repository.reportIssue("合成目录暂时离线", source: source)
    #expect(try await repository.sources().first { $0.id == source.id }?.state.issue == "合成目录暂时离线")

    let invalidParameters = "{\"source\":\(source.id),\"config\":{\"unsupported\":true}}"
    let invalidRows = try await pool.query(
        "INSERT INTO inkcre.jobs(type,parameters,timeout_seconds,status) VALUES (\(SourceJobs.type),\(invalidParameters)::jsonb,300,'pending') RETURNING id"
    )
    let invalidID = try #require(try await invalidRows.decode(Int.self).first { _ in true })
    #expect(try await repository.pendingScans(source).isEmpty)
    let invalidStatus = try await pool.query(
        "SELECT status::text FROM inkcre.jobs WHERE id=\(invalidID)")
    #expect(try await invalidStatus.decode(String.self).first { _ in true } == "failed")
    let jobID = try await repository.submitScan(source)
    let job = try #require(try await repository.claim(jobID, source: source))
    #expect(try await repository.claim(jobID, source: source) == nil)
    let result = try await DirectoryScanner.scan(source: source, repository: repository, job: job)
    try await repository.close(job, status: "failed", state: result)
    let cancelledID = try await repository.submitScan(source)
    let cancelled = try #require(try await repository.claim(cancelledID, source: source))
    await #expect(throws: CancellationError.self) {
        try await DirectoryScanner.scan(source: source, repository: repository, job: cancelled) {
            progress in
            if progress.completed == 1 {
                do {
                    try await pool.query(
                        "UPDATE inkcre.jobs SET abort_requested=true WHERE id=\(cancelledID)")
                } catch { Issue.record("无法设置合成取消请求：\(error)") }
            }
        }
    }
    try await repository.close(cancelled, status: "aborted", state: DirectoryState())
    try await repository.setEnabled(false, source: source)
    await #expect(throws: (any Error).self) {
        try await DirectoryScanner.scan(source: source, repository: repository)
    }
    await #expect(throws: (any Error).self) { try await repository.remove(source) }
    try await repository.remove(
        try #require(try await repository.sources().first { $0.id == source.id }))
    #expect(try await repository.sources().isEmpty)
    #expect(try await repository.records(source: source).count == 6)
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
    let unchanged = try FileExtractor.observe(
        url, peer: target.peerID, previous: original.metadata.revision)
    let record = FileRecord(id: 1, metadata: original.metadata, bodyID: 2)
    let source = DirectorySource(
        id: 1, config: DirectoryConfig(peer: target.peerID, path: folder.path), block: 3,
        state: DirectoryState())
    #expect(unchanged.content == nil && !unchanged.changes(original.metadata))
    try await LocalFilesRepository(target: target, password: "unused", database: PeerDatabase())
        .save(
            unchanged, replacing: record, source: source)
    var missing = original.metadata
    missing.available = false
    #expect(unchanged.changes(missing))
    var failed = original.metadata
    failed.issue = "上次读取失败"
    #expect(unchanged.changes(failed))
    var moved = unchanged
    moved.metadata.location = try PeerFileLocation(
        peer: target.peerID, path: folder.appendingPathComponent("renamed.txt").path
    ).uri
    #expect(moved.changes(original.metadata))
}
