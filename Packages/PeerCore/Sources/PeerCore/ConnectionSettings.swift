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

    public func resolve(_ frozen: ConnectionTarget) throws -> ConnectionTarget {
        guard let current = try loadAll().connections.first(where: { $0.id == frozen.id }),
            current.hasSameDestination(as: frozen)
        else { throw PeerError.needsAction("原目标连接不可用，请恢复该信息库的连接。") }
        return current
    }

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
            guard saved.connections[index].hasSameDestination(as: target) else {
                throw PeerError.invalid("修改信息库地址需要创建新连接，已有材料的目标不能改变。")
            }
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

}

public struct PeerHostContext: Sendable {
    public let database: PeerDatabase
    public let identity: String
    public let directory: URL
    public let connections: ConnectionSettings
    public let credentials: CredentialStore
    public init(
        identity: String, directory: URL, database: PeerDatabase = PeerDatabase(),
        credentials: CredentialStore? = nil
    ) {
        self.database = database
        self.identity = identity
        self.directory = directory
        connections = ConnectionSettings(url: directory.appendingPathComponent("connection.json"))
        self.credentials = credentials ?? CredentialStore(service: "\(identity).connections")
    }

    /// Saving through the Host updates the same session used by every bundled extension.
    public func savePassword(_ password: String, for target: ConnectionTarget) async throws {
        try target.validate()
        try credentials.save(password, for: target.id, allowInteraction: true)
        try await database.authorize(target, password: password)
    }

    /// Explicitly reread Keychain; unchanged authentication keeps its client, failure ends the session.
    public func reauthorize(_ target: ConnectionTarget, allowInteraction: Bool = true) async throws
    {
        try target.validate()
        do {
            let password = try credentials.read(for: target.id, allowInteraction: allowInteraction)
            try await database.authorize(target, password: password)
        } catch {
            await database.invalidate(target.id)
            throw error
        }
    }
}
