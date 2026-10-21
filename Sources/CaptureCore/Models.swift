import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum CaptureError: LocalizedError, Sendable {
    case invalid(String)
    case storage(String)
    case connection(String)
    case needsAction(String)
    case outcomeUnknown

    public var errorDescription: String? {
        switch self {
        case .invalid(let message), .storage(let message),
             .connection(let message), .needsAction(let message): message
        case .outcomeUnknown: "请求已发出，结果待确认。原材料已保留，将用同一提交身份恢复。"
        }
    }
}

public enum CaptureEntry: String, Codable, Sendable {
    case selection, paste, screenshot, manual
}

public struct CaptureOrigin: Codable, Sendable, Equatable {
    public var applicationID: String?
    public var title: String?
    public var url: String?

    public init(applicationID: String? = nil, title: String? = nil, url: String? = nil) {
        self.applicationID = applicationID
        self.title = title
        self.url = url
    }

    enum CodingKeys: String, CodingKey {
        case applicationID = "application_id"
        case title, url
    }
}

public struct Material: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable { case text, image }
    public let kind: Kind
    public var text: String?
    public let mimeType: String?
    public let data: Data?
    public let filename: String?
    // UI identity is local and is never part of the shared capture contract.
    public var id = UUID()

    public init(text: String) {
        kind = .text
        self.text = text
        mimeType = nil
        data = nil
        filename = nil
    }

    public init(image: Data, mimeType: String, filename: String? = nil) {
        kind = .image
        text = nil
        self.mimeType = mimeType
        data = image
        self.filename = filename
    }

    enum CodingKeys: String, CodingKey {
        case kind, text, filename
        case mimeType = "mime_type"
        case data = "data_base64"
    }

    public var byteCount: Int { data?.count ?? text?.utf8.count ?? 0 }
}

public struct CapturePayload: Codable, Sendable {
    public let submissionID: UUID
    public var capturedAt: Date
    public var entry: CaptureEntry
    public var origin: CaptureOrigin?
    public var materials: [Material]
    public var annotation: String?

    public init(
        submissionID: UUID = UUID(), capturedAt: Date = Date(),
        entry: CaptureEntry = .manual, origin: CaptureOrigin? = nil,
        materials: [Material] = [], annotation: String? = nil
    ) {
        self.submissionID = submissionID
        self.capturedAt = capturedAt
        self.entry = entry
        self.origin = origin
        self.materials = materials
        self.annotation = annotation
    }

    enum CodingKeys: String, CodingKey {
        case submissionID = "submission_id"
        case capturedAt = "captured_at"
        case entry, origin, materials, annotation
    }

    public func validate() throws {
        guard !materials.isEmpty || !(annotation ?? "").isEmpty else {
            throw CaptureError.invalid("先写下想法，或加入一份材料。")
        }
        guard materials.count <= 128 else { throw CaptureError.invalid("材料数量超过 128 项。") }
        for (value, limit) in [(origin?.applicationID, 1024), (origin?.title, 4096), (origin?.url, 8192)] {
            guard (value?.unicodeScalars.count ?? 0) <= limit else {
                throw CaptureError.invalid("来源信息过长，请缩短后收入。")
            }
        }
        let size = materials.reduce(annotation?.utf8.count ?? 0) { $0 + $1.byteCount }
        guard size <= 32 * 1024 * 1024 else {
            throw CaptureError.invalid("材料累计超过 32 MiB，请拆分后收入。")
        }
        for material in materials {
            switch material.kind {
            case .text:
                guard let text = material.text, !text.isEmpty, material.data == nil else {
                    throw CaptureError.invalid("文字材料为空或格式不正确。")
                }
            case .image:
                guard let bytes = material.data, !bytes.isEmpty,
                      ["image/png", "image/jpeg", "image/gif", "image/webp"].contains(material.mimeType),
                      material.text == nil else {
                    throw CaptureError.invalid("图片为空或格式不支持。")
                }
                guard (material.filename?.unicodeScalars.count ?? 0) <= 512,
                      let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                      CGImageSourceGetStatus(source) == .statusComplete,
                      let identifier = CGImageSourceGetType(source) as String?,
                      UTType(identifier)?.preferredMIMEType == material.mimeType,
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      width > 0, height > 0, width <= 89_478_485 / height,
                      CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil else {
                    throw CaptureError.invalid("图片内容与格式不符、文件损坏或解码尺寸过大。")
                }
            }
        }
    }
}

public struct ConnectionTarget: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let peerID: UUID
    public var postgrestURL: URL
    public var webURL: URL?
    public var name: String

    public init(
        id: UUID = UUID(), peerID: UUID = UUID(), postgrestURL: URL,
        webURL: URL? = nil, name: String = "我的信息库"
    ) {
        self.id = id
        self.peerID = peerID
        self.postgrestURL = postgrestURL
        self.webURL = webURL
        self.name = name
    }

    public func validate() throws {
        for url in [postgrestURL, webURL].compactMap({ $0 }) {
            guard ["http", "https"].contains(url.scheme), url.host != nil,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
                throw CaptureError.invalid("连接地址须为不含凭据、查询参数或片段的 HTTP(S) 地址。")
            }
        }
    }
}

public struct CaptureResult: Codable, Sendable, Equatable {
    public enum Availability: String, Codable, Sendable { case available, deleted }
    public let submissionID: UUID
    public let rootBlockID: Int
    public let committedAt: Date
    public let availability: Availability

    public init(submissionID: UUID, rootBlockID: Int, committedAt: Date, availability: Availability) {
        self.submissionID = submissionID
        self.rootBlockID = rootBlockID
        self.committedAt = committedAt
        self.availability = availability
    }

    enum CodingKeys: String, CodingKey {
        case submissionID = "submission_id"
        case rootBlockID = "root_block_id"
        case committedAt = "committed_at"
        case availability
    }
}

public struct CaptureRecord: Codable, Sendable, Identifiable {
    public enum State: String, Codable, Sendable {
        case draft, pending, unknown, needsAction, cancelled, confirmed
    }
    public let id: UUID
    public var payload: CapturePayload?
    public var target: ConnectionTarget?
    public var state: State
    public var result: CaptureResult?
    public var message: String?
    public var attempts: Int
    public var updatedAt: Date

    public init(payload: CapturePayload = CapturePayload()) {
        id = payload.submissionID
        self.payload = payload
        state = .draft
        attempts = 0
        updatedAt = Date()
    }

    public var statusLabel: String {
        switch state {
        case .draft: "草稿"
        case .pending: "本机已保留，待收入"
        case .unknown: "结果待确认"
        case .needsAction: "需要处理"
        case .cancelled: "已取消后续发送"
        case .confirmed: result?.availability == .deleted ? "曾收入，内容已删除" : "已收入"
        }
    }
}

public enum CaptureJSON {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else {
                throw CaptureError.invalid("时间格式无效。")
            }
            return date
        }
        return try decoder.decode(type, from: data)
    }
}
