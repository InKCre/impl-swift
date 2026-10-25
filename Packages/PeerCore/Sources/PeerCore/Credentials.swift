import Foundation
import Security

public struct CredentialStore: Sendable {
    private let service: String
    private static let accessLock = NSLock()

    public init(service: String) { self.service = service }

    public func save(_ secret: String, for connection: UUID) throws {
        Self.accessLock.lock()
        defer { Self.accessLock.unlock() }
        guard !secret.isEmpty else {
            throw PeerError.invalid("请输入数据库密码。")
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connection.uuidString,
        ]
        let data = Data(secret.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw PeerError.storage("Keychain 保存失败（\(status)）。") }
    }

    public func read(for connection: UUID, allowInteraction: Bool = false) throws -> String {
        Self.accessLock.lock()
        defer { Self.accessLock.unlock() }
        // File-based Keychain ignores LAContext; serialize and restore its process-wide UI policy.
        var previous: DarwinBoolean = false
        guard SecKeychainGetUserInteractionAllowed(&previous) == errSecSuccess,
            SecKeychainSetUserInteractionAllowed(allowInteraction) == errSecSuccess
        else { throw PeerError.storage("无法设置密钥串访问方式。") }
        defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connection.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
            throw PeerError.needsAction("凭据暂不可用，请在连接设置中解锁密钥串或重新保存密码。")
        }
        guard status == errSecSuccess, let data = result as? Data,
            let secret = String(data: data, encoding: .utf8)
        else {
            throw PeerError.needsAction("无法读取此信息库的凭据，请更新数据库密码。")
        }
        return secret
    }
}
