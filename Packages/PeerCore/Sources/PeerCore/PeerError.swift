import Foundation

public enum PeerError: LocalizedError, Sendable {
    case invalid(String)
    case storage(String)
    case connection(String)
    case needsAction(String)
    case outcomeUnknown

    public var errorDescription: String? {
        switch self {
        case .invalid(let message), .storage(let message),
            .connection(let message), .needsAction(let message):
            message
        case .outcomeUnknown: "写入已发出，结果尚未确认。"
        }
    }
}
