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
        let context = PeerHostContext(
            identity: service, directory: directory, credentials: credentials)
        let settings = context.connections
        let first = ConnectionTarget(host: "first.example", database: "first", username: "old_role")
        let second = ConnectionTarget(host: "second.example", database: "second", username: "peer")
        try await settings.save(first)
        try await settings.save(second)
        let edited = try await context.saveEdited(
            host: first.host, port: "5432", database: first.database,
            username: "new_role", tls: .require, web: "https://first.example",
            password: "synthetic",
            name: "新名称", previous: first)
        let original = try await context.database.client(
            for: edited, credentials: .keychain(credentials))
        _ = try await context.saveEdited(
            host: edited.host, port: "5432", database: edited.database,
            username: edited.username, tls: .require, web: "https://renamed.example",
            password: "", name: "展示变化", previous: edited)
        #expect(
            try await context.database.client(for: edited, credentials: .keychain(credentials))
                === original)
        try credentials.save("external-update", for: edited.id)
        _ = try await context.saveEdited(
            host: edited.host, port: "5432", database: edited.database,
            username: edited.username, tls: .require, web: "https://first.example",
            password: "", name: "新名称", previous: edited)
        let updated = try await context.database.client(
            for: edited, credentials: .keychain(credentials))
        #expect(updated !== original)
        #expect(try await context.database.client(for: edited, password: "synthetic") === updated)
        _ = try await context.saveEdited(
            host: edited.host, port: "5432", database: edited.database,
            username: edited.username, tls: .require, web: "https://first.example",
            password: "updated", name: "新名称", previous: edited)
        let savedPasswordClient = try await context.database.client(
            for: edited, password: "synthetic")
        #expect(savedPasswordClient !== updated)
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
        await context.database.shutdown()
    }

}
