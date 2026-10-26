import Foundation
import PeerCore
import Security
import Testing

@Suite(.serialized)
struct CredentialStoreTests {
    @Test func backgroundReadsRejectUntrustedItemsWithoutInteraction() throws {
        let service = "dev.inkcre.credentials-test.\(UUID())"
        let connection = UUID()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connection.uuidString,
        ]
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        command.arguments = [
            "add-generic-password", "-s", service, "-a", connection.uuidString,
            "-w", "disposable-fixture", "-T", "/usr/bin/security",
        ]
        try command.run()
        command.waitUntilExit()
        #expect(command.terminationStatus == 0)
        defer { SecItemDelete(query as CFDictionary) }

        let store = CredentialStore(service: service)
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
        let service = "dev.inkcre.credentials-test.\(UUID())"
        let connection = UUID()
        defer {
            SecItemDelete(
                [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                ] as CFDictionary)
        }
        let store = CredentialStore(service: service)
        try store.save("first-fixture", for: connection)
        #expect(try store.read(for: connection) == "first-fixture")
        try store.save("updated-fixture", for: connection)
        #expect(try store.read(for: connection) == "updated-fixture")
    }
}
