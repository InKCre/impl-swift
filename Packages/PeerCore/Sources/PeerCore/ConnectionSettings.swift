import Foundation

public actor ConnectionSettings {
    private let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> ConnectionTarget? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(ConnectionTarget.self, from: Data(contentsOf: url))
    }
    public func save(_ target: ConnectionTarget) throws {
        try target.validate()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(target).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public func saveEdited(
        host: String, port: String, database: String, username: String, tls: ConnectionTarget.TLS,
        web: String, password: String, previous: ConnectionTarget?, credentials: CredentialStore
    ) throws -> ConnectionTarget {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(port) else { throw PeerError.invalid("数据库端口无效。") }
        let web = web.trimmingCharacters(in: .whitespacesAndNewlines)
        let webURL = web.isEmpty ? nil : URL(string: web)
        if !web.isEmpty && webURL == nil { throw PeerError.invalid("Web 地址无效。") }
        let same =
            previous?.host == host && previous?.port == port && previous?.database == database
        let sameCredentials = same && previous?.username == username
        let target = ConnectionTarget(
            id: sameCredentials ? previous!.id : UUID(), peerID: same ? previous!.peerID : UUID(),
            host: host, port: port, database: database, username: username, tls: tls,
            webURL: webURL,
            name: host)
        try target.validate()
        if !password.isEmpty { try credentials.save(password, for: target.id) }
        _ = try credentials.read(for: target.id)
        try save(target)
        return target
    }

}

public struct PeerHostContext: Sendable {
    public let identity: String
    public let directory: URL
    public let connections: ConnectionSettings
    public let credentials: CredentialStore
    public init(identity: String, directory: URL) {
        self.identity = identity
        self.directory = directory
        connections = ConnectionSettings(url: directory.appendingPathComponent("connection.json"))
        credentials = CredentialStore(service: "\(identity).connections")
    }
}
