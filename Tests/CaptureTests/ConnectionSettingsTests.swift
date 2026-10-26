import Foundation
import PeerCore
import Security
import Testing

struct ConnectionSettingsTests {
    @Test func savesMultipleConnectionsAndRestoresSelectionWithoutChangingIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("connection.json")
        let settings = ConnectionSettings(url: url)
        let first = ConnectionTarget(
            host: "one.example", database: "first", username: "peer", name: "个人")
        let second = ConnectionTarget(
            host: "two.example", database: "second", username: "peer", name: "工作")
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

    @Test func rejectsUnsupportedOrCorruptFormatsWithoutModifyingData() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = ConnectionTarget(host: "one.example", database: "first", username: "peer")
        try JSONEncoder().encode(original).write(to: url)
        let settings = ConnectionSettings(url: url)
        let previous = try Data(contentsOf: url)
        await #expect(throws: (any Error).self) { try await settings.loadAll() }
        #expect(try Data(contentsOf: url) == previous)
        try Data("{\"connections\":42}".utf8).write(to: url)
        await #expect(throws: (any Error).self) { try await settings.loadAll() }
        #expect(try String(contentsOf: url, encoding: .utf8) == "{\"connections\":42}")
    }
    @Test func editingCredentialsKeepsIdentityAndResolvesWhileAnotherConnectionIsSelected()
        async throws
    {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        let service = "dev.inkcre.connection-edit.\(UUID())"
        let credentials = CredentialStore(service: service)
        defer {
            SecItemDelete(
                [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                ] as CFDictionary)
            try? FileManager.default.removeItem(at: directory)
        }
        let settings = ConnectionSettings(url: directory.appendingPathComponent("connection.json"))
        let first = ConnectionTarget(host: "first.example", database: "first", username: "old_role")
        let second = ConnectionTarget(host: "second.example", database: "second", username: "peer")
        try await settings.save(first)
        try await settings.save(second)
        let edited = try await settings.saveEdited(
            host: first.host, port: "5432", database: first.database,
            username: "new_role", tls: .require, web: "https://first.example",
            password: "synthetic",
            name: "新名称", previous: first, credentials: credentials)
        #expect(edited.id == first.id && edited.peerID == first.peerID)
        #expect(try await settings.loadAll().connections == [edited, second])
        _ = try await settings.select(second.id)
        #expect(try await settings.resolve(first) == edited)
        #expect(try await settings.load() == second)
        var redirected = edited
        redirected.database = "another_database"
        await #expect(throws: PeerError.self) { try await settings.save(redirected) }
        await #expect(throws: PeerError.self) { try await settings.resolve(redirected) }
        #expect(try await settings.resolve(first) == edited)
    }

    @Test func displayEditsReusePoolAndCredentialEditsReplaceIt() async throws {
        let database = PeerDatabase()
        let target = ConnectionTarget(host: "localhost", database: "unused", username: "peer")
        let original = try await database.client(for: target, password: "unused")
        var edited = target
        edited.name = "新名称"
        edited.webURL = URL(string: "https://example.test")
        #expect(try await database.client(for: edited, password: "unused") === original)
        edited.username = "new_role"
        let replaced = try await database.client(for: edited, password: "unused")
        #expect(replaced !== original)
        #expect(try await database.client(for: edited, password: "changed") !== replaced)
        await database.shutdown()
    }

}
