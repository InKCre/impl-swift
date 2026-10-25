import Foundation
import PeerCore

public enum LocalFilesContract {
    public static let descriptor = NativeExtensionDescriptor(
        name: "inkcre/local-files", distribution: "swift_bundled", version: "0.1.0")
    public static let sourceType = "extensions.local_files.directory.v1"
    public static let resolver = "extensions.local_files.file.v1"
    public static let extractor = "mac-native-text.v1"
}

public enum FileJSON {
    public static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
    public static func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(text.utf8))
    }
}

public struct PeerFileLocation: Sendable, Equatable {
    public let peer: UUID
    public let path: String
    public init(peer: UUID, path: String) throws {
        guard path.hasPrefix("/"), !path.contains("\0") else {
            throw PeerError.invalid("文件位置需要绝对路径。")
        }
        self.peer = peer
        self.path = path
    }
    public init(uri: String) throws {
        guard let components = URLComponents(string: uri), components.scheme == "inkcre-peer-file",
            let host = components.host, let peer = UUID(uuidString: host),
            components.user == nil, components.password == nil, components.port == nil,
            components.query == nil, components.fragment == nil
        else { throw PeerError.invalid("原文件链接无效。") }
        try self.init(peer: peer, path: components.path)
    }
    public var uri: String {
        var components = URLComponents()
        components.scheme = "inkcre-peer-file"
        components.host = peer.uuidString.lowercased()
        components.path = path
        return components.string!
    }
    public func localURL(for peer: UUID) throws -> URL {
        guard self.peer == peer else { throw PeerError.needsAction("原件位于另一个 Peer。") }
        return URL(fileURLWithPath: path)
    }
}

public struct DirectoryConfig: Codable, Sendable, Equatable {
    public var peer: UUID
    public var path: String
    public var enabled: Bool
    public init(peer: UUID, path: String, enabled: Bool = true) {
        self.peer = peer
        self.path = path
        self.enabled = enabled
    }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(peer.uuidString.lowercased(), forKey: .peer)
        try values.encode(path, forKey: .path)
        try values.encode(enabled, forKey: .enabled)
    }
}

public struct DirectorySource: Sendable, Identifiable {
    public let id: Int
    public var config: DirectoryConfig
    public let block: Int?
    public let state: DirectoryState
}

public struct DirectoryState: Codable, Sendable {
    // 序列化字段遵循 Local Files 跨端合同。
    // swift-format-ignore: AlwaysUseLowerCamelCase
    public var scanned_at: Date?
    public var issue: String?
    public var errors: Int
    public init(scanned_at: Date? = nil, issue: String? = nil, errors: Int = 0) {
        self.scanned_at = scanned_at
        self.issue = issue
        self.errors = errors
    }
}

public struct FileIdentity: Codable, Sendable, Equatable {
    public let volume: String
    public let number: UInt64
    public let created: Date
    init(volume: String, number: UInt64, created: Date) {
        self.volume = volume
        self.number = number
        self.created = Date(timeIntervalSince1970: floor(created.timeIntervalSince1970))
    }
}

public struct FileRevision: Codable, Sendable, Equatable {
    public let sha256: String
    public let extractor: String
    // 序列化字段遵循 Local Files 跨端合同。
    // swift-format-ignore: AlwaysUseLowerCamelCase
    public let extracted_at: Date
    public let scope: String
}

public struct FileMetadata: Codable, Sendable, Equatable {
    public var location: String
    public var format: String
    public var identity: FileIdentity?
    public var available: Bool
    // 序列化字段遵循 Local Files 跨端合同。
    // swift-format-ignore: AlwaysUseLowerCamelCase
    public var observed_at: Date
    public var revision: FileRevision?
    public var issue: String?
}

public struct FileRecord: Sendable, Identifiable {
    public let id: Int
    public var metadata: FileMetadata
    public let bodyID: Int?
    public var path: String {
        (try? PeerFileLocation(uri: metadata.location).path) ?? metadata.location
    }
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

public struct FileObservation: Sendable {
    public var metadata: FileMetadata
    public let text: String?

    func changes(_ previous: FileMetadata) -> Bool {
        var current = metadata
        current.observed_at = previous.observed_at
        if text == nil { current.revision = previous.revision }
        return current != previous
    }
}

public struct DirectoryBinding: Codable, Sendable, Identifiable {
    public let source: Int
    public let target: ConnectionTarget
    public var bookmark: Data
    public var id: String { "\(target.peerID).\(source)" }
    public init(source: Int, target: ConnectionTarget, bookmark: Data) {
        self.source = source
        self.target = target
        self.bookmark = bookmark
    }
}
