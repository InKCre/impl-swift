import Foundation
import PeerCore

extension PeerHostContext {
    public func saveEdited(
        host: String, port: String, database: String, username: String, tls: ConnectionTarget.TLS,
        web: String, password: String, name: String = "", previous: ConnectionTarget?
    ) async throws -> ConnectionTarget {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(port) else { throw PeerError.invalid("数据库端口无效。") }
        let web = web.trimmingCharacters(in: .whitespacesAndNewlines)
        let webURL = web.isEmpty ? nil : URL(string: web)
        if !web.isEmpty && webURL == nil { throw PeerError.invalid("Web 地址无效。") }
        let same =
            previous?.host == host && previous?.port == port && previous?.database == database
        let target = ConnectionTarget(
            id: same ? previous!.id : UUID(), peerID: same ? previous!.peerID : UUID(),
            host: host, port: port, database: database, username: username, tls: tls,
            webURL: webURL,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? host : name.trimmingCharacters(in: .whitespacesAndNewlines))
        try target.validate()
        if !password.isEmpty {
            try await savePassword(password, for: target)
        } else {
            try await reauthorize(target)
        }
        try await connections.save(target)
        return target
    }
}
