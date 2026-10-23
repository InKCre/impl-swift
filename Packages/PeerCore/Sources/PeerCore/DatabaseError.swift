import Foundation
import PostgresNIO

extension PeerDatabase {
    public static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let transaction = error as? PostgresTransactionError,
           transaction.rollbackError == nil, transaction.commitError == nil,
           let cause = transaction.closureError { return isCancellation(cause) }
        return false
    }
    public static func failure(_ error: Error, dispatched: Bool = false) -> PeerError {
        if let transaction = error as? PostgresTransactionError,
            transaction.rollbackError == nil, transaction.commitError == nil,
            let cause = transaction.closureError
        {
            return failure(cause, dispatched: dispatched)
        }
        if let error = error as? PeerError { return error }
        if let pg = error as? PSQLError, let code = pg.serverInfo?[.sqlState] {
            switch String(code.prefix(2)) {
            case "28", "42": return .needsAction("数据库角色权限或协议不符，请检查运行凭据与数据库初始化。")
            case "22", "23": return .needsAction("数据库拒绝了写入参数或约束。")
            default: break
            }
        }
        return dispatched ? .outcomeUnknown : .connection("暂时无法连接 PostgreSQL，请检查网络和连接配置。")
    }
}
