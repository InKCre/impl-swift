import Foundation

public struct ConnectionTarget: Codable, Sendable, Equatable, Identifiable {
    public enum TLS: String, Codable, Sendable, CaseIterable { case require, disable }
    public let id: UUID
    public let peerID: UUID
    public var host: String
    public var port: Int
    public var database: String
    public var username: String
    public var tls: TLS
    public var webURL: URL?
    public var name: String

    public init(
        id: UUID = UUID(), peerID: UUID = UUID(), host: String, port: Int = 5432,
        database: String, username: String, tls: TLS = .require,
        webURL: URL? = nil, name: String = "我的信息库"
    ) {
        self.id = id
        self.peerID = peerID
        self.host = host
        self.port = port
        self.database = database
        self.username = username
        self.tls = tls
        self.webURL = webURL
        self.name = name
    }

    public func validate() throws {
        guard !host.isEmpty, !host.contains(where: { $0.isWhitespace }), !host.contains("/"),
            (1...65535).contains(port), !database.isEmpty, !username.isEmpty,
            ![host, database, username].contains(where: { $0.contains("\0") })
        else {
            throw PeerError.invalid("请输入有效的数据库主机、端口、库名与运行角色。")
        }
        if tls == .disable && !["localhost", "127.0.0.1", "::1"].contains(host) {
            throw PeerError.invalid("远端数据库必须使用 TLS；仅本机回环开发连接可关闭 TLS。")
        }
        if let url = webURL {
            guard ["http", "https"].contains(url.scheme), url.host != nil, url.user == nil,
                url.password == nil, url.query == nil, url.fragment == nil
            else {
                throw PeerError.invalid("Web 地址须为不含凭据的 HTTP(S) 地址。")
            }
        }
    }
}
