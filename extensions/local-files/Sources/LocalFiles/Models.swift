import Foundation
import PeerCore

public enum LocalFilesContract {
    public static let descriptor = NativeExtensionDescriptor.bundled(
        resourceBundle: "InKCreLocalFiles_LocalFiles", developmentBundle: .module)
    public static let sourceType = "extensions.local_files.directory.v1"
    public static let resolver = "extensions.local_files.file.v2"
    public static let legacyResolver = "extensions.local_files.file.v1"
    public static let extractor = "mac-native-content.v2"
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
    public var bodyResolver: String? = "core.text.v1"
    public var path: String {
        (try? PeerFileLocation(uri: metadata.location).path) ?? metadata.location
    }
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

public struct FileObservation: Sendable {
    public var metadata: FileMetadata
    public let content: String?

    func changes(_ previous: FileMetadata) -> Bool {
        var current = metadata
        current.observed_at = previous.observed_at
        if content == nil { current.revision = previous.revision }
        return current != previous
    }
}

public struct DirectoryBinding: Codable, Sendable, Identifiable {
    public let source: Int
    public let connectionID: UUID
    public let peerID: UUID
    public var bookmark: Data
    public var id: String { "\(peerID).\(source)" }
    public init(source: Int, target: ConnectionTarget, bookmark: Data) {
        self.source = source
        self.connectionID = target.id
        self.peerID = target.peerID
        self.bookmark = bookmark
    }
}

func bodyResolver(for format: String) -> String {
    switch format {
    case "html": "core.html.v1"
    case "markdown": "core.markdown.v1"
    default: "core.text.v1"
    }
}

func storedFile(
    id: Int, resolver: String, content: String, bodyID: Int?, bodyResolver: String?, storage: Int?
) throws -> FileRecord {
    let metadata = try FileJSON.decode(FileMetadata.self, content)
    let allowed =
        resolver == LocalFilesContract.legacyResolver
        ? ["core.text.v1"] : ["core.text.v1", "core.html.v1", "core.markdown.v1"]
    if let bodyID {
        guard let bodyResolver, allowed.contains(bodyResolver), storage == nil else {
            throw PeerError.invalid("文件正文类型不符。")
        }
        return FileRecord(id: id, metadata: metadata, bodyID: bodyID, bodyResolver: bodyResolver)
    }
    guard metadata.revision == nil else { throw PeerError.invalid("文件资料缺少成功修订的正文。") }
    return FileRecord(id: id, metadata: metadata, bodyID: nil, bodyResolver: nil)
}
