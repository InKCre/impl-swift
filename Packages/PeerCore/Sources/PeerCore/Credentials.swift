import Foundation
import Security

public struct CredentialStore: Sendable {
    private let service: String
    private let keychain: KeychainReference?
    private static let accessLock = NSLock()
    // Only accessed inside withAccess. These generations contain no credential contents.
    private static let generations = Generations()
    private final class Generations: @unchecked Sendable {
        var next: UInt64 = 0
        var values: [String: [UUID: UInt64]] = [:]
    }

    private func invalidate(_ connection: UUID) {
        Self.generations.next &+= 1
        Self.generations.values[service, default: [:]][connection] = Self.generations.next
    }

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
            invalidate(connection)
        }
    }

    public func read(for connection: UUID, allowInteraction: Bool = false) throws -> String {
        try Self.withAccess(allowInteraction: allowInteraction) {
            if allowInteraction {
                invalidate(connection)
            }
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

    struct Revision: Equatable, Sendable {
        let service: String
        let attributes: Data
        let change: UInt64
    }

    /// Read identity, metadata and lock state, without asking Security.framework to copy the password.
    func revision(for connection: UUID) throws -> Revision {
        try Self.withAccess(allowInteraction: false) {
            var query = query
            query[kSecAttrAccount as String] = connection.uuidString
            query[kSecReturnAttributes as String] = true
            query[kSecReturnRef as String] = true
            query[kSecReturnPersistentRef as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess, var attributes = result as? [String: Any],
                let reference = attributes.removeValue(forKey: kSecValueRef as String),
                CFGetTypeID(reference as CFTypeRef) == SecKeychainItemGetTypeID()
            else {
                throw PeerError.needsAction("凭据暂不可用，请在连接设置中解锁密钥串或重新保存密码。")
            }
            let item = reference as! SecKeychainItem
            var keychain: SecKeychain?
            guard SecKeychainItemCopyKeychain(item, &keychain) == errSecSuccess, let keychain else {
                throw PeerError.needsAction("无法访问此信息库的密钥串，请检查连接凭据。")
            }
            var keychainStatus: SecKeychainStatus = 0
            guard SecKeychainGetStatus(keychain, &keychainStatus) == errSecSuccess,
                keychainStatus & kSecUnlockStateStatus != 0
            else {
                throw PeerError.needsAction("凭据暂不可用，请在连接设置中解锁密钥串或重新保存密码。")
            }
            return Revision(
                service: service,
                attributes: try PropertyListSerialization.data(
                    fromPropertyList: attributes.keys.sorted().map { [$0, attributes[$0]!] },
                    format: .binary, options: 0),
                change: Self.generations.values[service]?[connection] ?? 0)
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

/// A credential source, resolved by PeerDatabase at the lifetime boundary of its connection pool.
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
