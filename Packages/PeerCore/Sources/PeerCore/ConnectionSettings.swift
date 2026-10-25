import Foundation

public actor ConnectionSettings {
    private let url: URL
    public init(url: URL) { self.url = url }
    public struct SavedConnections: Codable, Sendable {
        public var selected: UUID?
        public var connections: [ConnectionTarget]
        public var current: ConnectionTarget? { connections.first { $0.id == selected } }
    }

    public func loadAll() throws -> SavedConnections {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return SavedConnections(selected: nil, connections: [])
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        // Preserve the existing single connection, including its Keychain and Peer identities.
        if let target = try? decoder.decode(ConnectionTarget.self, from: data) {
            try target.validate()
            return SavedConnections(selected: target.id, connections: [target])
        }
        let saved = try decoder.decode(SavedConnections.self, from: data)
        guard Set(saved.connections.map(\.id)).count == saved.connections.count,
            saved.selected == nil || saved.current != nil
        else {
            throw PeerError.invalid("保存的连接列表无效。")
        }
        for target in saved.connections { try target.validate() }
        return saved
    }

    public func load() throws -> ConnectionTarget? { try loadAll().current }

    public func select(_ id: UUID) throws -> ConnectionTarget {
        var saved = try loadAll()
        guard let target = saved.connections.first(where: { $0.id == id }) else {
            throw PeerError.invalid("连接不存在。")
        }
        saved.selected = id
        try persist(saved)
        return target
    }

    public func save(_ target: ConnectionTarget) throws {
        try target.validate()
        var saved = try loadAll()
        if let index = saved.connections.firstIndex(where: { $0.id == target.id }) {
            saved.connections[index] = target
        } else {
            saved.connections.append(target)
        }
        saved.selected = target.id
        try persist(saved)
    }

    private func persist(_ saved: SavedConnections) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(saved).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public func saveEdited(
        host: String, port: String, database: String, username: String, tls: ConnectionTarget.TLS,
        web: String, password: String, name: String = "", previous: ConnectionTarget?,
        credentials: CredentialStore
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
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? host : name.trimmingCharacters(in: .whitespacesAndNewlines))
        try target.validate()
        if !password.isEmpty { try credentials.save(password, for: target.id) }
        _ = try credentials.read(for: target.id, allowInteraction: true)
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
