import Foundation

public struct PeerClient: Sendable {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 90
            configuration.httpCookieStorage = nil
            self.session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
        }
    }

    public func register(_ target: ConnectionTarget, secret: String) async throws -> Date {
        try target.validate()
        let identity = target.peerID.uuidString.lowercased()
        let registration: [String: Any] = [
            "id": identity, "name": Host.current().localizedName ?? "InKCre Mac",
            "application_version": "0.1.0", "capabilities": [],
            "config_schema": [:], "config": [:], "labels": ["macOS"],
        ]
        _ = try await database(
            target, path: "peers", method: "POST",
            query: [.init(name: "on_conflict", value: "id")],
            body: JSONSerialization.data(withJSONObject: registration), secret: secret,
            prefer: "resolution=ignore-duplicates,return=minimal"
        )
        let runtime: [String: Any] = [
            "application_version": "0.1.0", "capabilities": [], "config_schema": [:],
        ]
        _ = try await database(
            target, path: "peers", method: "PATCH",
            query: [.init(name: "id", value: "eq.\(identity)")],
            body: JSONSerialization.data(withJSONObject: runtime), secret: secret
        )
        let lease = try await database(
            target, path: "rpc/renew_peer_lease", method: "POST",
            body: JSONSerialization.data(withJSONObject: ["peer": identity, "ttl_seconds": 120]),
            secret: secret
        )
        return try CaptureJSON.decode(Date.self, from: lease).addingTimeInterval(-120)
    }

    public func checkConnection(_ target: ConnectionTarget, secret: String) async throws {
        _ = try await register(target, secret: secret)
        _ = try await database(
            target, path: "capture_receipts",
            query: [.init(name: "select", value: "submission_id,graph_digest"), .init(name: "limit", value: "0")],
            secret: secret
        )
    }

    public func recover(_ record: CaptureRecord, secret: String) async throws -> CaptureResult? {
        guard let target = record.target else { throw CaptureError.invalid("待办缺少目标。") }
        let data = try await database(
            target, path: "capture_receipts",
            query: [
                .init(name: "submission_id", value: "eq.\(record.id.uuidString.lowercased())"),
                .init(name: "select", value: "submission_id,payload_digest,root_block_id,committed_at"),
            ], secret: secret
        )
        struct Receipt: Decodable {
            let submission_id: UUID
            let payload_digest: String
            let root_block_id: Int
            let committed_at: Date
        }
        let receipts = try CaptureJSON.decode([Receipt].self, from: data)
        guard let receipt = receipts.first else { return nil }
        guard receipts.count == 1, receipt.submission_id == record.id else {
            throw CaptureError.needsAction("共享回执与待办不一致。")
        }
        guard let payload = record.payload, try payload.canonicalDigest() == receipt.payload_digest else {
            throw CaptureError.needsAction("共享回执的材料指纹与本机不同。原材料已保留，请检查提交身份冲突。")
        }
        let roots = try await database(
            target, path: "blocks",
            query: [.init(name: "id", value: "eq.\(receipt.root_block_id)"),
                    .init(name: "select", value: "id")], secret: secret
        )
        struct Root: Decodable { let id: Int }
        let exists = try CaptureJSON.decode([Root].self, from: roots).contains { $0.id == receipt.root_block_id }
        return CaptureResult(
            submissionID: record.id, rootBlockID: receipt.root_block_id,
            committedAt: receipt.committed_at, availability: exists ? .available : .deleted
        )
    }

    public func submit(_ record: CaptureRecord, secret: String) async throws -> CaptureResult {
        guard let target = record.target, let payload = record.payload else {
            throw CaptureError.invalid("待办缺少冻结的材料或目标。")
        }
        let body = try CaptureJSON.encode(CaptureCommit(payload))
        guard body.count <= 48 * 1024 * 1024 else {
            throw CaptureError.needsAction("编码后的请求超过 48 MiB，请保留材料并处理。")
        }
        let data = try await database(
            target, path: "rpc/commit_capture", method: "POST", body: body,
            secret: secret, isCaptureDispatch: true
        )
        guard let reported = try? CaptureJSON.decode(CaptureResult.self, from: data),
              reported.submissionID == record.id else { throw CaptureError.outcomeUnknown }
        // Local materials are released only after the shared receipt validates their fingerprint.
        guard let persisted = try await recover(record, secret: secret),
              persisted.rootBlockID == reported.rootBlockID else { throw CaptureError.outcomeUnknown }
        return persisted
    }

    private func database(
        _ target: ConnectionTarget, path: String, method: String = "GET",
        query: [URLQueryItem] = [], body: Data? = nil, secret: String, prefer: String? = nil,
        isCaptureDispatch: Bool = false
    ) async throws -> Data {
        var url = target.postgrestURL
        for component in path.split(separator: "/") { url.appendPathComponent(String(component)) }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw CaptureError.invalid("连接地址无效。")
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let endpoint = components.url else { throw CaptureError.invalid("连接地址无效。") }
        return try await request(
            endpoint, method: method, body: body, secret: secret,
            profile: "inkcre", prefer: prefer, isCaptureDispatch: isCaptureDispatch
        )
    }

    private func request(
        _ url: URL, method: String, body: Data?, secret: String,
        profile: String? = nil, prefer: String? = nil, isCaptureDispatch: Bool
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(try PeerToken.create(secret: secret))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let profile {
            request.setValue(profile, forHTTPHeaderField: "Accept-Profile")
            request.setValue(profile, forHTTPHeaderField: "Content-Profile")
        }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if isCaptureDispatch { throw CaptureError.outcomeUnknown }
            throw CaptureError.connection("暂时无法连接信息库，请检查网络与连接地址。")
        }
        guard let http = response as? HTTPURLResponse else {
            throw CaptureError.outcomeUnknown
        }
        guard (200..<300).contains(http.statusCode) else {
            if isCaptureDispatch, http.statusCode >= 500 || http.statusCode == 429 { throw CaptureError.outcomeUnknown }
            switch http.statusCode {
            case 401, 403: throw CaptureError.needsAction("凭据被拒绝，请更新连接凭据并检查系统时间。")
            case 404: throw CaptureError.needsAction("目标缺少 Capture 写入协议，请更新共享数据库。")
            case 409: throw CaptureError.needsAction("提交身份与已保存内容冲突，请保留原待办。")
            case 413: throw CaptureError.needsAction("请求超过服务端或代理限额，材料仍保留。")
            case 422: throw CaptureError.needsAction("服务端拒绝了材料格式，请保留待办并检查内容。")
            case 429, 502, 503, 504: throw CaptureError.connection("服务暂时不可用，稍后自动重试。")
            default: throw CaptureError.needsAction("信息库返回错误（HTTP \(http.statusCode)），材料仍保留。")
            }
        }
        return data
    }
}

private final class RejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Credentials and private material go only to the explicitly configured/published endpoint.
        completionHandler(nil)
    }
}
