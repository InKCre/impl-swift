import Foundation
import Security
import Testing

@testable import PeerCore

@Suite(.serialized)
struct CredentialStoreTests {
    private final class Fixture {
        let directory: URL
        let keychain: SecKeychain
        static let password = "disposable-keychain-password"
        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let path = directory.appendingPathComponent("fixture.keychain").path
            let (status, created) = try CredentialStore.withAccess(allowInteraction: false) {
                var created: SecKeychain?
                let status = Self.password.withCString { bytes in
                    SecKeychainCreate(
                        path, UInt32(Self.password.utf8.count), bytes, false, nil, &created)
                }
                return (status, created)
            }
            keychain = try #require(created)
            #expect(status == errSecSuccess)
        }
        deinit {
            let removed = try? CredentialStore.withAccess(allowInteraction: false) {
                let unlocked = Self.password.withCString {
                    SecKeychainUnlock(keychain, UInt32(Self.password.utf8.count), $0, true)
                }
                #expect(unlocked == errSecSuccess)
                let status = SecKeychainDelete(keychain)
                #expect(status == errSecSuccess)
                return status == errSecSuccess
            }
            if removed == true { try? FileManager.default.removeItem(at: directory) }
        }
        func unlock() throws {
            let status = try CredentialStore.withAccess(allowInteraction: false) {
                Self.password.withCString {
                    SecKeychainUnlock(keychain, UInt32(Self.password.utf8.count), $0, true)
                }
            }
            #expect(status == errSecSuccess)
        }
    }

    @Test func backgroundReadsRejectUntrustedItemsWithoutInteraction() throws {
        let fixture = try Fixture()
        let service = "dev.inkcre.credentials-test.\(UUID())"
        let connection = UUID()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connection.uuidString,
            kSecMatchSearchList as String: [fixture.keychain],
        ]
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        command.arguments = [
            "add-generic-password", "-s", service, "-a", connection.uuidString,
            "-w", "disposable-fixture", "-T", "/usr/bin/security",
            fixture.directory.appendingPathComponent("fixture.keychain").path,
        ]
        try command.run()
        command.waitUntilExit()
        #expect(command.terminationStatus == 0)
        defer {
            _ = try? CredentialStore.withAccess(allowInteraction: false) {
                SecItemDelete(query as CFDictionary)
            }
        }

        let store = CredentialStore(service: service, keychain: fixture.keychain)
        for _ in 0..<3 {
            do {
                _ = try store.read(for: connection)
                Issue.record("无权访问的凭据不能静默读取成功")
            } catch PeerError.needsAction(let message) {
                #expect(message.contains("凭据暂不可用"))
            }
        }
    }

    @Test func appOwnedPasswordCanBeReadAndUpdatedWithoutCaching() throws {
        let fixture = try Fixture()
        let service = "dev.inkcre.credentials-test.\(UUID())"
        let connection = UUID()
        defer {
            _ = try? CredentialStore.withAccess(allowInteraction: false) {
                SecItemDelete(
                    [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrService as String: service,
                        kSecMatchSearchList as String: [fixture.keychain],
                    ] as CFDictionary)
            }
        }
        let store = CredentialStore(service: service, keychain: fixture.keychain)
        try store.save("first-fixture", for: connection)
        #expect(try store.read(for: connection) == "first-fixture")
        try store.save("updated-fixture", for: connection)
        #expect(try store.read(for: connection) == "updated-fixture")
    }

    @Test func poolReusesKeychainAuthenticationAndImmediatelyObservesAnotherStoreSaving()
        async throws
    {
        let fixture = try Fixture()
        let service = "dev.inkcre.credentials-test.\(UUID())"
        let first = CredentialStore(service: service, keychain: fixture.keychain)
        let second = CredentialStore(service: service, keychain: fixture.keychain)
        let target = ConnectionTarget(host: "localhost", database: "unused", username: "peer")
        let database = PeerDatabase()
        try first.save("first-fixture", for: target.id)
        let original = try await database.client(for: target, credentials: .keychain(first))
        for _ in 0..<500 {
            #expect(
                try await database.client(for: target, credentials: .keychain(second)) === original)
        }
        var renamed = target
        renamed.name = "新名称"
        renamed.webURL = URL(string: "https://example.test")
        try second.save("first-fixture", for: target.id)
        #expect(
            try await database.client(for: renamed, credentials: .keychain(second)) === original)
        // No timer or timestamp boundary: updates in the same second must replace authentication.
        try second.save("updated-fixture", for: target.id)
        let updated = try await database.client(for: target, credentials: .keychain(second))
        #expect(updated !== original)
        #expect(try await database.client(for: target, credentials: .keychain(first)) === updated)
        #expect(
            try CredentialStore.withAccess(allowInteraction: false) {
                SecItemDelete(
                    [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrService as String: service,
                        kSecMatchSearchList as String: [fixture.keychain],
                    ] as CFDictionary)
            } == errSecSuccess)
        await #expect(throws: PeerError.self) {
            try await database.client(for: target, credentials: .keychain(first))
        }
        await database.shutdown()
    }

    @Test func lockingAKeychainRevokesAnExistingPoolAndUnlockingRestoresIt() async throws {
        let fixture = try Fixture()
        let store = CredentialStore(
            service: "dev.inkcre.credentials-test.\(UUID())", keychain: fixture.keychain)
        let target = ConnectionTarget(host: "localhost", database: "unused", username: "peer")
        let database = PeerDatabase()
        try store.save("fixture", for: target.id)
        let original = try await database.client(for: target, credentials: .keychain(store))
        #expect(
            try CredentialStore.withAccess(allowInteraction: false) {
                SecKeychainLock(fixture.keychain)
            } == errSecSuccess)
        await #expect(throws: PeerError.self) {
            try await database.client(for: target, credentials: .keychain(store))
        }
        try fixture.unlock()
        let restored = try await database.client(for: target, credentials: .keychain(store))
        #expect(restored !== original)
        await database.shutdown()
    }

}
