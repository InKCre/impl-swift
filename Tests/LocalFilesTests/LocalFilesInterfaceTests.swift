import AppKit
import Foundation
import LocalFiles
import PeerCore
import Security
import SwiftUI
import Testing
import WebKit

@testable import LocalFilesMac

@Suite(.serialized) @MainActor
struct LocalFilesInterfaceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["INKCRE_FILES_TEST_DATABASE"] != nil))
    func monitorRestartPauseAndFileReadingInHiddenWindow() async throws {
        _ = NSApplication.shared
        let env = ProcessInfo.processInfo.environment
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let context = PeerHostContext(
            identity: "dev.inkcre.files-tests.\(UUID())",
            directory: root.appendingPathComponent("host"))
        let target = ConnectionTarget(
            host: "127.0.0.1", port: Int(env["INKCRE_FILES_TEST_PORT"] ?? "55483")!,
            database: try #require(env["INKCRE_FILES_TEST_DATABASE"]), username: "inkcre_core",
            tls: .disable)
        try context.credentials.save(
            try #require(env["INKCRE_FILES_TEST_PASSWORD"]), for: target.id)
        try await context.connections.save(target)
        defer {
            SecItemDelete(
                [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: "\(context.identity).connections",
                ] as CFDictionary)
            try? FileManager.default.removeItem(at: root)
        }
        let folder = root.appendingPathComponent("documents")
        try fileFixtures(folder)
        let model = LocalFilesModel(context: context)
        defer {
            print(
                "Local files final state: sources=\(model.sources.count), records=\(model.records.count), issue=\(model.issue ?? "none"), status=\(model.source.map(model.status) ?? "none")"
            )
        }
        try model.start()
        defer { Task { await model.stop() } }
        await model.refresh()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 570, height: 600),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentViewController = NSHostingController(rootView: LocalFilesView(model: model))
        window.setContentSize(NSSize(width: 570, height: 600))
        defer { window.orderOut(nil) }
        try await until { !model.loading && model.target != nil }
        try await snapshot(window, name: "files-empty")
        await model.addDirectory(folder, target: target)
        #expect(model.issue == nil)
        try await until { model.records.count == 6 && model.source.map(model.isScanning) == false }
        let file = try #require(model.records.first { $0.name == "note.md" })
        model.selectedFile = model.records.first { $0.name == "note.pdf" }?.id
        model.selectedFile = file.id
        #expect(model.selectedContent == nil && model.loadingContent)
        try await until {
            model.selectedContent == "# 标题\n\n第一段。\n\n- 列表\n" && !model.loadingContent
        }
        try await until {
            guard let view = window.contentView, let reader = self.webReader(in: view),
                !reader.isLoading
            else { return false }
            return
                (try? await reader.evaluateJavaScript("document.querySelector('h1')?.textContent"))
                as? String == "标题"
        }
        #expect(!window.isVisible)
        let database = PeerDatabase.shared
        let pool = try await database.client(
            for: target, password: try #require(env["INKCRE_FILES_TEST_PASSWORD"]))
        let catalogVersion = try await pool.query(
            "SELECT xmin::text FROM inkcre.sources_types WHERE id=\(LocalFilesContract.sourceType)"
        )
        .decode(String.self).first { @Sendable _ in true }
        for _ in 0..<3 { await model.refresh() }
        let afterRefresh = try await pool.query(
            "SELECT xmin::text FROM inkcre.sources_types WHERE id=\(LocalFilesContract.sourceType)"
        )
        .decode(String.self).first { @Sendable _ in true }
        #expect(catalogVersion == afterRefresh)
        #expect(model.selectedContent != nil && !model.loadingContent)
        try await snapshot(window, name: "files-body")
        model.selectedFile = model.records.first { $0.name == "note.html" }?.id
        try await until {
            guard model.file?.bodyResolver == "core.html.v1", !model.loadingContent,
                let view = window.contentView, let reader = self.webReader(in: view),
                !reader.isLoading
            else { return false }
            return
                (try? await reader.evaluateJavaScript("document.querySelector('td')?.textContent"))
                as? String == "A"
        }
        let reader = try #require(window.contentView.flatMap(webReader))
        let code = try await reader.evaluateJavaScript("document.querySelector('pre')?.textContent")
        #expect((code as? String)?.contains("<node>& value\n  indented") == true)
        #expect(
            try await reader.evaluateJavaScript("typeof window.not_body") as? String == "undefined")
        #expect(
            try await reader.evaluateJavaScript(
                "document.querySelectorAll('video,track,[src]').length") as? Int == 0)
        #expect(
            try await reader.evaluateJavaScript(
                "!!document.querySelector('a[href=\"https://example.org/captions.vtt\"]')") as? Bool
                == true)
        try await snapshot(window, name: "files-html")
        if let path = env["INKCRE_LAYOUT_EVIDENCE_DIR"] {
            let image = try await reader.takeSnapshot(configuration: nil)
            let data = try #require(image.tiffRepresentation)
            try #require(NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]))
                .write(
                    to: URL(fileURLWithPath: path).appendingPathComponent("files-html-content.png"))
        }
        model.selectedFile = file.id
        try await until { model.selectedContent == "# 标题\n\n第一段。\n\n- 列表\n" }
        let url = folder.appendingPathComponent("note.md")
        try Data("# 自动监视后的正文".utf8).write(to: url, options: .atomic)
        try await until { model.selectedContent == "# 自动监视后的正文" }
        let source = try #require(model.source)
        let client = LocalFileClient(
            target: target, password: try #require(env["INKCRE_FILES_TEST_PASSWORD"]))
        let other = ConnectionTarget(
            host: target.host, port: target.port, database: target.database,
            username: target.username, tls: target.tls)
        try context.credentials.save(
            try #require(env["INKCRE_FILES_TEST_PASSWORD"]), for: other.id)
        try await context.connections.save(other)
        await model.connectionDidChange(other)
        #expect(model.sources.isEmpty && model.records.isEmpty)
        try Data("# 后台目录继续监视".utf8).write(to: url, options: .atomic)
        try await until {
            guard
                let record = try? await client.records(source: source).first(where: {
                    $0.id == file.id
                })
            else { return false }
            return (try? await client.content(for: record)) == "# 后台目录继续监视"
        }
        #expect(model.target?.id == other.id && model.sources.isEmpty && model.records.isEmpty)
        _ = try await context.connections.select(target.id)
        await model.connectionDidChange(target)
        try await until { model.records.contains { $0.id == file.id } }
        model.selectedFile = file.id
        try await until { model.selectedContent == "# 后台目录继续监视" }
        model.toggle(try #require(model.source))
        try await until { model.source?.config.enabled == false && !model.working }
        try Data("# 暂停时修改".utf8).write(to: url, options: .atomic)
        try await Task.sleep(for: .seconds(2))
        #expect(model.selectedContent == "# 后台目录继续监视")
        try await snapshot(window, name: "files-paused")
        model.toggle(try #require(model.source))
        try await until { model.selectedContent == "# 暂停时修改" && !model.working }
        await model.stop()
        try Data("# 停机时修改".utf8).write(to: url, options: .atomic)
        try await Task.sleep(for: .seconds(2))
        #expect(try await client.content(for: file) == "# 暂停时修改")
        #expect(!model.isScanning(source))
        try model.start()
        try await until { model.selectedContent == "# 停机时修改" }
        try FileManager.default.removeItem(at: url)
        try await until { model.file?.metadata.available == false }
        #expect(model.selectedContent == "# 停机时修改")
        try await snapshot(window, name: "files-original-missing")
        try Data("not a pdf".utf8).write(
            to: folder.appendingPathComponent("note.pdf"), options: .atomic)
        try await until {
            model.records.contains { $0.name == "note.pdf" && $0.metadata.issue != nil }
        }
        model.selectedFile = model.records.first { $0.name == "note.pdf" }?.id
        try await until { model.selectedContent != nil && !model.loadingContent }
        try await snapshot(window, name: "files-failure")
        let restoredSource = try #require(model.source)
        model.remove(restoredSource)
        try await until { model.sources.isEmpty && !model.working }
        #expect(try await client.records(source: restoredSource).count == 6)
        #expect(!window.isVisible)
        await model.stop()
    }

    private func until(_ condition: @escaping @MainActor () async -> Bool) async throws {
        for _ in 0..<150 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(await condition(), "等待本地文件主流程状态超时")
        throw PeerError.needsAction("测试等待状态超时。")
    }

    private func webReader(in view: NSView) -> WKWebView? {
        if let reader = view as? WKWebView { return reader }
        for child in view.subviews { if let reader = webReader(in: child) { return reader } }
        return nil
    }

    private func snapshot(_ window: NSWindow, name: String) async throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(150))
            let view = try #require(window.contentView?.superview)
            view.layoutSubtreeIfNeeded()
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            #expect(bitmap.pixelsWide >= 570 && bitmap.pixelsHigh >= 600)
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let path = ProcessInfo.processInfo.environment["INKCRE_LAYOUT_EVIDENCE_DIR"] {
                try #require(bitmap.representation(using: .png, properties: [:])).write(
                    to: URL(fileURLWithPath: path).appendingPathComponent(
                        "\(name)-\(appearance.rawValue).png"))
            }
        }
    }
}

@Test func safeFileReadingKeepsStructureAndBlocksSourceCode() throws {
    let source = """
        # 标题

        | Item | Value |
        | --- | --- |
        | A | 12 |

        - [x] 完成
        - [ ] 待办

        ```html
        <node>& value
          indented
        ```

        ~~删除~~ https://example.org

        <a href="#part">文内目录</a><h2 id="part">章节</h2>

        <script>window.executed = true</script><iframe src="https://invalid.test/frame"></iframe>
        <img src="https://example.org/image.png" alt="图片说明"><a href="javascript:alert(1)">bad</a>
        <video src="https://example.org/video.mp4"><track src="https://example.org/captions.vtt" label="English"><p>已有文字稿 <a href="https://example.org/transcript">完整文字稿</a></p></video>
        """
    let html = try readingDocument(source, resolver: "core.markdown.v1")
    #expect(html.contains("<table>") && html.contains("<del>删除</del>"))
    #expect(html.contains("&lt;node&gt;&amp; value\n  indented"))
    #expect(html.contains("checked") && html.contains("disabled"))
    #expect(html.contains("https://example.org/image.png") && html.contains("图片说明"))
    #expect(
        !html.contains("window.executed") && !html.contains("<iframe")
            && !html.contains("javascript:"))
    #expect(
        html.contains("https://example.org/video.mp4")
            && html.contains("https://example.org/captions.vtt"))
    #expect(!html.contains("<video") && !html.contains("<track"))
    #expect(html.contains("已有文字稿") && html.contains("https://example.org/transcript"))
    #expect(html.contains("default-src 'none'"))
    #expect(html.contains("href=\"#part\"") && html.contains("id=\"part\""))
}
