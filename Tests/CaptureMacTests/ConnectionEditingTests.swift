import Foundation
import PeerCore
import PeerMacUI
import Security
import Testing

struct ConnectionEditingTests {
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

}
