import CryptoKit
import Foundation
import PeerCore

extension CapturePayload {
    /// Matches Capture v1's sorted UTF-8 JSON, including explicit null optionals.
    public func canonicalDigest() throws -> String {
        // The immutable wire payload has millisecond precision. Hash that same representation.
        let wire = try CaptureJSON.decode(CapturePayload.self, from: CaptureJSON.encode(self))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        let null = NSNull()
        let origin: Any =
            wire.origin.map {
                [
                    "application_id": $0.applicationID as Any? ?? null,
                    "title": $0.title as Any? ?? null, "url": $0.url as Any? ?? null,
                ]
            } ?? null
        let materials: [[String: Any]] = try wire.materials.map { material in
            switch material.kind {
            case .text:
                guard let text = material.text else { throw PeerError.invalid("文字材料格式不正确。") }
                return ["kind": "text", "text": text]
            case .image:
                guard let data = material.data, let mime = material.mimeType else {
                    throw PeerError.invalid("图片材料格式不正确。")
                }
                return [
                    "kind": "image", "mime_type": mime,
                    "filename": material.filename as Any? ?? null,
                    "data_sha256": Self.sha256(data),
                ]
            }
        }
        let document: [String: Any] = [
            "submission_id": wire.submissionID.uuidString.lowercased(),
            "captured_at": formatter.string(from: wire.capturedAt) + "000+00:00",
            "entry": wire.entry.rawValue, "origin": origin, "materials": materials,
            "annotation": wire.annotation as Any? ?? null,
        ]
        return Self.sha256(
            try JSONSerialization.data(
                withJSONObject: document, options: [.sortedKeys, .withoutEscapingSlashes]
            ))
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
