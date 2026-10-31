import Foundation
import LocalFiles
import PeerCore
import Security
import Testing

@testable import LocalFilesMac

private actor ScanGate {
    private(set) var count = 0
    private var waiting: [(Int, CheckedContinuation<Void, Never>)] = []
    private var releases: [CheckedContinuation<Void, Never>] = []

    func scan() async {
        count += 1
        let ready = waiting.filter { $0.0 <= count }
        waiting.removeAll { $0.0 <= count }
        for (_, continuation) in ready { continuation.resume() }
        // Deliberately finish only when released: stopping must await in-flight extraction.
        await withCheckedContinuation { releases.append($0) }
    }
    func waitForScan(_ number: Int) async {
        if count < number {
            await withCheckedContinuation { waiting.append((number, $0)) }
        }
    }
    func finishScan() { releases.removeFirst().resume() }
}

@Suite(.serialized) @MainActor
struct DirectoryMonitorTests {
    @Test(
        .enabled(if: ProcessInfo.processInfo.environment["INKCRE_FILES_TEST_DATABASE"] != nil),
        .timeLimit(.minutes(1)))
    func coalescedChangesAndConcurrentStopsWaitForTheSameScan() async throws {
        let env = ProcessInfo.processInfo.environment
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let context = PeerHostContext(
            identity: "dev.inkcre.monitor-tests.\(UUID())", directory: root)
        let target = ConnectionTarget(
            host: "127.0.0.1", port: Int(env["INKCRE_FILES_TEST_PORT"] ?? "55483")!,
            database: try #require(env["INKCRE_FILES_TEST_DATABASE"]), username: "inkcre_core",
            tls: .disable)
        let secret = try #require(env["INKCRE_FILES_TEST_PASSWORD"])
        try context.credentials.save(secret, for: target.id)
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
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let client = LocalFileClient(target: target, password: secret)
        try await client.prepare()
        let source = try await client.createDirectory(path: folder.path)
        let gate = ScanGate()
        var sourceUpdates = 0
        let monitor = try DirectoryMonitor(
            source: source, target: target, context: context,
            bookmark: folder.bookmarkData(
                options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil),
            onBookmarkRenewed: { _ in }, onState: { _, _ in },
            onSources: { _ in sourceUpdates += 1 },
            scan: { _, _, _, _ in
                await gate.scan()
                return DirectoryState()
            })
        // A remote Job wakes a clean monitor; the Model need not inspect pending jobs or dirty state.
        _ = try await client.submitScan(source)
        monitor.refresh()
        await gate.waitForScan(1)
        monitor.schedule()
        monitor.schedule()
        await gate.finishScan()
        await gate.waitForScan(2)
        #expect(sourceUpdates == 1)
        var startedStops = 0
        var finishedStops = 0
        let first = Task {
            startedStops += 1
            await monitor.stop()
            finishedStops += 1
        }
        let second = Task {
            startedStops += 1
            await monitor.stop()
            finishedStops += 1
        }
        while startedStops != 2 { await Task.yield() }
        #expect(finishedStops == 0)
        monitor.schedule()
        monitor.refresh()
        await gate.finishScan()
        await first.value
        await second.value
        #expect(finishedStops == 2)
        #expect(await gate.count == 2)
        #expect(sourceUpdates == 1)
        await monitor.stop()
        #expect(await gate.count == 2)
    }
}
