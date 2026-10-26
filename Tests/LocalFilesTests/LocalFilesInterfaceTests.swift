import AppKit
import Foundation
import LocalFiles
import PeerCore
import Security
import SwiftUI
import Testing

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
        #expect(model.selectedText == nil && model.loadingText)
        try await until { model.selectedText == "# 标题\n\n第一段。\n\n- 列表\n" && !model.loadingText }
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
        #expect(model.selectedText != nil && !model.loadingText)
        try await snapshot(window, name: "files-body")
        let url = folder.appendingPathComponent("note.md")
        try Data("# 自动监视后的正文".utf8).write(to: url, options: .atomic)
        try await until { model.selectedText == "# 自动监视后的正文" }
        let source = try #require(model.source)
        model.toggle(source)
        try await until { model.source?.config.enabled == false && !model.working }
        try Data("# 暂停时修改".utf8).write(to: url, options: .atomic)
        try await Task.sleep(for: .seconds(2))
        #expect(model.selectedText == "# 自动监视后的正文")
        try await snapshot(window, name: "files-paused")
        model.toggle(try #require(model.source))
        try await until { model.selectedText == "# 暂停时修改" && !model.working }
        await model.stop()
        try Data("# 停机时修改".utf8).write(to: url, options: .atomic)
        try model.start()
        try await until { model.selectedText == "# 停机时修改" }
        try FileManager.default.removeItem(at: url)
        try await until { model.file?.metadata.available == false }
        #expect(model.selectedText == "# 停机时修改")
        try await snapshot(window, name: "files-original-missing")
        try Data("not a pdf".utf8).write(
            to: folder.appendingPathComponent("note.pdf"), options: .atomic)
        try await until {
            model.records.contains { $0.name == "note.pdf" && $0.metadata.issue != nil }
        }
        model.selectedFile = model.records.first { $0.name == "note.pdf" }?.id
        try await until { model.selectedText != nil && !model.loadingText }
        try await snapshot(window, name: "files-failure")
        let restoredSource = try #require(model.source)
        let client = LocalFileClient(
            target: target, password: try #require(env["INKCRE_FILES_TEST_PASSWORD"]))
        model.remove(restoredSource)
        try await until { model.sources.isEmpty && !model.working }
        #expect(try await client.records(source: restoredSource).count == 6)
        #expect(!window.isVisible)
        await model.stop()
    }

    private func until(_ condition: @escaping @MainActor () -> Bool) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(condition(), "等待本地文件主流程状态超时")
        throw PeerError.needsAction("测试等待状态超时。")
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
