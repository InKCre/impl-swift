import Foundation
import PeerCore
import Testing

struct ConnectionSettingsTests {
    @Test func savesMultipleConnectionsAndRestoresSelectionWithoutChangingIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("connection.json")
        let settings = ConnectionSettings(url: url)
        let first = ConnectionTarget(host: "one.example", database: "first", username: "peer", name: "个人")
        let second = ConnectionTarget(host: "two.example", database: "second", username: "peer", name: "工作")
        try await settings.save(first)
        try await settings.save(second)
        #expect(try await settings.load() == second)
        #expect(try await settings.select(first.id) == first)
        let reopened = ConnectionSettings(url: url)
        #expect(try await reopened.load() == first)
        #expect(try await reopened.loadAll().connections == [first, second])
        var renamed = first
        renamed.name = "私人信息库"
        try await reopened.save(renamed)
        #expect(try await reopened.loadAll().connections == [renamed, second])
        #expect(try await reopened.select(second.id) == second)
        await #expect(throws: (any Error).self) { try await reopened.select(UUID()) }
        #expect(try await reopened.load() == second)
    }

    @Test func preservesExistingSingleConnectionAndRejectsCorruptLists() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = ConnectionTarget(host: "one.example", database: "first", username: "peer")
        try JSONEncoder().encode(original).write(to: url)
        let settings = ConnectionSettings(url: url)
        #expect(try await settings.loadAll().connections == [original])
        #expect(try await settings.select(original.id) == original)
        #expect(try await ConnectionSettings(url: url).load() == original)
        try Data("{\"connections\":42}".utf8).write(to: url)
        await #expect(throws: (any Error).self) { try await settings.loadAll() }
        #expect(try String(contentsOf: url, encoding: .utf8) == "{\"connections\":42}")
    }
}
