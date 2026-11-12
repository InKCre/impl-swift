import Foundation
import Security

public struct CredentialStore: Sendable {
    private let service: String
    private let keychain: KeychainReference?
    private static let accessLock = NSLock()
    /// An explicit keychain scopes independent consumers and disposable acceptance fixtures.
    public init(service: String, keychain: SecKeychain? = nil) {
        self.service = service
        self.keychain = keychain.map(KeychainReference.init)
    }

    private final class KeychainReference: @unchecked Sendable {
        // Security.framework keychain references are thread-safe; all accesses also use accessLock.
        let value: SecKeychain
        init(_ value: SecKeychain) { self.value = value }
    }

    private var query: [String: Any] {
        var result: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let keychain { result[kSecMatchSearchList as String] = [keychain.value] }
        return result
    }

    public func save(_ secret: String, for connection: UUID, allowInteraction: Bool = false) throws
    {
        try Self.withAccess(allowInteraction: allowInteraction) {
            guard !secret.isEmpty else {
                throw PeerError.invalid("请输入数据库密码。")
            }
            var query = query
            query[kSecAttrAccount as String] = connection.uuidString
            let data = Data(secret.utf8)
            var status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
            if status == errSecItemNotFound {
                var item = query
                item.removeValue(forKey: kSecMatchSearchList as String)
                if let keychain { item[kSecUseKeychain as String] = keychain.value }
                item[kSecValueData as String] = data
                status = SecItemAdd(item as CFDictionary, nil)
            }
            guard status == errSecSuccess else {
                throw PeerError.storage("Keychain 保存失败（\(status)）。")
            }
        }
    }

    public func read(for connection: UUID, allowInteraction: Bool = false) throws -> String {
        try Self.withAccess(allowInteraction: allowInteraction) {
            var query = query
            query[kSecAttrAccount as String] = connection.uuidString
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
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

    static func withAccess<Result>(allowInteraction: Bool, _ body: () throws -> Result) throws
        -> Result
    {
        Self.accessLock.lock()
        defer { Self.accessLock.unlock() }
        // File-based Keychain ignores LAContext; serialize and restore its process-wide UI policy.
        var previous: DarwinBoolean = false
        guard SecKeychainGetUserInteractionAllowed(&previous) == errSecSuccess,
            SecKeychainSetUserInteractionAllowed(allowInteraction) == errSecSuccess
        else { throw PeerError.storage("无法设置密钥串访问方式。") }
        defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        return try body()
    }
}

/// A bootstrap credential source. PeerDatabase resolves it only when no session exists.
public enum DatabaseCredentials: Sendable {
    case password(String)
    case keychain(CredentialStore)

    /// One-off access for consumers that do not own a reusable database authentication session.
    public func read(for connection: UUID) throws -> String {
        switch self {
        case .password(let password): return password
        case .keychain(let store): return try store.read(for: connection)
        }
    }
}
