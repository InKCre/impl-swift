import CryptoKit
import Foundation
import Security

public struct CredentialStore: Sendable {
    private let service: String

    public init(service: String) { self.service = service }

    public func save(_ secret: String, for connection: UUID) throws {
        guard secret.utf8.count >= 32 else {
            throw CaptureError.invalid("部署签名凭据至少需要 32 个 UTF-8 字节。")
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
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CaptureError.storage("Keychain 保存失败（\(status)）。") }
    }

    public func read(for connection: UUID) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connection.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let secret = String(data: data, encoding: .utf8) else {
            throw CaptureError.needsAction("无法读取此信息库的凭据，请在连接设置中重新保存。")
        }
        return secret
    }
}

public enum PeerToken {
    public static func create(secret: String, now: Date = Date()) throws -> String {
        guard secret.utf8.count >= 32 else { throw CaptureError.invalid("部署签名凭据过短。") }
        let header = try JSONSerialization.data(withJSONObject: ["alg": "HS256", "typ": "JWT"])
        let seconds = Int(now.timeIntervalSince1970)
        let claims = try JSONSerialization.data(withJSONObject: [
            "role": "authenticated", "iss": "inkcre-peer", "aud": "inkcre-api",
            "iat": seconds, "exp": seconds + 3600,
        ])
        let content = "\(base64URL(header)).\(base64URL(claims))"
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(content.utf8), using: SymmetricKey(data: Data(secret.utf8))
        )
        return "\(content).\(base64URL(Data(signature)))"
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
